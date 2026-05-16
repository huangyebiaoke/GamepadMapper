@preconcurrency import AppKit
import CoreGraphics
import Foundation
import Observation

/// Translates gamepad state changes into keyboard and mouse events via CGEvent.
/// Runs entirely on a background thread to ensure reliable operation even when
/// the app is in the background and the main run loop is idle.
@Observable
final class MappingEngine {
    static let shared = MappingEngine()

    private let queue = DispatchQueue(label: "com.gamepadmapper.engine", qos: .userInteractive)

    /// Published on main thread for UI binding.
    @MainActor var isActive = false

    /// Cached profile entries for background polling. Updated from main thread.
    private var cachedEntries: [MappingEntry] = []
    private var cachedSensitivity: Float = 15.0
    private var cachedBoundary: DragBoundary?

    private let eventSource: CGEventSource

    /// Tracks which keys are currently held down. Protected by lock.
    private var activeKeys: Set<CGKeyCode> = []
    /// Tracks which mouse buttons are currently held down (click mappings). Protected by lock.
    private var activeMouseButtons: Set<MouseButton> = []
    /// Tracks which mouse buttons are held as drag anchors. Protected by lock.
    private var activeDragButtons: Set<MouseButton> = []

    /// Protects mutable state accessed from the background poll queue.
    private let lock = NSLock()

    private var pollTimer: DispatchSourceTimer?
    private var activityAssertion: NSObjectProtocol?

    /// Tracks the cursor position we set via CGWarpMouseCursorPosition.
    private var trackedCursorPos: CGPoint?
    /// Frame counter for periodic cursor re-sync.
    private var frameCount: Int = 0
    /// Whether any analog → mouseMove delta was produced this poll frame.
    private var stickMovedThisFrame: Bool = false
    /// Whether we already snapped cursor to boundary center during the current drag session.
    private var hasSnappedToCenter: Bool = false

    /// Actions to perform after releasing the lock.
    private enum OutputAction {
        case keyDown(CGKeyCode)
        case keyUp(CGKeyCode)
        case mouseDown(MouseButton, cursorPos: CGPoint)
        case mouseUp(MouseButton, cursorPos: CGPoint)
        case mouseMove(Float, Float)
        case warpCursor(CGPoint)
    }

    private init() {
        self.eventSource = CGEventSource(stateID: .privateState)!
    }

    // MARK: - Start / Stop

    func start() {
        Task { @MainActor in
            let hid = HIDGamepadReader.shared
            hid.start()
            GameControllerManager.shared.startMonitoring()

            let pm = ProfileManager.shared
            let entries = pm.activeProfile?.entries ?? []
            let sensitivity = Float(pm.activeProfile?.mouseSensitivity ?? 15.0)
            let boundary = pm.activeProfile?.dragBoundary

            queue.async { [weak self] in
                self?.startOnQueue(entries: entries, sensitivity: sensitivity, boundary: boundary)
            }
        }
    }

    private func startOnQueue(entries: [MappingEntry], sensitivity: Float, boundary: DragBoundary?) {
        lock.lock()
        defer { lock.unlock() }

        guard pollTimer == nil else { return }

        cachedEntries = entries
        cachedSensitivity = sensitivity
        cachedBoundary = boundary

        EngineLogger.clear()
        EngineLogger.log("startOnQueue: entries=\(entries.count)")

        activityAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Gamepad polling requires real-time response"
        )

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        pollTimer = timer

        Task { @MainActor in
            isActive = true
        }

        NSLog("[MappingEngine] Started. Entries: \(entries.count)")
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        EngineLogger.log("STOP called")

        let currentMousePos: CGPoint
        if let mouseEvent = CGEvent(source: eventSource) {
            currentMousePos = mouseEvent.location
        } else {
            currentMousePos = .zero
        }

        lock.lock()
        pollTimer?.cancel()
        pollTimer = nil
        trackedCursorPos = nil

        let keysToRelease = activeKeys
        activeKeys.removeAll()
        let mouseButtonsToRelease = activeMouseButtons
        activeMouseButtons.removeAll()
        let dragButtonsToRelease = activeDragButtons
        activeDragButtons.removeAll()
        cachedEntries = []

        if let assertion = activityAssertion {
            ProcessInfo.processInfo.endActivity(assertion)
            activityAssertion = nil
        }
        lock.unlock()

