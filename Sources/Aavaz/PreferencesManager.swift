import Foundation

struct Profile: Codable, Sendable {
    var name: String
    var modelName: String
    var useVAD: Bool
    var initialPrompt: String
    var injectionDelay: TimeInterval
    var useCoreML: Bool
}

struct Preferences: Codable, Sendable {
    var profiles: [Profile]
    var activeProfileIndex: Int
    var triggerKeyCode: UInt16
    var doubleTapWindow: TimeInterval
    var restoreClipboard: Bool

    var activeProfile: Profile {
        profiles[activeProfileIndex]
    }

    static let `default` = Preferences(
        profiles: [
            Profile(name: "Fast", modelName: "tiny.en", useVAD: false, initialPrompt: "", injectionDelay: 0.1, useCoreML: false),
            Profile(name: "Balanced", modelName: "base.en", useVAD: false, initialPrompt: "", injectionDelay: 0.1, useCoreML: false),
            Profile(name: "Quality", modelName: "medium.en", useVAD: false, initialPrompt: "", injectionDelay: 0.1, useCoreML: true),
        ],
        activeProfileIndex: 0,
        triggerKeyCode: 60,
        doubleTapWindow: 0.3,
        restoreClipboard: true
    )
}

final class PreferencesManager: Sendable {
    static let prefsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("aavaz", isDirectory: true)
    }()

    static let prefsURL: URL = {
        prefsDirectory.appendingPathComponent("preferences.json")
    }()

    func load() -> Preferences {
        guard FileManager.default.fileExists(atPath: Self.prefsURL.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: Self.prefsURL)
            return try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            print("Failed to load preferences: \(error). Using defaults.")
            return .default
        }
    }

    func save(_ prefs: Preferences) throws {
        try FileManager.default.createDirectory(at: Self.prefsDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(prefs)
        try data.write(to: Self.prefsURL, options: .atomic)
    }
}
