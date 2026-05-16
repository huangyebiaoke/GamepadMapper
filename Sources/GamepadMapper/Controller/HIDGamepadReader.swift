import Foundation
import IOKit.hid

/// Reads gamepad state directly from the HID layer using IOHIDManager.
/// Unlike GameController framework, IOHIDManager delivers input events even when
/// the app is in the background.
final class HIDGamepadReader: @unchecked Sendable {
    static let shared = HIDGamepadReader()

    struct State {
        var dpadUp: Float = 0
        var dpadDown: Float = 0
        var dpadLeft: Float = 0
        var dpadRight: Float = 0
        var buttonA: Float = 0
        var buttonB: Float = 0
        var buttonX: Float = 0
        var buttonY: Float = 0
        var leftShoulder: Float = 0
        var rightShoulder: Float = 0
        var leftThumbstickButton: Float = 0
        var rightThumbstickButton: Float = 0
        var leftStickX: Float = 0
        var leftStickY: Float = 0
        var rightStickX: Float = 0
        var rightStickY: Float = 0
        var leftTrigger: Float = 0
        var rightTrigger: Float = 0
    }

    private var manager: IOHIDManager?
    private let lock = NSLock()
    private var _state = State()
    private var isRunning = false
    private var isConnected = false
    private var deviceName = ""
    private var hidThread: Thread?
    private var hidRunLoop: CFRunLoop?

    /// Mapping from HID usage to state key path. Discovered per-device.
    /// Each entry stores (usagePage, usage) to prevent cross-page collisions.
    private var buttonMap: [(usagePage: UInt32, usage: UInt32, keyPath: WritableKeyPath<State, Float>)] = []
    private var axisMap: [(usagePage: UInt32, usage: UInt32, keyPath: WritableKeyPath<State, Float>, min: Int32, max: Int32)] = []
    /// True if the controller has individual D-pad buttons mapped (usage 11-14 on Button page).
    /// When true, the hat switch is ignored because its transitional values conflict with button state.
    private var hasIndividualDpadButtons = false

    private init() {}

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        isRunning = true

