import UIKit

final class AppConfiguration {
    static let shared = AppConfiguration()
    private init() {}

    func initialize() {
        // Initialize database first
        DatabaseManager.shared.initialize()
        
        // Ensure data directories exist
        ensureDataDirectories()

        ThemeManager.shared.loadSavedTheme()
        ReadingSettingsRepository.shared.initialize()
        TransferManager.shared.initialize()

        // Configure global appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .lvPrimary
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 18, weight: .bold)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        UINavigationBar.appearance().tintColor = .white

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
    
    private func ensureDataDirectories() {
        let fm = FileManager.default
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        
        // Ensure books directory exists
        let booksDir = (docsDir as NSString).appendingPathComponent("LVReadBooks")
        if !fm.fileExists(atPath: booksDir) {
            try? fm.createDirectory(atPath: booksDir, withIntermediateDirectories: true)
        }
        
        // Ensure covers directory exists
        let coversDir = (docsDir as NSString).appendingPathComponent("LVReadCovers")
        if !fm.fileExists(atPath: coversDir) {
            try? fm.createDirectory(atPath: coversDir, withIntermediateDirectories: true)
        }
    }
}
