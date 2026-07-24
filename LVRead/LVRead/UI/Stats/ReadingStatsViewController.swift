import UIKit

final class ReadingStatsViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "阅读统计"
        buildInterface()
        reloadStatistics()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .darkModeChanged,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        applyNavigationAppearance()
        reloadStatistics()
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

        let stats = ReadingStatsRepository.shared.getStats()
        let analytics = ReadingAnalytics(stats: stats)
        let timeSummary = ReadingStatsRepository.shared.consistentReadingSummary()
        let books = BookRepository.shared.getAll()
        let bookStats = ReadingStatsRepository.shared.getBookStats()

        stackView.addArrangedSubview(makeSummaryGrid(items: [
            ("总时长", "\(timeSummary.total) 分钟", "clock"),
            ("总页数", "\(stats.totalPagesRead) 页", "doc.text"),
            ("本周", "\(timeSummary.weekly) 分钟", "calendar"),
            ("连续阅读", "\(analytics.currentStreak) 天", "flame")
        ]))

        stackView.addArrangedSubview(makeSection(
            title: "阅读时段",
            subtitle: "",
            content: LVHourlyReadingHistoryView(repository: .shared)
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

        stackView.addArrangedSubview(makeAdviceCard(
            ReadingAdviceEngine.shared.suggestions().map(\.text)
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
        LVBookshelfModuleStyle.applyAccent(to: icon)
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let value = UILabel()
        value.text = item.1
        value.font = .systemFont(ofSize: 20, weight: .bold)
        value.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.75
        let title = UILabel()
        title.text = item.0
        title.font = .systemFont(ofSize: 12)
        title.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
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
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        subtitleLabel.isHidden = subtitle.isEmpty
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
        navigationController?.navigationBar.tintColor = LVBookshelfModuleStyle.accent
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

/// Browses every date that contains reading records without leaving the chart.
final class LVHourlyReadingHistoryView: UIView {
    private let repository: ReadingStatsRepository
    private let dates: [Date]
    private var selectedIndex: Int
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let dateLabel = UILabel()
    private let totalLabel = UILabel()
    private let chart: LVHourlyReadingChartView

    init(repository: ReadingStatsRepository) {
        self.repository = repository
        dates = repository.hourlyReadingDates()
        selectedIndex = max(dates.count - 1, 0)
        chart = LVHourlyReadingChartView(
            minutesByHour: repository.hourlyReadingMinutes(for: dates[max(dates.count - 1, 0)])
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
        previousButton.accessibilityLabel = "上一条阅读日期"
        nextButton.accessibilityLabel = "下一条阅读日期"
        previousButton.addTarget(self, action: #selector(showPreviousDate), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(showNextDate), for: .touchUpInside)
        [previousButton, nextButton].forEach {
            $0.tintColor = LVBookshelfModuleStyle.accent
            $0.widthAnchor.constraint(equalToConstant: 44).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        dateLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        dateLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        dateLabel.textAlignment = .center
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        totalLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        totalLabel.textAlignment = .center

        let labels = UIStackView(arrangedSubviews: [dateLabel, totalLabel])
        labels.axis = .vertical
        labels.spacing = 4
        let navigator = UIStackView(arrangedSubviews: [previousButton, labels, nextButton])
        navigator.axis = .horizontal
        navigator.alignment = .center
        navigator.distribution = .fill

        let stack = UIStackView(arrangedSubviews: [navigator, chart])
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
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "yyyy年M月d日 · 今天" : "yyyy年M月d日"
        dateLabel.text = formatter.string(from: date)
        totalLabel.text = "当日阅读总时间：\(repository.displayedReadingMinutes(for: date))分钟"
        chart.update(minutesByHour: displayedMinutes.map(Double.init))
        previousButton.isEnabled = selectedIndex > 0
        nextButton.isEnabled = selectedIndex < dates.count - 1
        previousButton.alpha = previousButton.isEnabled ? 1 : 0.3
        nextButton.alpha = nextButton.isEnabled ? 1 : 0.3
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
}

/// A tappable 24-hour reading chart. Every point represents the foreground
/// reading time accumulated within that clock hour, capped visually at 60 min.
final class LVHourlyReadingChartView: UIView {
    private var minutesByHour: [Double]
    private let detailLabel = UILabel()
    private var selectedHour: Int?

    init(minutesByHour: [Double]) {
        self.minutesByHour = Array(minutesByHour.prefix(24))
            + Array(repeating: 0.0, count: max(0, 24 - minutesByHour.count))
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = "今日每小时阅读时长图表"
        backgroundColor = .clear
        heightAnchor.constraint(equalToConstant: 240).isActive = true
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        detailLabel.textAlignment = .center
        detailLabel.textColor = LVBookshelfModuleStyle.accent
        detailLabel.text = "点击数据点查看每小时阅读时长"
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

    func update(minutesByHour: [Double]) {
        self.minutesByHour = Array(minutesByHour.prefix(24))
            + Array(repeating: 0.0, count: max(0, 24 - minutesByHour.count))
        selectedHour = nil
        detailLabel.text = "点击数据点查看每小时阅读时长"
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

        let path = UIBezierPath()
        for hour in 0..<24 {
            let minutes = min(max(minutesByHour[hour], 0), 60)
            let point = CGPoint(
                x: plot.minX + (CGFloat(hour) + 0.5) / 24 * plot.width,
                y: plot.maxY - CGFloat(minutes / 60) * plot.height
            )
            hour == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        accent.setStroke()
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.stroke()

        for hour in 0..<24 {
            let minutes = min(max(minutesByHour[hour], 0), 60)
            guard minutes > 0 else { continue }
            let point = CGPoint(
                x: plot.minX + (CGFloat(hour) + 0.5) / 24 * plot.width,
                y: plot.maxY - CGFloat(minutes / 60) * plot.height
            )
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
        detailLabel.text = String(
            format: "%02d:00–%02d:00 · %d 分钟",
            hour,
            (hour + 1) % 24,
            Int(minutes.rounded())
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
            value.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
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
