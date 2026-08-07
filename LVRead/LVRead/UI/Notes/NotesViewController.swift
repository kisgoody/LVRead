import UIKit
import UniformTypeIdentifiers

final class NotesViewController: UIViewController {
    private enum Filter: Int { case all, excerpts, comments, bookmarks }
    private struct Asset {
        let record: LVNoteRecord

        var id: String { record.id }
    }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionsButton = UIButton(type: .system)
    private let searchBar = UISearchBar()
    private let filterScrollView = UIScrollView()
    private let filterStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = LVEmptyStateView(
        icon: "bookmark",
        title: L("还没有笔记"),
        subtitle: L("阅读时可以添加摘录、评论或书签，保存的内容会集中显示在这里。")
    )
    private let moduleNavigation = LVModuleNavigationView(selectedModule: .notes)

    private var assets: [Asset] = []
    private var visibleAssets: [Asset] = []
    private var filter: Filter = .all
    private var searchText = ""
    private var isFirstAppearance = true

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadData),
            name: NSNotification.Name("LVReadSettingsChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(incomingMarkdown(_:)),
            name: .lvReadMarkdownReceived,
            object: nil
        )
        loadAssets()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .notes)
        if isFirstAppearance {
            isFirstAppearance = false
        } else {
            loadAssets()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = modulePageBackground
        titleLabel.text = L("笔记")
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .notes)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        subtitleLabel.numberOfLines = 2

        actionsButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        actionsButton.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .bold), forImageIn: .normal)
        actionsButton.accessibilityLabel = L("导入或导出笔记")
        actionsButton.addTarget(self, action: #selector(showExchangeActions), for: .touchUpInside)
        actionsButton.layer.cornerRadius = 22
        actionsButton.layer.borderWidth = 1
        actionsButton.layer.shadowOffset = CGSize(width: 0, height: 8)
        actionsButton.layer.shadowRadius = 18
        actionsButton.layer.shadowOpacity = 0.06

        searchBar.placeholder = L("搜索书名、章节、摘录或批注")
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.accessibilityLabel = L("搜索笔记")

        filterScrollView.showsHorizontalScrollIndicator = false
        filterStackView.axis = .horizontal
        filterStackView.spacing = 8
        filterScrollView.addSubview(filterStackView)
        [L("全部"), L("摘录"), L("评论"), L("书签")].enumerated().forEach { index, title in
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
        [titleLabel, subtitleLabel, actionsButton, searchBar, filterScrollView, tableView, emptyView, moduleNavigation].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        filterStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            actionsButton.widthAnchor.constraint(equalToConstant: 44),
            actionsButton.heightAnchor.constraint(equalToConstant: 44),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
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
        let live = books.flatMap { book -> [Asset] in
            let bookmarks = BookRepository.shared.getBookmarks(for: book.id).map { value in
                Asset(record: LVNoteRecord(
                    id: value.id, bookHash: book.fileHash, bookTitle: book.title,
                    bookAuthor: book.author, chapterIndex: value.chapterIndex,
                    pageOffset: value.pageOffset, chapterTitle: value.chapterTitle,
                    originalText: value.snippet, comment: nil, kind: .bookmark,
                    createdAt: value.createdAt
                ))
            }
            let annotations = BookRepository.shared.getHighlights(for: book.id).map { value in
                Asset(record: LVNoteRecord(
                    id: value.id, bookHash: book.fileHash, bookTitle: book.title,
                    bookAuthor: book.author, chapterIndex: value.chapterIndex,
                    pageOffset: value.pageOffset,
                    chapterTitle: BookRepository.shared.getChapters(for: book.id)[safe: value.chapterIndex]?.title
                        ?? LF("第 %d 章", value.chapterIndex + 1),
                    originalText: value.text, comment: value.note,
                    kind: value.isComment ? .comment : .excerpt,
                    createdAt: value.createdAt
                ))
            }
            return bookmarks + annotations
        }
        let liveIDs = Set(live.map(\.id))
        let archived = LVNoteRecordStore.shared.records()
            .filter { !liveIDs.contains($0.id) }
            .map { Asset(record: $0) }
        assets = (live + archived).sorted { $0.record.createdAt > $1.record.createdAt }
        applyFilter()
    }

    private func applyFilter() {
        visibleAssets = assets.filter { asset in
            let matchesKind: Bool
            switch (filter, asset.record.kind) {
            case (.all, _), (.excerpts, .excerpt), (.comments, .comment), (.bookmarks, .bookmark):
                matchesKind = true
            default: matchesKind = false
            }
            guard matchesKind else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [asset.record.bookTitle, asset.record.chapterTitle, asset.record.originalText, asset.record.comment ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let bookmarkCount = assets.filter { $0.record.kind == .bookmark }.count
        let excerptCount = assets.filter { $0.record.kind == .excerpt }.count
        let commentCount = assets.filter { $0.record.kind == .comment }.count
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
        actionsButton.tintColor = LVBookshelfModuleStyle.accent
        actionsButton.backgroundColor = LVBookshelfModuleStyle.cardBackground
        actionsButton.layer.borderColor = LVBookshelfModuleStyle.divider.cgColor
        actionsButton.layer.shadowColor = (DarkModeManager.shared.isDarkMode ? UIColor.black : UIColor(hex: "#2A221A")).cgColor
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
            LF("全部 %d", assets.count),
            LF("摘录 %d", excerptCount),
            LF("评论 %d", commentCount),
            LF("书签 %d", bookmarkCount)
        ]
        UIView.performWithoutAnimation {
            for case let chip as UIButton in filterStackView.arrangedSubviews {
                chip.setTitle(titles[chip.tag], for: .normal)
            }
            applyFilterAppearance()
            filterStackView.layoutIfNeeded()
        }
    }

    private func open(_ asset: Asset) {
        navigationController?.pushViewController(NoteDetailViewController(record: asset.record), animated: true)
    }

    @objc private func showExchangeActions() {
        let sheet = UIAlertController(title: L("笔记导入与导出"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("导出 Markdown"), style: .default) { [weak self] _ in
            self?.exportNotes()
        })
        sheet.addAction(UIAlertAction(title: L("从本地文件导入"), style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: true)
            picker.delegate = self
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: L("取消"), style: .cancel))
        if let popover = sheet.popoverPresentationController { popover.sourceView = actionsButton }
        present(sheet, animated: true)
    }

    private func exportNotes() {
        guard !assets.isEmpty else {
            LVToast.show(message: L("暂无可导出的笔记"), style: .info)
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LVRead-Notes.md")
            try LVNotesMarkdown.encode(assets.map(\.record)).write(to: url, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController { popover.sourceView = actionsButton }
            present(activity, animated: true)
        } catch {
            LVToast.show(message: L("笔记导出失败"), style: .error)
        }
    }

    private func importNotes(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let records = try LVNotesMarkdown.decode(String(contentsOf: url, encoding: .utf8))
            LVNoteRecordStore.shared.save(records)
            loadAssets()
            LVToast.show(message: LF("已导入 %d 条笔记", records.count), style: .success)
        } catch {
            LVToast.show(message: L("文件不符合 LVRead 笔记规范"), style: .error)
        }
    }

    @objc private func incomingMarkdown(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        importNotes(from: url)
    }
}

