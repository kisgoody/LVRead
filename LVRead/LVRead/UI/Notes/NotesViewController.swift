import UIKit

final class NotesViewController: UIViewController {
    private enum Filter: Int { case all, annotations, bookmarks }
    private enum AssetKind { case bookmark(Bookmark), annotation(Highlight) }

    private struct Asset {
        let id: String
        let book: Book
        let chapterIndex: Int
        let pageOffset: Int
        let chapterTitle: String
        let excerpt: String
        let note: String?
        let createdAt: Date
        let kind: AssetKind
    }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let searchBar = UISearchBar()
    private let metricsStack = UIStackView()
    private let annotationMetric = UILabel()
    private let bookmarkMetric = UILabel()
    private let recentMetric = UILabel()
    private let filterControl = UISegmentedControl(items: ["全部", "评论", "书签"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = LVEmptyStateView(
        icon: "bookmark",
        title: "还没有笔记",
        subtitle: "阅读时可以添加评论或书签，保存的内容会集中显示在这里。"
    )
    private let moduleNavigation = LVModuleNavigationView(selectedModule: .notes)

    private var assets: [Asset] = []
    private var visibleAssets: [Asset] = []
    private var filter: Filter = .all
    private var searchText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        applyDarkAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notesDarkModeChanged),
            name: .darkModeChanged,
            object: nil
        )
        loadAssets()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadData),
            name: NSNotification.Name("LVReadSettingsChanged"),
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        loadAssets()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = modulePageBackground
        titleLabel.text = "笔记"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .notes)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText

        searchBar.placeholder = "搜索书名、章节、摘录或批注"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.accessibilityLabel = "搜索笔记"

        metricsStack.axis = .horizontal
        metricsStack.spacing = 8
        metricsStack.distribution = .fillEqually
        metricsStack.addArrangedSubview(makeMetricCard(valueLabel: annotationMetric, title: "评论"))
        metricsStack.addArrangedSubview(makeMetricCard(valueLabel: bookmarkMetric, title: "书签"))
        metricsStack.addArrangedSubview(makeMetricCard(valueLabel: recentMetric, title: "最近"))

        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        applyFilterAppearance()

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 136
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LVNoteCardCell.self, forCellReuseIdentifier: LVNoteCardCell.reuseIdentifier)

        moduleNavigation.onSelect = { [weak self] module in self?.showMainModule(module) }
        [titleLabel, subtitleLabel, searchBar, metricsStack, filterControl, tableView, emptyView, moduleNavigation].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            searchBar.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            metricsStack.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            metricsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            metricsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            metricsStack.heightAnchor.constraint(equalToConstant: 72),
            filterControl.topAnchor.constraint(equalTo: metricsStack.bottomAnchor, constant: 16),
            filterControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            filterControl.heightAnchor.constraint(equalToConstant: 36),
            tableView.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: moduleNavigation.topAnchor),
            emptyView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            moduleNavigation.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            moduleNavigation.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            moduleNavigation.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            moduleNavigation.heightAnchor.constraint(equalToConstant: 76)
        ])
    }

    private func makeMetricCard(valueLabel: UILabel, title: String) -> UIView {
        let card = UIView()
        LVBookshelfModuleStyle.applyCard(to: card)
        valueLabel.font = .systemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        valueLabel.textAlignment = .center
        let caption = UILabel()
        caption.text = title
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        caption.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [valueLabel, caption])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8)
        ])
        return card
    }

    @objc private func reloadData() { loadAssets() }

    private func loadAssets() {
        let books = BookRepository.shared.getAll()
        assets = books.flatMap { book -> [Asset] in
            let bookmarks = BookRepository.shared.getBookmarks(for: book.id).map { value in
                Asset(id: value.id, book: book, chapterIndex: value.chapterIndex,
                      pageOffset: value.pageOffset, chapterTitle: value.chapterTitle,
                      excerpt: value.snippet, note: nil, createdAt: value.createdAt,
                      kind: .bookmark(value))
            }
            let annotations = BookRepository.shared.getHighlights(for: book.id).map { value in
                Asset(id: value.id, book: book, chapterIndex: value.chapterIndex,
                      pageOffset: value.pageOffset,
                      chapterTitle: BookRepository.shared.getChapters(for: book.id)[safe: value.chapterIndex]?.title ?? "第 \(value.chapterIndex + 1) 章",
                      excerpt: value.text, note: value.note, createdAt: value.createdAt,
                      kind: .annotation(value))
            }
            return bookmarks + annotations
        }.sorted { $0.createdAt > $1.createdAt }
        applyFilter()
    }

    private func applyFilter() {
        visibleAssets = assets.filter { asset in
            let matchesKind: Bool
            switch (filter, asset.kind) {
            case (.all, _), (.annotations, .annotation), (.bookmarks, .bookmark): matchesKind = true
            default: matchesKind = false
            }
            guard matchesKind else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [asset.book.title, asset.chapterTitle, asset.excerpt, asset.note ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let bookmarkCount = assets.filter { if case .bookmark = $0.kind { return true }; return false }.count
        let annotationCount = assets.count - bookmarkCount
        annotationMetric.text = "\(annotationCount)"
        bookmarkMetric.text = "\(bookmarkCount)"
        recentMetric.text = assets.first.map { Calendar.current.isDateInToday($0.createdAt) ? "今日" : "近期" } ?? "—"
        emptyView.isHidden = !visibleAssets.isEmpty
        tableView.reloadData()
    }

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        applyFilter()
    }

    @objc private func notesDarkModeChanged() {
        applyDarkAppearance()
    }

    private func applyDarkAppearance() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        searchBar.searchTextField.backgroundColor = LVBookshelfModuleStyle.cardBackground
        searchBar.searchTextField.textColor = LVBookshelfModuleStyle.primaryText
        searchBar.tintColor = LVBookshelfModuleStyle.accent
        LVBookshelfModuleStyle.refreshCards(in: view)
        LVBookshelfModuleStyle.refreshAccents(in: view)
        applyFilterAppearance()
        tableView.reloadData()
    }

    private func applyFilterAppearance() {
        filterControl.backgroundColor = LVBookshelfModuleStyle.cardBackground
        filterControl.selectedSegmentTintColor = LVBookshelfModuleStyle.primaryText
        filterControl.setTitleTextAttributes(
            [.foregroundColor: LVBookshelfModuleStyle.pageBackground],
            for: .selected
        )
        filterControl.setTitleTextAttributes(
            [.foregroundColor: LVBookshelfModuleStyle.secondaryText],
            for: .normal
        )
    }

    private func open(_ asset: Asset) {
        navigationController?.pushViewController(
            NativeDocumentReaderViewController(
                book: BookRepository.shared.getById(asset.book.id) ?? asset.book,
                initialChapterIndex: asset.chapterIndex,
                initialPageOffset: asset.pageOffset,
                persistsReadingProgress: false
            ),
            animated: true
        )
    }
}

