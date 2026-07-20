import UIKit
import Combine

// MARK: - Dark Mode Manager

/// Manages app-wide dark mode settings and provides seamless switching
final class DarkModeManager: ObservableObject {

    // MARK: - Singleton

    static let shared = DarkModeManager()

    // MARK: - Published Properties

    @Published var isDarkMode: Bool = false {
        didSet {
            if isDarkMode != oldValue {
                applyTheme()
                UserDefaults.standard.set(isDarkMode, forKey: Keys.darkModeEnabled)
            }
        }
    }

    @Published private(set) var currentTheme: ReadingTheme = .bookshelf

    @Published private(set) var appearanceMode: AppearanceMode = .light {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            updateFromAppearanceMode()
        }
    }

    // MARK: - Types

    enum AppearanceMode: String, CaseIterable {
        case system = "SYSTEM"
        case light = "LIGHT"
        case dark = "DARK"

        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色模式"
            case .dark: return "深色模式"
            }
        }
    }

    // MARK: - Keys

    private struct Keys {
        static let darkModeEnabled = "darkModeEnabled"
        static let appearanceMode = "appearanceMode"
        static let lastLightTheme = "lastLightReadingTheme"
        static let lastDarkTheme = "lastDarkReadingTheme"
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var styleObserver: NSObjectProtocol?

    // MARK: - Initialization

    private init() {
        loadSavedSettings()
        observeSystemAppearance()
    }

    // MARK: - Public Methods

    /// Apply dark mode theme to all UI
    func applyTheme() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyTheme()
            }
            return
        }

        updateWindowTheme()
        updateNavigationBarAppearance()
        updateTabBarAppearance()
        NotificationCenter.default.post(name: .darkModeChanged, object: nil)
    }

    /// Toggle between dark and light mode
    func toggleDarkMode() {
        setNightMode(!isDarkMode)
    }

    func selectReadingTheme(_ theme: ReadingTheme) {
        let selected = theme == .custom ? .white : theme
        let modeChanged = isDarkMode != selected.isDarkAppearance
        currentTheme = selected
        remember(selected)

        var settings = ReadingSettingsRepository.shared.load()
        settings.readingTheme = selected
        settings.backgroundColor = selected.backgroundColor
        settings.nightMode = selected.isDarkAppearance
        ReadingSettingsRepository.shared.save(settings)

        appearanceMode = selected.isDarkAppearance ? .dark : .light
        if !modeChanged { applyTheme() }
    }

    func setNightMode(_ enabled: Bool) {
        let key = enabled ? Keys.lastDarkTheme : Keys.lastLightTheme
        let fallback: ReadingTheme = enabled ? .oled : .bookshelf
        let saved = UserDefaults.standard.string(forKey: key)
            .flatMap(ReadingTheme.init(rawValue:))
        let selected = saved.flatMap { $0.isDarkAppearance == enabled ? $0 : nil } ?? fallback
        selectReadingTheme(selected)
    }

    // MARK: - Private Methods

    private func loadSavedSettings() {
        var settings = ReadingSettingsRepository.shared.load()
        let selected = settings.readingTheme == .custom ? ReadingTheme.white : settings.readingTheme
        currentTheme = selected
        remember(selected)
        if settings.readingTheme != selected {
            settings.readingTheme = selected
            settings.backgroundColor = selected.backgroundColor
            settings.nightMode = selected.isDarkAppearance
            ReadingSettingsRepository.shared.save(settings)
        }
        appearanceMode = selected.isDarkAppearance ? .dark : .light
    }

    private func updateFromAppearanceMode() {
        switch appearanceMode {
        case .system:
            // Listen to system changes
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        case .light:
            isDarkMode = false
        case .dark:
            isDarkMode = true
        }
    }

    private func observeSystemAppearance() {
        styleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.appearanceMode == .system else { return }
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            if self.isDarkMode != isDark {
                self.isDarkMode = isDark
            }
        }
    }

    private func remember(_ theme: ReadingTheme) {
        UserDefaults.standard.set(
            theme.rawValue,
            forKey: theme.isDarkAppearance ? Keys.lastDarkTheme : Keys.lastLightTheme
        )
    }

    private func updateNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(hex: currentTheme.backgroundColor)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(hex: currentTheme.textColor)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(hex: currentTheme.textColor)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(hex: currentTheme.panelColor)

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    private func updateWindowTheme() {
        let style: UIUserInterfaceStyle = isDarkMode ? .dark : .light
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = style }
    }

    // MARK: - Color Helpers

    static func adaptiveColor(light: UIColor, dark: UIColor) -> UIColor {
        return UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }

    static var adaptiveBackground: UIColor {
        UIColor { _ in UIColor(hex: DarkModeManager.shared.currentTheme.backgroundColor) }
    }

    static var adaptiveTextPrimary: UIColor {
        UIColor { _ in UIColor(hex: DarkModeManager.shared.currentTheme.textColor) }
    }

    static var adaptiveTextSecondary: UIColor {
        UIColor { _ in UIColor(hex: DarkModeManager.shared.currentTheme.textColor).withAlphaComponent(0.64) }
    }

    static var adaptiveSurface: UIColor {
        UIColor { _ in UIColor(hex: DarkModeManager.shared.currentTheme.panelColor) }
    }

    static var adaptiveDivider: UIColor {
        UIColor { _ in UIColor(hex: DarkModeManager.shared.currentTheme.textColor).withAlphaComponent(0.14) }
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let darkModeChanged = Notification.Name("darkModeChanged")
}

// MARK: - UIViewController Extension for Dark Mode Support

extension UIViewController {
    
    /// Called when dark mode changes - override in subclasses
    func darkModeDidChange(isDark: Bool) {
        // Override in subclasses to update UI
    }

    /// Setup dark mode observer in viewDidLoad
    func setupDarkModeObserver() {
        NotificationCenter.default.addObserver(
            forName: .darkModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let isDark = DarkModeManager.shared.isDarkMode
            self.darkModeDidChange(isDark: isDark)
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

// MARK: - UIColor Extension for Dark Mode

extension UIColor {
    
    /// Returns a color that automatically adapts to dark mode
    static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        return DarkModeManager.adaptiveColor(light: light, dark: dark)
    }

    /// Convenience property for adaptive background
    static var adaptiveBackground: UIColor {
        return DarkModeManager.adaptiveBackground
    }

    /// Convenience property for adaptive primary text
    static var adaptiveText: UIColor {
        return DarkModeManager.adaptiveTextPrimary
    }

    /// Convenience property for adaptive secondary text
    static var adaptiveSecondaryText: UIColor {
        return DarkModeManager.adaptiveTextSecondary
    }

    /// Convenience property for adaptive surface
    static var adaptiveSurface: UIColor {
        return DarkModeManager.adaptiveSurface
    }
}
