import UIKit

private final class ReaderRestorationState {
    var didTransition = false
}

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

        let splash = SplashViewController()
        splash.onComplete = { [weak self] in
            guard let self else { return }
            let navigationController = self.makeBookshelfNavigationController()
            guard let window = self.window else { return }

            if connectionOptions.urlContexts.isEmpty,
               let book = NativeReaderRestorationStore.restorableBook() {
                self.restoreReader(
                    for: book,
                    in: navigationController,
                    window: window
                )
                return
            }

            self.showRootViewController(with: navigationController, in: window)

            if let url = connectionOptions.urlContexts.first?.url {
                self.handleIncomingFile(url)
            }
        }

        window?.rootViewController = splash
        window?.makeKeyAndVisible()
    }

    private func restoreReader(
        for book: Book,
        in navigationController: UINavigationController,
        window: UIWindow
    ) {
        let reader = NativeDocumentReaderViewController(book: book)
        let restorationState = ReaderRestorationState()
        reader.prepareForPresentation(
            in: window.bounds,
            safeAreaInsets: window.safeAreaInsets
        ) { [weak self, weak window] result in
            guard let self, let window else { return }
            guard !restorationState.didTransition else { return }
            restorationState.didTransition = true
            switch result {
            case .success:
                self.showPreparedReader(reader, in: navigationController, window: window)
            case .failure(let error):
                LVLogger.error(
                    "Failed to restore prepared reader: \(error.localizedDescription)",
                    category: .ui
                )
                self.showRootViewController(with: navigationController, in: window)
            }
        }

        // The first off-screen layout can rebuild the page controller and request
        // another pass. Since the reader is not in the window yet, run that pass
        // explicitly so preparation can finish while the splash remains visible.
        DispatchQueue.main.async {
            reader.view.setNeedsLayout()
            reader.view.layoutIfNeeded()
        }

        // Never leave the app trapped on the splash if a damaged file or an
        // unexpected reader error prevents the preparation callback from firing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak window] in
            guard let self, let window else { return }
            guard !restorationState.didTransition else { return }
            restorationState.didTransition = true
            LVLogger.error("Reader restoration timed out", category: .ui)
            self.showPreparedReader(reader, in: navigationController, window: window)
        }
    }

    private func showPreparedReader(
        _ reader: NativeDocumentReaderViewController,
        in navigationController: UINavigationController,
        window: UIWindow
    ) {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            navigationController.viewControllers.append(reader)
            showRootViewController(with: navigationController, in: window)
            return
        }

        let splashOverlay = window.snapshotView(afterScreenUpdates: true)
        showRootViewController(with: navigationController, in: window, animated: false)
        if let splashOverlay {
            splashOverlay.frame = window.bounds
            splashOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(splashOverlay)
        }

        DispatchQueue.main.async {
            navigationController.pushViewController(reader, animated: false)
            UIView.animate(
                withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25,
                animations: { splashOverlay?.alpha = 0 },
                completion: { _ in splashOverlay?.removeFromSuperview() }
            )
        }
    }

    private func showRootViewController(
        with navigationController: UINavigationController,
        in window: UIWindow,
        animated: Bool = true
    ) {
        let updateRoot = {
            window.rootViewController = self.makeRootViewController(
                contentNavigationController: navigationController
            )
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(
                with: window,
                duration: 0.4,
                options: .transitionCrossDissolve,
                animations: updateRoot
            )
        } else {
            updateRoot()
        }
        DarkModeManager.shared.applyTheme()
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
