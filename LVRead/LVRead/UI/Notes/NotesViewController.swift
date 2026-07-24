import UIKit

final class NotesViewController: UIViewController {
    private enum Filter: Int { case all, excerpts, comments, bookmarks }
    private enum AssetKind { case bookmark(Bookmark), excerpt(Highlight), comment(Highlight) }

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
    private let filterScrollView = UIScrollView()
    private let filterStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = LVEmptyStateView(
        icon: "bookmark",
        title: "还没有笔记",
        subtitle: "阅读时可以添加摘录、评论或书签，保存的内容会集中显示在这里。"
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

        filterScrollView.showsHorizontalScrollIndicator = false
        filterStackView.axis = .horizontal
        filterStackView.spacing = 8
        filterScrollView.addSubview(filterStackView)
        ["全部", "摘录", "评论", "书签"].enumerated().forEach { index, title in
            filterStackView.addArrangedSubview(makeFilterChip(title: title, tag: index))
        }
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
        [titleLabel, subtitleLabel, searchBar, filterScrollView, tableView, emptyView, moduleNavigation].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        filterStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            searchBar.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            filterScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            filterScrollView.heightAnchor.constraint(equalToConstant: 36),
            filterStackView.topAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.topAnchor),
            filterStackView.leadingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.leadingAnchor),
            filterStackView.trailingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.trailingAnchor),
            filterStackView.bottomAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.bottomAnchor),
            filterStackView.heightAnchor.constraint(equalTo: filterScrollView.frameLayoutGuide.heightAnchor),
            tableView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor, constant: 12),
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
                      kind: value.isComment ? .comment(value) : .excerpt(value))
            }
            return bookmarks + annotations
        }.sorted { $0.createdAt > $1.createdAt }
        applyFilter()
    }

    private func applyFilter() {
        visibleAssets = assets.filter { asset in
            let matchesKind: Bool
            switch (filter, asset.kind) {
            case (.all, _), (.excerpts, .excerpt), (.comments, .comment), (.bookmarks, .bookmark):
                matchesKind = true
            default: matchesKind = false
            }
            guard matchesKind else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [asset.book.title, asset.chapterTitle, asset.excerpt, asset.note ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let bookmarkCount = assets.filter { if case .bookmark = $0.kind { return true }; return false }.count
        let excerptCount = assets.filter { if case .excerpt = $0.kind { return true }; return false }.count
        let commentCount = assets.filter { if case .comment = $0.kind { return true }; return false }.count
        updateFilterChipTitles(
            excerptCount: excerptCount,
            commentCount: commentCount,
            bookmarkCount: bookmarkCount
        )
        emptyView.isHidden = !visibleAssets.isEmpty
        tableView.reloadData()
    }

    @objc private func filterChanged(_ sender: UIButton) {
        filter = Filter(rawValue: sender.tag) ?? .all
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
        let panel = LVBookshelfModuleStyle.cardBackground
        let text = LVBookshelfModuleStyle.secondaryText
        let accent = LVBookshelfModuleStyle.primaryText
        let divider = LVBookshelfModuleStyle.divider
        for case let chip as UIButton in filterStackView.arrangedSubviews {
            let selected = chip.tag == filter.rawValue
            chip.backgroundColor = selected ? accent : panel
            chip.layer.borderColor = (selected ? accent : divider).cgColor
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: selected ? .bold : .medium)
            chip.setTitleColor(selected ? LVBookshelfModuleStyle.pageBackground : text, for: .normal)
        }
    }

    private func makeFilterChip(title: String, tag: Int) -> UIButton {
        let chip = UIButton(type: .system)
        chip.setTitle(title, for: .normal)
        chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        chip.layer.cornerRadius = 18
        chip.layer.borderWidth = 1
        chip.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        chip.tag = tag
        chip.addTarget(self, action: #selector(filterChanged(_:)), for: .touchUpInside)
        chip.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return chip
    }

    private func updateFilterChipTitles(
        excerptCount: Int,
        commentCount: Int,
        bookmarkCount: Int
    ) {
        let titles = [
            "全部 \(assets.count)",
            "摘录 \(excerptCount)",
            "评论 \(commentCount)",
            "书签 \(bookmarkCount)"
        ]
        for case let chip as UIButton in filterStackView.arrangedSubviews {
            chip.setTitle(titles[chip.tag], for: .normal)
        }
        applyFilterAppearance()
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
        switch asset.kind {
        case .bookmark: kind = "书签标识"
        case .excerpt: kind = "摘录"
        case .comment: kind = "评论标记"
        }
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
            case let .excerpt(value), let .comment(value): BookRepository.shared.deleteHighlight(value.id)
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
