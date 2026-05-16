import AppKit
import SwiftUI

/// A borderless window with a translucent circle + crosshair.
final class DragBoundaryOverlayWindow: NSPanel {
    var onPositionChanged: ((CGPoint) -> Void)?
    var onClose: ((CGPoint) -> Void)?
    var onRadiusChanged: ((Double) -> Void)?

    private(set) var circleCenter: CGPoint = .zero
    var radius: Double

    private var circleView: CircleOverlayView?
    private var overlayContentView: NSView?

    private var dragState: DragState = .idle
    private enum DragState {
        case idle
        case moving(offsetX: Double, offsetY: Double)
        case resizing
    }

    private var displayLink: CVDisplayLink?

    init(initialCenter: CGPoint, radius: Double) {
        self.radius = radius
        self.circleCenter = initialCenter

        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = max(radius * 2 + 80, 200)
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
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true

        let flippedY = screenFrame.height - initialCenter.y
        let origin = CGPoint(
            x: initialCenter.x - panelSize / 2,
            y: flippedY - panelSize / 2
        )
        self.setFrameOrigin(origin)

        let contentView = NSView(frame: panelRect)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = contentView
        self.overlayContentView = contentView

        let circle = CircleOverlayView(radius: radius)
        circle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(circle)
        self.circleView = circle

        NSLayoutConstraint.activate([
            circle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

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

        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            closeBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            closeBtn.widthAnchor.constraint(equalToConstant: 22),
            closeBtn.heightAnchor.constraint(equalToConstant: 22),
        ])

        // Display link for continuous cursor + visual updates (doesn't rely on tracking areas)
        startDisplayLink()
    }

