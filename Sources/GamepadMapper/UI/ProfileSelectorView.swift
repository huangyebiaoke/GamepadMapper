import SwiftUI

struct ProfileSelectorView: View {
    let profileManager: ProfileManager
    var onClose: (() -> Void)?
    @State private var newProfileName = ""
    @State private var showNewProfileSheet = false
    @State private var editingProfile: MappingProfile?
    @State private var selectedProfileID: UUID?
    @Bindable private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = languageManager.currentLanguage
        VStack(spacing: 0) {
            List {
                ForEach(profileManager.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        if profile.id == profileManager.activeProfileID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .onTapGesture {
                        selectedProfileID = profile.id
                        profileManager.activateProfile(id: profile.id)
                        MappingEngine.shared.refreshProfileCache()
                    }
                    .contextMenu {
                        Button("duplicate".localized) {
                            _ = profileManager.duplicateProfile(profile)
                        }
                        Button("rename".localized) {
                            editingProfile = profile
                        }
                        Divider()
                        Button("delete".localized, role: .destructive) {
                            profileManager.deleteProfile(profile)
                        }
                        .disabled(profileManager.profiles.count <= 1)
                    }
                }
            }

            Divider()

            HStack {
                Button("new_profile".localized) {
                    showNewProfileSheet = true
                }
                .controlSize(.regular)

                Button("reset_default".localized) {
                    _ = profileManager.resetToDefault()
                    MappingEngine.shared.refreshProfileCache()
                }
                .controlSize(.regular)

                Spacer()

                Button("done".localized) {
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()
        }
        .frame(minWidth: 350, minHeight: 300)
        .onAppear {
            selectedProfileID = profileManager.activeProfileID
        }
        .sheet(isPresented: $showNewProfileSheet) {
            newProfileSheet
        }
        .sheet(item: $editingProfile) { profile in
            RenameProfileView(
                profile: profile,
                onSave: { updated in
                    profileManager.saveProfile(updated)
                    editingProfile = nil
                },
                onCancel: {
                    editingProfile = nil
                }
            )
        }
    }

    private var newProfileSheet: some View {
        VStack(spacing: 16) {
            Text("new_profile".localized)
                .font(.headline)
            TextField("profile_name_placeholder".localized, text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    createNewProfile()
                }
            HStack {
                Button("cancel".localized) {
                    showNewProfileSheet = false
                    newProfileName = ""
                }
                Button("create".localized) {
                    createNewProfile()
                }
                .disabled(newProfileName.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    private func createNewProfile() {
        guard !newProfileName.isEmpty else { return }
        _ = profileManager.createProfile(name: newProfileName)
        MappingEngine.shared.refreshProfileCache()
        showNewProfileSheet = false
        newProfileName = ""
    }
}

// MARK: - Rename Sheet

struct RenameProfileView: View {
    let profile: MappingProfile
    let onSave: (MappingProfile) -> Void
    let onCancel: () -> Void
    @State private var name: String

    init(profile: MappingProfile, onSave: @escaping (MappingProfile) -> Void, onCancel: @escaping () -> Void) {
        self.profile = profile
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("rename_profile".localized)
                .font(.headline)
            TextField("profile_name_placeholder".localized, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    saveName()
                }
            HStack {
                Button("cancel".localized, action: onCancel)
                Button("save".localized) { saveName() }
                    .disabled(name.isEmpty)
                    .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    private func saveName() {
        var updated = profile
        updated.name = name
        onSave(updated)
    }
}
