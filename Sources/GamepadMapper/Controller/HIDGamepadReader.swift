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
    private var buttonMap: [(usage: UInt32, keyPath: WritableKeyPath<State, Float>)] = []
    private var axisMap: [(usage: UInt32, keyPath: WritableKeyPath<State, Float>, min: Int32, max: Int32)] = []

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
            // Unschedule on whatever run loop it's on (the background thread's)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        _state = State()
        buttonMap = []
        axisMap = []
        deviceName = ""
        isConnected = false
        syncConnectionState(name: "", connected: false)

        // Stop the background thread's run loop
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
                axisMap.append((usage, \State.leftStickX, logMin, logMax))
            } else {
                axisMap.append((usage, \State.rightStickX, logMin, logMax))
            }
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Y)):
            if axisMap.first(where: { $0.keyPath == \State.leftStickY }) == nil {
                axisMap.append((usage, \State.leftStickY, logMin, logMax))
            } else {
                axisMap.append((usage, \State.rightStickY, logMin, logMax))
            }
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rx)):
            axisMap.append((usage, \State.rightStickX, logMin, logMax))
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Ry)):
            axisMap.append((usage, \State.rightStickY, logMin, logMax))
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Z)):
            axisMap.append((usage, \State.leftTrigger, logMin, logMax))
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Rz)):
            axisMap.append((usage, \State.rightTrigger, logMin, logMax))

        // Button page - standard gamepad buttons
        case (UInt32(kHIDPage_Button), 1):
            buttonMap.append((usage, \State.buttonA))
        case (UInt32(kHIDPage_Button), 2):
            buttonMap.append((usage, \State.buttonB))
        case (UInt32(kHIDPage_Button), 3):
            buttonMap.append((usage, \State.buttonX))
        case (UInt32(kHIDPage_Button), 4):
            buttonMap.append((usage, \State.buttonY))
        case (UInt32(kHIDPage_Button), 5):
            buttonMap.append((usage, \State.leftShoulder))
        case (UInt32(kHIDPage_Button), 6):
            buttonMap.append((usage, \State.rightShoulder))
        case (UInt32(kHIDPage_Button), 7):
            buttonMap.append((usage, \State.leftTrigger))
        case (UInt32(kHIDPage_Button), 8):
            buttonMap.append((usage, \State.rightTrigger))
        case (UInt32(kHIDPage_Button), 9):
            buttonMap.append((usage, \State.leftThumbstickButton))
        case (UInt32(kHIDPage_Button), 10):
            buttonMap.append((usage, \State.rightThumbstickButton))
        case (UInt32(kHIDPage_Button), 11):
            buttonMap.append((usage, \State.dpadUp))
        case (UInt32(kHIDPage_Button), 12):
            buttonMap.append((usage, \State.dpadDown))
        case (UInt32(kHIDPage_Button), 13):
            buttonMap.append((usage, \State.dpadLeft))
        case (UInt32(kHIDPage_Button), 14):
            buttonMap.append((usage, \State.dpadRight))

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

        // Check button map
        if let mapping = buttonMap.first(where: { $0.usage == usage }) {
            _state[keyPath: mapping.keyPath] = intValue > 0 ? 1.0 : 0.0
            return
        }

        // Check axis map
        if let mapping = axisMap.first(where: { $0.usage == usage }) {
            let range = Float(mapping.max - mapping.min)
            let normalized = range > 0 ? (Float(Int32(intValue) - mapping.min) / range) * 2.0 - 1.0 : 0.0
            _state[keyPath: mapping.keyPath] = normalized
            return
        }

        // Handle hat switch (D-pad)
        if usagePage == UInt32(kHIDPage_GenericDesktop) && usage == UInt32(kHIDUsage_GD_Hatswitch) {
            // Hat switch: 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8=neutral
            // Diagonals snap to the NEAREST cardinal direction (vertical priority).
            // This avoids the original "db" bug where SW=5 fired BOTH Down+Left keys.
            switch intValue {
            case 0: // N
                _state.dpadUp = 1.0; _state.dpadDown = 0.0; _state.dpadLeft = 0.0; _state.dpadRight = 0.0
            case 1, 7: // NE, NW → Up
                _state.dpadUp = 1.0; _state.dpadDown = 0.0; _state.dpadLeft = 0.0; _state.dpadRight = 0.0
            case 2: // E
                _state.dpadUp = 0.0; _state.dpadDown = 0.0; _state.dpadLeft = 0.0; _state.dpadRight = 1.0
            case 3, 5: // SE, SW → Down
                _state.dpadUp = 0.0; _state.dpadDown = 1.0; _state.dpadLeft = 0.0; _state.dpadRight = 0.0
            case 4: // S
                _state.dpadUp = 0.0; _state.dpadDown = 1.0; _state.dpadLeft = 0.0; _state.dpadRight = 0.0
            case 6: // W
                _state.dpadUp = 0.0; _state.dpadDown = 0.0; _state.dpadLeft = 1.0; _state.dpadRight = 0.0
            default: // 8 or anything else = neutral
                _state.dpadUp = 0.0; _state.dpadDown = 0.0; _state.dpadLeft = 0.0; _state.dpadRight = 0.0
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
