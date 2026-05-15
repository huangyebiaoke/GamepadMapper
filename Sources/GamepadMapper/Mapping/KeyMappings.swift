import CoreGraphics

// MARK: - Key Codes

enum KeyMappings {
    // MARK: Letters
    static let a: CGKeyCode = 0x00
    static let b: CGKeyCode = 0x0B
    static let c: CGKeyCode = 0x08
    static let d: CGKeyCode = 0x02
    static let e: CGKeyCode = 0x0E
    static let f: CGKeyCode = 0x03
    static let g: CGKeyCode = 0x05
    static let h: CGKeyCode = 0x04
    static let i: CGKeyCode = 0x22
    static let j: CGKeyCode = 0x26
    static let k: CGKeyCode = 0x28
    static let l: CGKeyCode = 0x25
    static let m: CGKeyCode = 0x2E
    static let n: CGKeyCode = 0x2D
    static let o: CGKeyCode = 0x1F
    static let p: CGKeyCode = 0x23
    static let q: CGKeyCode = 0x0C
    static let r: CGKeyCode = 0x0F
    static let s: CGKeyCode = 0x01
    static let t: CGKeyCode = 0x11
    static let u: CGKeyCode = 0x20
    static let v: CGKeyCode = 0x09
    static let w: CGKeyCode = 0x0D
    static let x: CGKeyCode = 0x07
    static let y: CGKeyCode = 0x10
    static let z: CGKeyCode = 0x06

    // MARK: Numbers
    static let zero: CGKeyCode = 0x1D
    static let one: CGKeyCode = 0x12
    static let two: CGKeyCode = 0x13
    static let three: CGKeyCode = 0x14
    static let four: CGKeyCode = 0x15
    static let five: CGKeyCode = 0x17
    static let six: CGKeyCode = 0x16
    static let seven: CGKeyCode = 0x1A
    static let eight: CGKeyCode = 0x1C
    static let nine: CGKeyCode = 0x19

    // MARK: Function Keys
    static let f1: CGKeyCode = 0x7A
    static let f2: CGKeyCode = 0x78
    static let f3: CGKeyCode = 0x63
    static let f4: CGKeyCode = 0x76
    static let f5: CGKeyCode = 0x60
    static let f6: CGKeyCode = 0x61
    static let f7: CGKeyCode = 0x62
    static let f8: CGKeyCode = 0x64
    static let f9: CGKeyCode = 0x65
    static let f10: CGKeyCode = 0x6D
    static let f11: CGKeyCode = 0x67
    static let f12: CGKeyCode = 0x6F

    // MARK: Control Keys
    static let space: CGKeyCode = 0x31
    static let enter: CGKeyCode = 0x24
    static let tab: CGKeyCode = 0x30
    static let escape: CGKeyCode = 0x35
    static let backspace: CGKeyCode = 0x33
    static let delete: CGKeyCode = 0x75

    // MARK: Arrow Keys
    static let upArrow: CGKeyCode = 0x7E
    static let downArrow: CGKeyCode = 0x7D
    static let leftArrow: CGKeyCode = 0x7B
    static let rightArrow: CGKeyCode = 0x7C

    // MARK: Modifier Keys
    static let leftShift: CGKeyCode = 0x38
    static let rightShift: CGKeyCode = 0x3C
    static let leftControl: CGKeyCode = 0x3B
    static let rightControl: CGKeyCode = 0x3E
    static let leftOption: CGKeyCode = 0x3A
    static let rightOption: CGKeyCode = 0x3D
    static let leftCommand: CGKeyCode = 0x37
    static let rightCommand: CGKeyCode = 0x36

    // MARK: Other
    static let capsLock: CGKeyCode = 0x39
    static let tilde: CGKeyCode = 0x32
    static let minus: CGKeyCode = 0x1B
    static let equal: CGKeyCode = 0x18
    static let leftBracket: CGKeyCode = 0x21
    static let rightBracket: CGKeyCode = 0x1E
    static let backslash: CGKeyCode = 0x2A
    static let semicolon: CGKeyCode = 0x29
    static let quote: CGKeyCode = 0x27
    static let comma: CGKeyCode = 0x2B
    static let period: CGKeyCode = 0x2F
    static let slash: CGKeyCode = 0x2C

