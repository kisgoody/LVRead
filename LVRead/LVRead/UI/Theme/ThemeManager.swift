import UIKit

final class ThemeManager {
    static let shared = ThemeManager()

    private let defaults = UserDefaults.standard
    private let themeKey = "selected_reading_theme"
    private let autoSwitchKey = "auto_theme_switch_enabled"

    private(set) var currentTheme: ReadingTheme = .white
    var isAutoSwitchEnabled: Bool {
        get { defaults.bool(forKey: autoSwitchKey) }
        set { defaults.set(newValue, forKey: autoSwitchKey) }
    }

    private init() {}

    func loadSavedTheme() {
        if let saved = defaults.string(forKey: themeKey),
           let theme = ReadingTheme(rawValue: saved) {
            currentTheme = theme
        }
    }

    func applyTheme(_ theme: ReadingTheme) {
        currentTheme = theme
        defaults.set(theme.rawValue, forKey: themeKey)
    }

    func autoThemeForCurrentTime() -> ReadingTheme {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<10: return .mint
        case 10..<17: return .white
        case 17..<21: return .latte
        default: return .oled
        }
    }

    func backgroundColor(for theme: ReadingTheme? = nil) -> UIColor {
        UIColor(hex: (theme ?? currentTheme).backgroundColor)
    }

    func textColor(for theme: ReadingTheme? = nil) -> UIColor {
        UIColor(hex: (theme ?? currentTheme).textColor)
    }

    func accentColor(for theme: ReadingTheme? = nil) -> UIColor {
        UIColor(hex: (theme ?? currentTheme).accentColor)
    }
}