        // Start a dedicated background thread with its own run loop for HID events.
        // This ensures HID callbacks fire even when the main run loop is idle (app in background).
        let startSem = DispatchSemaphore(value: 0)
        hidThread = Thread { [weak self] in
            guard let self else { return }
            self.hidRunLoop = CFRunLoopGetCurrent()
            self.setupAndOpenManager()
            startSem.signal()
            CFRunLoopRun()
        }
        hidThread?.start()
        startSem.wait()
    }

    private func setupAndOpenManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let mgr = manager else {
            EngineLogger.log("HID: Failed to create IOHIDManager")
            return
        }

        // Match all gamepad/joystick devices
        let gamepadCriteria: CFArray = [
            createMatchingDict(page: UInt32(kHIDPage_GenericDesktop), usage: UInt32(kHIDUsage_GD_GamePad)),
            createMatchingDict(page: UInt32(kHIDPage_GenericDesktop), usage: UInt32(kHIDUsage_GD_Joystick)),
            createMatchingDict(page: UInt32(kHIDPage_GenericDesktop), usage: UInt32(kHIDUsage_GD_MultiAxisController)),
        ] as CFArray

        IOHIDManagerSetDeviceMatchingMultiple(mgr, gamepadCriteria)

        let inputCallback: IOHIDValueCallback = { context, result, sender, value in
            let reader = Unmanaged<HIDGamepadReader>.fromOpaque(context!).takeUnretainedValue()
            reader.handleInput(value: value)
        }

        let deviceCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let reader = Unmanaged<HIDGamepadReader>.fromOpaque(context!).takeUnretainedValue()
            reader.handleDeviceAdded(device: device)
        }

        let removalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let reader = Unmanaged<HIDGamepadReader>.fromOpaque(context!).takeUnretainedValue()
            reader.handleDeviceRemoved(device: device)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(mgr, inputCallback, selfPtr)
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, deviceCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, removalCallback, selfPtr)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

        EngineLogger.log("HID: Manager opened on background thread")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false

        if let mgr = manager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        _state = State()
        buttonMap = []
        axisMap = []
        hasIndividualDpadButtons = false
        deviceName = ""
        isConnected = false

        // Inline syncConnectionState body — caller already holds the lock.
        // syncConnectionState() calls lock.lock() again → NSLock is non-recursive → DEADLOCK.
        Task { @MainActor in
            GameControllerManager.shared.isConnected = false
            GameControllerManager.shared.controllerName = ""
        }

        if let rl = hidRunLoop {
            CFRunLoopStop(rl)
        }
        hidRunLoop = nil
        hidThread = nil
        EngineLogger.log("HID: Manager closed, thread stopped")
    }

    func getState() -> State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    func value(for element: ControllerElement) -> Float {
        let s = getState()
        switch element {
        case .dpadUp: return s.dpadUp
        case .dpadDown: return s.dpadDown
        case .dpadLeft: return s.dpadLeft
        case .dpadRight: return s.dpadRight
        case .buttonA: return s.buttonA
        case .buttonB: return s.buttonB
        case .buttonX: return s.buttonX
        case .buttonY: return s.buttonY
        case .leftShoulder: return s.leftShoulder
        case .rightShoulder: return s.rightShoulder
        case .leftThumbstickButton: return s.leftThumbstickButton
        case .rightThumbstickButton: return s.rightThumbstickButton
        case .leftStickX: return s.leftStickX
        case .leftStickY: return s.leftStickY
        case .rightStickX: return s.rightStickX
        case .rightStickY: return s.rightStickY
        case .leftTrigger: return s.leftTrigger
        case .rightTrigger: return s.rightTrigger
        }
    }

    // MARK: - Device Discovery

    private func handleDeviceAdded(device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        deviceName = name
        EngineLogger.log("HID: Device added: \(name)")

        // Enumerate all elements to build a mapping
        let elementsRef = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let elements = elementsRef else { return }
        let count = CFArrayGetCount(elements)

        for i in 0..<count {
            let element = unsafeBitCast(CFArrayGetValueAtIndex(elements, i), to: IOHIDElement.self)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let type = IOHIDElementGetType(element)

            guard type == kIOHIDElementTypeInput_Button || type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Axis else { continue }

            // Try to identify common gamepad elements and map them
            identifyElement(usagePage: usagePage, usage: usage, element: element)
        }

        EngineLogger.log("HID: Mapped \(self.buttonMap.count) buttons, \(self.axisMap.count) axes for \(name)")
        self.syncConnectionState(name: name, connected: true)
    }

    private func handleDeviceRemoved(device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        EngineLogger.log("HID: Device removed: \(name)")
        buttonMap = []
        axisMap = []
        hasIndividualDpadButtons = false
        _state = State()
        syncConnectionState(name: "", connected: false)
    }

    private func syncConnectionState(name: String, connected: Bool) {
        lock.lock()
        self.deviceName = name
        self.isConnected = connected
        lock.unlock()

        Task { @MainActor in
            GameControllerManager.shared.isConnected = connected
            GameControllerManager.shared.controllerName = name
        }
    }

    private func identifyElement(usagePage: UInt32, usage: UInt32, element: IOHIDElement) {
        let logMin = Int32(IOHIDElementGetLogicalMin(element))
        let logMax = Int32(IOHIDElementGetLogicalMax(element))

        switch (usagePage, usage) {
        // Generic Desktop - D-Pad (hat switch)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Hatswitch)):
            break

        // Generic Desktop - Stick axes
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_X)):
            if axisMap.first(where: { $0.keyPath == \State.leftStickX }) == nil {
                axisMap.append((usagePage, usage, \State.leftStickX, logMin, logMax))
            } else {
                axisMap.append((usagePage, usage, \State.rightStickX, logMin, logMax))
            }
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Y)):
            if axisMap.first(where: { $0.keyPath == \State.leftStickY }) == nil {
                axisMap.append((usagePage, usage, \State.leftStickY, logMin, logMax))
            } else {
                axisMap.append((usagePage, usage, \State.rightStickY, logMin, logMax))
            }
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rx)):
            axisMap.append((usagePage, usage, \State.rightStickX, logMin, logMax))
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Ry)):
            axisMap.append((usagePage, usage, \State.rightStickY, logMin, logMax))
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Z)):
            axisMap.append((usagePage, usage, \State.leftTrigger, logMin, logMax))
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rz)):
            axisMap.append((usagePage, usage, \State.rightTrigger, logMin, logMax))

        // Button page - standard gamepad buttons
        case (UInt32(kHIDPage_Button), 1):
            buttonMap.append((usagePage, usage, \State.buttonA))
        case (UInt32(kHIDPage_Button), 2):
            buttonMap.append((usagePage, usage, \State.buttonB))
        case (UInt32(kHIDPage_Button), 3):
            buttonMap.append((usagePage, usage, \State.buttonX))
        case (UInt32(kHIDPage_Button), 4):
            buttonMap.append((usagePage, usage, \State.buttonY))
        case (UInt32(kHIDPage_Button), 5):
            buttonMap.append((usagePage, usage, \State.leftShoulder))
        case (UInt32(kHIDPage_Button), 6):
            buttonMap.append((usagePage, usage, \State.rightShoulder))
        case (UInt32(kHIDPage_Button), 7):
            buttonMap.append((usagePage, usage, \State.leftTrigger))
        case (UInt32(kHIDPage_Button), 8):
            buttonMap.append((usagePage, usage, \State.rightTrigger))
        case (UInt32(kHIDPage_Button), 9):
            buttonMap.append((usagePage, usage, \State.leftThumbstickButton))
        case (UInt32(kHIDPage_Button), 10):
            buttonMap.append((usagePage, usage, \State.rightThumbstickButton))
        case (UInt32(kHIDPage_Button), 11):
            buttonMap.append((usagePage, usage, \State.dpadUp)); hasIndividualDpadButtons = true
        case (UInt32(kHIDPage_Button), 12):
            buttonMap.append((usagePage, usage, \State.dpadDown)); hasIndividualDpadButtons = true
        case (UInt32(kHIDPage_Button), 13):
            buttonMap.append((usagePage, usage, \State.dpadLeft)); hasIndividualDpadButtons = true
        case (UInt32(kHIDPage_Button), 14):
            buttonMap.append((usagePage, usage, \State.dpadRight)); hasIndividualDpadButtons = true

        default:
            break
        }
    }

    // MARK: - Input Handling

    private func handleInput(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        lock.lock()
        defer { lock.unlock() }

        // Check button map (must match both usagePage AND usage)
        if let mapping = buttonMap.first(where: { $0.usagePage == usagePage && $0.usage == usage }) {
            _state[keyPath: mapping.keyPath] = intValue > 0 ? 1.0 : 0.0
            return
        }

        // Check axis map (must match both usagePage AND usage)
        if let mapping = axisMap.first(where: { $0.usagePage == usagePage && $0.usage == usage }) {
            let range = Float(mapping.max - mapping.min)
            let normalized = range > 0 ? (Float(Int32(intValue) - mapping.min) / range) * 2.0 - 1.0 : 0.0
            _state[keyPath: mapping.keyPath] = normalized
            return
        }

        // Handle hat switch (D-pad)
        // Standard HID hat values: 1=N, 2=NE, 3=E, 4=SE, 5=S, 6=SW, 7=W, 8=NW, 0=neutral
        // Each direction can be combined (diagonals set two axes at once).
        if usagePage == UInt32(kHIDPage_GenericDesktop) && usage == UInt32(kHIDUsage_GD_Hatswitch) {
            if hasIndividualDpadButtons {
                return
            }
            // Reset all, then set the active directions
            _state.dpadUp = 0.0; _state.dpadDown = 0.0; _state.dpadLeft = 0.0; _state.dpadRight = 0.0
            switch intValue {
            case 1: // N
                _state.dpadUp = 1.0
            case 2: // NE
                _state.dpadUp = 1.0; _state.dpadRight = 1.0
            case 3: // E
                _state.dpadRight = 1.0
            case 4: // SE
                _state.dpadDown = 1.0; _state.dpadRight = 1.0
            case 5: // S
                _state.dpadDown = 1.0
            case 6: // SW
                _state.dpadDown = 1.0; _state.dpadLeft = 1.0
            case 7: // W
                _state.dpadLeft = 1.0
            case 8: // NW
                _state.dpadUp = 1.0; _state.dpadLeft = 1.0
            default: // 0 or unknown → neutral, all cleared above
                break
            }
        }
    }

    // MARK: - Helpers

    private func createMatchingDict(page: UInt32, usage: UInt32) -> CFDictionary {
        let dict: NSDictionary = [
            kIOHIDDeviceUsagePageKey: NSNumber(value: page),
            kIOHIDDeviceUsageKey: NSNumber(value: usage),
        ]
        return dict as CFDictionary
    }
}
