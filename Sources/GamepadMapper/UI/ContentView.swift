import SwiftUI

struct ContentView: View {
    private let permissions = PermissionsManager.shared
    private let controller = GameControllerManager.shared
    private let profileManager = ProfileManager.shared
    private let engine = MappingEngine.shared
    @Bindable private var languageManager = LanguageManager.shared

    @State private var editorWindow: NSWindow?
    @State private var profileWindow: NSWindow?

    var body: some View {
        let _ = languageManager.currentLanguage // observe language changes
        VStack(spacing: 0) {
            if !permissions.hasAccessibilityPermission {
                PermissionPromptView(permissions: permissions)
            } else {
                mainContent
            }
        }
        .frame(minWidth: 420, minHeight: 350)
        .onAppear {
            controller.startMonitoring()
        }
        .onDisappear {
            // Only stop controller monitoring — engine runs independently on its
            // own background queue and must NOT be stopped when the window closes.
            controller.stopMonitoring()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 16) {
            header
            Divider()
            controllerStatus
            Divider()
            profileSection
            Spacer()
            actionButtons
        }
        .padding()
    }

    private var header: some View {
        HStack {
            Text("app_name".localized)
                .font(.title2.bold())
            Spacer()
            statusIndicator
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controller.isConnected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(controller.isConnected ? controller.controllerName : "no_controller".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controllerStatus: some View {
        ControllerStatusView(controller: controller)
            .frame(maxWidth: .infinity)
    }

    private var profileSection: some View {
        HStack {
            Text("profile_label".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(profileManager.activeProfile?.name ?? "none")
                .font(.subheadline.bold())
            Spacer()
            languageSelector
            Button("edit_mappings".localized) {
                openMappingEditor()
            }
            .controlSize(.regular)
            Button("profiles_button".localized) {
                openProfileManager()
            }
            .controlSize(.regular)
        }
    }

    private var languageSelector: some View {
        Picker("language".localized, selection: Binding(
            get: { languageManager.currentLanguage },
            set: { languageManager.setLanguage($0) }
        )) {
            ForEach(LanguageManager.supportedLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        }
        .frame(width: 120)
        .labelsHidden()
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(engine.isActive ? "stop_mapping".localized : "start_mapping".localized) {
                if engine.isActive {
                    engine.stop()
                } else {
                    guard permissions.hasAccessibilityPermission else { return }
                    engine.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(engine.isActive ? .red : .green)
            .frame(minWidth: 140)
            .disabled(!controller.isConnected || !permissions.hasAccessibilityPermission)

            if engine.isActive {
                Text("active".localized)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Child Windows

    private func openMappingEditor() {
        if let window = editorWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        editorWindow = window

        let editorView = MappingEditorView(
            profile: Binding(
                get: { profileManager.activeProfile ?? MappingProfile.defaultProfile() },
                set: {
                    profileManager.saveProfile($0)
                    MappingEngine.shared.refreshProfileCache()
                }
            ),
            onClose: { [weak window] in
                window?.close()
            }
        )
        window.contentView = NSHostingView(rootView: editorView)
        window.title = String(format: "edit_mappings_title".localized,
                              profileManager.activeProfile?.name ?? "")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func openProfileManager() {
        if let window = profileWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        profileWindow = window

        let profileView = ProfileSelectorView(
            profileManager: profileManager,
            onClose: { [weak window] in
                window?.close()
            }
        )
        window.contentView = NSHostingView(rootView: profileView)
        window.title = "profiles_title".localized
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
