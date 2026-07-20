import UIKit

enum LVMainModule {
    case shelf
    case notes
    case profile
}

enum LVModuleSubtitleProvider {
    private static let dateKey = "lv_module_subtitle_date"
    private static let valuesKey = "lv_module_subtitle_values"
    private static let values = [
        "拾字存光，落笔留章", "摘录世间字句，收藏心中山河", "与文字共情，把思绪存档",
        "藏书页碎语，记人间所思", "一文一注解，一念一收藏", "留存文字，沉淀思绪",
        "摘抄、批注、所思所感", "文字存档，灵感自留", "留住书中值得回味的片段",
        "为好文落笔，因所思留痕", "文字为骨，笔记为魂", "阅尽千行字，记下一寸心",
        "字落于心，笔藏于册", "拾句，存思，留忆", "书有注解，心有归处",
        "藏万千书卷，守一方阅读天地", "以书为伴，与自己相逢", "你的阅读宇宙",
        "为文字而生，因阅读而狂"
    ]

    static func subtitle(for module: LVMainModule) -> String {
        let assignments = dailyAssignments()
        return assignments[module.index]
    }

    private static func dailyAssignments() -> [String] {
        let defaults = UserDefaults.standard
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if defaults.string(forKey: dateKey) == today,
           let saved = defaults.stringArray(forKey: valuesKey),
           saved.count == 3,
           Set(saved).count == 3 {
            return saved
        }
        let selected = Array(values.shuffled().prefix(3))
        defaults.set(today, forKey: dateKey)
        defaults.set(selected, forKey: valuesKey)
        return selected
    }
}

final class LVModuleNavigationView: UIView {
    var onSelect: ((LVMainModule) -> Void)?

    private let stackView = UIStackView()
    private let shelfButton = LVModuleButton(type: .system)
    private let notesButton = LVModuleButton(type: .system)
    private let profileButton = LVModuleButton(type: .system)
    private let selectedModule: LVMainModule

    init(selectedModule: LVMainModule) {
        self.selectedModule = selectedModule
        super.init(frame: .zero)
        build()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(darkModeChanged),
            name: .darkModeChanged,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        applyAppearance()
        layer.borderWidth = 1 / UIScreen.main.scale

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        configure(shelfButton, title: "LVRead", symbol: "book.closed", module: .shelf)
        configure(notesButton, title: "笔记", symbol: "bookmark", module: .notes)
        configure(profileButton, title: "我的", symbol: "person", module: .profile)
        [shelfButton, notesButton, profileButton].forEach(stackView.addArrangedSubview)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func configure(
        _ button: UIButton,
        title: String,
        symbol: String,
        module: LVMainModule
    ) {
        let selected = module == selectedModule
        let color = selected ? LVBookshelfModuleStyle.accent : LVBookshelfModuleStyle.secondaryText
        button.setImage(
            UIImage(systemName: selected ? "\(symbol).fill" : symbol) ?? UIImage(systemName: symbol),
            for: .normal
        )
        button.setTitle(title, for: .normal)
        button.tintColor = color
        button.setTitleColor(color, for: .normal)
        button.backgroundColor = selected
            ? LVBookshelfModuleStyle.accent.withAlphaComponent(0.14)
            : .clear
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityLabel = title
        button.accessibilityTraits = selected ? [.button, .selected] : .button
        button.tag = module.tag
        button.addTarget(self, action: #selector(moduleTapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    @objc private func moduleTapped(_ sender: UIButton) {
        guard let module = LVMainModule(tag: sender.tag) else { return }
        onSelect?(module)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyAppearance()
    }

    private func applyAppearance() {
        backgroundColor = LVBookshelfModuleStyle.cardBackground
        layer.borderColor = LVBookshelfModuleStyle.divider.cgColor
        applyButtonAppearance(shelfButton, symbol: "book.closed", module: .shelf)
        applyButtonAppearance(notesButton, symbol: "bookmark", module: .notes)
        applyButtonAppearance(profileButton, symbol: "person", module: .profile)
    }

    @objc private func darkModeChanged() {
        applyAppearance()
        setNeedsLayout()
    }

    private func applyButtonAppearance(_ button: UIButton, symbol: String, module: LVMainModule) {
        let selected = module == selectedModule
        let color = selected ? LVBookshelfModuleStyle.accent : LVBookshelfModuleStyle.secondaryText
        button.setImage(
            UIImage(systemName: selected ? "\(symbol).fill" : symbol) ?? UIImage(systemName: symbol),
            for: .normal
        )
        button.tintColor = color
        button.setTitleColor(color, for: .normal)
        button.backgroundColor = selected
            ? LVBookshelfModuleStyle.accent.withAlphaComponent(0.14)
            : .clear
    }
}

/// Keeps the symbol and label inside the 52pt navigation content area.
final class LVModuleButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        let symbolSize = CGSize(width: 20, height: 20)
        imageView?.frame = CGRect(
            x: (bounds.width - symbolSize.width) / 2,
            y: 6,
            width: symbolSize.width,
            height: symbolSize.height
        )
        titleLabel?.sizeToFit()
        if let titleLabel {
            let height = min(titleLabel.bounds.height, 16)
            titleLabel.frame = CGRect(
                x: 4,
                y: 32,
                width: max(bounds.width - 8, 0),
                height: height
            )
            titleLabel.textAlignment = .center
        }
    }
}

extension UIViewController {
    func showMainModule(_ module: LVMainModule) {
        guard let navigationController else { return }
        let shelf = navigationController.viewControllers.first(where: { $0 is BookshelfViewController })
            ?? BookshelfViewController()
        switch module {
        case .shelf:
            navigationController.setViewControllers([shelf], animated: false)
        case .notes:
            if self is NotesViewController { return }
            navigationController.setViewControllers([shelf, NotesViewController()], animated: false)
        case .profile:
            if self is ProfileViewController { return }
            navigationController.setViewControllers([shelf, ProfileViewController()], animated: false)
        }
    }
}

private extension LVMainModule {
    var index: Int { tag }

    var tag: Int {
        switch self {
        case .shelf: return 0
        case .notes: return 1
        case .profile: return 2
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0: self = .shelf
        case 1: self = .notes
        case 2: self = .profile
        default: return nil
        }
    }
}
