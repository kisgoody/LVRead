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
    private var isGridView = true
    private var isEditingMode = false
    private var selectedBookIds: Set<String> = []
    private var searchText = ""
    private var currentSort: BookSortType = .recentRead
    private var progressFilter: ReadingProgressFilter = .all
    private var sourceFilter: BookSource? = nil
    private var isInitialLoad = true
    private var pendingCoverBook: Book?

    // MARK: - UI Components

    private let searchController = UISearchController(searchResultsController: nil)

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
        icon: "📚",
        title: "书架空空如也",
        subtitle: "点击右下角 + 按钮导入你的第一本书籍",
        actionTitle: "导入书籍"
    )
    private let fabButton = UIButton(type: .system)
    private let sortButton = UIButton(type: .system)
    private let toggleButton = UIButton(type: .system)
    private lazy var editButton = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEditMode))
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let taglineLabel = UILabel()
    private let summaryLabel = UILabel()
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
        loadBooks()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ImageCacheManager.shared.clearMemoryCache()
        applyReadingThemeToHome()
        loadBooks()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .lvBgDay
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false

        titleLabel.text = "LV Read"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center

        taglineLabel.text = "为文字而生，因阅读而狂热"
        taglineLabel.font = .systemFont(ofSize: 11, weight: .medium)
        taglineLabel.textAlignment = .center

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, taglineLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 0
        navigationItem.titleView = titleStack

        // Search controller
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索书名或作者..."
        navigationItem.searchController = searchController

        // Sort button
        sortButton.setImage(UIImage(systemName: "arrow.up.arrow.down"), for: .normal)
        sortButton.setPreferredSymbolConfiguration(.init(pointSize: 14, weight: .medium), forImageIn: .normal)
        sortButton.frame = CGRect(x: 0, y: 0, width: 26, height: 32)
        sortButton.tintColor = .white
        sortButton.addTarget(self, action: #selector(sortTapped), for: .touchUpInside)
        let sortBarItem = UIBarButtonItem(customView: sortButton)

        // View toggle button
        toggleButton.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        toggleButton.tintColor = .white
        toggleButton.addTarget(self, action: #selector(toggleViewMode), for: .touchUpInside)
        let toggleBarItem = UIBarButtonItem(customView: toggleButton)

        // Edit button
        editButton.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14, weight: .medium)], for: .normal)
        editButton.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14, weight: .medium)], for: .highlighted)
        editButton.tintColor = .white

        navigationItem.rightBarButtonItems = [editButton, toggleBarItem, sortBarItem]

        headerView.layer.cornerRadius = 0
        summaryLabel.font = .systemFont(ofSize: 14, weight: .medium)
        summaryLabel.numberOfLines = 1
        headerView.addSubview(summaryLabel)
        view.addSubview(headerView)

        // Filter chips
        filterScrollView.showsHorizontalScrollIndicator = false
        filterStackView.axis = .horizontal
        filterStackView.spacing = 8
        filterScrollView.addSubview(filterStackView)
        view.addSubview(filterScrollView)

        let chips = ["全部", "未读", "在读", "已读完", "TXT", "EPUB", "PDF"]
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

        // Table view (list)
        tableView.backgroundColor = .lvBgDay
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(BookListCell.self, forCellReuseIdentifier: BookListCell.reuseIdentifier)
        tableView.rowHeight = 100
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 84, bottom: 0, right: 0)
        tableView.isHidden = true

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
        fabButton.addPulseAnimation()

        // Skeleton for initial load
        for _ in 0..<8 {
            skeletonContainer.addSubview(LVSkeletonCell())
        }
        skeletonContainer.isHidden = true

        view.addSubviews(collectionView, tableView, emptyStateView, fabButton, skeletonContainer)

        // Layout
        headerView.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
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
            headerView.heightAnchor.constraint(equalToConstant: 44),

            summaryLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            summaryLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            filterScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 44),

            filterStackView.topAnchor.constraint(equalTo: filterScrollView.topAnchor, constant: 8),
            filterStackView.leadingAnchor.constraint(equalTo: filterScrollView.leadingAnchor, constant: 16),
            filterStackView.trailingAnchor.constraint(equalTo: filterScrollView.trailingAnchor, constant: -16),
            filterStackView.bottomAnchor.constraint(equalTo: filterScrollView.bottomAnchor, constant: -8),
            filterStackView.heightAnchor.constraint(equalToConstant: 28),

            collectionView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            tableView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            emptyStateView.widthAnchor.constraint(equalTo: view.widthAnchor),

            fabButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            fabButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            fabButton.widthAnchor.constraint(equalToConstant: 56),
            fabButton.heightAnchor.constraint(equalToConstant: 56),

            skeletonContainer.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            skeletonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonContainer.heightAnchor.constraint(equalToConstant: 400)
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

    private func applyReadingThemeToHome() {
        let theme = ReadingSettingsRepository.shared.load().readingTheme
        let background = UIColor(hex: theme.backgroundColor)
        let panel = UIColor(hex: theme.panelColor)
        let text = UIColor(hex: theme.textColor)
        let accent = UIColor(hex: theme.accentColor)

        view.backgroundColor = background
        headerView.backgroundColor = background
        titleLabel.textColor = text
        taglineLabel.textColor = text.withAlphaComponent(0.62)
        summaryLabel.textColor = text.withAlphaComponent(0.72)
        collectionView.backgroundColor = background
        tableView.backgroundColor = background
        filterScrollView.backgroundColor = background
        skeletonContainer.backgroundColor = background

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = panel
        appearance.titleTextAttributes = [.foregroundColor: text]
        appearance.largeTitleTextAttributes = [.foregroundColor: text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = accent

        sortButton.tintColor = accent
        toggleButton.tintColor = accent
        editButton.tintColor = accent
        fabButton.backgroundColor = accent
        fabButton.layer.shadowColor = accent.cgColor

        updateFilterChipColors()
    }

    private func updateFilterChipColors() {
        let theme = ReadingSettingsRepository.shared.load().readingTheme
        let panel = UIColor(hex: theme.panelColor)
        let text = UIColor(hex: theme.textColor)
        let accent = UIColor(hex: theme.accentColor)
        for case let chip as UIButton in filterStackView.arrangedSubviews {
            let selected = isChipSelected(chip)
            chip.backgroundColor = selected ? accent : panel
            chip.setTitleColor(selected ? UIColor.white : text.withAlphaComponent(0.75), for: .normal)
        }
    }

    private func isChipSelected(_ chip: UIButton) -> Bool {
        switch chip.tag {
        case 0: return progressFilter == .all && sourceFilter == nil
        case 1: return progressFilter == .unread
        case 2: return progressFilter == .reading
        case 3: return progressFilter == .finished
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

        if progressFilter != .all {
            result = result.filter { progressFilter.matches($0.readingProgress) }
        }

        filteredBooks = result
        let readingCount = books.filter { $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100 }.count
        let finishedCount = books.filter { $0.readingProgress.progressPercent >= 100 }.count
        summaryLabel.text = "\(books.count) 本藏书 · \(readingCount) 本在读 · \(finishedCount) 本已读"
        emptyStateView.isHidden = !filteredBooks.isEmpty
        collectionView.reloadData()
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func addBookTapped() {
        let alert = UIAlertController(title: "导入书籍", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "📁 从本地文件导入", style: .default) { [weak self] _ in
            self?.presentFilePicker()
        })
        alert.addAction(UIAlertAction(title: "📡 同网传输", style: .default) { [weak self] _ in
            let transferVC = TransferDeviceListViewController()
            self?.navigationController?.pushViewController(transferVC, animated: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = fabButton
        }
        present(alert, animated: true)
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
        present(alert, animated: true)
    }

    @objc private func toggleViewMode() {
        isGridView = true
        collectionView.isHidden = false
        tableView.isHidden = true
        collectionView.reloadData()
    }
    
    @objc private func toggleEditMode() {
        
        isEditingMode.toggle()
        selectedBookIds.removeAll()
        navigationItem.rightBarButtonItems?[0].title = isEditingMode ? "完成" : "编辑"

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
            _ = BookRepository.shared.update(updated)
            self?.loadBooks()
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
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
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
        let readerVC = ReaderViewController(book: book)
        readerVC.modalPresentationStyle = .fullScreen
        present(readerVC, animated: true)
    }

    // MARK: - Filter Chips

    private func createFilterChip(title: String, tag: Int) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        chip.backgroundColor = UIColor(white: 0.95, alpha: 1)
        chip.setTitleColor(.lvTextSecondary, for: .normal)
        chip.layer.cornerRadius = 14
        chip.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        chip.tag = tag
        chip.addTarget(self, action: #selector(filterChipTapped(_:)), for: .touchUpInside)
        chip.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return chip
    }

    @objc private func filterChipTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0: progressFilter = .all; sourceFilter = nil
        case 1: progressFilter = .unread
        case 2: progressFilter = .reading
        case 3: progressFilter = .finished
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
            cell.configure(with: filteredBooks[indexPath.item])
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
        return CGSize(width: width, height: width * 1.7)
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
        cell.configure(with: filteredBooks[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openReader(for: filteredBooks[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            guard let self = self else { return }
            self.confirmDelete(self.filteredBooks[indexPath.row])
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - UISearchResultsUpdating

extension BookshelfViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilters()
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
