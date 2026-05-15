import SwiftUI

struct PermissionPromptView: View {
    let permissions: PermissionsManager
    @Bindable private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = languageManager.currentLanguage
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("permission_title".localized)
                .font(.title2.bold())

            Text("permission_description".localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            VStack(alignment: .leading, spacing: 8) {
                Text("permission_step1".localized)
                Text("permission_step2".localized)
                Text("permission_step3".localized)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 300, alignment: .leading)

            Button("open_system_settings".localized) {
                permissions.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("check_permission".localized) {
                permissions.checkPermission()
            }
            .controlSize(.small)

            Spacer()
        }
        .padding(40)
    }
}
