import Foundation
import UIKit

final class ReadingSettingsRepository {
    static let shared = ReadingSettingsRepository()
    private let defaults = UserDefaults.standard
    private let settingsKey = "reading_settings"
    private let padTypographyDefaultsKey = "reading_settings_pad_typography_defaults_v1"

    private init() {}

    func initialize() {}

    func load() -> ReadingSettings {
        var settings: ReadingSettings
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(ReadingSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        if settings.readingTheme != .custom {
            settings.backgroundColor = settings.readingTheme.backgroundColor
        }
        if UIDevice.current.userInterfaceIdiom == .pad,
           !defaults.bool(forKey: padTypographyDefaultsKey) {
            defaults.set(true, forKey: padTypographyDefaultsKey)
            let updated = ReadingSettings.applyingPadTypographyDefaults(to: settings)
            if updated != settings {
                settings = updated
                save(settings)
            }
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
        defaults.removeObject(forKey: padTypographyDefaultsKey)
    }
}
