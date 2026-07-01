import Foundation

final class ReadingSettingsRepository {
    static let shared = ReadingSettingsRepository()
    private let defaults = UserDefaults.standard
    private let settingsKey = "reading_settings"

    private init() {}

    func initialize() {}

    func load() -> ReadingSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(ReadingSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: ReadingSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    func reset() {
        defaults.removeObject(forKey: settingsKey)
    }
}
