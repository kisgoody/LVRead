import UIKit

final class ProfileViewController: UIViewController {
    private enum Keys { static let dailyGoalMinutes = "profile_daily_reading_goal_minutes" }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let overviewMetricsView = LVReadingOverviewMetricsView()
    private let streakMetricLabel = UILabel()
    private let nightSwitch = UISwitch()
    private let restoreReadingSwitch = UISwitch()
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
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .profile)
        applyAppearance()
        updateContent()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        view.backgroundColor = profilePageBackground
        titleLabel.text = L("我的")
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        subtitleLabel.text = LVModuleSubtitleProvider.subtitle(for: .profile)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        subtitleLabel.numberOfLines = 2

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
        stackView.addArrangedSubview(makePreferencesCard())
        stackView.addArrangedSubview(makeAboutCard())
        moduleNavigation.onSelect = { [weak self] module in self?.showMainModule(module) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
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

    private func makeStatsCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading("\(L("阅读概览")) · \(L("今日"))")
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        streakMetricLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        streakMetricLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        streakMetricLabel.textAlignment = .right
        streakMetricLabel.adjustsFontSizeToFitWidth = true
        streakMetricLabel.minimumScaleFactor = 0.8
        let header = UIStackView(arrangedSubviews: [heading, UIView(), streakMetricLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let button = UIButton(type: .system)
        button.setTitle(L("查看详细阅读统计"), for: .normal)
        button.setImage(UIImage(systemName: "chart.bar.xaxis"), for: .normal)
        LVBookshelfModuleStyle.applyAccent(to: button)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentHorizontalAlignment = .left
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: #selector(showStats), for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [
            header, overviewMetricsView, divider(), button
        ])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makePreferencesCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading(L("阅读偏好"))

        let nightRow = makeRow(title: L("夜间模式"), subtitle: L("降低界面亮度，适合暗光环境"), control: nightSwitch)
        nightSwitch.addTarget(self, action: #selector(nightChanged), for: .valueChanged)

        let restoreRow = makeRow(
            title: L("恢复上次阅读"),
            subtitle: L("在阅读时退出APP，App 重新启动后自动返回上次阅读的书籍"),
            control: restoreReadingSwitch
        )
        restoreReadingSwitch.addTarget(
            self,
            action: #selector(restoreReadingChanged),
            for: .valueChanged
        )
        restoreReadingSwitch.accessibilityLabel = L("恢复上次阅读")
        restoreReadingSwitch.accessibilityHint = L("在阅读时退出APP，App 重新启动后自动返回上次阅读的书籍")

        goalStepper.minimumValue = 10
        goalStepper.maximumValue = 180
        goalStepper.stepValue = 10
        goalStepper.addTarget(self, action: #selector(goalChanged), for: .valueChanged)
        let goalRow = makeRow(title: L("每日目标"), subtitle: L("用于展示每日阅读进度"), control: goalStepper)
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
            heading, nightRow, divider(), restoreRow, divider(), goalRow, goalValueRow,
            goalProgressView, goalProgressLabel
        ])
        content.axis = .vertical
        content.spacing = 12
        embed(content, in: card)
        return card
    }

    private func makeAboutCard() -> UIView {
        let card = makeCard()
        let heading = makeHeading(L("版本信息"))
        let label = UILabel()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("未知")
        label.text = LF("LVRead V%@", version)
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
        let todayPace = statsRepository.readingPaceSummary(for: Date())
        overviewMetricsView.update(with: todayPace)
        streakMetricLabel.text = LF("连续阅读 %d 天", analytics.currentStreak)
        let savedGoal = UserDefaults.standard.integer(forKey: Keys.dailyGoalMinutes)
        let goal = savedGoal > 0 ? savedGoal : 30
        nightSwitch.isOn = DarkModeManager.shared.isDarkMode
        restoreReadingSwitch.isOn = NativeReaderRestorationStore.isEnabled()
        goalStepper.value = Double(savedGoal > 0 ? savedGoal : 30)
        goalLabel.text = LF("目标：%d 分钟/天", Int(goalStepper.value))
        goalProgressView.progress = min(Float(todayMinutes) / Float(goal), 1)
        goalProgressLabel.text = todayMinutes >= goal
            ? LF("今日已阅读 %d 分钟，已达标", todayMinutes)
            : LF("今日 %d / %d 分钟，还差 %d 分钟", todayMinutes, goal, goal - todayMinutes)
        goalProgressView.accessibilityLabel = L("今日阅读目标进度")
        goalProgressView.accessibilityValue = goalProgressLabel.text
    }

    @objc private func showStats() {
        navigationController?.pushViewController(ReadingStatsViewController(), animated: true)
    }

    @objc private func nightChanged() {
        DarkModeManager.shared.setNightMode(nightSwitch.isOn)
    }

    @objc private func restoreReadingChanged() {
        NativeReaderRestorationStore.setEnabled(restoreReadingSwitch.isOn)
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
        nightSwitch.onTintColor = LVBookshelfModuleStyle.accent
        restoreReadingSwitch.onTintColor = LVBookshelfModuleStyle.accent
        goalProgressView.progressTintColor = LVBookshelfModuleStyle.accent
        goalProgressView.trackTintColor = LVBookshelfModuleStyle.divider
    }
}

private var profilePageBackground: UIColor {
    LVBookshelfModuleStyle.pageBackground
}
