import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}

fileprivate extension UIButton {
    func addPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.duration = 1.5
        pulse.fromValue = 1.0
        pulse.toValue = 1.08
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }
}

final class BookshelfViewController: UIViewController {

    // MARK: - Properties

    private var books: [Book] = []
    private var filteredBooks: [Book] = []
    private var isGridView = false
    private var isEditingMode = false
    private var selectedBookIds: Set<String> = []
    private var searchText = ""
    private var currentSort: BookSortType = .recentRead
    private var progressFilter: ReadingProgressFilter = .all
    private var sourceFilter: BookSource? = nil
    private var favoriteOnly = false
    private var isInitialLoad = true
    private var pendingCoverBook: Book?

    // MARK: - UI Components

    private let gridLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 100, right: 16)
        return layout
    }()

    private let collectionView: UICollectionView
    private let tableView: UITableView
    private let emptyStateView = LVEmptyStateView(
        icon: "books.vertical",
        title: "书架还是空的\n点击右上角“+”添加第一本书",
        subtitle: "导入本地文件后，可以在这里继续阅读、筛选和管理藏书"
    )
    private let fabButton = UIButton(type: .system)
    private let topAddButton = UIButton(type: .system)
    private let sortButton = UIButton(type: .system)
    private let toggleButton = UIButton(type: .system)
    private lazy var editButton = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEditMode))
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let taglineLabel = UILabel()
    private let navigationTitleStack = UIStackView()
    private let summaryLabel = UILabel()
    private let continueView = UIButton(type: .custom)
    private let continueEyebrowLabel = UILabel()
    private let continueTitleLabel = UILabel()
    private let continueSubtitleLabel = UILabel()
    private let continueProgressBar = UIProgressView()
    private let continueProgressLabel = UILabel()
    private let continueButton = UIButton(type: .system)
    private let continueGradientLayer = CAGradientLayer()
    private let sectionHeaderView = UIView()
    private let sectionTitleStack = UIStackView()
    private let sectionActionsStack = UIStackView()
    private let sectionTitleLabel = UILabel()
    private let sectionCountLabel = UILabel()
    private let sectionEditButton = UIButton(type: .system)
    private let sectionSortButton = UIButton(type: .system)
    private let sectionMoreButton = UIButton(type: .system)
    private let bottomNavView = UIView()
    private let bottomShelfButton = LVModuleButton(type: .system)
    private let bottomNotesButton = LVModuleButton(type: .system)
    private let bottomMineButton = LVModuleButton(type: .system)
    private let filterScrollView = UIScrollView()
    private let filterStackView = UIStackView()
    private let skeletonContainer = UIView()

    // MARK: - Init

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        tableView = UITableView(frame: .zero, style: .plain)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDarkModeChanged),
            name: .darkModeChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webSyncStateChanged),
            name: .webSyncConnectionStateChanged,
            object: nil
        )
        loadBooks()
    }

    @objc private func appDarkModeChanged() {
        applyReadingThemeToHome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        ImageCacheManager.shared.clearMemoryCache()
        applyReadingThemeToHome()
        loadBooks()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if transitionCoordinator?.viewController(forKey: .to) is ContinuousReaderViewController {
            return
        }
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        continueGradientLayer.frame = continueView.bounds
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .lvBgDay
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false

        titleLabel.text = "LV Read"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textAlignment = .left
        titleLabel.backgroundColor = .clear

        taglineLabel.text = LVModuleSubtitleProvider.subtitle(for: .shelf)
        taglineLabel.font = .systemFont(ofSize: 14, weight: .regular)
        taglineLabel.textAlignment = .left
        taglineLabel.backgroundColor = .clear

        navigationTitleStack.addArrangedSubview(titleLabel)
        navigationTitleStack.addArrangedSubview(taglineLabel)
        navigationTitleStack.axis = .vertical
        navigationTitleStack.alignment = .leading
        navigationTitleStack.spacing = 2
        navigationTitleStack.backgroundColor = .clear

        topAddButton.setImage(UIImage(systemName: "plus"), for: .normal)
        topAddButton.setPreferredSymbolConfiguration(.init(pointSize: 18, weight: .medium), forImageIn: .normal)
        topAddButton.backgroundColor = UIColor(hex: "#FFFDF8")
        topAddButton.layer.cornerRadius = 23
        topAddButton.layer.borderWidth = 1
        topAddButton.layer.borderColor = UIColor(hex: "#E3DBCF").cgColor
        topAddButton.layer.shadowColor = UIColor(hex: "#2A221A").cgColor
        topAddButton.layer.shadowOffset = CGSize(width: 0, height: 10)
        topAddButton.layer.shadowRadius = 22
        topAddButton.layer.shadowOpacity = 0.08
        topAddButton.addTarget(self, action: #selector(addBookTapped), for: .touchUpInside)

        // Sort button
        sortButton.setImage(UIImage(systemName: "arrow.up.arrow.down"), for: .normal)
        sortButton.setPreferredSymbolConfiguration(.init(pointSize: 14, weight: .medium), forImageIn: .normal)
        sortButton.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        sortButton.tintColor = .white
        sortButton.addTarget(self, action: #selector(sortTapped), for: .touchUpInside)

        // View toggle button
        toggleButton.setImage(UIImage(systemName: "square.grid.2x2"), for: .normal)
        toggleButton.setPreferredSymbolConfiguration(.init(pointSize: 15, weight: .medium), forImageIn: .normal)
        toggleButton.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        toggleButton.tintColor = .white
        toggleButton.addTarget(self, action: #selector(toggleViewMode), for: .touchUpInside)
        

        // Edit button
        editButton.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14, weight: .medium)], for: .normal)
        editButton.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14, weight: .medium)], for: .highlighted)
        editButton.tintColor = .white

        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItems = nil

        headerView.layer.cornerRadius = 0
        summaryLabel.font = .systemFont(ofSize: 14, weight: .medium)
        summaryLabel.numberOfLines = 1
        headerView.addSubviews(navigationTitleStack, topAddButton)
        view.addSubview(headerView)

        continueView.layer.cornerRadius = 8
        continueView.clipsToBounds = false
        continueView.layer.shadowColor = UIColor(hex: "#2A221A").cgColor
        continueView.layer.shadowOffset = CGSize(width: 0, height: 18)
        continueView.layer.shadowRadius = 42
        continueView.layer.shadowOpacity = 0.12
        continueGradientLayer.colors = [UIColor(hex: "#236D67").cgColor, UIColor(hex: "#2D425D").cgColor]
        continueGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        continueGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        continueGradientLayer.cornerRadius = 8
        continueView.layer.insertSublayer(continueGradientLayer, at: 0)
        continueEyebrowLabel.text = "继续阅读"
        continueEyebrowLabel.font = .systemFont(ofSize: 13, weight: .medium)
        continueEyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.74)
        continueTitleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        continueTitleLabel.textColor = .white
        continueSubtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        continueSubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        continueProgressBar.trackTintColor = UIColor.white.withAlphaComponent(0.22)
        continueProgressBar.progressTintColor = .white
        continueProgressBar.layer.cornerRadius = 3.5
        continueProgressBar.clipsToBounds = true
        continueProgressLabel.font = .systemFont(ofSize: 13, weight: .bold)
        continueProgressLabel.textColor = .white
        continueButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        continueButton.tintColor = .white
        continueButton.layer.cornerRadius = 17
        continueButton.layer.borderWidth = 1
        continueButton.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        continueButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        continueButton.isUserInteractionEnabled = false
        continueButton.isAccessibilityElement = false
        continueView.addTarget(self, action: #selector(continueReadingTapped), for: .touchUpInside)
        continueView.accessibilityTraits = .button
        continueView.accessibilityLabel = "继续阅读"
        continueView.addSubviews(continueEyebrowLabel, continueTitleLabel, continueSubtitleLabel, continueProgressBar, continueProgressLabel, continueButton)
        view.addSubview(continueView)

        sectionTitleLabel.text = "我的书籍"
        sectionTitleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        sectionTitleLabel.textColor = .lvTextPrimary
        sectionTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sectionCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sectionCountLabel.textColor = UIColor(hex: "#7C746B")
        sectionCountLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sectionCountLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sectionTitleStack.axis = .horizontal
        sectionTitleStack.alignment = .center
        sectionTitleStack.spacing = 8
        sectionTitleStack.backgroundColor = .clear
        sectionTitleStack.addArrangedSubview(sectionTitleLabel)
        sectionActionsStack.axis = .horizontal
        sectionActionsStack.alignment = .center
        sectionActionsStack.spacing = 8
        sectionActionsStack.backgroundColor = .clear
        sectionCountLabel.isHidden = true
        sectionEditButton.setImage(UIImage(systemName: "pencil"), for: .normal)
        sectionEditButton.addTarget(self, action: #selector(toggleEditMode), for: .touchUpInside)
        sectionSortButton.setImage(UIImage(systemName: "arrow.up.arrow.down"), for: .normal)
        sectionSortButton.addTarget(self, action: #selector(sortTapped), for: .touchUpInside)
        sectionMoreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        sectionMoreButton.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .bold), forImageIn: .normal)
        sectionMoreButton.addTarget(self, action: #selector(moreActionsTapped), for: .touchUpInside)
        [sectionEditButton, sectionSortButton, toggleButton, sectionMoreButton].forEach {
            $0.tintColor = UIColor(hex: "#236D67")
            $0.backgroundColor = UIColor(hex: "#FFFDF8")
            $0.layer.cornerRadius = 18
            $0.layer.borderWidth = 1
            $0.layer.borderColor = UIColor(hex: "#E3DBCF").cgColor
            $0.layer.shadowColor = UIColor(hex: "#2A221A").cgColor
            $0.layer.shadowOffset = CGSize(width: 0, height: 8)
            $0.layer.shadowRadius = 18
            $0.layer.shadowOpacity = 0.06
        }
        sectionActionsStack.addArrangedSubview(sectionMoreButton)
        sectionHeaderView.addSubviews(sectionTitleStack, sectionActionsStack)
        sectionHeaderView.backgroundColor = .clear
        view.addSubview(sectionHeaderView)

        configureBottomNavigation()

        // Filter chips
        filterScrollView.showsHorizontalScrollIndicator = false
        filterStackView.axis = .horizontal
        filterStackView.spacing = 8
        filterScrollView.addSubview(filterStackView)
        view.addSubview(filterScrollView)

        let chips = ["全部", "阅读中", "待读", "已读完", "收藏"]
        for (idx, title) in chips.enumerated() {
            let chip = createFilterChip(title: title, tag: idx)
            filterStackView.addArrangedSubview(chip)
        }

        // Collection view (grid)
        collectionView.backgroundColor = .lvBgDay
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(BookCell.self, forCellWithReuseIdentifier: BookCell.reuseIdentifier)
        collectionView.alwaysBounceVertical = true
        collectionView.isHidden = true

        // Table view (list)
        tableView.backgroundColor = .lvBgDay
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(BookListCell.self, forCellReuseIdentifier: BookListCell.reuseIdentifier)
        tableView.rowHeight = 116
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        tableView.isHidden = false

        // Empty state
        emptyStateView.onAction = { [weak self] in self?.addBookTapped() }
        emptyStateView.isHidden = true

        // FAB
        fabButton.backgroundColor = .lvSecondary
        fabButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)),
            for: .normal
        )
        fabButton.tintColor = .white
        fabButton.layer.cornerRadius = 28
        fabButton.layer.shadowColor = UIColor.lvSecondary.cgColor
        fabButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        fabButton.layer.shadowRadius = 8
        fabButton.layer.shadowOpacity = 0.4
        fabButton.addTarget(self, action: #selector(addBookTapped), for: .touchUpInside)
        fabButton.isHidden = true

        // Skeleton for initial load
        for _ in 0..<8 {
            skeletonContainer.addSubview(LVSkeletonCell())
        }
        skeletonContainer.isHidden = true

        view.addSubviews(collectionView, tableView, emptyStateView, fabButton, skeletonContainer)

        // Layout
        headerView.translatesAutoresizingMaskIntoConstraints = false
        navigationTitleStack.translatesAutoresizingMaskIntoConstraints = false
        topAddButton.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        continueView.translatesAutoresizingMaskIntoConstraints = false
        continueEyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        continueTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        continueSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        continueProgressBar.translatesAutoresizingMaskIntoConstraints = false
        continueProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        sectionHeaderView.translatesAutoresizingMaskIntoConstraints = false
        sectionTitleStack.translatesAutoresizingMaskIntoConstraints = false
        sectionActionsStack.translatesAutoresizingMaskIntoConstraints = false
        sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionCountLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionEditButton.translatesAutoresizingMaskIntoConstraints = false
        sectionSortButton.translatesAutoresizingMaskIntoConstraints = false
        sectionMoreButton.translatesAutoresizingMaskIntoConstraints = false
        bottomNavView.translatesAutoresizingMaskIntoConstraints = false
        bottomShelfButton.translatesAutoresizingMaskIntoConstraints = false
        bottomNotesButton.translatesAutoresizingMaskIntoConstraints = false
        bottomMineButton.translatesAutoresizingMaskIntoConstraints = false
        filterScrollView.translatesAutoresizingMaskIntoConstraints = false
        filterStackView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        fabButton.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        skeletonContainer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 82),

            navigationTitleStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 18),
            navigationTitleStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor, constant: -1),
            navigationTitleStack.trailingAnchor.constraint(lessThanOrEqualTo: topAddButton.leadingAnchor, constant: -14),

            topAddButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -18),
            topAddButton.centerYAnchor.constraint(equalTo: navigationTitleStack.centerYAnchor),
            topAddButton.widthAnchor.constraint(equalToConstant: 46),
            topAddButton.heightAnchor.constraint(equalToConstant: 46),

            filterScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 56),

            filterStackView.topAnchor.constraint(equalTo: filterScrollView.topAnchor, constant: 8),
            filterStackView.leadingAnchor.constraint(equalTo: filterScrollView.leadingAnchor, constant: 16),
            filterStackView.trailingAnchor.constraint(equalTo: filterScrollView.trailingAnchor, constant: -16),
            filterStackView.bottomAnchor.constraint(equalTo: filterScrollView.bottomAnchor, constant: -8),
            filterStackView.heightAnchor.constraint(equalToConstant: 36),

            continueView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor, constant: 2),
            continueView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            continueView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            continueView.heightAnchor.constraint(equalToConstant: 140),

            continueEyebrowLabel.topAnchor.constraint(equalTo: continueView.topAnchor, constant: 20),
            continueEyebrowLabel.leadingAnchor.constraint(equalTo: continueView.leadingAnchor, constant: 16),
            continueButton.centerYAnchor.constraint(equalTo: continueEyebrowLabel.centerYAnchor),
            continueButton.trailingAnchor.constraint(equalTo: continueView.trailingAnchor, constant: -16),
            continueButton.widthAnchor.constraint(equalToConstant: 34),
            continueButton.heightAnchor.constraint(equalToConstant: 34),
            continueTitleLabel.topAnchor.constraint(equalTo: continueEyebrowLabel.bottomAnchor, constant: 16),
            continueTitleLabel.leadingAnchor.constraint(equalTo: continueView.leadingAnchor, constant: 16),
            continueTitleLabel.trailingAnchor.constraint(equalTo: continueView.trailingAnchor, constant: -16),
            continueSubtitleLabel.topAnchor.constraint(equalTo: continueTitleLabel.bottomAnchor, constant: 8),
            continueSubtitleLabel.leadingAnchor.constraint(equalTo: continueTitleLabel.leadingAnchor),
            continueSubtitleLabel.trailingAnchor.constraint(equalTo: continueTitleLabel.trailingAnchor),
            continueProgressBar.leadingAnchor.constraint(equalTo: continueTitleLabel.leadingAnchor),
            continueProgressBar.trailingAnchor.constraint(equalTo: continueProgressLabel.leadingAnchor, constant: -10),
            continueProgressBar.bottomAnchor.constraint(equalTo: continueView.bottomAnchor, constant: -20),
            continueProgressBar.heightAnchor.constraint(equalToConstant: 7),
            continueProgressLabel.centerYAnchor.constraint(equalTo: continueProgressBar.centerYAnchor),
            continueProgressLabel.trailingAnchor.constraint(equalTo: continueView.trailingAnchor, constant: -16),

            sectionHeaderView.topAnchor.constraint(equalTo: continueView.bottomAnchor, constant: 22),
            sectionHeaderView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            sectionHeaderView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            sectionHeaderView.heightAnchor.constraint(equalToConstant: 44),
            sectionTitleStack.leadingAnchor.constraint(equalTo: sectionHeaderView.leadingAnchor),
            sectionTitleStack.centerYAnchor.constraint(equalTo: sectionHeaderView.centerYAnchor),
            sectionTitleStack.trailingAnchor.constraint(lessThanOrEqualTo: sectionActionsStack.leadingAnchor, constant: -12),
            sectionActionsStack.trailingAnchor.constraint(equalTo: sectionHeaderView.trailingAnchor),
            sectionActionsStack.centerYAnchor.constraint(equalTo: sectionHeaderView.centerYAnchor),
            sectionMoreButton.widthAnchor.constraint(equalToConstant: 44),
            sectionMoreButton.heightAnchor.constraint(equalToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: sectionHeaderView.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomNavView.topAnchor),

            tableView.topAnchor.constraint(equalTo: sectionHeaderView.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomNavView.topAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            emptyStateView.widthAnchor.constraint(equalTo: view.widthAnchor),

            fabButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            fabButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            fabButton.widthAnchor.constraint(equalToConstant: 56),
            fabButton.heightAnchor.constraint(equalToConstant: 56),

            skeletonContainer.topAnchor.constraint(equalTo: sectionHeaderView.bottomAnchor),
            skeletonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonContainer.heightAnchor.constraint(equalToConstant: 400),

            bottomNavView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomNavView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomNavView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomNavView.heightAnchor.constraint(equalToConstant: 76)
        ])

        applyReadingThemeToHome()
    }

    private func setupBindings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookImported),
            name: .bookImported,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readingSettingsChanged),
            name: NSNotification.Name("LVReadSettingsChanged"),
            object: nil
        )
    }

    private func configureBottomNavigation() {
        bottomNavView.backgroundColor = LVBookshelfModuleStyle.cardBackground
        bottomNavView.layer.borderWidth = 1
        bottomNavView.layer.borderColor = LVBookshelfModuleStyle.divider.cgColor
        view.addSubview(bottomNavView)

        let stack = UIStackView(arrangedSubviews: [bottomShelfButton, bottomNotesButton, bottomMineButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomNavView.addSubview(stack)

        configureBottomNavButton(bottomShelfButton, title: "LVRead", icon: "book.closed", active: true)
        configureBottomNavButton(bottomNotesButton, title: "笔记", icon: "bookmark", active: false)
        configureBottomNavButton(bottomMineButton, title: "我的", icon: "person", active: false)
        bottomNotesButton.addTarget(self, action: #selector(openNotesModule), for: .touchUpInside)
        bottomMineButton.addTarget(self, action: #selector(openProfileModule), for: .touchUpInside)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bottomNavView.topAnchor, constant: 9),
            stack.leadingAnchor.constraint(equalTo: bottomNavView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: bottomNavView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomNavView.bottomAnchor, constant: -13)
        ])
    }

    @objc private func openNotesModule() {
        showMainModule(.notes)
    }

    @objc private func openProfileModule() {
        showMainModule(.profile)
    }

    private func configureBottomNavButton(_ button: UIButton, title: String, icon: String, active: Bool) {
        let color = active ? LVBookshelfModuleStyle.accent : LVBookshelfModuleStyle.secondaryText
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.setTitle(title, for: .normal)
        button.tintColor = color
        button.setTitleColor(color, for: .normal)
        button.backgroundColor = active
            ? LVBookshelfModuleStyle.accent.withAlphaComponent(0.14)
            : .clear
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: active ? .bold : .regular)
        button.imageView?.contentMode = .scaleAspectFit
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
    }

    private func applyReadingThemeToHome() {
        let isDark = DarkModeManager.shared.isDarkMode
        let background = LVBookshelfModuleStyle.pageBackground
        let panel = LVBookshelfModuleStyle.cardBackground
        let text = LVBookshelfModuleStyle.primaryText
        let secondaryText = LVBookshelfModuleStyle.secondaryText
        let divider = LVBookshelfModuleStyle.divider
        let accent = LVBookshelfModuleStyle.accent

        view.backgroundColor = background
        headerView.backgroundColor = background
        titleLabel.textColor = text
        taglineLabel.textColor = text.withAlphaComponent(0.62)
        summaryLabel.textColor = text.withAlphaComponent(0.72)
        collectionView.backgroundColor = background
        tableView.backgroundColor = background
        filterScrollView.backgroundColor = background
        skeletonContainer.backgroundColor = background
        sectionHeaderView.backgroundColor = .clear
        sectionTitleLabel.textColor = text
        sectionCountLabel.textColor = secondaryText
        bottomNavView.backgroundColor = panel
        bottomNavView.layer.borderColor = divider.cgColor
        let theme = DarkModeManager.shared.currentTheme
        let usesClassicContinueStyle: Bool = {
            switch theme {
            case .bookshelf, .warmYellow, .mint, .latte: return true
            default: return false
            }
        }()
        if usesClassicContinueStyle {
            continueGradientLayer.colors = [accent.cgColor, accent.darker(by: 0.16).cgColor]
            continueView.layer.borderWidth = 0
            continueEyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.74)
            continueTitleLabel.textColor = .white
            continueSubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
            continueProgressBar.trackTintColor = UIColor.white.withAlphaComponent(0.22)
            continueProgressBar.progressTintColor = .white
            continueProgressLabel.textColor = .white
            continueButton.tintColor = .white
            continueButton.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
            continueButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        } else {
            continueGradientLayer.colors = [
                UIColor(hex: theme.panelColor).cgColor,
                UIColor(hex: theme.controlSurfaceColor).cgColor
            ]
            continueView.layer.borderWidth = 1
            continueView.layer.borderColor = accent.withAlphaComponent(0.22).cgColor
            continueEyebrowLabel.textColor = accent
            continueTitleLabel.textColor = text
            continueSubtitleLabel.textColor = secondaryText
            continueProgressBar.trackTintColor = divider
            continueProgressBar.progressTintColor = accent
            continueProgressLabel.textColor = accent
            continueButton.tintColor = accent
            continueButton.layer.borderColor = accent.withAlphaComponent(0.28).cgColor
            continueButton.backgroundColor = accent.withAlphaComponent(0.10)
        }
        continueView.layer.shadowColor = (isDark ? UIColor.black : UIColor(hex: "#2A221A")).cgColor
        topAddButton.backgroundColor = panel
        topAddButton.layer.borderColor = divider.cgColor

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: text]
        appearance.largeTitleTextAttributes = [.foregroundColor: text]
        
        
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = accent

        sortButton.tintColor = accent
        toggleButton.tintColor = accent
        topAddButton.tintColor = text
        editButton.tintColor = accent
        fabButton.backgroundColor = accent
        fabButton.layer.shadowColor = accent.cgColor

        configureBottomNavButton(bottomShelfButton, title: "LVRead", icon: "book.closed", active: true)
        configureBottomNavButton(bottomNotesButton, title: "笔记", icon: "bookmark", active: false)
        configureBottomNavButton(bottomMineButton, title: "我的", icon: "person", active: false)

        updateFilterChipColors()
        collectionView.visibleCells.compactMap { $0 as? BookCell }.forEach { $0.applyAppearance() }
        tableView.visibleCells.compactMap { $0 as? BookListCell }.forEach { $0.applyAppearance() }
    }

    @objc private func webSyncStateChanged() {
        collectionView.reloadData()
        tableView.reloadData()
    }

    private func updateFilterChipColors() {
        let panel = LVBookshelfModuleStyle.cardBackground
        let text = LVBookshelfModuleStyle.secondaryText
        let accent = LVBookshelfModuleStyle.primaryText
        let divider = LVBookshelfModuleStyle.divider
        for case let chip as UIButton in filterStackView.arrangedSubviews {
            let selected = isChipSelected(chip)
            chip.backgroundColor = selected ? accent : panel
            chip.layer.borderColor = (selected ? accent : divider).cgColor
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: selected ? .bold : .medium)
            chip.setTitleColor(selected ? LVBookshelfModuleStyle.pageBackground : text, for: .normal)
        }
    }

    private func isChipSelected(_ chip: UIButton) -> Bool {
        switch chip.tag {
        case 0: return progressFilter == .all && sourceFilter == nil && !favoriteOnly
        case 1: return progressFilter == .reading
        case 2: return progressFilter == .unread
        case 3: return progressFilter == .finished
        case 4: return favoriteOnly
        default: return false
        }
    }

    // MARK: - Data

    private func loadBooks() {
        if isInitialLoad {
            skeletonContainer.isHidden = false
            isInitialLoad = false
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let allBooks = BookRepository.shared.getAll(sortBy: self.currentSort)
            DispatchQueue.main.async {
                self.skeletonContainer.isHidden = true
                self.books = allBooks
                self.applyFilters()
            }
        }
    }

    private func applyFilters() {
        var result = books

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let sourceFilter = sourceFilter {
            result = result.filter { $0.source == sourceFilter }
        }

        if favoriteOnly {
            result = result.filter { $0.isFavorite }
        }

        if progressFilter != .all {
            result = result.filter { progressFilter.matches($0.readingProgress) }
        }

        filteredBooks = result
        let readingCount = books.filter { $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100 }.count
        let hasNoBooks = books.isEmpty
        summaryLabel.text = nil
        updateFilterChipTitles(readingCount: readingCount)
        emptyStateView.isHidden = !filteredBooks.isEmpty
        filterScrollView.isHidden = hasNoBooks
        sectionHeaderView.isHidden = hasNoBooks

        if hasNoBooks {
            emptyStateView.updateIcon("books.vertical")
            emptyStateView.updateTitle("书架还是空的\n点击右上角“+”添加第一本书")
            emptyStateView.updateSubtitle("导入本地文件后，可以在这里继续阅读、筛选和管理藏书")
        } else if filteredBooks.isEmpty {
            emptyStateView.updateIcon("line.3.horizontal.decrease.circle")
            emptyStateView.updateTitle("没有找到符合条件的书籍")
            emptyStateView.updateSubtitle("请尝试调整筛选条件或搜索关键词")
        }

        updateContinueCard()
        collectionView.reloadData()
        tableView.reloadData()
    }

    private func updateFilterChipTitles(readingCount: Int) {
        let unreadCount = books.filter { $0.readingProgress.progressPercent <= 0 }.count
        let finishedCount = books.filter { $0.readingProgress.progressPercent >= 100 }.count
        let favoriteCount = books.filter { $0.isFavorite }.count
        let titles = [
            0: "全部",
            1: "阅读中 \(readingCount)",
            2: "待读 \(unreadCount)",
            3: "已读完 \(finishedCount)",
            4: "收藏 \(favoriteCount)"
        ]
        for case let chip as UIButton in filterStackView.arrangedSubviews {
            chip.setTitle(titles[chip.tag], for: .normal)
        }
        updateFilterChipColors()
    }

    private func updateContinueCard() {
        let candidate = books.first {
            $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100
        } ?? books.first

        guard let book = candidate else {
            continueView.isHidden = true
            return
        }

        continueView.isHidden = false
        continueTitleLabel.text = book.title
        continueSubtitleLabel.text = "\(book.author) · 第\(book.readingProgress.currentChapterIndex + 1)章 · \(book.fileFormat.displayName)"
        continueProgressBar.progress = Float(book.readingProgress.progressPercent / 100)
        continueProgressLabel.text = String(format: "%.0f%%", book.readingProgress.progressPercent)
        continueView.accessibilityLabel = "继续阅读《\(book.title)》，进度 \(continueProgressLabel.text ?? "")"
    }

    // MARK: - Actions

    @objc private func addBookTapped() {
        let alert = UIAlertController(title: "导入书籍", message: nil, preferredStyle: .actionSheet)
        let localAction = UIAlertAction(title: "从本地文件导入", style: .default) { [weak self] _ in
            self?.presentFilePicker()
        }
        localAction.setValue(UIImage(systemName: "doc.badge.plus"), forKey: "image")
        alert.addAction(localAction)

        let transferAction = UIAlertAction(title: "同网传输", style: .default) { [weak self] _ in
            let transferVC = TransferDeviceListViewController()
            self?.navigationController?.pushViewController(transferVC, animated: true)
        }
        transferAction.setValue(UIImage(systemName: "wifi"), forKey: "image")
        alert.addAction(transferAction)

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = topAddButton
        }
        present(alert, animated: true)
    }

    @objc private func moreActionsTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let editAction = UIAlertAction(title: isEditingMode ? "完成编辑" : "编辑", style: .default) { [weak self] _ in
            self?.toggleEditMode()
        }
        editAction.setValue(UIImage(systemName: isEditingMode ? "checkmark.circle" : "pencil"), forKey: "image")
        alert.addAction(editAction)

        let sortAction = UIAlertAction(title: "排序", style: .default) { [weak self] _ in
            DispatchQueue.main.async {
                self?.sortTapped()
            }
        }
        sortAction.setValue(UIImage(systemName: "arrow.up.arrow.down"), forKey: "image")
        alert.addAction(sortAction)

        let viewAction = UIAlertAction(title: isGridView ? "列表方式" : "宫格方式", style: .default) { [weak self] _ in
            self?.toggleViewMode()
        }
        viewAction.setValue(UIImage(systemName: isGridView ? "list.bullet" : "square.grid.2x2"), forKey: "image")
        alert.addAction(viewAction)

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sectionMoreButton
            popover.sourceRect = sectionMoreButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func continueReadingTapped() {
        guard let book = books.first(where: {
            $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100
        }) ?? books.first else { return }
        openReader(for: book)
    }

    private func presentFilePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .epub, .plainText, .pdf, .data
        ], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func sortTapped() {
        let alert = UIAlertController(title: "排序方式", message: nil, preferredStyle: .actionSheet)
        for sortType in BookSortType.allCases {
            let title = sortType.rawValue
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.currentSort = sortType
                self?.loadBooks()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sectionMoreButton
            popover.sourceRect = sectionMoreButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func toggleViewMode() {
        isGridView.toggle()
        collectionView.isHidden = !isGridView
        tableView.isHidden = isGridView
        let iconName = isGridView ? "list.bullet" : "square.grid.2x2"
        toggleButton.setImage(UIImage(systemName: iconName), for: .normal)
        collectionView.reloadData()
        tableView.reloadData()
    }
    
    @objc private func toggleEditMode() {
        
        isEditingMode.toggle()
        selectedBookIds.removeAll()
        sectionMoreButton.backgroundColor = isEditingMode ? UIColor(hex: "#DCEFEB") : UIColor(hex: "#FFFDF8")

        if isEditingMode {
            let deleteBarItem = UIBarButtonItem(
                title: "删除",
                style: .plain,
                target: self,
                action: #selector(batchDelete)
            )
            deleteBarItem.tintColor = .lvError
            navigationItem.leftBarButtonItem = deleteBarItem
        } else {
            navigationItem.leftBarButtonItem = nil
        }
        collectionView.reloadData()
    }

    @objc private func batchDelete() {
        guard !selectedBookIds.isEmpty else { return }
        let alert = UIAlertController(
            title: "确定删除 \(selectedBookIds.count) 本书？",
            message: "该操作不可撤销",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            _ = BookRepository.shared.deleteBatch(Array(self.selectedBookIds))
            self.selectedBookIds.removeAll()
            self.toggleEditMode()
            self.loadBooks()
            LVToast.show(message: "已删除", style: .info)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func bookImported() {
        loadBooks()
    }

    @objc private func readingSettingsChanged() {
        applyReadingThemeToHome()
        collectionView.reloadData()
        tableView.reloadData()
    }

    // MARK: - Book Actions

    private func showBookActions(for book: Book, at indexPath: IndexPath) {
        let alert = UIAlertController(title: book.title, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "✏️ 修改信息", style: .default) { [weak self] _ in
            self?.showRenameDialog(for: book)
        })
        alert.addAction(UIAlertAction(title: "🖼️ 修改封面", style: .default) { [weak self] _ in
            self?.showChangeCover(for: book)
        })
        alert.addAction(UIAlertAction(title: "📤 分享", style: .default) { [weak self] _ in
            self?.shareBook(book)
        })
        alert.addAction(UIAlertAction(title: "🗑️ 删除", style: .destructive) { [weak self] _ in
            self?.confirmDelete(book)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showRenameDialog(for book: Book) {
        let alert = UIAlertController(title: "修改书名", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = book.title }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let newTitle = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !newTitle.isEmpty else { return }
            var updated = book
            updated.title = String(newTitle.prefix(50))
            switch BookRepository.shared.update(updated) {
            case .success:
                self?.loadBooks()
                LVToast.show(message: "书名已修改", style: .success)
            case .failure:
                LVToast.show(message: "修改失败，请稍后重试", style: .error)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showChangeCover(for book: Book) {
        pendingCoverBook = book
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.allowsEditing = true
        present(picker, animated: true)
    }

    private func shareBook(_ book: Book) {
        let url = URL(fileURLWithPath: book.resolvedFilePath())
        guard FileManager.default.fileExists(atPath: url.path) else {
            LVToast.show(message: "原文件不存在，无法分享", style: .error)
            return
        }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(activityVC, animated: true)
    }

    private func confirmDelete(_ book: Book) {
        let alert = UIAlertController(
            title: "确定删除《\(book.title)》？",
            message: "该操作不可撤销",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            _ = BookRepository.shared.delete(book.id)
            self?.loadBooks()
            LVToast.show(message: "已删除", style: .info)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func openReader(for book: Book) {
        let filePath = book.resolvedFilePath()
        guard FileManager.default.fileExists(atPath: filePath) else {
            LVToast.show(message: "原文件不存在，请重新导入", style: .error)
            return
        }
        if book.fileFormat != .pdf,
           BookRepository.shared.getChapters(for: book.id).isEmpty {
            do {
                let metadata = try BookImportManager.shared.parserFor(format: book.fileFormat)
                    .parseMetadata(filePath: filePath)
                let restored = metadata.chapters.enumerated().map { index, chapter in
                    Chapter(
                        bookId: book.id,
                        title: chapter.title,
                        level: chapter.level,
                        orderIndex: index,
                        startOffset: chapter.startOffset,
                        endOffset: chapter.endOffset,
                        pageCount: chapter.pageCount,
                        internalHref: chapter.internalHref
                    )
                }
                guard !restored.isEmpty else {
                    LVToast.show(message: "无法恢复章节，请重新导入", style: .error)
                    return
                }
                BookRepository.shared.insertChapters(restored)
            } catch {
                LVToast.show(message: "章节恢复失败，请重新导入", style: .error)
                return
            }
        }
        let readerVC = NativeDocumentReaderViewController(book: book)
        navigationController?.pushViewController(readerVC, animated: true)
    }

    private func openWebSync(for book: Book) {
        guard let page = WebSyncServer.shared.savedPageSnapshot(for: book.id) else {
            LVToast.show(message: "请先打开《\(book.title)》生成阅读页面", style: .info)
            return
        }
        present(WebSyncViewController(book: book, page: page), animated: true)
    }

    // MARK: - Filter Chips

    private func createFilterChip(title: String, tag: Int) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        chip.backgroundColor = UIColor(hex: "#FFFDF8")
        chip.setTitleColor(UIColor(hex: "#7C746B"), for: .normal)
        chip.layer.cornerRadius = 18
        chip.layer.borderWidth = 1
        chip.layer.borderColor = UIColor(hex: "#E3DBCF").cgColor
        chip.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        chip.tag = tag
        chip.addTarget(self, action: #selector(filterChipTapped(_:)), for: .touchUpInside)
        chip.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return chip
    }

    @objc private func filterChipTapped(_ sender: UIButton) {
        favoriteOnly = false
        switch sender.tag {
        case 0: progressFilter = .all; sourceFilter = nil
        case 1: progressFilter = .reading
        case 2: progressFilter = .unread
        case 3: progressFilter = .finished
        case 4: progressFilter = .all; favoriteOnly = true
        default: break
        }
        updateFilterChipColors()
        applyFilters()
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension BookshelfViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return filteredBooks.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: BookCell.reuseIdentifier,
            for: indexPath
        ) as! BookCell
        if indexPath.item < filteredBooks.count {
            let book = filteredBooks[indexPath.item]
            cell.configure(
                with: book,
                syncConnected: WebSyncServer.shared.isConnected(to: book.id)
            )
            cell.onSyncTapped = { [weak self] in self?.openWebSync(for: book) }
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let padding: CGFloat = 16
        let spacing: CGFloat = 8
        let availableWidth = view.bounds.width - (padding * 2) - spacing * 2
        let width = availableWidth / 3
        let height = (width - 20) * 1.35 + 10 + 4 + 6 + 18 + 20
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < filteredBooks.count else { return }
        let book = filteredBooks[indexPath.item]
        if isEditingMode {
            if selectedBookIds.contains(book.id) {
                selectedBookIds.remove(book.id)
            } else {
                selectedBookIds.insert(book.id)
            }
            collectionView.reloadItems(at: [indexPath])
        } else {
            openReader(for: book)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.item < filteredBooks.count else { return nil }
        let book = filteredBooks[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let rename = UIAction(title: "修改信息", image: UIImage(systemName: "pencil")) { _ in
                self?.showRenameDialog(for: book)
            }
            let share = UIAction(title: "分享", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self?.shareBook(book)
            }
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDelete(book)
            }
            return UIMenu(children: [rename, share, delete])
        }
    }
}

// MARK: - UITableView DataSource & Delegate

extension BookshelfViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredBooks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: BookListCell.reuseIdentifier,
            for: indexPath
        ) as! BookListCell
        let book = filteredBooks[indexPath.row]
        cell.configure(
            with: book,
            syncConnected: WebSyncServer.shared.isConnected(to: book.id)
        )
        cell.onSyncTapped = { [weak self] in self?.openWebSync(for: book) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openReader(for: filteredBooks[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard filteredBooks.indices.contains(indexPath.row) else { return nil }
        let book = filteredBooks[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.confirmDelete(book)
            completion(true)
        }
        let share = UIContextualAction(style: .normal, title: "分享") { [weak self] _, _, completion in
            self?.shareBook(book)
            completion(true)
        }
        share.backgroundColor = UIColor(hex: "#236D67")
        return UISwipeActionsConfiguration(actions: [delete, share])
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard filteredBooks.indices.contains(indexPath.row) else { return nil }
        let book = filteredBooks[indexPath.row]
        let rename = UIContextualAction(style: .normal, title: "改名") { [weak self] _, _, completion in
            self?.showRenameDialog(for: book)
            completion(true)
        }
        rename.backgroundColor = UIColor(hex: "#C2933D")
        return UISwipeActionsConfiguration(actions: [rename])
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard filteredBooks.indices.contains(indexPath.row) else { return nil }
        let book = filteredBooks[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let rename = UIAction(title: "修改书名", image: UIImage(systemName: "pencil")) { _ in
                self?.showRenameDialog(for: book)
            }
            let share = UIAction(title: "分享", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self?.shareBook(book)
            }
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDelete(book)
            }
            return UIMenu(children: [rename, share, delete])
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension BookshelfViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        let importVC = ImportProgressViewController()
        importVC.modalPresentationStyle = .overFullScreen
        importVC.modalTransitionStyle = .crossDissolve
        present(importVC, animated: true)

        BookImportManager.shared.importFileWithProgress(
            from: url,
            progressHandler: { progress, statusText in
                DispatchQueue.main.async {
                    importVC.updateProgress(progress, statusText: statusText)
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    importVC.dismiss(animated: true) {
                        switch result {
                        case .success:
                            LVToast.show(message: "导入成功!", style: .success)
                            self.loadBooks()
                        case .failure(let error):
                            LVToast.show(message: error.localizedDescription, style: .error)
                        }
                    }
                }
            }
        )
    }
}

// MARK: - UIImagePickerControllerDelegate, UINavigationControllerDelegate

extension BookshelfViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
    }
}
