@preconcurrency import GameController
import Foundation
import Observation

/// Represents the current state of a connected gamepad.
/// Connection state is synced from HIDGamepadReader for reliable background operation.
@Observable
final class GameControllerManager: @unchecked Sendable {
    static let shared = GameControllerManager()

    var connectedController: GCController?
    var isConnected = false
    var controllerName = ""

    // MARK: - Button States (binary)

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

    // MARK: - Analog States

    var leftStickX: Float = 0
    var leftStickY: Float = 0
    var rightStickX: Float = 0
    var rightStickY: Float = 0
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0

    private let lock = NSLock()
    private var isMonitoring = false
    private var handlerTokens: [NSObjectProtocol] = []

    private init() {}

    // MARK: - Start / Stop

    func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        guard !isMonitoring else { return }
        isMonitoring = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect, object: nil)

        if let existing = GCController.controllers().first {
            setupController(existing)
        }
    }

    func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        guard isMonitoring else { return }
        isMonitoring = false

        for token in handlerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        handlerTokens.removeAll()

        connectedController = nil
        isConnected = false
        controllerName = ""
        resetAllStates()
    }

    // MARK: - Notifications

    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        setupController(controller)
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController,
              controller === connectedController else { return }
        connectedController = nil
        isConnected = false
        controllerName = ""
        resetAllStates()
    }

    // MARK: - Controller Setup

    private func setupController(_ controller: GCController) {
        connectedController = controller
        isConnected = true
        controllerName = controller.vendorName ?? "Unknown Controller"

        guard let gamepad = controller.extendedGamepad else { return }

        // Register valueChangedHandler for every element.
        // This is event-driven and works even when the app is in the background,
        // unlike polling which only works for foreground apps.
        handlerTokens.removeAll()

        // D-Pad (GCControllerDirectionPad → individual buttons are GCControllerButtonInput)
        gamepad.dpad.up.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.dpadUp = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.dpad.up)
        gamepad.dpad.down.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.dpadDown = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.dpad.down)
        gamepad.dpad.left.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.dpadLeft = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.dpad.left)
        gamepad.dpad.right.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.dpadRight = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.dpad.right)

        // Face buttons
        gamepad.buttonA.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.buttonA = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.buttonA)
        gamepad.buttonB.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.buttonB = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.buttonB)
        gamepad.buttonX.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.buttonX = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.buttonX)
        gamepad.buttonY.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.buttonY = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.buttonY)

        // Shoulder buttons
        gamepad.leftShoulder.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.leftShoulder = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.leftShoulder)
        gamepad.rightShoulder.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.rightShoulder = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.rightShoulder)

        // Thumbstick buttons
        if let lsb = gamepad.leftThumbstickButton {
            lsb.valueChangedHandler = { [weak self] _, value, _ in
                self?.lock.lock(); self?.leftThumbstickButton = value; self?.lock.unlock()
            }
            handlerTokens.append(lsb)
        }
        if let rsb = gamepad.rightThumbstickButton {
            rsb.valueChangedHandler = { [weak self] _, value, _ in
                self?.lock.lock(); self?.rightThumbstickButton = value; self?.lock.unlock()
            }
            handlerTokens.append(rsb)
        }

        // Left stick axes (GCControllerAxisInput)
        let lxHandler: GCControllerAxisValueChangedHandler = { [weak self] _, value in
            self?.lock.lock(); self?.leftStickX = value; self?.lock.unlock()
        }
        gamepad.leftThumbstick.xAxis.valueChangedHandler = lxHandler
        handlerTokens.append(gamepad.leftThumbstick.xAxis)
        let lyHandler: GCControllerAxisValueChangedHandler = { [weak self] _, value in
            self?.lock.lock(); self?.leftStickY = value; self?.lock.unlock()
        }
        gamepad.leftThumbstick.yAxis.valueChangedHandler = lyHandler
        handlerTokens.append(gamepad.leftThumbstick.yAxis)

        // Right stick axes (GCControllerAxisInput)
        let rxHandler: GCControllerAxisValueChangedHandler = { [weak self] _, value in
            self?.lock.lock(); self?.rightStickX = value; self?.lock.unlock()
        }
        gamepad.rightThumbstick.xAxis.valueChangedHandler = rxHandler
        handlerTokens.append(gamepad.rightThumbstick.xAxis)
        let ryHandler: GCControllerAxisValueChangedHandler = { [weak self] _, value in
            self?.lock.lock(); self?.rightStickY = value; self?.lock.unlock()
        }
        gamepad.rightThumbstick.yAxis.valueChangedHandler = ryHandler
        handlerTokens.append(gamepad.rightThumbstick.yAxis)

        // Triggers (GCControllerButtonInput — triggers expose as button inputs)
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.leftTrigger = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.leftTrigger)
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            self?.lock.lock(); self?.rightTrigger = value; self?.lock.unlock()
        }
        handlerTokens.append(gamepad.rightTrigger)

        EngineLogger.log("GameControllerManager: setupController done, registered \(self.handlerTokens.count) handlers")
    }

    // MARK: - Get Value for Element

    func value(for element: ControllerElement) -> Float {
        lock.lock()
        defer { lock.unlock() }

        switch element {
        case .dpadUp: return dpadUp
        case .dpadDown: return dpadDown
        case .dpadLeft: return dpadLeft
        case .dpadRight: return dpadRight
        case .buttonA: return buttonA
        case .buttonB: return buttonB
        case .buttonX: return buttonX
        case .buttonY: return buttonY
        case .leftShoulder: return leftShoulder
        case .rightShoulder: return rightShoulder
        case .leftThumbstickButton: return leftThumbstickButton
        case .rightThumbstickButton: return rightThumbstickButton
        case .leftStickX: return leftStickX
        case .leftStickY: return leftStickY
        case .rightStickX: return rightStickX
        case .rightStickY: return rightStickY
        case .leftTrigger: return leftTrigger
        case .rightTrigger: return rightTrigger
        }
    }

    private func resetAllStates() {
        dpadUp = 0; dpadDown = 0; dpadLeft = 0; dpadRight = 0
        buttonA = 0; buttonB = 0; buttonX = 0; buttonY = 0
        leftShoulder = 0; rightShoulder = 0
        leftThumbstickButton = 0; rightThumbstickButton = 0
        leftStickX = 0; leftStickY = 0; rightStickX = 0; rightStickY = 0
        leftTrigger = 0; rightTrigger = 0
    }
}
