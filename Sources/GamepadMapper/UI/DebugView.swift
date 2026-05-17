import SwiftUI

struct DebugView: View {
    private let controller = GameControllerManager.shared
    private let permissions = PermissionsManager.shared
    private let engine = MappingEngine.shared
    private let profileManager = ProfileManager.shared
    @Bindable private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = languageManager.currentLanguage
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("debug_permission".localized + " **" + (permissions.hasAccessibilityPermission ? "permission_granted".localized : "permission_denied".localized) + "**")
                Text("debug_controller".localized + " **" + (controller.isConnected ? controller.controllerName : "no".localized) + "**")
                Text("debug_engine".localized + " **" + (engine.isActive ? "yes".localized : "no".localized) + "**")
                Text("debug_profile".localized + " **" + (profileManager.activeProfile?.name ?? "None") + "**")
                Text("debug_entries".localized + " **\(profileManager.activeProfile?.entries.count ?? 0)**")
            }
            .font(.system(.body, design: .monospaced))

            Divider()

            Group {
                Text("debug_buttons".localized)
                Text("  A=\(String(format: "%.2f", controller.buttonA))  B=\(String(format: "%.2f", controller.buttonB))  X=\(String(format: "%.2f", controller.buttonX))  Y=\(String(format: "%.2f", controller.buttonY))")
                Text("  LB=\(String(format: "%.2f", controller.leftShoulder))  RB=\(String(format: "%.2f", controller.rightShoulder))")
                Text("  L3=\(String(format: "%.2f", controller.leftThumbstickButton))  R3=\(String(format: "%.2f", controller.rightThumbstickButton))")
                Text("debug_stick_l".localized + " X=\(String(format: "%.2f", controller.leftStickX))  Y=\(String(format: "%.2f", controller.leftStickY))")
                Text("debug_stick_r".localized + " X=\(String(format: "%.2f", controller.rightStickX))  Y=\(String(format: "%.2f", controller.rightStickY))")
                Text("debug_triggers".localized + " LT=\(String(format: "%.2f", controller.leftTrigger))  RT=\(String(format: "%.2f", controller.rightTrigger))")
                Text("debug_dpad".localized + " U=\(String(format: "%.2f", controller.dpadUp))  D=\(String(format: "%.2f", controller.dpadDown))  L=\(String(format: "%.2f", controller.dpadLeft))  R=\(String(format: "%.2f", controller.dpadRight))")
            }
            .font(.system(.body, design: .monospaced))

            Divider()

            HStack {
                Button("check_permission".localized) {
                    permissions.checkPermission()
                }
                Button("open_accessibility_settings".localized) {
                    permissions.openAccessibilitySettings()
                }
            }
        }
        .padding()
        .frame(width: 450)
    }
}
