import UIKit

final class ProfileViewController: UIViewController {
    private enum Keys { static let dailyGoalMinutes = "profile_daily_reading_goal_minutes" }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let todayMetricLabel = UILabel()
    private let pagesMetricLabel = UILabel()
    private let streakMetricLabel = UILabel()
    private let adviceLabel = UILabel()
    private let libraryStatsLabel = UILabel()
    private let noteStatsLabel = UILabel()
    private let nightSwitch = UISwitch()
    private let goalLabel = UILabel()
    private let goalStepper = UIStepper()
    private let moduleNavigation = LVModuleNavigationView(selectedModule: .profile)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .darkModeChanged,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        updateContent()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = profilePageBackground
        titleLabel.text = "我的"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .lvAdaptiveTextPrimary
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .profile)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .lvAdaptiveTextSecondary

        scrollView.alwaysBounceVertical = true
        stackView.axis = .vertical
        stackView.spacing = 12
        scrollView.addSubview(stackView)
        [titleLabel, subtitleLabel, scrollView, moduleNavigation].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(makeMetricsGrid())
        stackView.addArrangedSubview(makeAdviceCard())
        stackView.addArrangedSubview(makeStatsCard())
        stackView.addArrangedSubview(makePreferencesCard())
        stackView.addArrangedSubview(makeAboutCard())
        moduleNavigation.onSelect = { [weak self] module in self?.showMainModule(module) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: moduleNavigation.topAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            moduleNavigation.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            moduleNavigation.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            moduleNavigation.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            moduleNavigation.heightAnchor.constraint(equalToConstant: 76)
        ])
    }

    private func makeMetricsGrid() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            makeMetric(valueLabel: todayMetricLabel, title: "今日"),
            makeMetric(valueLabel: pagesMetricLabel, title: "累计页数"),
            makeMetric(valueLabel: streakMetricLabel, title: "连续")
        ])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return stack
    }

    private func makeMetric(valueLabel: UILabel, title: String) -> UIView {
        let card = makeCard()
        valueLabel.font = .systemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = .lvAdaptiveTextPrimary
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        let caption = UILabel()
        caption.text = title
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .lvAdaptiveTextSecondary
        caption.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [valueLabel, caption])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8)
        ])
        return card
    }

    private func makeAdviceCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: "#2B2418") : UIColor(hex: "#FFF7E8")
        }
        card.layer.cornerRadius = 8
        let marker = UIView()
        marker.backgroundColor = UIColor(hex: "#C2933D")
        let heading = UILabel()
        heading.text = "阅读建议"
        heading.font = .systemFont(ofSize: 14, weight: .bold)
        heading.textColor = .lvAdaptiveTextPrimary
        adviceLabel.font = .systemFont(ofSize: 14)
        adviceLabel.textColor = .lvAdaptiveTextSecondary
        adviceLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [heading, adviceLabel])
        stack.axis = .vertical
        stack.spacing = 4
        [marker, stack].forEach {
            card.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            marker.topAnchor.constraint(equalTo: card.topAnchor),
            marker.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            marker.widthAnchor.constraint(equalToConstant: 4),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func makeStatsCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading("阅读统计")
        summaryLabel.numberOfLines = 0
        summaryLabel.font = .systemFont(ofSize: 14)
        summaryLabel.textColor = .lvAdaptiveTextSecondary

        let button = UIButton(type: .system)
        button.setTitle("查看完整统计与建议", for: .normal)
        button.setImage(UIImage(systemName: "chart.bar.xaxis"), for: .normal)
        button.tintColor = UIColor(hex: "#236D67")
        button.setTitleColor(UIColor(hex: "#236D67"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentHorizontalAlignment = .left
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: #selector(showStats), for: .touchUpInside)

        let libraryHeading = makeSectionTitle("藏书统计")
        libraryStatsLabel.font = .systemFont(ofSize: 14)
        libraryStatsLabel.textColor = .lvAdaptiveTextSecondary
        libraryStatsLabel.numberOfLines = 0
        let noteHeading = makeSectionTitle("笔记统计")
        noteStatsLabel.font = .systemFont(ofSize: 14)
        noteStatsLabel.textColor = .lvAdaptiveTextSecondary
        noteStatsLabel.numberOfLines = 0
        let content = UIStackView(arrangedSubviews: [
            heading, summaryLabel, divider(), libraryHeading, libraryStatsLabel,
            divider(), noteHeading, noteStatsLabel, button
        ])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .lvAdaptiveTextPrimary
        return label
    }

    private func makePreferencesCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading("阅读偏好")

        let nightRow = makeRow(title: "夜间模式", subtitle: "降低界面亮度，适合暗光环境", control: nightSwitch)
        nightSwitch.addTarget(self, action: #selector(nightChanged), for: .valueChanged)

        goalStepper.minimumValue = 10
        goalStepper.maximumValue = 180
        goalStepper.stepValue = 10
        goalStepper.addTarget(self, action: #selector(goalChanged), for: .valueChanged)
        let goalRow = makeRow(title: "每日目标", subtitle: "用于生成阅读建议", control: goalStepper)
        goalLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        goalLabel.textColor = UIColor(hex: "#236D67")

        let goalValueRow = UIStackView(arrangedSubviews: [goalLabel, UIView()])
        goalValueRow.axis = .horizontal

        let content = UIStackView(arrangedSubviews: [heading, nightRow, divider(), goalRow, goalValueRow])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeAboutCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading("模块说明")
        let label = UILabel()
        label.text = "笔记用于管理书签、摘录和批注；我的用于阅读统计、目标和全局偏好。"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .lvAdaptiveTextSecondary
        label.numberOfLines = 0
        let content = UIStackView(arrangedSubviews: [heading, label])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = profileCardBackground
        card.layer.cornerRadius = 8
        card.layer.borderWidth = 1 / UIScreen.main.scale
        card.layer.borderColor = UIColor.lvAdaptiveDivider.cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowRadius = 17
        card.layer.shadowOffset = CGSize(width: 0, height: 7)
        return card
    }

    private func makeHeading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .lvAdaptiveTextPrimary
        return label
    }

    private func makeRow(title: String, subtitle: String, control: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .lvAdaptiveTextPrimary
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .lvAdaptiveTextSecondary
        subtitleLabel.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 4
        let row = UIStackView(arrangedSubviews: [labels, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        return row
    }

    private func divider() -> UIView {
        let value = UIView()
        value.backgroundColor = .lvAdaptiveDivider
        value.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return value
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

    private func updateContent() {
        let stats = ReadingStatsRepository.shared.getStats()
        let analytics = ReadingAnalytics(stats: stats)
        let books = BookRepository.shared.getAll()
        let noteCount = books.reduce(0) {
            $0 + BookRepository.shared.getBookmarks(for: $1.id).count
                + BookRepository.shared.getHighlights(for: $1.id).count
        }
        let finishedCount = books.filter { $0.readingProgress.progressPercent >= 100 }.count
        let readingCount = books.filter { $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100 }.count
        todayMetricLabel.text = "\(analytics.todayReadingMinutes)m"
        pagesMetricLabel.text = "\(stats.totalPagesRead)"
        streakMetricLabel.text = "\(analytics.currentStreak)天"
        let savedGoal = UserDefaults.standard.integer(forKey: Keys.dailyGoalMinutes)
        let goal = savedGoal > 0 ? savedGoal : 30
        adviceLabel.text = analytics.todayReadingMinutes >= goal
            ? "今天已完成 \(goal) 分钟目标，保持当前阅读节奏。"
            : "今天距离目标还差 \(goal - analytics.todayReadingMinutes) 分钟，可以安排一次短阅读。"
        summaryLabel.text = "累计阅读 \(analytics.totalReadingTimeFormatted)\n阅读 \(stats.totalPagesRead) 页 · 完成 \(finishedCount) 本 · 沉淀 \(noteCount) 条笔记"
        libraryStatsLabel.text = "总藏书 \(books.count) 本，阅读中 \(readingCount) 本，已读完 \(finishedCount) 本。"
        let bookmarkCount = books.reduce(0) { $0 + BookRepository.shared.getBookmarks(for: $1.id).count }
        let annotationCount = books.reduce(0) { $0 + BookRepository.shared.getHighlights(for: $1.id).count }
        noteStatsLabel.text = "评论 \(annotationCount) 条，书签 \(bookmarkCount) 个。"
        nightSwitch.isOn = DarkModeManager.shared.isDarkMode
        goalStepper.value = Double(savedGoal > 0 ? savedGoal : 30)
        goalLabel.text = "当前目标：\(Int(goalStepper.value)) 分钟/天"
    }

    @objc private func showStats() {
        navigationController?.pushViewController(ReadingStatsViewController(), animated: true)
    }

    @objc private func nightChanged() {
        DarkModeManager.shared.appearanceMode = nightSwitch.isOn ? .dark : .light
    }

    @objc private func goalChanged() {
        let value = Int(goalStepper.value)
        UserDefaults.standard.set(value, forKey: Keys.dailyGoalMinutes)
        goalLabel.text = "当前目标：\(value) 分钟/天"
    }

    @objc private func themeChanged() {
        view.backgroundColor = profilePageBackground
        view.setNeedsLayout()
        updateContent()
    }
}

private var profilePageBackground: UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .dark ? .lvBgNight : UIColor(hex: "#F5F2EC")
    }
}

private var profileCardBackground: UIColor {
    UIColor { traits in
        traits.userInterfaceStyle == .dark ? .lvSurfaceDark : UIColor(hex: "#FFFDF8")
    }
}
