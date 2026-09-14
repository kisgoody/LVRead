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

/// iPad navigation adapter: existing feature code can keep requesting navigation,
/// while secondary pages are presented over the right-side content context.
final class LVPadPresentingNavigationController: UINavigationController {
    var bookTransitionSource: BookOpenTransitionSource?
    private var bookTransitionAnimator: BookOpenTransitionAnimator?

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        let presentedNavigation = LVPadPresentingNavigationController()
        presentedNavigation.setViewControllers([viewController], animated: false)
        if viewController is NativeDocumentReaderViewController {
            presentedNavigation.bookTransitionSource = bookTransitionSource
            bookTransitionSource = nil
            let animator = BookOpenTransitionAnimator(source: presentedNavigation.bookTransitionSource)
            presentedNavigation.bookTransitionAnimator = animator
            presentedNavigation.transitioningDelegate = animator
            presentedNavigation.modalPresentationStyle = .fullScreen
            presentedNavigation.setNavigationBarHidden(true, animated: false)
        } else {
            presentedNavigation.modalPresentationStyle = .overCurrentContext
        }
        presentedNavigation.definesPresentationContext = true
        AppearanceManager.shared.configure(presentedNavigation)
        present(presentedNavigation, animated: animated)
    }

    @discardableResult
    override func popViewController(animated: Bool) -> UIViewController? {
        guard viewControllers.count > 1 else {
            let current = topViewController
            dismiss(animated: animated)
            return current
        }
        return super.popViewController(animated: animated)
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)

        if connectionOptions.urlContexts.isEmpty,
           let book = NativeReaderRestorationStore.restorableBook() {
            let navigationController = makeBookshelfNavigationController()
            let reader = NativeDocumentReaderViewController(book: book)
            if UIDevice.current.userInterfaceIdiom == .pad {
                DispatchQueue.main.async {
                    navigationController.pushViewController(reader, animated: false)
                }
            } else {
                navigationController.viewControllers.append(reader)
            }
            window?.rootViewController = makeRootViewController(contentNavigationController: navigationController)
            window?.makeKeyAndVisible()
            DarkModeManager.shared.applyTheme()
            return
        }

        let splash = SplashViewController()
        splash.onComplete = { [weak self] in
            guard let self else { return }
            let navigationController = self.makeBookshelfNavigationController()

            guard let window = self.window else { return }
            UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
                self.window?.rootViewController = self.makeRootViewController(contentNavigationController: navigationController)
            }
            DarkModeManager.shared.applyTheme()

            if let url = connectionOptions.urlContexts.first?.url {
                self.handleIncomingFile(url)
            }
        }

        window?.rootViewController = splash
        window?.makeKeyAndVisible()
    }

    private func makeBookshelfNavigationController() -> UINavigationController {
        let navigationController: UINavigationController
        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController = LVPadPresentingNavigationController(
                navigationBarClass: BookshelfNavigationBar.self,
                toolbarClass: nil
            )
            navigationController.definesPresentationContext = true
        } else {
            navigationController = UINavigationController(
                navigationBarClass: BookshelfNavigationBar.self,
                toolbarClass: nil
            )
        }
        navigationController.viewControllers = [BookshelfViewController()]
        navigationController.navigationBar.prefersLargeTitles = false
        AppearanceManager.shared.configure(navigationController)
        return navigationController
    }

    private func makeRootViewController(
        contentNavigationController: UINavigationController
    ) -> UIViewController {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            return contentNavigationController
        }
        return LVPadMainViewController(navigationController: contentNavigationController)
    }

    private var contentNavigationController: UINavigationController? {
        if let navigation = window?.rootViewController as? UINavigationController {
            return navigation
        }
        return (window?.rootViewController as? LVPadMainViewController)?.contentNavigationController
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
        WebSyncServer.shared.reconnectAfterForegroundIfNeeded()
    }

    private func handleIncomingFile(_ url: URL) {
        if url.pathExtension.lowercased() == "md" {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let markdown = String(data: data, encoding: .utf8) else {
                LVToast.show(message: L("无法读取导入文件"), style: .error)
                return
            }
            let notification: Notification.Name
            let destination: UIViewController
            if markdown.contains("<!-- LVREAD-NOTES:1 -->") {
                notification = .lvReadMarkdownReceived
                destination = NotesViewController()
            } else if markdown.contains("<!-- LVREAD-STATS:1 -->") {
                notification = .lvReadStatsMarkdownReceived
                destination = ReadingStatsViewController()
            } else {
                LVToast.show(message: L("文件不符合 LVRead 导入规范"), style: .error)
                return
            }
            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? data.write(to: localURL, options: .atomic)
            if let navigation = contentNavigationController {
                navigation.pushViewController(destination, animated: false)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: notification, object: localURL)
                }
            }
            return
        }
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
    static let lvReadMarkdownReceived = Notification.Name("lvReadMarkdownReceived")
    static let lvReadStatsMarkdownReceived = Notification.Name("lvReadStatsMarkdownReceived")
}
