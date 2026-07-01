import UIKit

final class AppearanceManager {
    static let shared = AppearanceManager()
    private init() {}

    func configure(_ navigationController: UINavigationController) {
        // Create gradient appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(hex: "#C0392B")
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(hex: "#F5F0E8"),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(hex: "#F5F0E8"),
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        
        // Configure navigation bar
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        
        // Tint color for bar button items
        navigationController.navigationBar.tintColor = UIColor(hex: "#F5F0E8")
        
        // Enable large titles
        navigationController.navigationBar.prefersLargeTitles = true
        
        // Add blur effect for translucent appearance
        navigationController.navigationBar.isTranslucent = false
    }
    
    func configureTabBar(_ tabBarController: UITabBarController) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .lvSurface
        
        // Configure normal and scrollEdge appearance
        tabBarController.tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBarController.tabBar.scrollEdgeAppearance = appearance
        }
        
        // Tint color
        tabBarController.tabBar.tintColor = UIColor(hex: "#C0392B")
        tabBarController.tabBar.unselectedItemTintColor = .lvTextTertiary
    }
    
    // MARK: - Global Button Style
    func stylePrimaryButton(_ button: UIButton) {
        button.backgroundColor = UIColor(hex: "#C0392B")
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 12
    }
    
    // MARK: - Card Style
    func styleCard(_ view: UIView) {
        view.backgroundColor = .lvSurface
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.layer.shadowOpacity = 0.08
    }
    
    // MARK: - Segmented Control Style
    func styleSegmentedControl(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = UIColor(hex: "#C0392B")
        control.setTitleTextAttributes([
            .foregroundColor: UIColor.lvTextSecondary,
            .font: UIFont.systemFont(ofSize: 13, weight: .medium)
        ], for: .normal)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(hex: "#F5F0E8"),
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ], for: .selected)
    }
}
