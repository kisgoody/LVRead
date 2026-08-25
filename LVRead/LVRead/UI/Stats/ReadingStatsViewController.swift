import UIKit
import UniformTypeIdentifiers

final class ReadingStatsViewController: UIViewController, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let navigationBackButton = UIButton(type: .system)
    private let navigationActionsButton = UIButton(type: .system)
    private let overviewStreakLabel = UILabel()
    private weak var previousInteractivePopGestureDelegate: UIGestureRecognizerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("阅读统计")
        configureNavigationButtons()
        buildInterface()
        reloadStatistics()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .darkModeChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(incomingMarkdown(_:)),
            name: .lvReadStatsMarkdownReceived,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        applyNavigationAppearance()
        reloadStatistics()
        enableInteractivePopGesture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreInteractivePopGestureDelegate()
    }

    private func buildInterface() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        applyNavigationAppearance()
        scrollView.alwaysBounceVertical = true
        stackView.axis = .vertical
        stackView.spacing = 24
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func reloadStatistics() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let repository = ReadingStatsRepository.shared
        let stats = repository.getStats()
        let analytics = ReadingAnalytics(stats: stats)
        let books = BookRepository.shared.getAll()
        let bookStats = ReadingStatsRepository.shared.getBookStats()

        overviewStreakLabel.text = LF("连续阅读 %d 天", analytics.currentStreak)
        stackView.addArrangedSubview(makeOverviewCard(repository: repository))

        let hourlyHistory = LVHourlyReadingHistoryView(repository: .shared) { [weak self] date in
            self?.confirmDeleteStatistics(on: date)
        }
        stackView.addArrangedSubview(makeSection(
            title: L("单日阅读"),
            subtitle: "",
            trailingView: hourlyHistory.sectionDeleteButton,
            content: hourlyHistory
        ))

        let timeDistribution = LVReadingTimeDistributionView(repository: .shared)
        stackView.addArrangedSubview(makeSection(
            title: L("阅读时间分布"),
            subtitle: "",
            trailingView: timeDistribution.sectionRangeControl,
            content: timeDistribution
        ))

        let topBooks = bookStats.sorted { $0.value.readingTimeSeconds > $1.value.readingTimeSeconds }
            .prefix(5)
            .compactMap { id, value -> LVStatsBarChartView.Item? in
                guard let book = books.first(where: { $0.id == id }) else { return nil }
                let minutes = value.readingTimeSeconds / 60
                let pace = ReadingPace.wordsPerMinute(
                    words: value.charactersRead,
                    effectiveSeconds: value.paceReadingTimeSeconds
                )
                return .init(
                    label: readableBookTitle(for: book),
                    value: Double(minutes),
                    valueText: LF("%d 分钟 · %@", minutes, paceText(pace))
                )
            }
        stackView.addArrangedSubview(makeSection(
            title: L("常读书籍"),
            subtitle: L("按累计阅读有效时长排序"),
            content: LVStatsBarChartView(
                items: Array(topBooks),
                color: .lvPrimary,
                showsFullContent: true
            )
        ))

        let booksByFormat: [String: [Book]] = Dictionary(grouping: books) { book in
            book.fileFormat.displayName
        }
        let formatItems: [LVStatsBarChartView.Item] = booksByFormat.map {
            LVStatsBarChartView.Item(
                label: $0.key,
                value: Double($0.value.count),
                valueText: LF("%d 本", $0.value.count)
            )
        }
        let formats = formatItems.sorted { $0.value > $1.value }
        stackView.addArrangedSubview(makeSection(
            title: L("文件格式分布"),
            subtitle: L("当前书架的内容组成"),
            content: LVStatsBarChartView(items: formats, color: .lvAccent)
        ))

        stackView.addArrangedSubview(makeAdviceCard(
            ReadingAdviceEngine.shared.suggestions().map(\.text)
        ))
    }

    private func makeOverviewCard(repository: ReadingStatsRepository) -> UIView {
        let card = makeCard()
        let titleLabel = UILabel()
        titleLabel.text = L("阅读概览")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText

        overviewStreakLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        overviewStreakLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        overviewStreakLabel.textAlignment = .right
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), overviewStreakLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let content = UIStackView(arrangedSubviews: [
            header, makeOverviewTable(repository: repository)
        ])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeOverviewTable(repository: ReadingStatsRepository) -> UIView {
        let container = UIView()
        let table = UIStackView()
        table.axis = .horizontal
        table.distribution = .fillProportionally
        table.spacing = 4
        let summaries = [
            repository.readingPaceSummary(lastDays: nil),
            repository.readingPaceSummary(lastDays: 7),
            repository.readingPaceSummary(for: Date())
        ]
        let rows = [
            [L("范围"), L("有效阅读时长"), L("阅读节奏"), L("阅读页数"), L("阅读字数")],
            overviewRowValues(range: L("全部"), summary: summaries[0]),
            overviewRowValues(range: L("近7日"), summary: summaries[1]),
            overviewRowValues(range: L("今日"), summary: summaries[2])
        ]
        for columnIndex in rows[0].indices {
            let values = rows.map { $0[columnIndex] }
            let column = makeOverviewColumn(
                values,
                emphasizesValues: columnIndex == 0
            )
            table.addArrangedSubview(column)
            column.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        container.addSubview(table)
        table.translatesAutoresizingMaskIntoConstraints = false
        let tableHeight = CGFloat(48 + 56 * 3) + 3 / UIScreen.main.scale
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: container.topAnchor),
            table.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: tableHeight)
        ])
        return container
    }

    private func overviewRowValues(range: String, summary: ReadingPaceSummary) -> [String] {
        [
            range,
            overviewDurationText(summary.effectiveSeconds),
            paceText(summary.wordsPerMinute),
            LF("%d 页", summary.pages),
            LF("%d 字", summary.words)
        ]
    }

    private func makeOverviewColumn(
        _ values: [String],
        emphasizesValues: Bool
    ) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 0
        values.enumerated().forEach { index, text in
            if index > 0 { column.addArrangedSubview(makeOverviewDivider()) }
            let label = UILabel()
            label.text = text
            label.font = .systemFont(
                ofSize: index == 0 ? 10 : 11,
                weight: index == 0 || emphasizesValues ? .semibold : .regular
            )
            label.textColor = index == 0
                ? LVBookshelfModuleStyle.adaptiveSecondaryText
                : LVBookshelfModuleStyle.adaptivePrimaryText
            label.textAlignment = .center
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.allowsDefaultTighteningForTruncation = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.heightAnchor.constraint(equalToConstant: index == 0 ? 48 : 56).isActive = true
            column.addArrangedSubview(label)
        }
        return column
    }

    private func makeOverviewDivider() -> UIView {
        let line = UIView()
        line.backgroundColor = LVBookshelfModuleStyle.adaptiveDivider
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private func overviewDurationText(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        return hours > 0 ? LF("%d 小时 %d 分钟", hours, minutes) : LF("%d 分钟", minutes)
    }

    private func paceText(_ value: Int?) -> String {
        value.map { LF("%d 字/分钟", $0) } ?? L("--")
    }

    private func makeSection(
        title: String,
        subtitle: String,
        trailingView: UIView? = nil,
        content: UIView
    ) -> UIView {
        let card = makeCard()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        titleLabel.numberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header: UIView
        if let trailingView {
            let spacer = UIView()
            let row = UIStackView(arrangedSubviews: [titleLabel, spacer, trailingView])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8
            header = row
        } else {
            header = titleLabel
        }

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        subtitleLabel.isHidden = subtitle.isEmpty
        let stack = UIStackView(arrangedSubviews: [header, subtitleLabel, content])
        stack.axis = .vertical
        stack.spacing = 12
        embed(stack, in: card)
        return card
    }

    private func makeAdviceCard(_ suggestions: [String]) -> UIView {
        let card = makeCard()
        let title = UILabel()
        title.text = L("阅读建议")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        let stack = UIStackView(arrangedSubviews: [title])
        stack.axis = .vertical
        stack.spacing = 12
        suggestions.forEach { suggestion in
            let label = UILabel()
            label.text = "• \(suggestion)"
            label.font = .systemFont(ofSize: 14)
            label.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        embed(stack, in: card)
        return card
    }

    private func makeCard() -> UIView {
        let card = UIView()
        LVBookshelfModuleStyle.applyCard(to: card)
        return card
    }

    private func readableBookTitle(for book: Book) -> String {
        let metadataTitle: String?
        if book.title.caseInsensitiveCompare(book.fileHash) == .orderedSame {
            metadataTitle = try? BookImportManager.shared
                .parserFor(format: book.fileFormat)
                .parseMetadata(filePath: book.resolvedFilePath())
                .title
        } else {
            metadataTitle = nil
        }
        return LVStatsMarkdown.readableBookTitle(
            storedTitle: book.title,
            fileHash: book.fileHash,
            metadataTitle: metadataTitle
        )
    }

    @objc private func themeChanged() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        applyNavigationAppearance()
        reloadStatistics()
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

    private func configureNavigationButtons() {
        configureNavigationButton(
            navigationBackButton,
            symbol: "chevron.left",
            accessibilityLabel: L("返回")
        )
        navigationBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        navigationItem.leftBarButtonItem = makeTransparentBarItem(navigationBackButton)

        configureNavigationButton(
            navigationActionsButton,
            symbol: "ellipsis.circle",
            accessibilityLabel: L("统计导入与导出")
        )
        navigationActionsButton.addTarget(self, action: #selector(showExchangeActions), for: .touchUpInside)
        navigationItem.rightBarButtonItem = makeTransparentBarItem(navigationActionsButton)
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

    private func embed(_ content: UIView, in card: UIView) {
        card.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
    }

    @objc private func showExchangeActions() {
        let sheet = UIAlertController(title: L("统计导入与导出"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("导出 Markdown"), style: .default) { [weak self] _ in
            self?.exportStats()
        })
        sheet.addAction(UIAlertAction(title: L("从本地文件导入"), style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: true)
            picker.delegate = self
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: L("取消"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func exportStats() {
        do {
            let repository = ReadingStatsRepository.shared
            let archive = repository.exportArchive()
            let books = BookRepository.shared.getAll()
            let booksByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
            let booksByFormat: [String: [Book]] = Dictionary(grouping: books) { book in
                book.fileFormat.displayName
            }
            let fileFormatItems: [LVStatsMarkdown.FileFormatSummary] = booksByFormat.map {
                LVStatsMarkdown.FileFormatSummary(name: $0.key, bookCount: $0.value.count)
            }
            let fileFormats = fileFormatItems.sorted {
                $0.bookCount == $1.bookCount ? $0.name < $1.name : $0.bookCount > $1.bookCount
            }
            let frequentBooks = repository.getBookStats()
                .compactMap { id, stat -> LVStatsMarkdown.FrequentBookSummary? in
                    guard let book = booksByID[id] else { return nil }
                    return .init(
                        identifier: book.fileHash,
                        title: readableBookTitle(for: book),
                        readingTimeSeconds: stat.readingTimeSeconds,
                        paceReadingTimeSeconds: stat.paceReadingTimeSeconds,
                        pagesRead: stat.pagesRead,
                        charactersRead: stat.charactersRead
                    )
                }
                .sorted {
                    $0.readingTimeSeconds == $1.readingTimeSeconds
                        ? $0.title.localizedCompare($1.title) == .orderedAscending
                        : $0.readingTimeSeconds > $1.readingTimeSeconds
                }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LVRead-Reading-Stats.md")
            try LVStatsMarkdown.encode(
                archive,
                fileFormats: fileFormats,
                frequentBooks: Array(frequentBooks)
            ).write(to: url, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItem
            }
            present(activity, animated: true)
        } catch {
            LVToast.show(message: L("阅读统计导出失败"), style: .error)
        }
    }

    private func importStats(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let archive = try LVStatsMarkdown.decode(String(contentsOf: url, encoding: .utf8))
            let overlaps = ReadingStatsRepository.shared.overlappingDates(with: archive)
            guard !overlaps.isEmpty else {
                finishImport(archive, overwrite: false)
                return
            }
            let alert = UIAlertController(
                title: L("发现重复时间段"),
                message: LF("有 %d 天的统计记录重复，是否覆盖这些日期？", overlaps.count),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L("保留现有记录"), style: .default) { [weak self] _ in
                self?.finishImport(archive, overwrite: false)
            })
            alert.addAction(UIAlertAction(title: L("覆盖重复日期"), style: .destructive) { [weak self] _ in
                self?.finishImport(archive, overwrite: true)
            })
            alert.addAction(UIAlertAction(title: L("取消"), style: .cancel))
            present(alert, animated: true)
        } catch {
            LVToast.show(message: L("文件不符合 LVRead 阅读统计规范"), style: .error)
        }
    }

    private func finishImport(_ archive: LVReadingStatsArchive, overwrite: Bool) {
        ReadingStatsRepository.shared.importArchive(archive, overwriteOverlaps: overwrite)
        reloadStatistics()
        LVToast.show(message: L("阅读统计导入成功"), style: .success)
    }

    private func confirmDeleteStatistics(on date: Date) {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        let alert = UIAlertController(
            title: L("删除当天阅读记录"),
            message: LF("确定删除 %@ 的阅读统计吗？", formatter.string(from: date)),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L("删除"), style: .destructive) { [weak self] _ in
            ReadingStatsRepository.shared.deleteReadingRecords(on: date)
            self?.reloadStatistics()
        })
        alert.addAction(UIAlertAction(title: L("取消"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func incomingMarkdown(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        importStats(from: url)
    }
}

extension ReadingStatsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importStats(from: url)
    }
}

enum LVStatsMarkdown {
    struct FileFormatSummary: Equatable {
        let name: String
        let bookCount: Int
    }

    struct FrequentBookSummary: Equatable {
        let identifier: String
        let title: String
        let readingTimeSeconds: Int
        let paceReadingTimeSeconds: Int
        let pagesRead: Int
        let charactersRead: Int

        init(
            identifier: String,
            title: String,
            readingTimeSeconds: Int,
            paceReadingTimeSeconds: Int = 0,
            pagesRead: Int,
            charactersRead: Int
        ) {
            self.identifier = identifier
            self.title = title
            self.readingTimeSeconds = readingTimeSeconds
            self.paceReadingTimeSeconds = paceReadingTimeSeconds
            self.pagesRead = pagesRead
            self.charactersRead = charactersRead
        }
    }

    static func encode(
        _ archive: LVReadingStatsArchive,
        fileFormats: [FileFormatSummary] = [],
        frequentBooks: [FrequentBookSummary] = []
    ) throws -> String {
        let data = try JSONEncoder().encode(archive)
        let dates = Set(archive.dailyMinutes.keys)
            .union(archive.hourlySeconds.keys.map { String($0.prefix(10)) })
            .union(archive.hourlyPaceSeconds.keys.map { String($0.prefix(10)) })
            .union(archive.dailyPages.keys)
            .union(archive.hourlyPages.keys.map { String($0.prefix(10)) })
            .union(archive.dailyCharacters.keys)
            .union(archive.hourlyCharacters.keys.map { String($0.prefix(10)) })
            .sorted()
        let dailyRows = dates.map { date in
            let seconds = effectiveSeconds(on: date, in: archive)
            let words = archive.dailyCharacters[date] ?? 0
            let pace = paceText(words: words, seconds: paceSeconds(on: date, in: archive))
            return "| \(date) | \(duration(seconds)) | \(archive.dailyPages[date] ?? 0) | \(words) | \(pace) | \(activeHours(on: date, in: archive)) |"
        }.joined(separator: "\n")
        let hourlyRows = (0..<24).map { hour in
            let seconds = archive.hourlySeconds.reduce(0) { result, item in
                result + (Int(item.key.suffix(2)) == hour ? item.value : 0)
            }
            let pages = archive.hourlyPages.reduce(0) { result, item in
                result + (Int(item.key.suffix(2)) == hour ? item.value : 0)
            }
            let characters = archive.hourlyCharacters.reduce(0) { result, item in
                result + (Int(item.key.suffix(2)) == hour ? item.value : 0)
            }
            let paceSeconds = archive.hourlyPaceSeconds.reduce(0) { result, item in
                result + (Int(item.key.suffix(2)) == hour ? item.value : 0)
            }
            return "| \(String(format: "%02d:00–%02d:00", hour, (hour + 1) % 24)) | \(duration(seconds)) | \(pages) | \(characters) | \(paceText(words: characters, seconds: paceSeconds)) |"
        }.joined(separator: "\n")
        let dailyDetails = dates.map { date in
            let hourKeys = Set(archive.hourlySeconds.keys)
                .union(archive.hourlyPaceSeconds.keys)
                .union(archive.hourlyPages.keys)
                .union(archive.hourlyCharacters.keys)
                .sorted()
            let rows = hourKeys.compactMap { key -> String? in
                guard key.hasPrefix("\(date)-") else { return nil }
                let seconds = archive.hourlySeconds[key] ?? 0
                let paceSeconds = archive.hourlyPaceSeconds[key] ?? 0
                let pages = archive.hourlyPages[key] ?? 0
                let characters = archive.hourlyCharacters[key] ?? 0
                let hour = Int(key.suffix(2)) ?? 0
                return "| \(String(format: "%02d:00–%02d:00", hour, (hour + 1) % 24)) | \(duration(seconds)) | \(seconds) | \(pages) | \(characters) | \(paceText(words: characters, seconds: paceSeconds)) |"
            }.joined(separator: "\n")
            return """
            ### \(date)

            - 当日阅读有效时长 / Daily Effective Reading：\(archive.dailyMinutes[date] ?? 0) 分钟 / min
            - 当日阅读页数 / Daily Pages：\(archive.dailyPages[date] ?? 0) 页 / pages
            - 当日阅读字数 / Daily Word Count：\(archive.dailyCharacters[date] ?? 0) 字 / words
            - 当日阅读节奏 / Daily Reading Pace：\(paceText(words: archive.dailyCharacters[date] ?? 0, seconds: paceSeconds(on: date, in: archive)))

            \(rows.isEmpty ? "_无小时明细 / No hourly details_" : "| 时段 / Period | 阅读有效时长 / Effective Reading | 秒 / Seconds | 页数 / Pages | 字数 / Word Count | 阅读节奏 / Reading Pace |\n| --- | ---: | ---: | ---: | ---: | ---: |\n\(rows)")
            """
        }.joined(separator: "\n\n")
        let totalSeconds = max(
            archive.totalReadingSeconds,
            archive.dailyMinutes.values.reduce(0, +) * 60,
            archive.hourlySeconds.values.reduce(0, +)
        )
        let totalPages = max(archive.totalPagesRead, archive.dailyPages.values.reduce(0, +))
        let totalCharacters = max(
            archive.totalCharactersRead,
            archive.dailyCharacters.values.reduce(0, +)
        )
        let totalPaceSeconds = archive.hourlyPaceSeconds.values.reduce(0, +)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let endDay = Calendar.current.startOfDay(for: archive.exportedAt)
        let startDay = Calendar.current.date(byAdding: .day, value: -6, to: endDay) ?? endDay
        let startKey = formatter.string(from: startDay)
        let endKey = formatter.string(from: endDay)
        let recentDates = dates.filter { $0 >= startKey && $0 <= endKey }
        let recentSeconds = recentDates.reduce(0) { $0 + effectiveSeconds(on: $1, in: archive) }
        let recentPaceSeconds = recentDates.reduce(0) { $0 + paceSeconds(on: $1, in: archive) }
        let recentPages = recentDates.reduce(0) { $0 + pages(on: $1, in: archive) }
        let recentWords = recentDates.reduce(0) { $0 + characters(on: $1, in: archive) }
        let todaySeconds = effectiveSeconds(on: endKey, in: archive)
        let todayPaceSeconds = paceSeconds(on: endKey, in: archive)
        let todayPages = pages(on: endKey, in: archive)
        let todayWords = characters(on: endKey, in: archive)
        let overviewRows = [
            "| 全部 / All | \(duration(totalSeconds)) | \(paceText(words: totalCharacters, seconds: totalPaceSeconds)) | \(totalPages) | \(totalCharacters) |",
            "| 近7日 / Last 7 Days | \(duration(recentSeconds)) | \(paceText(words: recentWords, seconds: recentPaceSeconds)) | \(recentPages) | \(recentWords) |",
            "| 今日 / Today | \(duration(todaySeconds)) | \(paceText(words: todayWords, seconds: todayPaceSeconds)) | \(todayPages) | \(todayWords) |"
        ].joined(separator: "\n")
        let streak = currentStreak(in: archive, endingAt: endDay)
        let activeHourRecords = Set(archive.hourlySeconds.keys)
            .union(archive.hourlyPaceSeconds.keys)
            .union(archive.hourlyPages.keys)
            .union(archive.hourlyCharacters.keys)
            .count
        let formatRows = fileFormats.map {
            "| \(tableCell($0.name)) | \($0.bookCount) |"
        }.joined(separator: "\n")
        let frequentBookRows = frequentBooks.enumerated().map { index, item in
            "| \(index + 1) | \(tableCell(item.identifier)) | \(tableCell(item.title)) | \(duration(item.readingTimeSeconds)) | \(item.pagesRead) | \(item.charactersRead) | \(paceText(words: item.charactersRead, seconds: item.paceReadingTimeSeconds)) |"
        }.joined(separator: "\n")
        return """
        # LVRead 阅读统计 / Reading Stats

        <!-- LVREAD-STATS:1 -->

        ## 统计总览 / Overview

        - 导出时间 / Exported：\(ISO8601DateFormatter().string(from: archive.exportedAt))
        - 记录天数 / Days：\(dates.count)
        - 连续阅读 / Current Streak：\(streak) 天 / days
        - 有记录的小时数 / Active Hour Records：\(activeHourRecords)

        ### 阅读概览 / Reading Overview

        | 范围 / Range | 阅读有效时长 / Effective Reading | 阅读节奏 / Reading Pace | 阅读页数 / Pages | 阅读字数 / Word Count |
        | --- | ---: | ---: | ---: | ---: |
        \(overviewRows)

        ## 统计规则 / Statistics Rules

        - 阅读有效时长：阅读页位于前台、菜单和设置关闭、未听书，且距最近一次操作不足 2 分钟；超过 2 分钟的空闲时间不计入。
        - 阅读字数：只统计有效阅读状态下实际经过的正文范围；中文按汉字、字母和数字计数，英文按单词计数；空白、排版标点、Emoji、控制字符和 HTML 标签不计入。
        - 阅读节奏：有效阅读字数 × 60 ÷ 同口径有效阅读秒数；少于 60 秒或字数为 0 时显示 `--`，不评价快慢。
        - 页数：按有效阅读状态下经过的排版页累计，会随字号、边距和屏幕尺寸变化，不参与阅读节奏计算。
        - 字数规则版本 / Word Count Rule Version：\(archive.wordCountRuleVersion)

        ## 每日统计 / Daily Summary

        | 日期 / Date | 阅读有效时长 / Effective Reading | 阅读页数 / Pages | 阅读字数 / Word Count | 阅读节奏 / Reading Pace | 活跃时段 / Active Periods |
        | --- | ---: | ---: | ---: | ---: | ---: |
        \(dailyRows)

        ## 24 小时累计分布 / 24-Hour Distribution

        | 时段 / Period | 阅读有效时长 / Effective Reading | 阅读页数 / Pages | 阅读字数 / Word Count | 阅读节奏 / Reading Pace |
        | --- | ---: | ---: | ---: | ---: |
        \(hourlyRows)

        ## 逐日小时明细 / Hourly Details by Date

        \(dailyDetails)

        ## 文件格式分布 / File Format Distribution

        \(formatRows.isEmpty ? "_暂无数据 / No data_" : "| 文件格式 / Format | 书籍数量 / Books |\n| --- | ---: |\n\(formatRows)")

        ## 常读书籍 / Frequently Read Books

        \(frequentBookRows.isEmpty ? "_暂无数据 / No data_" : "| 排名 / Rank | 书籍标识 / Book ID | 书籍名称 / Book Title | 累计阅读有效时长 / Effective Reading Time | 阅读页数 / Pages | 阅读字数 / Word Count | 阅读节奏 / Reading Pace |\n| ---: | --- | --- | ---: | ---: | ---: | ---: |\n\(frequentBookRows)")

        ---

        ## LVRead 导入数据 / Import Data

        > 以下数据用于 LVRead 识别和导入，请勿修改或删除。

        ```lvread-stats-data
        \(data.base64EncodedString())
        ```
        """
    }

    private static func tableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "|", with: "\\|")
    }

    static func readableBookTitle(storedTitle: String, fileHash: String, metadataTitle: String?) -> String {
        let stored = storedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stored.caseInsensitiveCompare(fileHash) == .orderedSame,
              let metadata = metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !metadata.isEmpty,
              metadata.caseInsensitiveCompare(fileHash) != .orderedSame else {
            return stored
        }
        return metadata
    }

    private static func activeHours(on date: String, in archive: LVReadingStatsArchive) -> Int {
        Set(archive.hourlySeconds.keys)
            .union(archive.hourlyPaceSeconds.keys)
            .union(archive.hourlyPages.keys)
            .union(archive.hourlyCharacters.keys)
            .filter { $0.hasPrefix("\(date)-") }
            .count
    }

    private static func effectiveSeconds(on date: String, in archive: LVReadingStatsArchive) -> Int {
        let detailed = archive.hourlySeconds.reduce(0) {
            $0 + ($1.key.hasPrefix("\(date)-") ? $1.value : 0)
        }
        return detailed > 0 ? detailed : (archive.dailyMinutes[date] ?? 0) * 60
    }

    private static func paceSeconds(on date: String, in archive: LVReadingStatsArchive) -> Int {
        archive.hourlyPaceSeconds.reduce(0) {
            $0 + ($1.key.hasPrefix("\(date)-") ? $1.value : 0)
        }
    }

    private static func pages(on date: String, in archive: LVReadingStatsArchive) -> Int {
        let detailed = archive.hourlyPages.reduce(0) {
            $0 + ($1.key.hasPrefix("\(date)-") ? $1.value : 0)
        }
        return detailed > 0 ? detailed : (archive.dailyPages[date] ?? 0)
    }

    private static func characters(on date: String, in archive: LVReadingStatsArchive) -> Int {
        let detailed = archive.hourlyCharacters.reduce(0) {
            $0 + ($1.key.hasPrefix("\(date)-") ? $1.value : 0)
        }
        return detailed > 0 ? detailed : (archive.dailyCharacters[date] ?? 0)
    }

    private static func currentStreak(in archive: LVReadingStatsArchive, endingAt endDate: Date) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var date = endDate
        var result = 0
        while effectiveSeconds(on: formatter.string(from: date), in: archive) > 0 {
            result += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) else {
                break
            }
            date = previous
        }
        return result
    }

    private static func paceText(words: Int, seconds: Int) -> String {
        ReadingPace.wordsPerMinute(words: words, effectiveSeconds: seconds)
            .map { "\($0) 字/分钟" } ?? "--"
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }

    static func decode(_ markdown: String) throws -> LVReadingStatsArchive {
        let marker = "```lvread-stats-data\n"
        guard markdown.contains("<!-- LVREAD-STATS:1 -->"),
              let start = markdown.range(of: marker)?.upperBound,
              let end = markdown.range(of: "\n```", range: start..<markdown.endIndex)?.lowerBound,
              let data = Data(base64Encoded: String(markdown[start..<end])) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let archive = try JSONDecoder().decode(LVReadingStatsArchive.self, from: data)
        let datePattern = #"^\d{4}-\d{2}-\d{2}$"#
        let hourPattern = #"^\d{4}-\d{2}-\d{2}-([01]\d|2[0-3])$"#
        guard archive.format == "LVRead Reading Stats", archive.version == 1,
              archive.totalReadingSeconds >= 0,
              archive.totalPagesRead >= 0,
              archive.totalCharactersRead >= 0,
              archive.wordCountRuleVersion >= 1,
              archive.dailyMinutes.allSatisfy({
                  $0.key.range(of: datePattern, options: .regularExpression) != nil && $0.value >= 0
              }),
              archive.hourlySeconds.allSatisfy({
                  $0.key.range(of: hourPattern, options: .regularExpression) != nil && $0.value >= 0
              }),
              archive.hourlyPaceSeconds.allSatisfy({
                  $0.key.range(of: hourPattern, options: .regularExpression) != nil && $0.value >= 0
              }),
              archive.dailyPages.allSatisfy({
                  $0.key.range(of: datePattern, options: .regularExpression) != nil && $0.value >= 0
              }),
              archive.hourlyPages.allSatisfy({
                  $0.key.range(of: hourPattern, options: .regularExpression) != nil && $0.value >= 0
              }),
              archive.dailyCharacters.allSatisfy({
                  $0.key.range(of: datePattern, options: .regularExpression) != nil && $0.value >= 0
              }),
              archive.hourlyCharacters.allSatisfy({
                  $0.key.range(of: hourPattern, options: .regularExpression) != nil && $0.value >= 0
              }) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return archive
    }
}

/// Browses every date that contains reading records without leaving the chart.
final class LVHourlyReadingHistoryView: UIView {
    private let repository: ReadingStatsRepository
    private let onDelete: (Date) -> Void
    private let dates: [Date]
    private var selectedIndex: Int
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    fileprivate let sectionDeleteButton = UIButton(type: .system)
    private let dateLabel = UILabel()
    private let totalLabel = UILabel()
    private let chart: LVHourlyReadingChartView

    init(repository: ReadingStatsRepository, onDelete: @escaping (Date) -> Void) {
        self.repository = repository
        self.onDelete = onDelete
        dates = repository.hourlyReadingDates()
        selectedIndex = max(dates.count - 1, 0)
        chart = LVHourlyReadingChartView(
            minutesByHour: repository.hourlyReadingMinutes(for: dates[max(dates.count - 1, 0)]),
            paceSecondsByHour: repository.displayedHourlyPaceSeconds(for: dates[max(dates.count - 1, 0)]),
            pagesByHour: repository.displayedHourlyPages(for: dates[max(dates.count - 1, 0)]),
            charactersByHour: repository.displayedHourlyCharacters(for: dates[max(dates.count - 1, 0)])
        )
        super.init(frame: .zero)
        build()
        refreshDate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        previousButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        nextButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        previousButton.accessibilityLabel = L("上一条阅读日期")
        nextButton.accessibilityLabel = L("下一条阅读日期")
        previousButton.addTarget(self, action: #selector(showPreviousDate), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(showNextDate), for: .touchUpInside)
        [previousButton, nextButton].forEach {
            $0.tintColor = LVBookshelfModuleStyle.accent
            $0.widthAnchor.constraint(equalToConstant: 44).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        sectionDeleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        sectionDeleteButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 16, weight: .medium),
            forImageIn: .normal
        )
        sectionDeleteButton.tintColor = LVBookshelfModuleStyle.accent
        sectionDeleteButton.accessibilityLabel = L("删除当天记录")
        sectionDeleteButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        sectionDeleteButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        sectionDeleteButton.addTarget(self, action: #selector(deleteSelectedDate), for: .touchUpInside)

        dateLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        dateLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        dateLabel.textAlignment = .center
        dateLabel.adjustsFontSizeToFitWidth = true
        dateLabel.minimumScaleFactor = 0.8
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        totalLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        totalLabel.textAlignment = .center
        totalLabel.numberOfLines = 0

        let navigator = UIStackView(arrangedSubviews: [previousButton, dateLabel, nextButton])
        navigator.axis = .horizontal
        navigator.alignment = .center
        navigator.distribution = .fill

        let stack = UIStackView(arrangedSubviews: [navigator, totalLabel, chart])
        stack.axis = .vertical
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func refreshDate() {
        guard dates.indices.contains(selectedIndex) else { return }
        let date = dates[selectedIndex]
        let displayedMinutes = repository.displayedHourlyMinutes(for: date)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? L("yyyy年M月d日 · 今天") : L("yyyy年M月d日")
        dateLabel.text = formatter.string(from: date)
        totalLabel.text = LF(
            "当日阅读：%d 分钟 · %d 页 · %d 字 · %@",
            repository.displayedReadingMinutes(for: date),
            repository.displayedReadingPages(for: date),
            repository.displayedReadingCharacters(for: date),
            repository.readingPaceSummary(for: date).wordsPerMinute.map {
                LF("%d 字/分钟", $0)
            } ?? L("--")
        )
        chart.update(
            minutesByHour: displayedMinutes.map(Double.init),
            paceSecondsByHour: repository.displayedHourlyPaceSeconds(for: date),
            pagesByHour: repository.displayedHourlyPages(for: date),
            charactersByHour: repository.displayedHourlyCharacters(for: date)
        )
        previousButton.isEnabled = selectedIndex > 0
        nextButton.isEnabled = selectedIndex < dates.count - 1
        previousButton.alpha = previousButton.isEnabled ? 1 : 0.3
        nextButton.alpha = nextButton.isEnabled ? 1 : 0.3
        sectionDeleteButton.isEnabled = repository.hasReadingRecords(on: date)
        sectionDeleteButton.alpha = sectionDeleteButton.isEnabled ? 1 : 0.3
        accessibilityLabel = "\(dateLabel.text ?? "")，\(totalLabel.text ?? "")"
    }

    @objc private func showPreviousDate() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        refreshDate()
    }

    @objc private func showNextDate() {
        guard selectedIndex < dates.count - 1 else { return }
        selectedIndex += 1
        refreshDate()
    }

    @objc private func deleteSelectedDate() {
        guard dates.indices.contains(selectedIndex) else { return }
        onDelete(dates[selectedIndex])
    }
}

final class LVReadingPaceTrendView: UIView {
    private let repository: ReadingStatsRepository
    private let rangeControl = UISegmentedControl(items: [L("7天"), L("全部")])
    private let chart: LVReadingPaceTrendChartView
    var sectionRangeControl: UIView { rangeControl }

    init(repository: ReadingStatsRepository) {
        self.repository = repository
        chart = LVReadingPaceTrendChartView(points: repository.readingPacePoints(lastDays: 7))
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        rangeControl.selectedSegmentIndex = 0
        rangeControl.selectedSegmentTintColor = LVBookshelfModuleStyle.accent
        rangeControl.backgroundColor = .lvAdaptiveSurfaceSecondary
        rangeControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: LVBookshelfModuleStyle.primaryText
        ], for: .normal)
        rangeControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
        rangeControl.setEnabled(repository.hasReadingTimeDistributionBeyondSevenDays(), forSegmentAt: 1)
        rangeControl.layer.cornerRadius = 16
        rangeControl.clipsToBounds = true
        NSLayoutConstraint.activate([
            rangeControl.widthAnchor.constraint(equalToConstant: 96),
            rangeControl.heightAnchor.constraint(equalToConstant: 32)
        ])
        rangeControl.addTarget(self, action: #selector(rangeChanged), for: .valueChanged)

        addSubview(chart)
        chart.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chart.topAnchor.constraint(equalTo: topAnchor),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func rangeChanged() {
        chart.update(points: repository.readingPacePoints(
            lastDays: rangeControl.selectedSegmentIndex == 0 ? 7 : nil
        ))
    }
}

final class LVReadingPaceTrendChartView: UIView {
    private var points: [ReadingPacePoint]
    private let detailLabel = UILabel()
    private var selectedIndex: Int?

    init(points: [ReadingPacePoint]) {
        self.points = points
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = L("每日阅读节奏趋势图")
        heightAnchor.constraint(equalToConstant: 240).isActive = true
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        detailLabel.textAlignment = .center
        detailLabel.textColor = LVBookshelfModuleStyle.accent
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.7
        detailLabel.text = L("点击数据点查看每日阅读节奏")
        addSubview(detailLabel)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            detailLabel.topAnchor.constraint(equalTo: topAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chartTapped(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(points: [ReadingPacePoint]) {
        self.points = points
        selectedIndex = nil
        detailLabel.text = L("点击数据点查看每日阅读节奏")
        accessibilityValue = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let plot = CGRect(x: 36, y: 40, width: max(bounds.width - 44, 1), height: 156)
        let values = points.compactMap(\.summary.wordsPerMinute)
        let maximum = max(100, Int(ceil(Double(values.max() ?? 0) / 100)) * 100)
        let textColor = LVBookshelfModuleStyle.secondaryText
        let gridColor = LVBookshelfModuleStyle.divider.withAlphaComponent(0.8)
        let accent = LVBookshelfModuleStyle.accent

        context.setLineWidth(1 / UIScreen.main.scale)
        context.setStrokeColor(gridColor.cgColor)
        for step in 0...2 {
            let value = maximum * step / 2
            let y = plot.maxY - CGFloat(value) / CGFloat(maximum) * plot.height
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()
            drawText("\(value)", at: CGPoint(x: 0, y: y - 7), color: textColor)
        }
        drawText(L("字/分钟"), at: CGPoint(x: 0, y: plot.minY - 18), color: textColor)

        guard !points.isEmpty, !values.isEmpty else {
            drawCenteredText(L("暂无同口径数据"), in: plot, color: textColor)
            return
        }
        let xForIndex: (Int) -> CGFloat = { index in
            guard self.points.count > 1 else { return plot.midX }
            return plot.minX + CGFloat(index) / CGFloat(self.points.count - 1) * plot.width
        }
        var segment = UIBezierPath()
        var hasSegment = false
        for (index, point) in points.enumerated() {
            guard let pace = point.summary.wordsPerMinute else {
                accent.setStroke()
                segment.lineWidth = 2
                segment.stroke()
                segment = UIBezierPath()
                hasSegment = false
                continue
            }
            let value = CGPoint(
                x: xForIndex(index),
                y: plot.maxY - CGFloat(pace) / CGFloat(maximum) * plot.height
            )
            if hasSegment { segment.addLine(to: value) } else { segment.move(to: value); hasSegment = true }
            let radius: CGFloat = selectedIndex == index ? 5 : 3
            context.setFillColor(accent.cgColor)
            context.fillEllipse(in: CGRect(x: value.x - radius, y: value.y - radius, width: radius * 2, height: radius * 2))
        }
        accent.setStroke()
        segment.lineWidth = 2
        segment.lineJoinStyle = .round
        segment.stroke()

        let indexes = Set([0, points.count / 2, points.count - 1])
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        for index in indexes.sorted() {
            drawText(
                formatter.string(from: points[index].date),
                at: CGPoint(x: xForIndex(index) - 10, y: plot.maxY + 8),
                color: textColor
            )
        }
    }

    @objc private func chartTapped(_ gesture: UITapGestureRecognizer) {
        guard !points.isEmpty else { return }
        let plot = CGRect(x: 36, y: 40, width: max(bounds.width - 44, 1), height: 156)
        let ratio = min(max((gesture.location(in: self).x - plot.minX) / plot.width, 0), 1)
        let index = points.count == 1 ? 0 : Int((ratio * CGFloat(points.count - 1)).rounded())
        selectedIndex = index
        let point = points[index]
        let formatter = DateFormatter()
        formatter.dateFormat = L("M月d日")
        detailLabel.text = LF(
            "%@ · %d 分钟 · %d 字 · %@",
            formatter.string(from: point.date),
            Int((Double(point.summary.effectiveSeconds) / 60).rounded()),
            point.summary.words,
            point.summary.wordsPerMinute.map { LF("%d 字/分钟", $0) } ?? L("数据不足")
        )
        accessibilityValue = detailLabel.text
        UISelectionFeedbackGenerator().selectionChanged()
        setNeedsDisplay()
    }

    private func drawText(_ text: String, at point: CGPoint, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: color
        ])
    }

    private func drawCenteredText(_ text: String, in rect: CGRect, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

final class LVReadingTimeDistributionView: UIView {
    private let repository: ReadingStatsRepository
    private let rangeControl = UISegmentedControl(items: [L("今日"), L("近7日"), L("全部")])
    private let chart: LVReadingTimeDistributionChartView
    var sectionRangeControl: UIView { rangeControl }

    init(repository: ReadingStatsRepository) {
        self.repository = repository
        let distribution = repository.readingTimeDistribution(lastDays: 7)
        chart = LVReadingTimeDistributionChartView(
            minutesByHour: distribution.minutes,
            paceSecondsByHour: distribution.paceSeconds,
            pagesByHour: distribution.pages,
            charactersByHour: distribution.characters
        )
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        rangeControl.selectedSegmentIndex = 1
        rangeControl.selectedSegmentTintColor = LVBookshelfModuleStyle.accent
        rangeControl.backgroundColor = .lvAdaptiveSurfaceSecondary
        rangeControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: LVBookshelfModuleStyle.primaryText
        ], for: .normal)
        rangeControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
        rangeControl.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: LVBookshelfModuleStyle.secondaryText.withAlphaComponent(0.45)
        ], for: .disabled)
        rangeControl.setEnabled(repository.hasReadingTimeDistributionBeyondSevenDays(), forSegmentAt: 2)
        rangeControl.layer.cornerRadius = 16
        rangeControl.clipsToBounds = true
        NSLayoutConstraint.activate([
            rangeControl.widthAnchor.constraint(equalToConstant: 144),
            rangeControl.heightAnchor.constraint(equalToConstant: 32)
        ])
        rangeControl.addTarget(self, action: #selector(rangeChanged), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [chart])
        stack.axis = .vertical
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func rangeChanged() {
        let lastDays: Int?
        switch rangeControl.selectedSegmentIndex {
        case 0: lastDays = 1
        case 1: lastDays = 7
        default: lastDays = nil
        }
        let distribution = repository.readingTimeDistribution(
            lastDays: lastDays
        )
        chart.update(
            minutesByHour: distribution.minutes,
            paceSecondsByHour: distribution.paceSeconds,
            pagesByHour: distribution.pages,
            charactersByHour: distribution.characters
        )
    }
}

final class LVReadingTimeDistributionChartView: UIView {
    private var minutesByHour: [Double]
    private var paceSecondsByHour: [Int]
    private var pagesByHour: [Int]
    private var charactersByHour: [Int]
    private let detailLabel = UILabel()
    private var selectedHour: Int?

    init(
        minutesByHour: [Double],
        paceSecondsByHour: [Int],
        pagesByHour: [Int],
        charactersByHour: [Int]
    ) {
        self.minutesByHour = Self.normalized(minutesByHour, fallback: 0)
        self.paceSecondsByHour = Self.normalized(paceSecondsByHour, fallback: 0)
        self.pagesByHour = Self.normalized(pagesByHour, fallback: 0)
        self.charactersByHour = Self.normalized(charactersByHour, fallback: 0)
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = L("阅读时间分布柱状图")
        backgroundColor = .clear
        heightAnchor.constraint(equalToConstant: 240).isActive = true
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        detailLabel.textAlignment = .center
        detailLabel.textColor = LVBookshelfModuleStyle.accent
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.75
        detailLabel.text = L("点击柱形查看每小时累计有效阅读、页数、字数和阅读节奏")
        addSubview(detailLabel)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            detailLabel.topAnchor.constraint(equalTo: topAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chartTapped(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        minutesByHour: [Double],
        paceSecondsByHour: [Int],
        pagesByHour: [Int],
        charactersByHour: [Int]
    ) {
        self.minutesByHour = Self.normalized(minutesByHour, fallback: 0)
        self.paceSecondsByHour = Self.normalized(paceSecondsByHour, fallback: 0)
        self.pagesByHour = Self.normalized(pagesByHour, fallback: 0)
        self.charactersByHour = Self.normalized(charactersByHour, fallback: 0)
        selectedHour = nil
        detailLabel.text = L("点击柱形查看每小时累计有效阅读、页数、字数和阅读节奏")
        accessibilityValue = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let textColor = LVBookshelfModuleStyle.secondaryText
        let gridColor = LVBookshelfModuleStyle.divider.withAlphaComponent(0.8)
        let accent = LVBookshelfModuleStyle.accent
        let plot = CGRect(x: 36, y: 38, width: max(bounds.width - 42, 1), height: 164)
        let maximum = max(10, ceil((minutesByHour.max() ?? 0) / 10) * 10)

        context.setLineWidth(1 / UIScreen.main.scale)
        context.setStrokeColor(gridColor.cgColor)
        for step in 0...2 {
            let value = maximum * Double(step) / 2
            let y = plot.maxY - CGFloat(value / maximum) * plot.height
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()
            drawAxisText("\(Int(value.rounded()))", at: CGPoint(x: 0, y: y - 7), color: textColor)
        }
        drawAxisText(L("分钟"), at: CGPoint(x: 0, y: plot.minY - 18), color: textColor)

        let slotWidth = plot.width / 24
        let barWidth = max(2, slotWidth * 0.62)
        for hour in 0..<24 {
            let height = CGFloat(max(minutesByHour[hour], 0) / maximum) * plot.height
            let bar = CGRect(
                x: plot.minX + CGFloat(hour) * slotWidth + (slotWidth - barWidth) / 2,
                y: plot.maxY - height,
                width: barWidth,
                height: height
            )
            context.setFillColor((selectedHour == hour ? accent : accent.withAlphaComponent(0.72)).cgColor)
            if height > 0 {
                let cornerRadius = min(barWidth / 2, height)
                let path = UIBezierPath(
                    roundedRect: bar,
                    byRoundingCorners: [.topLeft, .topRight],
                    cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
                )
                context.addPath(path.cgPath)
                context.fillPath()
            }
            if selectedHour == hour && height == 0 {
                context.fill(CGRect(x: bar.minX, y: plot.maxY - 2, width: bar.width, height: 2))
            }
        }

        for hour in stride(from: 0, through: 20, by: 4) {
            let x = plot.minX + (CGFloat(hour) + 0.5) * slotWidth
            drawAxisText("\(hour)", at: CGPoint(x: x - 6, y: plot.maxY + 8), color: textColor)
        }
        drawAxisText("23", at: CGPoint(x: plot.maxX - 10, y: plot.maxY + 8), color: textColor)
    }

    private func drawAxisText(_ text: String, at point: CGPoint, color: UIColor) {
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: color
            ]
        )
    }

    @objc private func chartTapped(_ gesture: UITapGestureRecognizer) {
        let plot = CGRect(x: 36, y: 38, width: max(bounds.width - 42, 1), height: 164)
        let x = min(max(gesture.location(in: self).x, plot.minX), plot.maxX)
        let hour = min(max(Int((x - plot.minX) / plot.width * 24), 0), 23)
        selectedHour = hour
        let pace = ReadingPace.wordsPerMinute(
            words: charactersByHour[hour],
            effectiveSeconds: paceSecondsByHour[hour]
        )
        detailLabel.text = String(
            format: L("%02d:00–%02d:00 · %d 分钟 · %d 页 · %d 字 · %@"),
            hour,
            (hour + 1) % 24,
            Int(minutesByHour[hour].rounded()),
            pagesByHour[hour],
            charactersByHour[hour],
            pace.map { LF("%d 字/分钟", $0) } ?? L("--")
        )
        accessibilityValue = detailLabel.text
        UISelectionFeedbackGenerator().selectionChanged()
        setNeedsDisplay()
    }

    private static func normalized<T>(_ values: [T], fallback: T) -> [T] {
        Array(values.prefix(24)) + Array(repeating: fallback, count: max(0, 24 - values.count))
    }
}

/// A tappable 24-hour reading chart. Every point represents the foreground
/// reading time accumulated within that clock hour, capped visually at 60 min.
final class LVHourlyReadingChartView: UIView {
    private var minutesByHour: [Double]
    private var paceSecondsByHour: [Int]
    private var pagesByHour: [Int]
    private var charactersByHour: [Int]
    private let detailLabel = UILabel()
    private var selectedHour: Int?

    init(
        minutesByHour: [Double],
        paceSecondsByHour: [Int],
        pagesByHour: [Int],
        charactersByHour: [Int]
    ) {
        self.minutesByHour = Array(minutesByHour.prefix(24))
            + Array(repeating: 0.0, count: max(0, 24 - minutesByHour.count))
        self.paceSecondsByHour = Array(paceSecondsByHour.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - paceSecondsByHour.count))
        self.pagesByHour = Array(pagesByHour.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - pagesByHour.count))
        self.charactersByHour = Array(charactersByHour.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - charactersByHour.count))
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = L("今日每小时阅读有效时长、页数和字数图表")
        backgroundColor = .clear
        heightAnchor.constraint(equalToConstant: 240).isActive = true
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        detailLabel.textAlignment = .center
        detailLabel.textColor = LVBookshelfModuleStyle.accent
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.75
        detailLabel.text = L("点击数据点查看每小时有效阅读、页数、字数和阅读节奏")
        addSubview(detailLabel)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            detailLabel.topAnchor.constraint(equalTo: topAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chartTapped(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        minutesByHour: [Double],
        paceSecondsByHour: [Int],
        pagesByHour: [Int],
        charactersByHour: [Int]
    ) {
        self.minutesByHour = Array(minutesByHour.prefix(24))
            + Array(repeating: 0.0, count: max(0, 24 - minutesByHour.count))
        self.paceSecondsByHour = Array(paceSecondsByHour.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - paceSecondsByHour.count))
        self.pagesByHour = Array(pagesByHour.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - pagesByHour.count))
        self.charactersByHour = Array(charactersByHour.prefix(24))
            + Array(repeating: 0, count: max(0, 24 - charactersByHour.count))
        selectedHour = nil
        detailLabel.text = L("点击数据点查看每小时有效阅读、页数、字数和阅读节奏")
        accessibilityValue = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let textColor = LVBookshelfModuleStyle.secondaryText
        let gridColor = LVBookshelfModuleStyle.divider.withAlphaComponent(0.8)
        let accent = LVBookshelfModuleStyle.accent
        let plot = CGRect(x: 28, y: 38, width: max(bounds.width - 34, 1), height: 164)

        context.setLineWidth(1 / UIScreen.main.scale)
        context.setStrokeColor(gridColor.cgColor)
        for minute in stride(from: 0, through: 60, by: 20) {
            let y = plot.maxY - CGFloat(minute) / 60 * plot.height
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()
            drawAxisText("\(minute)", at: CGPoint(x: 0, y: y - 7), color: textColor)
        }

        let points = (0..<24).map { hour in
            let minutes = min(max(minutesByHour[hour], 0), 60)
            return CGPoint(
                x: plot.minX + (CGFloat(hour) + 0.5) / 24 * plot.width,
                y: plot.maxY - CGFloat(minutes / 60) * plot.height
            )
        }
        let path = UIBezierPath()
        if let first = points.first {
            path.move(to: first)
            for index in 0..<(points.count - 1) {
                let previous = points[max(index - 1, 0)]
                let current = points[index]
                let next = points[index + 1]
                let following = points[min(index + 2, points.count - 1)]
                var firstControl = CGPoint(
                    x: current.x + (next.x - previous.x) / 6,
                    y: current.y + (next.y - previous.y) / 6
                )
                var secondControl = CGPoint(
                    x: next.x - (following.x - current.x) / 6,
                    y: next.y - (following.y - current.y) / 6
                )
                firstControl.y = min(max(firstControl.y, plot.minY), plot.maxY)
                secondControl.y = min(max(secondControl.y, plot.minY), plot.maxY)
                path.addCurve(to: next, controlPoint1: firstControl, controlPoint2: secondControl)
            }
        }
        accent.setStroke()
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.stroke()

        for hour in 0..<24 {
            let minutes = min(max(minutesByHour[hour], 0), 60)
            guard minutes > 0 else { continue }
            let point = points[hour]
            let selected = selectedHour == hour
            context.setFillColor((selected ? accent : accent.withAlphaComponent(0.72)).cgColor)
            let radius: CGFloat = selected ? 5 : 3
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }

        for hour in stride(from: 0, through: 24, by: 4) {
            let x = plot.minX + CGFloat(hour) / 24 * plot.width
            drawAxisText("\(hour)", at: CGPoint(x: x - 6, y: plot.maxY + 8), color: textColor)
        }
    }

    private func drawAxisText(_ text: String, at point: CGPoint, color: UIColor) {
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: color
            ]
        )
    }

    @objc private func chartTapped(_ gesture: UITapGestureRecognizer) {
        let plot = CGRect(x: 28, y: 38, width: max(bounds.width - 34, 1), height: 164)
        let x = min(max(gesture.location(in: self).x, plot.minX), plot.maxX)
        let hour = min(max(Int(floor((x - plot.minX) / plot.width * 24)), 0), 23)
        selectedHour = hour
        let minutes = minutesByHour[hour]
        let pace = ReadingPace.wordsPerMinute(
            words: charactersByHour[hour],
            effectiveSeconds: paceSecondsByHour[hour]
        )
        detailLabel.text = String(
            format: L("%02d:00–%02d:00 · %d 分钟 · %d 页 · %d 字 · %@"),
            hour,
            (hour + 1) % 24,
            Int(minutes.rounded()),
            pagesByHour[hour],
            charactersByHour[hour],
            pace.map { LF("%d 字/分钟", $0) } ?? L("--")
        )
        accessibilityValue = detailLabel.text
        UISelectionFeedbackGenerator().selectionChanged()
        setNeedsDisplay()
    }
}