extension NotesViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importNotes(from: url)
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
        switch asset.record.kind {
        case .bookmark: kind = L("书签标识")
        case .excerpt: kind = L("摘录")
        case .comment: kind = L("评论标记")
        }
        let body = [asset.record.originalText, asset.record.comment].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        cell.configure(kind: kind, title: "\(asset.record.bookTitle) · \(asset.record.chapterTitle)",
                       body: body.isEmpty ? L("未保存摘录") : body,
                       date: Self.dateFormatter.string(from: asset.record.createdAt))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(visibleAssets[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let asset = visibleAssets[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L("删除")) { [weak self] _, _, completion in
            LVNoteRecordStore.shared.delete(id: asset.id)
            switch asset.record.kind {
            case .bookmark: BookRepository.shared.deleteBookmark(asset.id)
            case .excerpt, .comment: BookRepository.shared.deleteHighlight(asset.id)
            }
            self?.loadAssets()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = L("MM月dd日 HH:mm")
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
        let footer = UIStackView(arrangedSubviews: [dateLabel, UIView()])
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
        kindLabel.text = kind
        titleLabel.text = title
        bodyLabel.text = body
        dateLabel.text = date
    }
}

private final class NoteDetailViewController: UIViewController, UIGestureRecognizerDelegate {
    private var record: LVNoteRecord
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let navigationBackButton = UIButton(type: .system)
    private let navigationActionsButton = UIButton(type: .system)
    private weak var previousInteractivePopGestureDelegate: UIGestureRecognizerDelegate?
    private weak var commentTextView: UITextView?
    private weak var commentEditButton: UIButton?
    private weak var returnButton: UIButton?

    init(record: LVNoteRecord) {
        self.record = record
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("笔记详情")
        configureActions()
        buildInterface()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: .darkModeChanged, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        applyNavigationAppearance()
        enableInteractivePopGesture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreInteractivePopGestureDelegate()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        stackView.axis = .vertical
        stackView.spacing = 24

        let kind = makeKindLabel()

        let bookTitle = UILabel()
        bookTitle.text = record.bookTitle
        bookTitle.font = .systemFont(ofSize: 20, weight: .bold)
        bookTitle.textColor = LVBookshelfModuleStyle.primaryText
        bookTitle.numberOfLines = 0
        bookTitle.adjustsFontForContentSizeCategory = true

        let chapterTitle = UILabel()
        chapterTitle.text = record.chapterTitle
        chapterTitle.font = .systemFont(ofSize: 14, weight: .medium)
        chapterTitle.textColor = LVBookshelfModuleStyle.secondaryText
        chapterTitle.numberOfLines = 0
        chapterTitle.adjustsFontForContentSizeCategory = true

        let metadata = UILabel()
        metadata.text = [record.bookAuthor, Self.dateFormatter.string(from: record.createdAt)]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        metadata.font = .systemFont(ofSize: 12)
        metadata.textColor = LVBookshelfModuleStyle.secondaryText
        metadata.numberOfLines = 0
        metadata.adjustsFontForContentSizeCategory = true

        let heading = UIStackView(arrangedSubviews: [kind, bookTitle, chapterTitle, metadata])
        heading.axis = .vertical
        heading.spacing = 8

        let originalBody = makeBodyLabel(record.originalText)
        let originalAction: UIButton? = BookRepository.shared.getByHash(record.bookHash) == nil
            ? nil
            : makeReturnButton()
        let original = makeSection(
            icon: "text.quote",
            title: L("原文"),
            body: originalBody,
            trailingView: originalAction
        )
        stackView.addArrangedSubview(heading)
        stackView.addArrangedSubview(original)

        if record.kind == .comment,
           let comment = record.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
           !comment.isEmpty {
            let textView = makeCommentTextView(comment)
            let editButton = makeCommentEditButton()
            commentTextView = textView
            commentEditButton = editButton
            stackView.addArrangedSubview(makeSection(
                icon: "text.bubble",
                title: L("评论内容"),
                body: textView,
                trailingView: editButton
            ))
        }

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func makeKindLabel() -> UILabel {
        let label = UILabel()
        switch record.kind {
        case .bookmark: label.text = L("书签")
        case .excerpt: label.text = L("摘录")
        case .comment: label.text = L("评论")
        }
        label.font = .systemFont(ofSize: 12, weight: .bold)
        LVBookshelfModuleStyle.applyAccent(to: label)
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func makeSection(
        icon: String,
        title: String,
        body: UIView,
        trailingView: UIView? = nil
    ) -> UIView {
        let card = UIView()
        LVBookshelfModuleStyle.applyCard(to: card)

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        LVBookshelfModuleStyle.applyAccent(to: iconView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        LVBookshelfModuleStyle.applyAccent(to: titleLabel)

        var headerViews: [UIView] = [iconView, titleLabel, UIView()]
        var actionSpacer: UIView?
        if trailingView != nil {
            let spacer = UIView()
            actionSpacer = spacer
            headerViews.append(spacer)
        }
        let sectionHeader = UIStackView(arrangedSubviews: headerViews)
        sectionHeader.axis = .horizontal
        sectionHeader.alignment = .center
        sectionHeader.spacing = 8

        let stack = UIStackView(arrangedSubviews: [sectionHeader, body])
        stack.axis = .vertical
        stack.spacing = 16
        card.addSubview(stack)
        if let trailingView { card.addSubview(trailingView) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ]
        if let trailingView, let actionSpacer {
            trailingView.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(contentsOf: [
                actionSpacer.widthAnchor.constraint(equalTo: trailingView.widthAnchor),
                trailingView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                trailingView.centerYAnchor.constraint(equalTo: sectionHeader.centerYAnchor)
            ])
        }
        NSLayoutConstraint.activate(constraints)
        return card
    }

    private func makeBodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.isEmpty ? L("未保存原文") : text
        label.font = .systemFont(ofSize: 14)
        label.textColor = LVBookshelfModuleStyle.primaryText
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func makeReturnButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(L("回到原文"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.accessibilityHint = L("打开书籍并定位到这条笔记")
        button.addTarget(self, action: #selector(returnToOriginal), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        returnButton = button
        applyCardActionStyles()
        return button
    }

    private func makeCommentTextView(_ text: String) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = LVBookshelfModuleStyle.primaryText
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = L("评论内容")
        return textView
    }

    private func makeCommentEditButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bubble.and.pencil"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold),
            forImageIn: .normal
        )
        button.tintColor = LVBookshelfModuleStyle.accent
        button.accessibilityLabel = L("修改")
        button.addTarget(self, action: #selector(editComment), for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func configureActions() {
        configureNavigationButton(
            navigationBackButton,
            symbol: "chevron.left",
            accessibilityLabel: L("返回")
        )
        navigationBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        navigationItem.leftBarButtonItem = makeTransparentBarItem(navigationBackButton)

        configureNavigationButton(
            navigationActionsButton,
            symbol: "trash",
            accessibilityLabel: L("删除笔记")
        )
        navigationActionsButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .regular),
            forImageIn: .normal
        )
        navigationActionsButton.addTarget(self, action: #selector(confirmDelete), for: .touchUpInside)
        navigationItem.rightBarButtonItem = makeTransparentBarItem(navigationActionsButton)
        applyNavigationAppearance()
    }

    private func configureNavigationButton(
        _ button: UIButton,
        symbol: String,
        accessibilityLabel: String
    ) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.backgroundColor = .clear
        button.accessibilityLabel = accessibilityLabel
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func makeTransparentBarItem(_ button: UIButton) -> UIBarButtonItem {
        let item = UIBarButtonItem(customView: button)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
            item.sharesBackground = false
        }
        return item
    }

    private func applyNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = LVBookshelfModuleStyle.pageBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: LVBookshelfModuleStyle.primaryText]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationBackButton.tintColor = LVBookshelfModuleStyle.primaryText
        navigationActionsButton.tintColor = LVBookshelfModuleStyle.primaryText
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func enableInteractivePopGesture() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
        if gesture.delegate !== self {
            previousInteractivePopGestureDelegate = gesture.delegate
        }
        gesture.delegate = self
        gesture.isEnabled = true
    }

    private func restoreInteractivePopGestureDelegate() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer,
              gesture.delegate === self else { return }
        gesture.delegate = previousInteractivePopGestureDelegate
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }

    private func applyCardActionStyles() {
        let accent = LVBookshelfModuleStyle.accent
        returnButton?.backgroundColor = .clear
        returnButton?.setTitleColor(accent, for: .normal)
        commentEditButton?.backgroundColor = .clear
        commentEditButton?.tintColor = accent
        commentTextView?.textColor = LVBookshelfModuleStyle.primaryText
    }

    @objc private func editComment() {
        guard let textView = commentTextView else { return }
        if textView.isEditable {
            saveComment(textView.text)
            return
        }
        textView.isEditable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = LVBookshelfModuleStyle.divider.cgColor
        textView.backgroundColor = LVBookshelfModuleStyle.pageBackground
        commentEditButton?.setImage(UIImage(systemName: "checkmark"), for: .normal)
        commentEditButton?.accessibilityLabel = L("保存")
        textView.becomeFirstResponder()
    }

    private func saveComment(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            LVToast.show(message: L("评论内容不能为空"), style: .error)
            return
        }
        let comment = String(value.prefix(1000))
        if let book = BookRepository.shared.getByHash(record.bookHash),
           BookRepository.shared.getHighlights(for: book.id).contains(where: { $0.id == record.id }) {
            BookRepository.shared.updateHighlightNote(record.id, note: comment)
        } else {
            LVNoteRecordStore.shared.updateComment(id: record.id, comment: comment)
        }
        record = LVNoteRecord(
            id: record.id, bookHash: record.bookHash, bookTitle: record.bookTitle,
            bookAuthor: record.bookAuthor, chapterIndex: record.chapterIndex,
            pageOffset: record.pageOffset, chapterTitle: record.chapterTitle,
            originalText: record.originalText, comment: comment, kind: record.kind,
            createdAt: record.createdAt
        )
        commentTextView?.text = comment
        commentTextView?.isEditable = false
        commentTextView?.resignFirstResponder()
        commentTextView?.textContainerInset = .zero
        commentTextView?.layer.borderWidth = 0
        commentTextView?.backgroundColor = .clear
        commentEditButton?.setImage(UIImage(systemName: "bubble.and.pencil"), for: .normal)
        commentEditButton?.accessibilityLabel = L("修改")
        NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
        LVToast.show(message: L("评论已保存"), style: .success)
    }

    @objc private func confirmDelete() {
        let alert = UIAlertController(title: L("删除笔记"), message: L("删除后无法恢复"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("删除"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            LVNoteRecordStore.shared.delete(id: self.record.id)
            switch self.record.kind {
            case .bookmark: BookRepository.shared.deleteBookmark(self.record.id)
            case .excerpt, .comment: BookRepository.shared.deleteHighlight(self.record.id)
            }
            NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
            self.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: L("取消"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func returnToOriginal() {
        guard let book = BookRepository.shared.getByHash(record.bookHash) else { return }
        navigationController?.pushViewController(
            NativeDocumentReaderViewController(
                book: book,
                initialChapterIndex: record.chapterIndex,
                initialPageOffset: record.pageOffset,
                persistsReadingProgress: false
            ),
            animated: true
        )
    }

    @objc private func themeChanged() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        LVBookshelfModuleStyle.refreshCards(in: view)
        LVBookshelfModuleStyle.refreshAccents(in: view)
        applyCardActionStyles()
        if commentTextView?.isEditable == true {
            commentTextView?.layer.borderColor = LVBookshelfModuleStyle.divider.cgColor
            commentTextView?.backgroundColor = LVBookshelfModuleStyle.pageBackground
        }
        applyNavigationAppearance()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = L("yyyy年MM月dd日 HH:mm")
        return formatter
    }()
}

enum LVNotesMarkdown {
    private struct Envelope: Codable {
        let format: String
        let version: Int
        let notes: [LVNoteRecord]
    }

    static func encode(_ notes: [LVNoteRecord]) throws -> String {
        let envelope = Envelope(format: "LVRead Notes", version: 1, notes: notes)
        let data = try JSONEncoder().encode(envelope)
        let sortedNotes = notes.sorted { $0.createdAt > $1.createdAt }
        let details = sortedNotes.enumerated().map { index, note in
            let type: String
            switch note.kind {
            case .bookmark: type = "书签 / Bookmark"
            case .excerpt: type = "摘录 / Excerpt"
            case .comment: type = "评论 / Comment"
            }
            let comment = note.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            ## \(index + 1). \(heading(note.bookTitle))

            | 字段 / Field | 内容 / Value |
            | --- | --- |
            | 类型 / Type | \(type) |
            | 书籍 / Book | \(tableCell(note.bookTitle)) |
            | 作者 / Author | \(tableCell(note.bookAuthor.isEmpty ? "—" : note.bookAuthor)) |
            | 章节 / Chapter | \(tableCell(note.chapterTitle)) |
            | 章节序号 / Chapter No. | \(note.chapterIndex + 1) |
            | 原文位置 / Text Offset | \(note.pageOffset) |
            | 创建时间 / Created | \(ISO8601DateFormatter().string(from: note.createdAt)) |
            | 笔记 ID / Note ID | `\(note.id)` |
            | 书籍指纹 / Book Hash | `\(note.bookHash)` |

            ### 原文 / Original Text

            \(blockquote(note.originalText))
            \(comment.map { "\n### 评论 / Comment\n\n\(blockquote($0))" } ?? "")
            """
        }.joined(separator: "\n\n---\n\n")
        return """
        # LVRead 笔记 / Notes

        <!-- LVREAD-NOTES:1 -->

        - 笔记数量 / Total Notes：\(notes.count)

        \(details)

        ---

        ## LVRead 导入数据 / Import Data

        > 以下数据用于 LVRead 识别和导入，请勿修改或删除。

        ```lvread-notes-data
        \(data.base64EncodedString())
        ```
        """
    }

    private static func heading(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "#", with: "\\#")
    }

    private static func tableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "|", with: "\\|")
    }

    private static func blockquote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
    }

    static func decode(_ markdown: String) throws -> [LVNoteRecord] {
        let marker = "```lvread-notes-data\n"
        guard markdown.contains("<!-- LVREAD-NOTES:1 -->"),
              let start = markdown.range(of: marker)?.upperBound,
              let end = markdown.range(of: "\n```", range: start..<markdown.endIndex)?.lowerBound,
              let data = Data(base64Encoded: String(markdown[start..<end])) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.format == "LVRead Notes", envelope.version == 1,
              !envelope.notes.isEmpty,
              envelope.notes.allSatisfy({
                  !$0.id.isEmpty && !$0.bookHash.isEmpty && !$0.bookTitle.isEmpty
                      && $0.chapterIndex >= 0 && $0.pageOffset >= 0
              }) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return envelope.notes
    }
}

private var modulePageBackground: UIColor {
    LVBookshelfModuleStyle.pageBackground
}
