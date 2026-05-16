import AppKit
import SwiftUI

/// A borderless window with a translucent circle + crosshair.
/// Drag the circle to position it over the game, then close to capture the center.
final class DragBoundaryOverlayWindow: NSPanel {
    /// Called continuously as the overlay is dragged (flipped screen coords).
    var onPositionChanged: ((CGPoint) -> Void)?
    /// Called when the overlay is closed, passing the final center position.
    var onClose: ((CGPoint) -> Void)?

    private(set) var circleCenter: CGPoint = .zero
    private var radius: Double

    private var circleView: CircleOverlayView?
    private var closeBtnTopConstraint: NSLayoutConstraint?
    private var closeBtnTrailingConstraint: NSLayoutConstraint?

    init(initialCenter: CGPoint, radius: Double) {
        self.radius = radius
        self.circleCenter = initialCenter

        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Size the panel slightly larger than the circle so there's room for labels
        let panelSize = max(radius * 2 + 60, 160)
        let panelRect = CGRect(x: 0, y: 0, width: panelSize, height: panelSize)

        super.init(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true

        // Position window so the circle center matches the desired screen coordinate
        let flippedY = screenFrame.height - initialCenter.y
        let origin = CGPoint(
            x: initialCenter.x - panelSize / 2,
            y: flippedY - panelSize / 2
        )
        self.setFrameOrigin(origin)

        // Content view: transparent background
        let contentView = NSView(frame: panelRect)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = contentView

        // Circle overlay centered in the content view
        let circle = CircleOverlayView(radius: radius)
        circle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(circle)
        self.circleView = circle

        NSLayoutConstraint.activate([
            circle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        // Close button at the top-right corner of the panel
        let closeBtn = NSButton(frame: .zero)
        closeBtn.bezelStyle = .accessoryBarAction
        closeBtn.title = ""
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.imageScaling = .scaleProportionallyUpOrDown
        closeBtn.isBordered = false
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.target = self
        closeBtn.action = #selector(closeOverlay)
        contentView.addSubview(closeBtn)

        let topConstraint = closeBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8)
        let trailingConstraint = closeBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        closeBtnTopConstraint = topConstraint
        closeBtnTrailingConstraint = trailingConstraint
        NSLayoutConstraint.activate([
            topConstraint,
            trailingConstraint,
            closeBtn.widthAnchor.constraint(equalToConstant: 22),
            closeBtn.heightAnchor.constraint(equalToConstant: 22),
        ])

        // Instruction label (non-interactive so mouse events pass through for dragging)
        let label = NSTextField(labelWithString: "拖动定位")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 1, alpha: 0.7)
        label.alignment = .center
        label.isSelectable = false
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    func updateRadius(_ newRadius: Double) {
        self.radius = newRadius
        circleView?.updateRadius(newRadius)
        // Keep the current visual window center fixed on screen.
        let oldCenter = CGPoint(x: self.frame.midX, y: self.frame.midY)
        let newPanelSize = max(newRadius * 2 + 60, 160)
        let newOrigin = CGPoint(
            x: oldCenter.x - newPanelSize / 2,
            y: oldCenter.y - newPanelSize / 2
        )
        self.setFrame(CGRect(
            x: newOrigin.x, y: newOrigin.y,
            width: newPanelSize, height: newPanelSize
        ), display: true)
    }

    @objc private func closeOverlay() {
        captureAndClose()
    }

    private func captureAndClose() {
        guard let screen = NSScreen.main else {
            onClose?(circleCenter)
            self.close()
            return
        }
        // Calculate the actual screen center of this window
        let windowCenterInScreen = self.convertPoint(toScreen: CGPoint(
            x: self.frame.width / 2,
            y: self.frame.height / 2
        ))
        let flippedY = screen.frame.height - windowCenterInScreen.y
        let center = CGPoint(x: windowCenterInScreen.x, y: flippedY)
        circleCenter = center
        onClose?(center)
        self.close()
    }

    // Track window movement to update circleCenter continuously
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        if let screen = NSScreen.main {
            let windowCenterInScreen = self.convertPoint(toScreen: CGPoint(
                x: frameRect.width / 2,
                y: frameRect.height / 2
            ))
            let flippedY = screen.frame.height - windowCenterInScreen.y
            circleCenter = CGPoint(x: windowCenterInScreen.x, y: flippedY)
            onPositionChanged?(circleCenter)
        }
    }

    // Close on Escape key
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            captureAndClose()
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Custom Dragging (isMovableByWindowBackground unreliable for borderless panels)

    private var dragStartLocation: CGPoint?
    private var windowStartOrigin: CGPoint?

    override func mouseDown(with event: NSEvent) {
        // Only start drag on the panel background, not on subviews like the close button.
        let location = event.locationInWindow
        if !contentViewHasHitTest(location) {
            dragStartLocation = NSEvent.mouseLocation
            windowStartOrigin = self.frame.origin
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = dragStartLocation, let startOrigin = windowStartOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let currentLocation = NSEvent.mouseLocation
        let delta = CGPoint(
            x: currentLocation.x - startLocation.x,
            y: currentLocation.y - startLocation.y
        )
        let newOrigin = CGPoint(
            x: startOrigin.x + delta.x,
            y: startOrigin.y + delta.y
        )
        self.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        windowStartOrigin = nil
        super.mouseUp(with: event)
    }

    /// Returns true if the location hits an interactive button (close button).
    /// Everything else (circle, label, background) should drag the window.
    private func contentViewHasHitTest(_ location: CGPoint) -> Bool {
        guard let cv = contentView else { return false }
        let windowPoint = self.convertFromScreen(CGRect(origin: location, size: .zero)).origin
        let viewPoint = cv.convert(windowPoint, from: nil)
        let hitView = cv.hitTest(viewPoint)
        return hitView is NSButton
    }
}

/// Draws a translucent circle with crosshair and radius label.
final class CircleOverlayView: NSView {
    private var radius: Double

    init(radius: Double) {
        self.radius = radius
        let size = CGFloat(radius * 2 + 40)
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        self.radius = 100
        super.init(coder: coder)
    }

    func updateRadius(_ newRadius: Double) {
        self.radius = newRadius
        let size = CGFloat(newRadius * 2 + 40)
        self.setFrameSize(NSSize(width: size, height: size))
        self.needsDisplay = true
        self.superview?.needsLayout = true
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = CGFloat(radius)
        let cx = bounds.midX
        let cy = bounds.midY

        // Outer glow
        let glow = NSBezierPath(ovalIn: CGRect(
            x: cx - r - 10, y: cy - r - 10,
            width: (r + 10) * 2, height: (r + 10) * 2
        ))
        NSColor(cgColor: CGColor(red: 0.2, green: 0.55, blue: 1.0, alpha: 0.12))?.setFill()
        glow.fill()

        // Main circle fill
        let circle = NSBezierPath(ovalIn: CGRect(
            x: cx - r, y: cy - r,
            width: r * 2, height: r * 2
        ))
        NSColor(cgColor: CGColor(red: 0.15, green: 0.5, blue: 1.0, alpha: 0.2))?.setFill()
        circle.fill()

        // Circle stroke
        let strokeColor = NSColor(cgColor: CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.85))!
        strokeColor.setStroke()
        circle.lineWidth = 2
        circle.stroke()

        // Crosshair lines
        let chLen: CGFloat = 14
        let chWidth: CGFloat = 1.5
        let crosshairColor = NSColor(cgColor: CGColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.7))!
        crosshairColor.setStroke()

        let hLine = NSBezierPath()
        hLine.move(to: CGPoint(x: cx - chLen, y: cy))
        hLine.line(to: CGPoint(x: cx + chLen, y: cy))
        hLine.lineWidth = chWidth
        hLine.stroke()

        let vLine = NSBezierPath()
        vLine.move(to: CGPoint(x: cx, y: cy - chLen))
        vLine.line(to: CGPoint(x: cx, y: cy + chLen))
        vLine.lineWidth = chWidth
        vLine.stroke()

        // Center dot
        let dot = NSBezierPath(ovalIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
        NSColor(cgColor: CGColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.95))?.setFill()
        dot.fill()

        // Radius label above circle
        let label = "r=\(Int(radius))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.85),
        ]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let labelSize = attrStr.size()
        attrStr.draw(at: CGPoint(x: cx - labelSize.width / 2, y: cy + r + 6))
    }
}