final class LVStatsBarChartView: UIView {
    struct Item {
        let label: String
        let value: Double
        let valueText: String
    }

    init(items: [Item], color: UIColor, showsFullContent: Bool = false) {
        super.init(frame: .zero)
        build(items: items, color: color, showsFullContent: showsFullContent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(items: [Item], color: UIColor, showsFullContent: Bool) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        guard !items.isEmpty else {
            let empty = UILabel()
            empty.text = L("暂无数据")
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
            empty.textAlignment = .center
            empty.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(empty)
            return
        }

        let maximum = max(items.map(\.value).max() ?? 0, 1)
        for item in items {
            let label = UILabel()
            label.text = item.label
            label.font = .systemFont(ofSize: 12)
            label.textColor = LVBookshelfModuleStyle.adaptivePrimaryText

            let progress = UIProgressView(progressViewStyle: .default)
            progress.progress = Float(item.value / maximum)
            progress.progressTintColor = color
            progress.trackTintColor = .lvAdaptiveSurfaceSecondary
            progress.layer.cornerRadius = 2
            progress.clipsToBounds = true

            let value = UILabel()
            value.text = item.valueText
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            value.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
            value.textAlignment = .right
            let row: UIStackView
            if showsFullContent {
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                value.adjustsFontSizeToFitWidth = true
                value.minimumScaleFactor = 0.7
                value.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

                let header = UIStackView(arrangedSubviews: [label, value])
                header.axis = .horizontal
                header.alignment = .firstBaseline
                header.spacing = 8
                row = UIStackView(arrangedSubviews: [header, progress])
                row.axis = .vertical
            } else {
                label.lineBreakMode = .byTruncatingTail
                label.widthAnchor.constraint(equalToConstant: 72).isActive = true
                value.widthAnchor.constraint(equalToConstant: 64).isActive = true
                row = UIStackView(arrangedSubviews: [label, progress, value])
                row.axis = .horizontal
                row.alignment = .center
            }
            row.spacing = 8
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: showsFullContent ? 44 : 32).isActive = true
            stack.addArrangedSubview(row)
        }
    }
}
