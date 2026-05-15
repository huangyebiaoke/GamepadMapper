import CoreGraphics
import Foundation

// MARK: - Controller Element

enum ControllerElement: String, Codable, CaseIterable, Identifiable {
    // D-Pad
    case dpadUp, dpadDown, dpadLeft, dpadRight
    // Face buttons
    case buttonA, buttonB, buttonX, buttonY
    // Shoulder buttons
    case leftShoulder, rightShoulder
    // Triggers (analog)
    case leftTrigger, rightTrigger
    // Analog sticks (axes)
    case leftStickX, leftStickY, rightStickX, rightStickY
    // Thumbstick buttons
    case leftThumbstickButton, rightThumbstickButton

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dpadUp: return "dpad_up".localized
        case .dpadDown: return "dpad_down".localized
        case .dpadLeft: return "dpad_left".localized
        case .dpadRight: return "dpad_right".localized
        case .buttonA: return "button_a".localized
        case .buttonB: return "button_b".localized
        case .buttonX: return "button_x".localized
        case .buttonY: return "button_y".localized
        case .leftShoulder: return "left_shoulder".localized
        case .rightShoulder: return "right_shoulder".localized
        case .leftTrigger: return "left_trigger".localized
        case .rightTrigger: return "right_trigger".localized
        case .leftStickX: return "left_stick_x".localized
        case .leftStickY: return "left_stick_y".localized
        case .rightStickX: return "right_stick_x".localized
        case .rightStickY: return "right_stick_y".localized
        case .leftThumbstickButton: return "left_thumbstick_button".localized
        case .rightThumbstickButton: return "right_thumbstick_button".localized
        }
    }

    var isAnalog: Bool {
        switch self {
        case .leftTrigger, .rightTrigger, .leftStickX, .leftStickY, .rightStickX, .rightStickY:
            true
        default:
            false
        }
    }

    var category: String {
        switch self {
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return "category_dpad".localized
        case .buttonA, .buttonB, .buttonX, .buttonY: return "category_face_buttons".localized
        case .leftShoulder, .rightShoulder: return "category_shoulder".localized
        case .leftTrigger, .rightTrigger: return "category_triggers".localized
        case .leftStickX, .leftStickY, .leftThumbstickButton: return "category_left_stick".localized
        case .rightStickX, .rightStickY, .rightThumbstickButton: return "category_right_stick".localized
        }
    }
}

// MARK: - Mapping Target

enum MappingTarget: Equatable, Hashable, Identifiable {
    case key(CGKeyCode)
    case mouseButton(MouseButton)
    case mouseDrag(MouseButton)
    case mouseMove

    var id: String {
        switch self {
        case .key(let code): return "key_\(code)"
        case .mouseButton(let btn): return "mb_\(btn.rawValue)"
        case .mouseDrag(let btn): return "md_\(btn.rawValue)"
        case .mouseMove: return "mousemove"
        }
    }

    var displayName: String {
        switch self {
        case .key(let code):
            return KeyMappings.displayName(for: code)
        case .mouseButton(let btn):
            return btn.displayName
        case .mouseDrag(let btn):
            return btn.dragDisplayName
        case .mouseMove:
            return "target_mouse_move".localized
        }
    }

    static func == (lhs: MappingTarget, rhs: MappingTarget) -> Bool {
        switch (lhs, rhs) {
        case (.key(let a), .key(let b)): return a == b
        case (.mouseButton(let a), .mouseButton(let b)): return a == b
        case (.mouseDrag(let a), .mouseDrag(let b)): return a == b
        case (.mouseMove, .mouseMove): return true
        default: return false
        }
    }
}

// MARK: - MappingTarget Codable

private enum TargetCodingKeys: String, CodingKey {
    case type, keyCode, mouseButton
}

