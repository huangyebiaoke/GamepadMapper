import Foundation
import Observation

@Observable
@MainActor
final class ProfileManager {
    static let shared = ProfileManager()

    var profiles: [MappingProfile] = []
    var activeProfileID: UUID?

    private var profilesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GamepadMapper/Profiles")
        return dir
    }

    private init() {
        loadAllProfiles()
        if profiles.isEmpty {
            let defaultProfile = MappingProfile.defaultProfile()
            saveProfile(defaultProfile)
            activeProfileID = defaultProfile.id
        } else if activeProfileID == nil {
            activeProfileID = profiles.first?.id
        }
    }

    var activeProfile: MappingProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    // MARK: - Load

    func loadAllProfiles() {
        profiles = []
        guard let files = try? FileManager.default.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let profile = try? JSONDecoder().decode(MappingProfile.self, from: data) {
                profiles.append(profile)
            }
        }
        profiles.sort { $0.name < $1.name }
    }

    // MARK: - Save

    @discardableResult
    func saveProfile(_ profile: MappingProfile) -> MappingProfile {
        var updated = profile
        updated.updatedAt = .now

        do {
            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
            let fileURL = profilesDirectory.appendingPathComponent("\(updated.id.uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(updated)
            try data.write(to: fileURL)

            if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
                profiles[index] = updated
            } else {
                profiles.append(updated)
                profiles.sort { $0.name < $1.name }
            }
            return updated
        } catch {
            print("Failed to save profile: \(error)")
            return profile
        }
    }

    // MARK: - Delete

    func deleteProfile(_ profile: MappingProfile) {
        let fileURL = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id
        }
    }

    // MARK: - Duplicate

    func duplicateProfile(_ profile: MappingProfile) -> MappingProfile {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        copy.createdAt = .now
        copy.updatedAt = .now
        return saveProfile(copy)
    }

    // MARK: - Create New

    func createProfile(name: String) -> MappingProfile {
        let defaults = MappingProfile.defaultProfile()
        let profile = MappingProfile(
            name: name,
            entries: defaults.entries,
            createdAt: .now,
            updatedAt: .now
        )
        let saved = saveProfile(profile)
        activeProfileID = saved.id
        return saved
    }

    // MARK: - Activate

    func activateProfile(id: UUID) {
        activeProfileID = id
    }

    // MARK: - Reset to Default

    func resetToDefault() -> MappingProfile {
        // Delete all profiles with the default localized name
        let defaultName = "profile_name_default".localized
        let defaultsToDelete = profiles.filter { $0.name == defaultName }
        for p in defaultsToDelete {
            deleteProfile(p)
        }
        let profile = MappingProfile.defaultProfile()
        let saved = saveProfile(profile)
        activeProfileID = saved.id
        return saved
    }
}
