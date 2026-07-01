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

    @Published var appearanceMode: AppearanceMode = .system {
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
        DispatchQueue.main.async {
            self.updateNavigationBarAppearance()
            self.updateTabBarAppearance()
            self.updateWindowTheme()
            
            // Post notification for view controllers to update
            NotificationCenter.default.post(name: .darkModeChanged, object: nil)
        }
    }

    /// Toggle between dark and light mode
    func toggleDarkMode() {
        isDarkMode.toggle()
    }

    // MARK: - Private Methods

    private func loadSavedSettings() {
        if let savedMode = UserDefaults.standard.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: savedMode) {
            appearanceMode = mode
        }
        
        isDarkMode = UserDefaults.standard.bool(forKey: Keys.darkModeEnabled)
        updateFromAppearanceMode()
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
                self.applyTheme()
            }
        }
    }

    private func updateNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        
        if isDarkMode {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .lvBgNight
            appearance.titleTextAttributes = [
                .foregroundColor: UIColor.lvTextPrimaryDark
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor.lvTextPrimaryDark
            ]
        } else {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .lvPrimary
            appearance.titleTextAttributes = [
                .foregroundColor: UIColor.white
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor.white
            ]
        }

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        
        if isDarkMode {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .lvSurfaceDark
        } else {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .lvSurface
        }

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    private func updateWindowTheme() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        UIView.animate(withDuration: 0.3) {
            window.overrideUserInterfaceStyle = self.isDarkMode ? .dark : .light
        }
    }

    // MARK: - Color Helpers

    static func adaptiveColor(light: UIColor, dark: UIColor) -> UIColor {
        return UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }

    static var adaptiveBackground: UIColor {
        return adaptiveColor(light: .lvBgDay, dark: .lvBgNight)
    }

    static var adaptiveTextPrimary: UIColor {
        return adaptiveColor(light: .lvTextPrimary, dark: .lvTextPrimaryDark)
    }

    static var adaptiveTextSecondary: UIColor {
        return adaptiveColor(light: .lvTextSecondary, dark: .lvTextSecondaryDark)
    }

    static var adaptiveSurface: UIColor {
        return adaptiveColor(light: .lvSurface, dark: .lvSurfaceDark)
    }

    static var adaptiveDivider: UIColor {
        return adaptiveColor(light: .lvDivider, dark: .lvDividerDark)
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