extension NotesViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        applyFilter()
    }
}

extension NotesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleAssets.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let asset = visibleAssets[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: LVNoteCardCell.reuseIdentifier, for: indexPath) as! LVNoteCardCell
        let kind: String
        switch asset.kind { case .bookmark: kind = "书签标识"; case .annotation: kind = "评论标记" }
        let body = [asset.excerpt, asset.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        cell.configure(kind: kind, title: "\(asset.book.title) · \(asset.chapterTitle)",
                       body: body.isEmpty ? "未保存摘录" : body,
                       date: Self.dateFormatter.string(from: asset.createdAt))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(visibleAssets[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let asset = visibleAssets[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            switch asset.kind {
            case let .bookmark(value): BookRepository.shared.deleteBookmark(value.id)
            case let .annotation(value): BookRepository.shared.deleteHighlight(value.id)
            }
            self?.loadAssets()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter
    }()
}

private final class LVNoteCardCell: UITableViewCell {
    static let reuseIdentifier = "LVNoteCardCell"
    private let card = UIView()
    private let kindLabel = UILabel()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let dateLabel = UILabel()
    private let actionLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        LVBookshelfModuleStyle.applyCard(to: card)
        kindLabel.font = .systemFont(ofSize: 12, weight: .bold)
        LVBookshelfModuleStyle.applyAccent(to: kindLabel)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        bodyLabel.numberOfLines = 2
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        actionLabel.text = "回到原文"
        actionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        LVBookshelfModuleStyle.applyAccent(to: actionLabel)
        let footer = UIStackView(arrangedSubviews: [dateLabel, UIView(), actionLabel])
        footer.axis = .horizontal
        let stack = UIStackView(arrangedSubviews: [kindLabel, titleLabel, bodyLabel, footer])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(card)
        card.addSubview(stack)
        card.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(kind: String, title: String, body: String, date: String) {
        LVBookshelfModuleStyle.applyCard(to: card)
        LVBookshelfModuleStyle.applyAccent(to: kindLabel)
        LVBookshelfModuleStyle.applyAccent(to: actionLabel)
        kindLabel.text = kind
        titleLabel.text = title
        bodyLabel.text = body
        dateLabel.text = date
    }
}

private var modulePageBackground: UIColor {
    LVBookshelfModuleStyle.pageBackground
}
