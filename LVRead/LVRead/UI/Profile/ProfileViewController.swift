import UIKit

final class ProfileViewController: UIViewController {
    private enum Keys { static let dailyGoalMinutes = "profile_daily_reading_goal_minutes" }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let todayMetricLabel = UILabel()
    private let totalTimeMetricLabel = UILabel()
    private let pagesMetricLabel = UILabel()
    private let streakMetricLabel = UILabel()
    private let adviceLabel = UILabel()
    private let nightSwitch = UISwitch()
    private let goalLabel = UILabel()
    private let goalProgressView = UIProgressView(progressViewStyle: .default)
    private let goalProgressLabel = UILabel()
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
        applyAppearance()
        updateContent()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = profilePageBackground
        titleLabel.text = "我的"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .profile)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText

        scrollView.alwaysBounceVertical = true
        stackView.axis = .vertical
        stackView.spacing = 12
        scrollView.addSubview(stackView)
        [titleLabel, subtitleLabel, scrollView, moduleNavigation].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(makeStatsCard())
        stackView.addArrangedSubview(makeAdviceCard())
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
        let firstRow = UIStackView(arrangedSubviews: [
            makeMetric(valueLabel: todayMetricLabel, title: "今日阅读"),
            makeMetric(valueLabel: totalTimeMetricLabel, title: "累计时长")
        ])
        let secondRow = UIStackView(arrangedSubviews: [
            makeMetric(valueLabel: pagesMetricLabel, title: "累计页数"),
            makeMetric(valueLabel: streakMetricLabel, title: "连续阅读")
        ])
        [firstRow, secondRow].forEach {
            $0.axis = .horizontal
            $0.spacing = 8
            $0.distribution = .fillEqually
        }
        let stack = UIStackView(arrangedSubviews: [firstRow, divider(), secondRow])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeMetric(valueLabel: UILabel, title: String) -> UIView {
        let container = UIView()
        valueLabel.font = .systemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        let caption = UILabel()
        caption.text = title
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        caption.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [valueLabel, caption])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        ])
        return container
    }

    private func makeAdviceCard() -> UIView {
        let card = UIView()
        LVBookshelfModuleStyle.applyCard(to: card)
        let marker = UIView()
        marker.backgroundColor = UIColor(hex: "#C2933D")
        let heading = UILabel()
        heading.text = "阅读建议"
        heading.font = .systemFont(ofSize: 14, weight: .bold)
        heading.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        adviceLabel.font = .systemFont(ofSize: 14)
        adviceLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
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
        let heading = makeHeading("阅读概览")

        let button = UIButton(type: .system)
        button.setTitle("查看详细趋势与建议", for: .normal)
        button.setImage(UIImage(systemName: "chart.bar.xaxis"), for: .normal)
        LVBookshelfModuleStyle.applyAccent(to: button)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentHorizontalAlignment = .left
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: #selector(showStats), for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [
            heading, makeMetricsGrid(), divider(), button
        ])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
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
        LVBookshelfModuleStyle.applyAccent(to: goalLabel)

        let goalValueRow = UIStackView(arrangedSubviews: [goalLabel, UIView()])
        goalValueRow.axis = .horizontal

        goalProgressView.layer.cornerRadius = 2
        goalProgressView.clipsToBounds = true
        goalProgressView.heightAnchor.constraint(equalToConstant: 4).isActive = true
        goalProgressLabel.font = .systemFont(ofSize: 12)
        goalProgressLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        goalProgressLabel.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [
            heading, nightRow, divider(), goalRow, goalValueRow,
            goalProgressView, goalProgressLabel
        ])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeAboutCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading("版本信息")
        let label = UILabel()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        label.text = "LVRead 版本：V\(version)"
        label.font = .systemFont(ofSize: 14)
        label.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        label.numberOfLines = 0
        let content = UIStackView(arrangedSubviews: [heading, label])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeCard() -> UIView {
        let card = UIView()
        LVBookshelfModuleStyle.applyCard(to: card)
        return card
    }

    private func makeHeading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        return label
    }

    private func makeRow(title: String, subtitle: String, control: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
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
        value.backgroundColor = LVBookshelfModuleStyle.adaptiveDivider
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
        let statsRepository = ReadingStatsRepository.shared
        let stats = statsRepository.getStats()
        let analytics = ReadingAnalytics(stats: stats)
        let todayMinutes = statsRepository.displayedReadingMinutes(for: Date())
        todayMetricLabel.text = "\(todayMinutes)分钟"
        totalTimeMetricLabel.text = analytics.totalReadingTimeFormatted
        pagesMetricLabel.text = "\(stats.totalPagesRead)"
        streakMetricLabel.text = "\(analytics.currentStreak)天"
        let savedGoal = UserDefaults.standard.integer(forKey: Keys.dailyGoalMinutes)
        let goal = savedGoal > 0 ? savedGoal : 30
        let suggestions = ReadingAdviceEngine.shared.suggestions()
        adviceLabel.text = suggestions.map { "• \($0.text)" }.joined(separator: "\n\n")
        adviceLabel.accessibilityLabel = suggestions.map(\.text).joined(separator: "；")
        nightSwitch.isOn = DarkModeManager.shared.isDarkMode
        goalStepper.value = Double(savedGoal > 0 ? savedGoal : 30)
        goalLabel.text = "当前目标：\(Int(goalStepper.value)) 分钟/天"
        goalProgressView.progress = min(Float(todayMinutes) / Float(goal), 1)
        goalProgressLabel.text = todayMinutes >= goal
            ? "今日已阅读 \(todayMinutes) 分钟，已达到目标"
            : "今日已阅读 \(todayMinutes) / \(goal) 分钟，还差 \(goal - todayMinutes) 分钟"
        goalProgressView.accessibilityLabel = "今日阅读目标进度"
        goalProgressView.accessibilityValue = goalProgressLabel.text
    }

    @objc private func showStats() {
        navigationController?.pushViewController(ReadingStatsViewController(), animated: true)
    }

    @objc private func nightChanged() {
        DarkModeManager.shared.setNightMode(nightSwitch.isOn)
    }

    @objc private func goalChanged() {
        let value = Int(goalStepper.value)
        UserDefaults.standard.set(value, forKey: Keys.dailyGoalMinutes)
        updateContent()
    }

    @objc private func themeChanged() {
        applyAppearance()
        view.setNeedsLayout()
        updateContent()
    }

    private func applyAppearance() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        LVBookshelfModuleStyle.refreshCards(in: view)
        LVBookshelfModuleStyle.refreshAccents(in: view)
        goalProgressView.progressTintColor = LVBookshelfModuleStyle.accent
        goalProgressView.trackTintColor = LVBookshelfModuleStyle.divider
    }
}

private var profilePageBackground: UIColor {
    LVBookshelfModuleStyle.pageBackground
}