    // MARK: Display Names
    static func displayName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case a...z:
            let map: [CGKeyCode: String] = [
                a: "A", b: "B", c: "C", d: "D", e: "E", f: "F", g: "G",
                h: "H", i: "I", j: "J", k: "K", l: "L", m: "M", n: "N",
                o: "O", p: "P", q: "Q", r: "R", s: "S", t: "T", u: "U",
                v: "V", w: "W", x: "X", y: "Y", z: "Z"
            ]
            return map[keyCode] ?? "Key(\(keyCode))"
        case zero...nine:
            let map: [CGKeyCode: String] = [
                zero: "0", one: "1", two: "2", three: "3", four: "4",
                five: "5", six: "6", seven: "7", eight: "8", nine: "9"
            ]
            return map[keyCode] ?? "Num(\(keyCode))"
        case f1...f12:
            let map: [CGKeyCode: String] = [
                f1: "F1", f2: "F2", f3: "F3", f4: "F4", f5: "F5", f6: "F6",
                f7: "F7", f8: "F8", f9: "F9", f10: "F10", f11: "F11", f12: "F12"
            ]
            return map[keyCode] ?? "F(\(keyCode))"
        case space: return "Space"
        case enter: return "Enter"
        case tab: return "Tab"
        case escape: return "Esc"
        case backspace: return "Backspace"
        case delete: return "Delete"
        case upArrow: return "↑"
        case downArrow: return "↓"
        case leftArrow: return "←"
        case rightArrow: return "→"
        case leftShift: return "L-Shift"
        case rightShift: return "R-Shift"
        case leftControl: return "L-Ctrl"
        case rightControl: return "R-Ctrl"
        case leftOption: return "L-Opt"
        case rightOption: return "R-Opt"
        case leftCommand: return "L-Cmd"
        case rightCommand: return "R-Cmd"
        case capsLock: return "CapsLock"
        case tilde: return "~"
        case minus: return "-"
        case equal: return "="
        case leftBracket: return "["
        case rightBracket: return "]"
        case backslash: return "\\"
        case semicolon: return ";"
        case quote: return "'"
        case comma: return ","
        case period: return "."
        case slash: return "/"
        default: return "Key(\(keyCode))"
        }
    }

    // MARK: All Keys for Picker
    static var allKeys: [(name: String, code: CGKeyCode)] {
        [
            // Letters
            ("A", a), ("B", b), ("C", c), ("D", d), ("E", e), ("F", f),
            ("G", g), ("H", h), ("I", i), ("J", j), ("K", k), ("L", l),
            ("M", m), ("N", n), ("O", o), ("P", p), ("Q", q), ("R", r),
            ("S", s), ("T", t), ("U", u), ("V", v), ("W", w), ("X", x),
            ("Y", y), ("Z", z),
            // Numbers
            ("0", zero), ("1", one), ("2", two), ("3", three), ("4", four),
            ("5", five), ("6", six), ("7", seven), ("8", eight), ("9", nine),
            // Function
            ("F1", f1), ("F2", f2), ("F3", f3), ("F4", f4),
            ("F5", f5), ("F6", f6), ("F7", f7), ("F8", f8),
            ("F9", f9), ("F10", f10), ("F11", f11), ("F12", f12),
            // Control
            ("Space", space), ("Enter", enter), ("Tab", tab), ("Esc", escape),
            ("Backspace", backspace), ("Delete", delete),
            // Arrows
            ("↑", upArrow), ("↓", downArrow), ("←", leftArrow), ("→", rightArrow),
            // Modifiers
            ("L-Shift", leftShift), ("R-Shift", rightShift),
            ("L-Ctrl", leftControl), ("R-Ctrl", rightControl),
            ("L-Opt", leftOption), ("R-Opt", rightOption),
            ("L-Cmd", leftCommand), ("R-Cmd", rightCommand),
        ]
    }
}

// MARK: - Mouse Button

enum MouseButton: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case center

    var id: String { rawValue }

    var cgMouseButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .center: return .center
        }
    }

    var displayName: String {
        switch self {
        case .left: return "mouse_left".localized
        case .right: return "mouse_right".localized
        case .center: return "mouse_middle".localized
        }
    }
}
