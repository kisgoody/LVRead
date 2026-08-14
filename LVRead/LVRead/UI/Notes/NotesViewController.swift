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

        actionsButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        actionsButton.accessibilityLabel = L("导入或导出笔记")
        actionsButton.addTarget(self, action: #selector(showExchangeActions), for: .touchUpInside)
        actionsButton.tintColor = LVBookshelfModuleStyle.accent

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

private final class NoteDetailViewController: UIViewController {
    private var record: LVNoteRecord
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private weak var commentBodyLabel: UILabel?
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
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        stackView.axis = .vertical
        stackView.spacing = 24

        let kind = makeKindLabel()

        let header = UILabel()
        header.text = "\(record.bookTitle) · \(record.chapterTitle)"
        header.font = .systemFont(ofSize: 20, weight: .bold)
        header.textColor = LVBookshelfModuleStyle.primaryText
        header.numberOfLines = 0
        header.adjustsFontForContentSizeCategory = true

        let metadata = UILabel()
        metadata.text = [record.bookAuthor, Self.dateFormatter.string(from: record.createdAt)]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        metadata.font = .systemFont(ofSize: 12)
        metadata.textColor = LVBookshelfModuleStyle.secondaryText
        metadata.numberOfLines = 0
        metadata.adjustsFontForContentSizeCategory = true

        let heading = UIStackView(arrangedSubviews: [kind, header, metadata])
        heading.axis = .vertical
        heading.spacing = 8

        let original = makeSection(
            icon: "text.quote",
            title: L("原文"),
            text: record.originalText
        )
        stackView.addArrangedSubview(heading)
        stackView.addArrangedSubview(original.view)

        if record.kind == .comment,
           let comment = record.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
           !comment.isEmpty {
            let section = makeSection(icon: "text.bubble", title: L("评论内容"), text: comment)
            commentBodyLabel = section.body
            stackView.addArrangedSubview(section.view)
        }

        if BookRepository.shared.getByHash(record.bookHash) != nil {
            let button = UIButton(type: .system)
            button.setTitle(L("回到原文"), for: .normal)
            button.setImage(UIImage(systemName: "book.pages"), for: .normal)
            button.semanticContentAttribute = .forceLeftToRight
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            button.layer.cornerRadius = 12
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            button.accessibilityHint = L("打开书籍并定位到这条笔记")
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.addTarget(self, action: #selector(returnToOriginal), for: .touchUpInside)
            returnButton = button
            applyReturnButtonStyle()
            stackView.addArrangedSubview(button)
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
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
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

    private func makeSection(icon: String, title: String, text: String) -> (view: UIView, body: UILabel) {
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

        let sectionHeader = UIStackView(arrangedSubviews: [iconView, titleLabel, UIView()])
        sectionHeader.axis = .horizontal
        sectionHeader.alignment = .center
        sectionHeader.spacing = 8

        let body = UILabel()
        body.text = text.isEmpty ? L("未保存原文") : text
        body.font = .systemFont(ofSize: 14)
        body.textColor = LVBookshelfModuleStyle.primaryText
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [sectionHeader, body])
        stack.axis = .vertical
        stack.spacing = 16
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ])
        return (card, body)
    }

    private func configureActions() {
        var actions: [UIAction] = []
        if record.kind == .comment {
            actions.append(UIAction(title: L("修改"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.editComment()
            })
        }
        actions.append(UIAction(title: L("删除"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.confirmDelete()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: actions)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L("更多操作")
    }

    private func applyReturnButtonStyle() {
        let accent = LVBookshelfModuleStyle.accent
        returnButton?.backgroundColor = accent
        returnButton?.tintColor = accent.contrastingTextColor
        returnButton?.setTitleColor(accent.contrastingTextColor, for: .normal)
    }

    private func editComment() {
        let alert = UIAlertController(title: L("修改评论"), message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] in
            $0.text = self?.record.comment
            $0.placeholder = L("评论不能为空，最多1000字")
        }
        alert.addAction(UIAlertAction(title: L("保存"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                LVToast.show(message: L("评论内容不能为空"), style: .error)
                return
            }
            let comment = String(value.prefix(1000))
            if let book = BookRepository.shared.getByHash(self.record.bookHash),
               BookRepository.shared.getHighlights(for: book.id).contains(where: { $0.id == self.record.id }) {
                BookRepository.shared.updateHighlightNote(self.record.id, note: comment)
            } else {
                LVNoteRecordStore.shared.updateComment(id: self.record.id, comment: comment)
            }
            self.record = LVNoteRecord(
                id: self.record.id, bookHash: self.record.bookHash, bookTitle: self.record.bookTitle,
                bookAuthor: self.record.bookAuthor, chapterIndex: self.record.chapterIndex,
                pageOffset: self.record.pageOffset, chapterTitle: self.record.chapterTitle,
                originalText: self.record.originalText, comment: comment, kind: self.record.kind,
                createdAt: self.record.createdAt
            )
            self.commentBodyLabel?.text = comment
            NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
            LVToast.show(message: L("评论已保存"), style: .success)
        })
        alert.addAction(UIAlertAction(title: L("取消"), style: .cancel))
        present(alert, animated: true)
    }

    private func confirmDelete() {
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
        applyReturnButtonStyle()
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