        for keyCode in keysToRelease {
            if let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: keyCode,
                keyDown: false
            ) {
                event.post(tap: .cghidEventTap)
            }
        }
        for button in mouseButtonsToRelease {
            releaseMouse(button: button, cursorPos: currentMousePos)
        }
        for button in dragButtonsToRelease {
            releaseMouse(button: button, cursorPos: currentMousePos)
        }

        Task { @MainActor in
            isActive = false
            HIDGamepadReader.shared.stop()
            GameControllerManager.shared.stopMonitoring()
        }
    }

    private func releaseMouse(button: MouseButton, cursorPos: CGPoint) {
        let mouseType: CGEventType = switch button {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        case .center: .otherMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: mouseType,
            mouseCursorPosition: cursorPos,
            mouseButton: button.cgMouseButton
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    @MainActor
    func refreshProfileCache() {
        let pm = ProfileManager.shared
        let entries = pm.activeProfile?.entries ?? []
        let sensitivity = Float(pm.activeProfile?.mouseSensitivity ?? 15.0)
        let boundary = pm.activeProfile?.dragBoundary
        queue.async { [weak self] in
            self?.lock.lock()
            defer { self?.lock.unlock() }
            self?.cachedEntries = entries
            self?.cachedSensitivity = sensitivity
            self?.cachedBoundary = boundary
        }
    }

    // MARK: - Polling (runs on background queue)

    /// Two-phase poll: compute state changes under lock, post CGEvents outside.
    /// This prevents CGEvent.post latency from blocking the lock and starving stopOnQueue().
    private func poll() {
        var actions: [OutputAction] = []
        var snapCenter: CGPoint?

        lock.lock()

        guard pollTimer != nil, !cachedEntries.isEmpty else {
            lock.unlock()
            return
        }

        let hid = HIDGamepadReader.shared
        let sensitivity = cachedSensitivity
        let entries = cachedEntries
        let boundary = cachedBoundary
        stickMovedThisFrame = false

        // Phase 1: compute state changes and collect actions under lock.
        for entry in entries {
            let value = hid.value(for: entry.source)
            if entry.source.isAnalog {
                computeAnalogActions(value: value, entry: entry, sensitivity: sensitivity, actions: &actions)
            } else {
                computeButtonActions(value: value, entry: entry, actions: &actions)
            }
        }

        // Drag snap-to-center.
        if !activeDragButtons.isEmpty {
            if !stickMovedThisFrame {
                if !hasSnappedToCenter, let boundary = boundary {
                    snapCenter = CGPoint(x: boundary.centerX, y: boundary.centerY)
                    trackedCursorPos = snapCenter
                    hasSnappedToCenter = true
                }
            } else {
                hasSnappedToCenter = false
            }
        } else {
            hasSnappedToCenter = false
        }

        lock.unlock()

        // Phase 2: post all CGEvents OUTSIDE the lock.
        // snapCenter warp must happen before other mouse actions.
        if let center = snapCenter {
            CGWarpMouseCursorPosition(center)
            postSnapDrag(center: center)
        }

        dispatchActions(actions)
    }

    // MARK: - Phase 1: Compute actions (called under lock)

    private func computeButtonActions(value: Float, entry: MappingEntry, actions: inout [OutputAction]) {
        guard let target = entry.target else { return }
        let isPressed = value > 0.5

        switch target {
        case .key(let keyCode):
            let keyIsDown = activeKeys.contains(keyCode)
            if isPressed, !keyIsDown {
                activeKeys.insert(keyCode)
                actions.append(.keyDown(keyCode))
            } else if !isPressed, keyIsDown {
                activeKeys.remove(keyCode)
                actions.append(.keyUp(keyCode))
            }

        case .mouseButton(let btn):
            let btnIsDown = activeMouseButtons.contains(btn)
            let pos = mousePositionForAction()
            if isPressed, !btnIsDown {
                activeMouseButtons.insert(btn)
                actions.append(.mouseDown(btn, cursorPos: pos))
            } else if !isPressed, btnIsDown {
                activeMouseButtons.remove(btn)
                actions.append(.mouseUp(btn, cursorPos: pos))
            }

        case .mouseDrag(let btn):
            let btnIsDown = activeDragButtons.contains(btn)
            let pos = mousePositionForAction()
            if isPressed, !btnIsDown {
                activeDragButtons.insert(btn)
                actions.append(.mouseDown(btn, cursorPos: pos))
            } else if !isPressed, btnIsDown {
                activeDragButtons.remove(btn)
                actions.append(.mouseUp(btn, cursorPos: pos))
            }

        case .mouseMove:
            break
        }
    }

    private func computeAnalogActions(value: Float, entry: MappingEntry, sensitivity: Float, actions: inout [OutputAction]) {
        guard let target = entry.target else { return }

        switch target {
        case .key(let keyCode):
            let shouldPress: Bool
            switch entry.direction {
            case .positive: shouldPress = value > entry.deadzone
            case .negative: shouldPress = value < -entry.deadzone
            }
            let isPressed = activeKeys.contains(keyCode)
            if shouldPress, !isPressed {
                activeKeys.insert(keyCode)
                actions.append(.keyDown(keyCode))
            } else if !shouldPress, isPressed {
                activeKeys.remove(keyCode)
                actions.append(.keyUp(keyCode))
            }

        case .mouseButton(let btn):
            let shouldPress = value > entry.analogThreshold
            let isPressed = activeMouseButtons.contains(btn)
            let pos = mousePositionForAction()
            if shouldPress, !isPressed {
                activeMouseButtons.insert(btn)
                actions.append(.mouseDown(btn, cursorPos: pos))
            } else if !shouldPress, isPressed {
                activeMouseButtons.remove(btn)
                actions.append(.mouseUp(btn, cursorPos: pos))
            }

        case .mouseDrag(let btn):
            let shouldDrag = value > entry.analogThreshold
            let isDragging = activeDragButtons.contains(btn)
            let pos = mousePositionForAction()
            if shouldDrag, !isDragging {
                activeDragButtons.insert(btn)
                actions.append(.mouseDown(btn, cursorPos: pos))
            } else if !shouldDrag, isDragging {
                activeDragButtons.remove(btn)
                actions.append(.mouseUp(btn, cursorPos: pos))
            }

        case .mouseMove:
            computeMouseMove(value: value, entry: entry, sensitivity: sensitivity, actions: &actions)
        }
    }

    private func computeMouseMove(value: Float, entry: MappingEntry, sensitivity: Float, actions: inout [OutputAction]) {
        switch entry.direction {
        case .positive: guard value > entry.deadzone else { return }
        case .negative: guard value < -entry.deadzone else { return }
        }

        let absValue = abs(value)
        let normalized = Float((Double(absValue) - Double(entry.deadzone)) / (1.0 - Double(entry.deadzone)))
        let delta = normalized * sensitivity

        var dx: Float = 0, dy: Float = 0
        switch entry.source {
        case .rightStickX, .leftStickX:
            dx = delta * (value > 0 ? 1 : -1)
        case .rightStickY, .leftStickY:
            dy = delta * (value > 0 ? 1 : -1)
        default:
            break
        }

        if dx != 0 || dy != 0 {
            stickMovedThisFrame = true
            actions.append(.mouseMove(dx, dy))
        }
    }

    /// Get cursor position for mouse button actions. Called under lock.
    private func mousePositionForAction() -> CGPoint {
        if let tracked = trackedCursorPos { return tracked }
        if let event = CGEvent(source: eventSource) { return event.location }
        return .zero
    }

    // MARK: - Phase 2: Dispatch actions (called OUTSIDE lock)

    private func dispatchActions(_ actions: [OutputAction]) {
        for action in actions {
            switch action {
            case .keyDown(let code):
                postKeyDown(code: code)
            case .keyUp(let code):
                postKeyUp(code: code)
            case .mouseDown(let btn, let pos):
                postMouseButtonDown(btn, at: pos)
            case .mouseUp(let btn, let pos):
                postMouseButtonUp(btn, at: pos)
            case .mouseMove(let dx, let dy):
                postMouseMoveAction(dx: dx, dy: dy)
            case .warpCursor(let pos):
                CGWarpMouseCursorPosition(pos)
            }
        }
    }

    private func postKeyDown(code: CGKeyCode) {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: code,
            keyDown: true
        ) else { return }
        if let character = unicodeCharacter(for: code) {
            let utf16 = Array(character.utf16)
            utf16.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
            }
        }
        event.flags = cgEventFlags(for: code)
        event.post(tap: .cghidEventTap)
    }

    private func postKeyUp(code: CGKeyCode) {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: code,
            keyDown: false
        ) else { return }
        if let character = unicodeCharacter(for: code) {
            let utf16 = Array(character.utf16)
            utf16.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
            }
        }
        event.flags = cgEventFlags(for: code)
        event.post(tap: .cghidEventTap)
    }

    private func postMouseButtonDown(_ button: MouseButton, at pos: CGPoint) {
        let mouseType: CGEventType = switch button {
        case .left: .leftMouseDown
        case .right: .rightMouseDown
        case .center: .otherMouseDown
        }
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: mouseType,
            mouseCursorPosition: pos,
            mouseButton: button.cgMouseButton
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postMouseButtonUp(_ button: MouseButton, at pos: CGPoint) {
        let mouseType: CGEventType = switch button {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        case .center: .otherMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: mouseType,
            mouseCursorPosition: pos,
            mouseButton: button.cgMouseButton
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Post a mouse move/drag action. Tracks cursor position for subsequent mouse button events.
    private func postMouseMoveAction(dx: Float, dy: Float) {
        frameCount += 1
        let shouldSync = frameCount % 60 == 0

        let currentPos: CGPoint
        if let tracked = trackedCursorPos, !shouldSync {
            currentPos = tracked
        } else if let event = CGEvent(source: eventSource) {
            currentPos = event.location
            trackedCursorPos = currentPos
        } else {
            currentPos = trackedCursorPos ?? .zero
        }

        let newPos = CGPoint(x: currentPos.x + Double(dx), y: currentPos.y + Double(dy))
        CGWarpMouseCursorPosition(newPos)
        trackedCursorPos = newPos

        // Clamp to drag boundary when dragging.
        let finalPos: CGPoint
        if !activeDragButtons.isEmpty, let boundary = cachedBoundary {
            let ddx = newPos.x - boundary.centerX
            let ddy = newPos.y - boundary.centerY
            let dist = sqrt(ddx * ddx + ddy * ddy)
            if dist > boundary.radius {
                let scale = boundary.radius / dist
                finalPos = CGPoint(
                    x: boundary.centerX + ddx * scale,
                    y: boundary.centerY + ddy * scale
                )
                CGWarpMouseCursorPosition(finalPos)
                trackedCursorPos = finalPos
            } else {
                finalPos = newPos
            }
        } else {
            finalPos = newPos
        }

        let dragBtn = activeDragButtons.first
        let eventType: CGEventType = switch dragBtn {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        case .center: .otherMouseDragged
        case nil: .mouseMoved
        }

        if let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: finalPos,
            mouseButton: dragBtn?.cgMouseButton ?? .left
        ) {
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
            event.post(tap: .cghidEventTap)
        }
    }

    /// Post a zero-delta drag event after snapping cursor to boundary center.
    private func postSnapDrag(center: CGPoint) {
        let dragBtn = activeDragButtons.first
        let eventType: CGEventType = switch dragBtn {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        case .center: .otherMouseDragged
        case nil: .mouseMoved
        }
        if let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: center,
            mouseButton: dragBtn?.cgMouseButton ?? .left
        ) {
            event.setIntegerValueField(.mouseEventDeltaX, value: 0)
            event.setIntegerValueField(.mouseEventDeltaY, value: 0)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Helpers

    private func unicodeCharacter(for keyCode: CGKeyCode) -> String? {
        let charMap: [CGKeyCode: String] = [
            0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f",
            0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l",
            0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r",
            0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x",
            0x10: "y", 0x06: "z",
            0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
            0x31: " ", 0x24: "\r", 0x30: "\t",
        ]
        return charMap[keyCode]
    }

    private func cgEventFlags(for keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 0x38, 0x3C: return .maskShift
        case 0x3B, 0x3E: return .maskControl
        case 0x3A, 0x3D: return .maskAlternate
        case 0x37, 0x36: return .maskCommand
        default: return []
        }
    }
}

private extension NSPoint {
    var flipped: CGPoint {
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGPoint(x: x, y: screenFrame.height - y)
    }
}
