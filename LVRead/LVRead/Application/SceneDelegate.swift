import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)

        let splash = SplashViewController()
        splash.onComplete = { [weak self] in
            guard let self = self else { return }
            
            let bookshelfVC = BookshelfViewController()
            let navigationController = UINavigationController(rootViewController: bookshelfVC)
            navigationController.navigationBar.prefersLargeTitles = true
            AppearanceManager.shared.configure(navigationController)

            UIView.transition(with: self.window!, duration: 0.4, options: .transitionCrossDissolve) {
                self.window?.rootViewController = navigationController
            }

            if let url = connectionOptions.urlContexts.first?.url {
                self.handleIncomingFile(url)
            }
        }

        window?.rootViewController = splash
        window?.makeKeyAndVisible()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            handleIncomingFile(url)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        WebSyncServer.shared.stopIfNeeded()
        TransferManager.shared.handleBackgroundTransition()
        PageCacheManager.shared.handleBackgroundTransition()
        ImageCacheManager.shared.handleBackgroundTransition()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        TransferManager.shared.handleForegroundTransition()
    }

    private func handleIncomingFile(_ url: URL) {
        BookImportManager.shared.importFile(from: url) { result in
            switch result {
            case .success:
                NotificationCenter.default.post(name: .bookImported, object: nil)
            case .failure(let error):
                DispatchQueue.main.async {
                    LVToast.show(message: error.localizedDescription)
                }
            }
        }
    }
}

extension Notification.Name {
    static let bookImported = Notification.Name("bookImported")
}
