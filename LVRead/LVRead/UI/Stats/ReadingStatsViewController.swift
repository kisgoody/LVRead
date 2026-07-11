import UIKit

final class ReadingStatsViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "阅读统计"
        buildInterface()
        reloadStatistics()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reloadStatistics()
    }

    private func buildInterface() {
        view.backgroundColor = .lvAdaptiveBackground
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

        let stats = ReadingStatsRepository.shared.getStats()
        let analytics = ReadingAnalytics(stats: stats)
        let books = BookRepository.shared.getAll()
        let bookStats = ReadingStatsRepository.shared.getBookStats()
        let bookmarkCount = books.reduce(0) { $0 + BookRepository.shared.getBookmarks(for: $1.id).count }
        let annotationCount = books.reduce(0) { $0 + BookRepository.shared.getHighlights(for: $1.id).count }

        stackView.addArrangedSubview(makeSummaryGrid(items: [
            ("总时长", analytics.totalReadingTimeFormatted, "clock"),
            ("总页数", "\(stats.totalPagesRead) 页", "doc.text"),
            ("本周", "\(analytics.weeklyReadingMinutes) 分钟", "calendar"),
            ("连续阅读", "\(analytics.currentStreak) 天", "flame")
        ]))

        let dailyItems = analytics.weeklyChartData.map {
            LVStatsBarChartView.Item(label: $0.date, value: Double($0.minutes), valueText: "\($0.minutes) 分")
        }
        stackView.addArrangedSubview(makeSection(
            title: "近 7 天阅读时长",
            subtitle: "每天实际完成的阅读分钟数",
            content: LVStatsBarChartView(items: dailyItems, color: UIColor(hex: "#236D67"))
        ))

        let weeklyItems = stats.weeklyReadingMinutes.keys.sorted().suffix(8).map { key in
            let value = stats.weeklyReadingMinutes[key] ?? 0
            return LVStatsBarChartView.Item(
                label: key.replacingOccurrences(of: "-W", with: "周"),
                value: Double(value),
                valueText: "\(value) 分"
            )
        }
        stackView.addArrangedSubview(makeSection(
            title: "周度趋势",
            subtitle: "最近 8 个有记录的自然周",
            content: LVStatsBarChartView(items: weeklyItems, color: .lvInfo)
        ))

        let unread = books.filter { $0.readingProgress.progressPercent <= 0 }.count
        let reading = books.filter { $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100 }.count
        let finished = books.filter { $0.readingProgress.progressPercent >= 100 }.count
        stackView.addArrangedSubview(makeSection(
            title: "藏书阅读状态",
            subtitle: "共 \(books.count) 本",
            content: LVStatsBarChartView(items: [
                .init(label: "待读", value: Double(unread), valueText: "\(unread) 本"),
                .init(label: "阅读中", value: Double(reading), valueText: "\(reading) 本"),
                .init(label: "已读完", value: Double(finished), valueText: "\(finished) 本")
            ], color: .lvSecondary)
        ))

        let formats = Dictionary(grouping: books, by: { $0.fileFormat.displayName })
            .map { LVStatsBarChartView.Item(label: $0.key, value: Double($0.value.count), valueText: "\($0.value.count) 本") }
            .sorted { $0.value > $1.value }
        stackView.addArrangedSubview(makeSection(
            title: "文件格式分布",
            subtitle: "当前书架的内容组成",
            content: LVStatsBarChartView(items: formats, color: .lvAccent)
        ))

        let topBooks = bookStats.sorted { $0.value.readingTimeSeconds > $1.value.readingTimeSeconds }
            .prefix(5)
            .compactMap { id, value -> LVStatsBarChartView.Item? in
                guard let book = books.first(where: { $0.id == id }) else { return nil }
                let minutes = value.readingTimeSeconds / 60
                return .init(label: book.title, value: Double(minutes), valueText: "\(minutes) 分")
            }
        stackView.addArrangedSubview(makeSection(
            title: "常读书籍",
            subtitle: "按累计阅读时长排序",
            content: LVStatsBarChartView(items: Array(topBooks), color: .lvPrimary)
        ))

        stackView.addArrangedSubview(makeSection(
            title: "笔记沉淀",
            subtitle: "阅读过程中保存的内容资产",
            content: LVStatsBarChartView(items: [
                .init(label: "书签", value: Double(bookmarkCount), valueText: "\(bookmarkCount) 个"),
                .init(label: "批注", value: Double(annotationCount), valueText: "\(annotationCount) 条")
            ], color: UIColor(hex: "#C67B5C"))
        ))

        stackView.addArrangedSubview(makeAdviceCard(
            suggestions(stats: stats, analytics: analytics, books: books, noteCount: bookmarkCount + annotationCount)
        ))
    }

    private func makeSummaryGrid(items: [(String, String, String)]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        for start in stride(from: 0, to: items.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.addArrangedSubview(makeMetricCard(items[start]))
            if start + 1 < items.count { row.addArrangedSubview(makeMetricCard(items[start + 1])) }
            container.addArrangedSubview(row)
        }
        return container
    }

    private func makeMetricCard(_ item: (String, String, String)) -> UIView {
        let card = makeCard()
        let icon = UIImageView(image: UIImage(systemName: item.2))
        icon.tintColor = UIColor(hex: "#236D67")
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let value = UILabel()
        value.text = item.1
        value.font = .systemFont(ofSize: 20, weight: .bold)
        value.textColor = .lvAdaptiveTextPrimary
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.75
        let title = UILabel()
        title.text = item.0
        title.font = .systemFont(ofSize: 12)
        title.textColor = .lvAdaptiveTextSecondary
        let stack = UIStackView(arrangedSubviews: [icon, value, title])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        embed(stack, in: card)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        return card
    }

    private func makeSection(title: String, subtitle: String, content: UIView) -> UIView {
        let card = makeCard()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .lvAdaptiveTextPrimary
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .lvAdaptiveTextSecondary
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, content])
        stack.axis = .vertical
        stack.spacing = 12
        embed(stack, in: card)
        return card
    }

    private func makeAdviceCard(_ suggestions: [String]) -> UIView {
        let card = makeCard()
        let title = UILabel()
        title.text = "阅读建议"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .lvAdaptiveTextPrimary
        let stack = UIStackView(arrangedSubviews: [title])
        stack.axis = .vertical
        stack.spacing = 12
        suggestions.forEach { suggestion in
            let label = UILabel()
            label.text = "• \(suggestion)"
            label.font = .systemFont(ofSize: 14)
            label.textColor = .lvAdaptiveTextSecondary
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        embed(stack, in: card)
        return card
    }

    private func suggestions(
        stats: ReadingStats,
        analytics: ReadingAnalytics,
        books: [Book],
        noteCount: Int
    ) -> [String] {
        let savedGoal = UserDefaults.standard.integer(forKey: "profile_daily_reading_goal_minutes")
        let goal = savedGoal > 0 ? savedGoal : 30
        var result: [String] = []
        if analytics.todayReadingMinutes < goal {
            result.append("今天距离 \(goal) 分钟目标还差 \(goal - analytics.todayReadingMinutes) 分钟，可以安排一次短阅读。")
        } else {
            result.append("今天已完成阅读目标，保持当前节奏即可。")
        }
        if analytics.currentStreak == 0 {
            result.append("连续阅读尚未建立，建议从每天固定 10 分钟开始。")
        } else {
            result.append("已经连续阅读 \(analytics.currentStreak) 天，尽量在相同时间段继续阅读。")
        }
        let readingBooks = books.filter { $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100 }
        if readingBooks.count > 3 {
            result.append("当前有 \(readingBooks.count) 本书同时在读，建议优先完成进度最高的 1–2 本。")
        }
        if stats.totalPagesRead > 20, noteCount == 0 {
            result.append("已有较多阅读记录但尚无笔记，可以尝试每章保存一个书签或批注。")
        } else if noteCount > 0 {
            result.append("已沉淀 \(noteCount) 条笔记，建议定期在“笔记”模块回顾和清理。")
        }
        return result
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .lvAdaptiveSurface
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.05
        card.layer.shadowRadius = 10
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        return card
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
}

final class LVStatsBarChartView: UIView {
    struct Item {
        let label: String
        let value: Double
        let valueText: String
    }

    init(items: [Item], color: UIColor) {
        super.init(frame: .zero)
        build(items: items, color: color)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(items: [Item], color: UIColor) {
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
            empty.text = "暂无数据"
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = .lvAdaptiveTextSecondary
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
            label.textColor = .lvAdaptiveTextPrimary
            label.lineBreakMode = .byTruncatingTail
            label.widthAnchor.constraint(equalToConstant: 72).isActive = true

            let progress = UIProgressView(progressViewStyle: .default)
            progress.progress = Float(item.value / maximum)
            progress.progressTintColor = color
            progress.trackTintColor = .lvAdaptiveSurfaceSecondary
            progress.layer.cornerRadius = 2
            progress.clipsToBounds = true

            let value = UILabel()
            value.text = item.valueText
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            value.textColor = .lvAdaptiveTextSecondary
            value.textAlignment = .right
            value.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let row = UIStackView(arrangedSubviews: [label, progress, value])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
            stack.addArrangedSubview(row)
        }
    }
}
