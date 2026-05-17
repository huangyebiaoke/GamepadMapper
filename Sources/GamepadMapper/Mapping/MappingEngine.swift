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
    /// Tracks which mouse buttons are held via mouseMove combo (stick-based drag). Protected by lock.
    private var comboDragButtons: Set<MouseButton> = []

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
    /// Whether any combo drag entry was active this frame (for post-poll release).
    private var comboDragActiveThisFrame: Bool = false
    /// Whether we already snapped cursor to boundary center during the current drag session.
    private var hasSnappedToCenter: Bool = false
    /// Frame counter for analog key repeat. Re-send key-down every N polls to simulate
    /// a continuously-held key, since CGEvent doesn't trigger macOS auto-repeat.
    private var keyRepeatFrameCount: Int = 0

    private init() {
        self.eventSource = CGEventSource(stateID: .privateState)!
    }

    // MARK: - Start / Stop

    func start() {
        // Grab state from main-thread singletons, then start on background queue.
        Task { @MainActor in
            let hid = HIDGamepadReader.shared
            hid.start()
            // Keep GameControllerManager for UI status display
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

        let startMsg = "startOnQueue: entries=\(entries.count)"
        EngineLogger.clear()
        EngineLogger.log(startMsg)

        // Prevent App Nap
        activityAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Gamepad polling requires real-time response"
        )

        // DispatchSourceTimer fires on this background queue — no main actor hop needed.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .nanoseconds(0))

        var pollCount = 0
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            pollCount += 1

            self.poll()
        }
        timer.resume()
        pollTimer = timer

        Task { @MainActor in
            isActive = true
        }

        NSLog("[MappingEngine] Started on background queue. Entries: \(entries.count)")
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        EngineLogger.log("STOP called")
        lock.lock()
        defer { lock.unlock() }

        pollTimer?.cancel()
        pollTimer = nil
        trackedCursorPos = nil
        releaseAllKeysLocked()
        releaseAllMouseButtonsLocked()
        keyRepeatFrameCount = 0
        cachedEntries = []

        if let assertion = activityAssertion {
            ProcessInfo.processInfo.endActivity(assertion)
            activityAssertion = nil
        }

        Task { @MainActor in
            isActive = false
            // Don't stop HID reader or GameControllerManager — they should
            // stay connected so the user can start mapping again without
            // reconnecting the controller.
        }
    }

    /// Call from main thread when the active profile changes.
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

    // MARK: - Polling (runs on background queue, no @MainActor)

    private func poll() {
        lock.lock()
        defer { lock.unlock() }

        guard pollTimer != nil else { return }
        guard !cachedEntries.isEmpty else { return }

        let hid = HIDGamepadReader.shared
        let sensitivity = cachedSensitivity
        let entries = cachedEntries
        let boundary = cachedBoundary

        stickMovedThisFrame = false
        comboDragActiveThisFrame = false

        for entry in entries {
            let value = hid.value(for: entry.source)
            if entry.source.isAnalog {
                processAnalogMappingLocked(value: value, entry: entry, sensitivity: sensitivity)
            } else {
                processButtonMappingLocked(value: value, entry: entry)
            }
        }

        // Stick-level combo drag: check overall stick displacement, not per-axis.
        // When a stick has mouseDrag combo targets, activate if the stick is displaced
        // in ANY direction, release only when the stick returns to center.
        processStickComboDragsLocked(hid: hid, entries: entries)

        // Key repeat: CGEvent key-down does NOT trigger macOS auto-repeat.
        // Re-send key-down for all currently-held keys every ~100ms so that
        // analog→key mappings produce continuous output while the stick is held.
        keyRepeatFrameCount += 1
        if keyRepeatFrameCount >= 12 {
            keyRepeatFrameCount = 0
            for keyCode in activeKeys {
                if let event = CGEvent(
                    keyboardEventSource: eventSource,
                    virtualKey: keyCode,
                    keyDown: true
                ) {
                    event.post(tap: .cghidEventTap)
                }
            }
        }

        // Snap-to-center: if drag is active but stick is neutral, warp cursor
        // back to the boundary center so the next direction starts from center.
        let isDragging = !activeDragButtons.isEmpty
        if isDragging {
            if !stickMovedThisFrame {
                if !hasSnappedToCenter, let boundary = boundary {
                    snapCursorToBoundaryCenter(boundary)
                    hasSnappedToCenter = true
                }
            } else {
                hasSnappedToCenter = false
            }
        } else {
            hasSnappedToCenter = false
        }

        // Combo drag cleanup: release any combo drag buttons that were NOT active this frame.
        // This handles the case where the stick returns to neutral — all combo entries
        // stop moving, so we release the buttons.
        let comboToRelease = comboDragButtons.filter { btn in
            !comboDragActiveThisFrame
        }
        for btn in comboToRelease {
            activeDragButtons.remove(btn)
            comboDragButtons.remove(btn)
            postMouseEvent(button: btn, down: false)
        }
    }

    // MARK: - Fire Single Target (lock must be held)

    /// Fire a single MappingTarget (press or release). Lock must be held.
    private func fireTarget(_ target: MappingTarget, down: Bool) {
        switch target {
        case .key(let keyCode):
            let isDown = activeKeys.contains(keyCode)
            if down && !isDown {
                postKeyEvent(keyCode: keyCode, down: true)
            } else if !down && isDown {
                postKeyEvent(keyCode: keyCode, down: false)
            }

        case .mouseButton(let btn):
            let isDown = activeMouseButtons.contains(btn)
            if down && !isDown {
                postMouseEvent(button: btn, down: true)
            } else if !down && isDown {
                postMouseEvent(button: btn, down: false)
            }

        case .mouseDrag(let btn):
            let isDown = activeDragButtons.contains(btn)
            if down && !isDown {
                postMouseEvent(button: btn, down: true)
                activeDragButtons.insert(btn)
            } else if !down && isDown {
                activeDragButtons.remove(btn)
                postMouseEvent(button: btn, down: false)
            }

        case .mouseMove:
            break
        }
    }

    // MARK: - Binary Button Mapping (lock must be held)

    private func processButtonMappingLocked(value: Float, entry: MappingEntry) {
        let isPressed = value > 0.5

        // Collect all targets: main + combos
        var allTargets: [MappingTarget] = []
        if let target = entry.target {
            allTargets.append(target)
        }
        allTargets.append(contentsOf: entry.comboTargets)

        guard !allTargets.isEmpty else { return }

        for target in allTargets {
            fireTarget(target, down: isPressed)
        }
    }

    // MARK: - Analog Mapping (lock must be held)

    private func processAnalogMappingLocked(value: Float, entry: MappingEntry, sensitivity: Float) {
        if let target = entry.target {
            switch target {
            case .key(let keyCode):
                processAnalogToKeyLocked(value: value, keyCode: keyCode, entry: entry)

            case .mouseButton(let btn):
                processAnalogToMouseButtonLocked(value: value, button: btn, threshold: entry.analogThreshold)

            case .mouseDrag(let btn):
                processAnalogToMouseDragLocked(value: value, button: btn, threshold: entry.analogThreshold)

            case .mouseMove:
                processAnalogToMouseMoveLocked(value: value, entry: entry, sensitivity: sensitivity)
            }
        }

        // Fire combo targets using the same analog activation logic
        processAnalogComboTargetsLocked(value: value, entry: entry)
    }

    // MARK: - Analog → Combo Targets (lock must be held)

    private func processAnalogComboTargetsLocked(value: Float, entry: MappingEntry) {
        guard !entry.comboTargets.isEmpty else { return }

        // For stick sources, mouseDrag combo targets are handled at the poll level
        // using overall stick magnitude (processStickComboDragsLocked). Skip them here
        // to prevent incorrect per-axis activation.
        let hasMouseDragCombo = entry.comboTargets.contains { target in
            if case .mouseDrag = target { true } else { false }
        }
        let isStickSource = entry.source == .leftStickX || entry.source == .leftStickY
            || entry.source == .rightStickX || entry.source == .rightStickY
            || entry.source == .leftThumbstickButton || entry.source == .rightThumbstickButton

        if hasMouseDragCombo && isStickSource {
            // Only process non-mouseDrag combo targets for this entry
            for comboTarget in entry.comboTargets {
                if case .mouseDrag = comboTarget { continue }
                fireTarget(comboTarget, down: isAnalogComboActive(value: value, entry: entry))
            }
            return
        }

        let isActive = isAnalogComboActive(value: value, entry: entry)
        for comboTarget in entry.comboTargets {
            fireTarget(comboTarget, down: isActive)
            if case .mouseDrag = comboTarget, isActive {
                comboDragActiveThisFrame = true
            }
        }
    }

    /// Determine if a combo target should be active based on analog value and entry direction.
    /// Always uses the entry's specific direction/deadzone — each mapping entry owns its combos.
    private func isAnalogComboActive(value: Float, entry: MappingEntry) -> Bool {
        switch entry.direction {
        case .positive:
            return value > entry.deadzone
        case .negative:
            return value < -entry.deadzone
        }
    }

    // MARK: - Stick-Level Combo Drags (lock must be held)

    /// Process mouseDrag combo targets for stick entries based on overall stick displacement.
    /// Each stick (left/right) is evaluated as a whole: if ANY axis is beyond deadzone,
    /// the combo drag stays active. Release only happens when the stick returns to center.
    private func processStickComboDragsLocked(hid: HIDGamepadReader, entries: [MappingEntry]) {
        let leftStickX = hid.value(for: .leftStickX)
        let leftStickY = hid.value(for: .leftStickY)
        let leftMagnitude = sqrt(leftStickX * leftStickX + leftStickY * leftStickY)

        let rightStickX = hid.value(for: .rightStickX)
        let rightStickY = hid.value(for: .rightStickY)
        let rightMagnitude = sqrt(rightStickX * rightStickX + rightStickY * rightStickY)

        for entry in entries {
            guard entry.source.isAnalog else { continue }

            // Only handle stick sources (not triggers)
            let magnitude: Float
            switch entry.source {
            case .leftStickX, .leftStickY, .leftThumbstickButton:
                magnitude = leftMagnitude
            case .rightStickX, .rightStickY, .rightThumbstickButton:
                magnitude = rightMagnitude
            default: continue
            }

            // Use the entry's deadzone to determine "stick is displaced"
            let isActive = magnitude > entry.deadzone
            if isActive { comboDragActiveThisFrame = true }

            // Fire mouseDrag combo targets based on overall stick magnitude
            for comboTarget in entry.comboTargets {
                if case .mouseDrag = comboTarget {
                    fireTarget(comboTarget, down: isActive)
                }
            }
        }
    }

    // MARK: - Analog → Key (lock must be held)

    private func processAnalogToKeyLocked(value: Float, keyCode: CGKeyCode, entry: MappingEntry) {
        let shouldPress: Bool
        switch entry.direction {
        case .positive:
            shouldPress = value > entry.deadzone
        case .negative:
            shouldPress = value < -entry.deadzone
        }

        let isPressed = activeKeys.contains(keyCode)
        if shouldPress && !isPressed {
            postKeyEvent(keyCode: keyCode, down: true)
        } else if !shouldPress && isPressed {
            postKeyEvent(keyCode: keyCode, down: false)
        }
    }

    // MARK: - Analog → Mouse Button (lock must be held)

    private func processAnalogToMouseButtonLocked(value: Float, button: MouseButton, threshold: Float) {
        let shouldPress = value > threshold
        let isPressed = activeMouseButtons.contains(button)

        if shouldPress && !isPressed {
            postMouseEvent(button: button, down: true)
        } else if !shouldPress && isPressed {
            postMouseEvent(button: button, down: false)
        }
    }

    // MARK: - Analog → Mouse Drag (lock must be held)

    private func processAnalogToMouseDragLocked(value: Float, button: MouseButton, threshold: Float) {
        let shouldPress = value > threshold
        let isPressed = activeDragButtons.contains(button)

        if shouldPress && !isPressed {
            postMouseEvent(button: button, down: true)
            activeDragButtons.insert(button)
        } else if !shouldPress && isPressed {
            activeDragButtons.remove(button)
            postMouseEvent(button: button, down: false)
        }
    }

    // MARK: - Analog → Mouse Move (lock must be held)

    private func processAnalogToMouseMoveLocked(value: Float, entry: MappingEntry, sensitivity: Float) {
        let isMoving: Bool
        switch entry.direction {
        case .positive:
            isMoving = value > entry.deadzone
        case .negative:
            isMoving = value < -entry.deadzone
        }

        // Handle combo drag button: activate when stick moves, release when neutral.
        if let comboBtn = entry.mouseMoveCombo {
            let btnIsDown = comboDragButtons.contains(comboBtn)
            if isMoving && !btnIsDown {
                postMouseEvent(button: comboBtn, down: true)
                activeDragButtons.insert(comboBtn)
                comboDragButtons.insert(comboBtn)
            } else if !isMoving && btnIsDown {
                activeDragButtons.remove(comboBtn)
                comboDragButtons.remove(comboBtn)
                postMouseEvent(button: comboBtn, down: false)
            }
            if isMoving {
                comboDragActiveThisFrame = true
            }
        }

        guard isMoving else { return }

        let absValue = abs(value)
        let deadzone = entry.deadzone
        let normalized = Float((Double(absValue) - Double(deadzone)) / (1.0 - Double(deadzone)))
        let delta = normalized * sensitivity

        var deltaX: Float = 0
        var deltaY: Float = 0

        switch entry.source {
        case .rightStickX, .leftStickX:
            deltaX = delta * (value > 0 ? 1 : -1)
        case .rightStickY, .leftStickY:
            // Flip Y axis: HID reports positive=up but screen Y is positive=down
            deltaY = delta * (value > 0 ? 1 : -1)
        default:
            break
        }

        if deltaX != 0 || deltaY != 0 {
            stickMovedThisFrame = true
            postMouseMove(deltaX: deltaX, deltaY: deltaY)
        }
    }

    // MARK: - CGEvent: Keyboard (called from background queue)

    private func postKeyEvent(keyCode: CGKeyCode, down: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: down
        ) else {
            EngineLogger.log("FAILED to create CGEvent for key \(keyCode)")
            return
        }

        if down, let character = unicodeCharacter(for: keyCode) {
            let utf16 = Array(character.utf16)
            utf16.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
            }
        }

        event.flags = cgEventFlags(for: keyCode)
        event.post(tap: .cghidEventTap)
        EngineLogger.log("Key \(down ? "DOWN" : "UP") code=\(keyCode)")

        if down {
            activeKeys.insert(keyCode)
        } else {
            activeKeys.remove(keyCode)
        }
    }

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

    // MARK: - CGEvent: Mouse Button (called from background queue)

    private func postMouseEvent(button: MouseButton, down: Bool) {
        let mouseType: CGEventType
        switch (button, down) {
        case (.left, true): mouseType = .leftMouseDown
        case (.left, false): mouseType = .leftMouseUp
        case (.right, true): mouseType = .rightMouseDown
        case (.right, false): mouseType = .rightMouseUp
        case (.center, true): mouseType = .otherMouseDown
        case (.center, false): mouseType = .otherMouseUp
        }

        // Use tracked cursor position when available to avoid jumps between
        // warp-based moves and button down/up events. Caller holds the lock.
        let mousePos: CGPoint
        if let tracked = trackedCursorPos {
            mousePos = tracked
        } else if let mouseEvent = CGEvent(source: eventSource) {
            mousePos = mouseEvent.location
        } else {
            mousePos = .zero
        }

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: mouseType,
            mouseCursorPosition: mousePos,
            mouseButton: button.cgMouseButton
        ) else {
            EngineLogger.log("FAILED to create mouse event for \(button.rawValue)")
            return
        }

        event.post(tap: .cghidEventTap)
        EngineLogger.log("Mouse \(down ? "DOWN" : "UP") \(button.rawValue)")

        if down {
            activeMouseButtons.insert(button)
        } else {
            activeMouseButtons.remove(button)
        }
    }

    // MARK: - CGEvent: Mouse Move (called from background queue, lock must be held)

    private func postMouseMove(deltaX: Float, deltaY: Float) {
        frameCount += 1
        let shouldSync = frameCount % 60 == 0

        let currentPos: CGPoint
        if let tracked = trackedCursorPos, !shouldSync {
            currentPos = tracked
        } else {
            if let mouseEvent = CGEvent(source: eventSource) {
                currentPos = mouseEvent.location
            } else {
                currentPos = trackedCursorPos ?? .zero
            }
            trackedCursorPos = currentPos
        }

        let newPos = CGPoint(
            x: currentPos.x + Double(deltaX),
            y: currentPos.y + Double(deltaY)
        )

        CGWarpMouseCursorPosition(newPos)
        trackedCursorPos = newPos

        // Clamp to drag boundary when dragging.
        let clampedPos: CGPoint
        if !activeDragButtons.isEmpty, let boundary = cachedBoundary {
            let dx = newPos.x - boundary.centerX
            let dy = newPos.y - boundary.centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist > boundary.radius {
                let scale = boundary.radius / dist
                clampedPos = CGPoint(
                    x: boundary.centerX + dx * scale,
                    y: boundary.centerY + dy * scale
                )
                CGWarpMouseCursorPosition(clampedPos)
                trackedCursorPos = clampedPos
            } else {
                clampedPos = newPos
            }
        } else {
            clampedPos = newPos
        }

        // If a drag button is held, post a drag event instead of a plain move.
        let dragBtn = activeDragButtons.first
        let eventType: CGEventType
        switch dragBtn {
        case .left: eventType = .leftMouseDragged
        case .right: eventType = .rightMouseDragged
        case .center: eventType = .otherMouseDragged
        case nil: eventType = .mouseMoved
        }

        if let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: clampedPos,
            mouseButton: dragBtn?.cgMouseButton ?? .left
        ) {
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64(deltaX))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64(deltaY))
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Drag Boundary (lock must be held)

    private func snapCursorToBoundaryCenter(_ boundary: DragBoundary) {
        let center = CGPoint(x: boundary.centerX, y: boundary.centerY)
        CGWarpMouseCursorPosition(center)
        trackedCursorPos = center

        let dragBtn = activeDragButtons.first
        let eventType: CGEventType
        switch dragBtn {
        case .left: eventType = .leftMouseDragged
        case .right: eventType = .rightMouseDragged
        case .center: eventType = .otherMouseDragged
        case nil: eventType = .mouseMoved
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

        EngineLogger.log("SNAP cursor to boundary center (\(Int(boundary.centerX)), \(Int(boundary.centerY)))")
    }

    // MARK: - Cleanup (lock must be held)

    private func releaseAllKeysLocked() {
        for keyCode in activeKeys {
            if let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: keyCode,
                keyDown: false
            ) {
                event.post(tap: .cghidEventTap)
            }
        }
        activeKeys.removeAll()
    }

    private func releaseAllMouseButtonsLocked() {
        for button in activeMouseButtons {
            postMouseEvent(button: button, down: false)
        }
        activeMouseButtons.removeAll()
        for button in activeDragButtons {
            postMouseEvent(button: button, down: false)
        }
        activeDragButtons.removeAll()
        comboDragButtons.removeAll()
    }

    // MARK: - NSPoint Extension

}

private extension NSPoint {
    var flipped: CGPoint {
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGPoint(x: x, y: screenFrame.height - y)
    }
}