extension MappingTarget: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TargetCodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "key":
            let code = try container.decode(UInt16.self, forKey: .keyCode)
            self = .key(CGKeyCode(code))
        case "mouseButton":
            let btn = try container.decode(MouseButton.self, forKey: .mouseButton)
            self = .mouseButton(btn)
        case "mouseDrag":
            let btn = try container.decode(MouseButton.self, forKey: .mouseButton)
            self = .mouseDrag(btn)
        case "mouseMove":
            self = .mouseMove
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TargetCodingKeys.self)
        switch self {
        case .key(let code):
            try container.encode("key", forKey: .type)
            try container.encode(code, forKey: .keyCode)
        case .mouseButton(let btn):
            try container.encode("mouseButton", forKey: .type)
            try container.encode(btn, forKey: .mouseButton)
        case .mouseDrag(let btn):
            try container.encode("mouseDrag", forKey: .type)
            try container.encode(btn, forKey: .mouseButton)
        case .mouseMove:
            try container.encode("mouseMove", forKey: .type)
        }
    }
}

// MARK: - Analog Axis Direction

enum AnalogDirection: String, Codable, Hashable {
    case positive
    case negative
}

// MARK: - Mapping Entry

struct MappingEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var source: ControllerElement
    var target: MappingTarget?
    var direction: AnalogDirection = .positive
    var deadzone: Float = 0.2
    var analogThreshold: Float = 0.5

    static func == (lhs: MappingEntry, rhs: MappingEntry) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.target == rhs.target
    }
}

// MARK: - Mapping Profile

struct MappingProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var entries: [MappingEntry]
    var mouseSensitivity: Double = 15.0
    var createdAt: Date
    var updatedAt: Date

    static func defaultProfile() -> MappingProfile {
        MappingProfile(
            name: "profile_name_default".localized,
            entries: [
                // Left stick → WASD
                MappingEntry(source: .leftStickY, target: .key(KeyMappings.w), direction: .negative, deadzone: 0.3),
                MappingEntry(source: .leftStickY, target: .key(KeyMappings.s), direction: .positive, deadzone: 0.3),
                MappingEntry(source: .leftStickX, target: .key(KeyMappings.a), direction: .negative, deadzone: 0.3),
                MappingEntry(source: .leftStickX, target: .key(KeyMappings.d), direction: .positive, deadzone: 0.3),
                // D-Pad → Arrow keys
                MappingEntry(source: .dpadUp, target: .key(KeyMappings.upArrow)),
                MappingEntry(source: .dpadDown, target: .key(KeyMappings.downArrow)),
                MappingEntry(source: .dpadLeft, target: .key(KeyMappings.leftArrow)),
                MappingEntry(source: .dpadRight, target: .key(KeyMappings.rightArrow)),
                // Face buttons
                MappingEntry(source: .buttonA, target: .key(KeyMappings.space)),
                MappingEntry(source: .buttonB, target: .key(KeyMappings.escape)),
                MappingEntry(source: .buttonX, target: .key(KeyMappings.enter)),
                MappingEntry(source: .buttonY, target: .key(KeyMappings.tab)),
                // Shoulder buttons → mouse buttons
                MappingEntry(source: .leftShoulder, target: .mouseButton(.left)),
                MappingEntry(source: .rightShoulder, target: .mouseButton(.right)),
                // Right stick → mouse move
                MappingEntry(source: .rightStickX, target: .mouseMove, direction: .positive, deadzone: 0.2),
                MappingEntry(source: .rightStickX, target: .mouseMove, direction: .negative, deadzone: 0.2),
                MappingEntry(source: .rightStickY, target: .mouseMove, direction: .positive, deadzone: 0.2),
                MappingEntry(source: .rightStickY, target: .mouseMove, direction: .negative, deadzone: 0.2),
                // Triggers → mouse buttons
                MappingEntry(source: .leftTrigger, target: .mouseButton(.left), analogThreshold: 0.5),
                MappingEntry(source: .rightTrigger, target: .mouseButton(.right), analogThreshold: 0.5),
            ],
            createdAt: .now,
            updatedAt: .now
        )
    }
}
