import UIKit

final class BookshelfNavigationBar: UINavigationBar {
    private let bookshelfHeight: CGFloat = 78

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height = bookshelfHeight
        return size
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var fittingSize = super.sizeThatFits(size)
        fittingSize.height = bookshelfHeight
        return fittingSize
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)

        let splash = SplashViewController()
        splash.onComplete = { [weak self] in
            guard let self = self else { return }
            
            let bookshelfVC = BookshelfViewController()
            let navigationController = UINavigationController(navigationBarClass: BookshelfNavigationBar.self, toolbarClass: nil)
            navigationController.viewControllers = [bookshelfVC]
            navigationController.navigationBar.prefersLargeTitles = false
            AppearanceManager.shared.configure(navigationController)

            UIView.transition(with: self.window!, duration: 0.4, options: .transitionCrossDissolve) {
                self.window?.rootViewController = navigationController
            }
            DarkModeManager.shared.applyTheme()
            WebSyncServer.shared.resumeSavedSessionIfNeeded()

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
        TransferManager.shared.handleBackgroundTransition()
        PageCacheManager.shared.handleBackgroundTransition()
        ImageCacheManager.shared.handleBackgroundTransition()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        TransferManager.shared.handleForegroundTransition()
        WebSyncServer.shared.resumeSavedSessionIfNeeded(restartListener: true)
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
