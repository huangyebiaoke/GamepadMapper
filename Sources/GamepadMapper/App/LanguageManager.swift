import Foundation
import Observation

@Observable
final class LanguageManager: @unchecked Sendable {
    static let shared = LanguageManager()

    static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-hans", "简体中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("ru", "Русский"),
        ("es", "Español"),
    ]

    var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "GamepadMapper.Language")
            updateBundle()
        }
    }

    private var localizationBundle: Bundle?

    private init() {
        let mainBundle = Bundle.main
        var resourceBase: URL?

        // 1. Check if .lproj directories exist directly in Bundle.main's resourceURL (proper .app bundle)
        if let resourceURL = mainBundle.resourceURL {
            let lprojDirs = (try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)) ?? []
            if lprojDirs.contains(where: { $0.pathExtension == "lproj" }) {
                resourceBase = resourceURL
            }
        }

        // 2. Search for .bundle subdirectories (SPM CLI build)
        if resourceBase == nil {
            let searchDirs: [URL]
            if let resourceURL = mainBundle.resourceURL {
                searchDirs = [resourceURL, resourceURL.deletingLastPathComponent()]
            } else {
                searchDirs = [mainBundle.bundleURL.deletingLastPathComponent()]
            }
            for dir in searchDirs {
                if dir.pathExtension == "bundle" {
                    resourceBase = dir
                    break
                }
                if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for item in items where item.pathExtension == "bundle" {
                        resourceBase = item
                        break
                    }
                }
                if resourceBase != nil { break }
            }
        }

        // Fallback
        if resourceBase == nil {
            resourceBase = mainBundle.bundleURL.deletingLastPathComponent()
        }

        self.resourceBase = resourceBase!

        // Load saved language
        let saved = UserDefaults.standard.string(forKey: "GamepadMapper.Language")
        if let saved, Self.supportedLanguages.contains(where: { $0.code == saved }) {
            self.currentLanguage = saved
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.currentLanguage = Self.matchPreferredLanguage(preferred)
        }

        updateBundle()
    }

    private let resourceBase: URL

    var currentLanguageName: String {
        Self.supportedLanguages.first { $0.code == currentLanguage }?.name ?? currentLanguage
    }

    func setLanguage(_ code: String) {
        currentLanguage = code
    }

    func localized(_ key: String, _ args: CVarArg...) -> String {
        let template: String
        if let bundle = localizationBundle {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key && !value.isEmpty {
                template = value
            } else {
                template = fallbackTemplate(key: key)
            }
        } else {
            template = fallbackTemplate(key: key)
        }
        // Replace %@ placeholders with string args (handles %@ bridging issues)
        var result = template
        for arg in args {
            if let str = arg as? String,
               let range = result.range(of: "%@") {
                result.replaceSubrange(range, with: str)
            } else {
                return String(format: template, arguments: args)
            }
        }
        return result
    }

    private func fallbackTemplate(key: String) -> String {
        if let contents = try? FileManager.default.contentsOfDirectory(at: resourceBase, includingPropertiesForKeys: nil),
           let enURL = contents.first(where: {
               $0.pathExtension == "lproj" &&
               $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("en") == .orderedSame
           }),
           let enBundle = Bundle(url: enURL) {
            let value = enBundle.localizedString(forKey: key, value: key, table: nil)
            return value
        }
        return key
    }

    private func updateBundle() {
        // Case-insensitive search for the lproj directory (e.g. zh-hans vs zh-Hans)
        let lprojURL: URL?
        if let contents = try? FileManager.default.contentsOfDirectory(at: resourceBase, includingPropertiesForKeys: nil) {
            lprojURL = contents.first { url in
                url.pathExtension == "lproj" &&
                url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(currentLanguage) == .orderedSame
            }
        } else {
            lprojURL = nil
        }
        localizationBundle = lprojURL.flatMap { Bundle(url: $0) }
    }

    private static func matchPreferredLanguage(_ preferred: String) -> String {
        let prefix = preferred.prefix(2).lowercased()
        switch prefix {
        case "zh": return "zh-hans"
        case "ja": return "ja"
        case "ko": return "ko"
        case "ru": return "ru"
        case "es": return "es"
        default: return "en"
        }
    }
}

// MARK: - Localization Helper

extension String {
    var localized: String {
        LanguageManager.shared.localized(self)
    }
}