    deinit {
        stopDisplayLink()
    }

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let window = Unmanaged<DragBoundaryOverlayWindow>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { window.tick() }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(link, callback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    /// Called at display refresh rate to update cursor and visuals from current mouse position.
    private func tick() {
        guard NSScreen.main != nil else { return }
        let mousePos = NSEvent.mouseLocation
        // Check if mouse is inside our window bounds
        let windowScreenOrigin = self.frame.origin
        let localX = mousePos.x - windowScreenOrigin.x
        let localY = mousePos.y - windowScreenOrigin.y
        guard let cv = contentView, let circle = circleView else { return }
        // localX/localY are already in window-local coords (Y=0 at bottom = NSView coords)
        let viewPoint = circle.convert(CGPoint(x: localX, y: localY), from: cv)

        let ddx = Double(viewPoint.x - circle.bounds.midX)
        let ddy = Double(viewPoint.y - circle.bounds.midY)
        let dist = sqrt(ddx * ddx + ddy * ddy)
        let r = radius
        let edgeThreshold: Double = 10

        if dist > r + edgeThreshold {
            // Only reset cursor if we're not dragging
            if case .idle = dragState {
                NSCursor.arrow.set()
                circle.setMousePosition(nil)
            }
        } else if abs(dist - r) < edgeThreshold {
            if case .idle = dragState {
                NSCursor.resizeUpDown.set()
            }
            circle.setMousePosition(viewPoint)
        } else {
            if case .idle = dragState {
                NSCursor.openHand.set()
            }
            circle.setMousePosition(nil)
        }
    }

    func updateRadius(_ newRadius: Double) {
        self.radius = newRadius
        circleView?.updateRadius(newRadius)
        let oldCenter = CGPoint(x: self.frame.midX, y: self.frame.midY)
        let newPanelSize = max(newRadius * 2 + 80, 200)
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            captureAndClose()
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Mouse events (handled by the panel, works after any setFrameOrigin)

    override func mouseDown(with event: NSEvent) {
        guard let cv = contentView, let circle = circleView else { return }
        let viewPoint = cv.convert(event.locationInWindow, from: nil)

        // Check if hit the close button
        if let hitView = cv.hitTest(viewPoint), hitView is NSButton {
            super.mouseDown(with: event)
            return
        }

        let circlePoint = circle.convert(viewPoint, from: cv)
        let dx = circlePoint.x - circle.bounds.midX
        let dy = circlePoint.y - circle.bounds.midY
        let dist = sqrt(dx * dx + dy * dy)
        let r = CGFloat(radius)
        let edgeThreshold: CGFloat = 10

        if dist > r + edgeThreshold { return }

        if abs(dist - r) < edgeThreshold {
            dragState = .resizing
            circle.setMousePosition(circlePoint)
        } else {
            let sp = self.convertPoint(toScreen: event.locationInWindow)
            dragState = .moving(
                offsetX: sp.x - self.frame.origin.x,
                offsetY: sp.y - self.frame.origin.y
            )
            circle.setMousePosition(nil)
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch dragState {
        case .moving(let offX, let offY):
            let sp = self.convertPoint(toScreen: event.locationInWindow)
            self.setFrameOrigin(CGPoint(
                x: sp.x - offX,
                y: sp.y - offY
            ))
            NSCursor.closedHand.set()
        case .resizing:
            let screenDist = distanceToCircleCenter(event: event)
            let newRadius = max(20, min(300, screenDist))
            if abs(newRadius - radius) > 0.5 {
                radius = newRadius
                updateRadius(newRadius)
                onRadiusChanged?(newRadius)
                circleView?.setMousePosition(circleViewPoint(event: event))
            }
        case .idle:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasResizing: Bool
        if case .resizing = dragState { wasResizing = true } else { wasResizing = false }
        dragState = .idle
        if wasResizing {
            circleView?.setMousePosition(nil)
        }
        NSCursor.arrow.set()
    }

    private func distanceToCircleCenter(event: NSEvent) -> Double {
        guard let screen = NSScreen.main else { return 0 }
        let screenPoint = self.convertPoint(toScreen: event.locationInWindow)
        let flippedY = screen.frame.height - screenPoint.y
        let dx = screenPoint.x - circleCenter.x
        let dy = flippedY - circleCenter.y
        return sqrt(dx * dx + dy * dy)
    }

    private func circleViewPoint(event: NSEvent) -> CGPoint? {
        guard let circle = circleView, let cv = contentView else { return nil }
        let inCV = cv.convert(event.locationInWindow, from: nil)
        return circle.convert(inCV, from: cv)
    }
}

/// Draws the circle, crosshair, radius line with tick marks, and radius label.
final class CircleOverlayView: NSView {
    private var radius: Double
    private var mousePositionInView: CGPoint?

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

    func setMousePosition(_ point: CGPoint?) {
        mousePositionInView = point
        self.needsDisplay = true
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = CGFloat(radius)
        let cx = bounds.midX
        let cy = bounds.midY

        let blue = NSColor(cgColor: CGColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.7))!
        let blueBright = NSColor(cgColor: CGColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.95))!
        let blueDim = NSColor(cgColor: CGColor(red: 0.2, green: 0.55, blue: 1.0, alpha: 0.12))!

        let glow = NSBezierPath(ovalIn: CGRect(
            x: cx - r - 10, y: cy - r - 10,
            width: (r + 10) * 2, height: (r + 10) * 2
        ))
        blueDim.setFill()
        glow.fill()

        let circle = NSBezierPath(ovalIn: CGRect(
            x: cx - r, y: cy - r,
            width: r * 2, height: r * 2
        ))
        NSColor(cgColor: CGColor(red: 0.15, green: 0.5, blue: 1.0, alpha: 0.2))?.setFill()
        circle.fill()

        blue.setStroke()
        circle.lineWidth = 2
        circle.stroke()

        let chLen: CGFloat = 14
        blue.setStroke()
        let hLine = NSBezierPath()
        hLine.move(to: CGPoint(x: cx - chLen, y: cy))
        hLine.line(to: CGPoint(x: cx + chLen, y: cy))
        hLine.lineWidth = 1.5
        hLine.stroke()

        let vLine = NSBezierPath()
        vLine.move(to: CGPoint(x: cx, y: cy - chLen))
        vLine.line(to: CGPoint(x: cx, y: cy + chLen))
        vLine.lineWidth = 1.5
        vLine.stroke()

        let dot = NSBezierPath(ovalIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
        blueBright.setFill()
        dot.fill()

        if let mousePos = mousePositionInView {
            let dx = mousePos.x - cx
            let dy = mousePos.y - cy
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 5 {
                drawRadiusLine(cx: cx, cy: cy, r: r, mousePos: mousePos, dist: dist)
                drawRadiusLabel(cx: cx, cy: cy, mousePos: mousePos, dist: dist, r: r)
            }
        }
    }

    private func drawRadiusLine(cx: CGFloat, cy: CGFloat, r: CGFloat, mousePos: CGPoint, dist: CGFloat) {
        let dx = mousePos.x - cx
        let dy = mousePos.y - cy
        let ux = dx / dist
        let uy = dy / dist

        let edgeX = cx + ux * r
        let edgeY = cy + uy * r
        let line = NSBezierPath()
        line.move(to: CGPoint(x: cx, y: cy))
        line.line(to: CGPoint(x: edgeX, y: edgeY))
        NSColor(cgColor: CGColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.5))?.setStroke()
        line.lineWidth = 1.2
        line.stroke()

        let px = -uy
        let py = ux
        let tickColor = NSColor(cgColor: CGColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.45))!
        tickColor.setStroke()

        let interval: CGFloat = 20
        let majorInterval: CGFloat = 50
        var d: CGFloat = interval
        while d < r - 5 {
            let isMajor = Int(round(d)) % Int(majorInterval) == 0
            let halfLen = isMajor ? CGFloat(4) : CGFloat(2)

            let tcx = cx + ux * d
            let tcy = cy + uy * d

            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: tcx + px * halfLen, y: tcy + py * halfLen))
            tick.line(to: CGPoint(x: tcx - px * halfLen, y: tcy - py * halfLen))
            tick.lineWidth = isMajor ? 1.2 : 0.8
            tick.stroke()

            d += interval
        }
    }

    private func drawRadiusLabel(cx: CGFloat, cy: CGFloat, mousePos: CGPoint, dist: CGFloat, r: CGFloat) {
        let dx = mousePos.x - cx
        let dy = mousePos.y - cy
        let ux = dx / dist
        let uy = dy / dist

        let labelX = cx + ux * r * 0.5
        let labelY = cy + uy * r * 0.5

        let label = "\(Int(radius))px"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.9),
        ]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let labelSize = attrStr.size()

        let pillRect = CGRect(
            x: labelX - labelSize.width / 2 - 6,
            y: labelY - labelSize.height / 2 - 3,
            width: labelSize.width + 12,
            height: labelSize.height + 6
        )
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
        NSColor(cgColor: CGColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.8))?.setFill()
        pill.fill()

        attrStr.draw(at: CGPoint(
            x: labelX - labelSize.width / 2,
            y: labelY - labelSize.height / 2
        ))
    }
}
