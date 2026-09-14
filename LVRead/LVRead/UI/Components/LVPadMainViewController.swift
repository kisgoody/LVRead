import UIKit

/// iPad-only shell. Existing feature controllers remain the single source of truth.
final class LVPadMainViewController: UIViewController {
    private let sidebar = UIView()
    private let brandLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stackView = UIStackView()
    let contentNavigationController: UINavigationController
    private var buttons: [LVMainModule: UIButton] = [:]
    private var selectedModule: LVMainModule?

    var readerPresentationBounds: CGRect { view.bounds }
    var readerPresentationSafeAreaInsets: UIEdgeInsets { view.safeAreaInsets }

    init(navigationController: UINavigationController) {
        contentNavigationController = navigationController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        selectedModule = .shelf
        if contentNavigationController.viewControllers.isEmpty {
            selectMainModule(.shelf, animated: false)
        } else {
            updateSelection()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .darkModeChanged, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(sidebar)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // Keep a distinct name from UIViewController.showMainModule to avoid overload recursion.
    func selectMainModule(_ module: LVMainModule, animated: Bool = true) {
        guard module != selectedModule
                || contentNavigationController.viewControllers.isEmpty
                || contentNavigationController.presentedViewController != nil else { return }
        if contentNavigationController.presentedViewController != nil {
            contentNavigationController.dismiss(animated: false) { [weak self] in
                self?.installMainModule(module, animated: animated)
            }
        } else {
            installMainModule(module, animated: animated)
        }
    }

    private func installMainModule(_ module: LVMainModule, animated: Bool) {
        let controller: UIViewController
        switch module {
        case .shelf: controller = BookshelfViewController()
        case .notes: controller = NotesViewController()
        case .profile: controller = ProfileViewController()
        }
        controller.loadViewIfNeeded()
        let install = {
            self.contentNavigationController.setViewControllers([controller], animated: false)
            self.contentNavigationController.view.alpha = 1
            self.contentNavigationController.view.transform = .identity
            self.contentNavigationController.view.isHidden = false
            self.contentNavigationController.view.isUserInteractionEnabled = true
            self.contentNavigationController.view.layoutIfNeeded()
            self.view.bringSubviewToFront(self.sidebar)
        }
        selectedModule = module
        updateSelection()

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            install()
            return
        }
        UIView.transition(
            with: contentNavigationController.view,
            duration: 0.24,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
            animations: install
        )
    }

    private func buildInterface() {
        brandLabel.text = "LVRead"
        brandLabel.font = .systemFont(ofSize: 30, weight: .bold)
        subtitleLabel.text = L("沉浸阅读空间")
        subtitleLabel.font = .systemFont(ofSize: 14)

        stackView.axis = .vertical
        stackView.spacing = 8
        [(LVMainModule.shelf, L("书架"), "books.vertical"), (.notes, L("笔记"), "bookmark"), (.profile, L("我的"), "person")]
            .forEach { module, title, symbol in
                let button = makeButton(title: title, symbol: symbol, module: module)
                buttons[module] = button
                stackView.addArrangedSubview(button)
            }

        addChild(contentNavigationController)
        [contentNavigationController.view, sidebar].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        [brandLabel, subtitleLabel, stackView].forEach { sidebar.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        contentNavigationController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 320),
            brandLabel.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 48),
            brandLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 32),
            subtitleLabel.topAnchor.constraint(equalTo: brandLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: brandLabel.leadingAnchor),
            stackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -24),
            contentNavigationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentNavigationController.view.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentNavigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentNavigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        applyAppearance()
    }

    private func makeButton(title: String, symbol: String, module: LVMainModule) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.tag = module.tag
        button.contentHorizontalAlignment = .leading
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addTarget(self, action: #selector(moduleTriggered(_:)), for: .primaryActionTriggered)
        return button
    }

    @objc private func moduleTriggered(_ sender: UIButton) {
        guard let module = LVMainModule(tag: sender.tag) else { return }
        selectMainModule(module)
    }

    @objc private func themeChanged() { applyAppearance() }

    private func applyAppearance() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        sidebar.backgroundColor = LVBookshelfModuleStyle.cardBackground
        brandLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        updateSelection()
    }

    private func updateSelection() {
        for (module, button) in buttons {
            let selected = module == selectedModule
            button.configuration?.baseForegroundColor = selected ? LVBookshelfModuleStyle.accent : LVBookshelfModuleStyle.adaptivePrimaryText
            button.backgroundColor = selected ? LVBookshelfModuleStyle.accent.withAlphaComponent(0.12) : .clear
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

}
