import UIKit

enum ReaderNavigationMode: String, CaseIterable {
    case simulation
    case horizontal
    case vertical
    case continuousVertical
    case none

    var title: String {
        switch self {
        case .simulation: return "仿真"
        case .horizontal: return "左右"
        case .vertical: return "上下"
        case .continuousVertical: return "滚屏"
        case .none: return "无动画"
        }
    }

    static func load() -> ReaderNavigationMode {
        let value = UserDefaults.standard.string(forKey: "native_reader_navigation_mode")
        return ReaderNavigationMode(rawValue: value ?? "") ?? .horizontal
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "native_reader_navigation_mode")
    }
}

final class NativeReaderCatalogViewController: UIViewController {
    var onSelect: ((Int) -> Void)?
    private let entries: [ReaderChapterContentPolicy.DirectoryEntry]
    private let currentIndex: Int
    private let currentEntryIndex: Int
    private let currentPageText: String
    private let settings: ReadingSettings
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(
        chapters: [Chapter],
        currentIndex: Int,
        currentPageText: String = "",
        settings: ReadingSettings = .default
    ) {
        let entries = ReaderChapterContentPolicy.directoryEntries(from: chapters)
        self.entries = entries
        self.currentIndex = currentIndex
        self.currentEntryIndex = entries.firstIndex {
            $0.sourceIndices.contains(currentIndex)
        } ?? 0
        self.currentPageText = currentPageText
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: settings.readingTheme.panelColor)
        buildHeader()
        buildTable()
        if #available(iOS 15.0, *) {
            sheetPresentationController?.detents = [.medium(), .large()]
            sheetPresentationController?.selectedDetentIdentifier = .medium
            sheetPresentationController?.prefersGrabberVisible = true
            sheetPresentationController?.prefersScrollingExpandsWhenScrolledToEdge = true
            sheetPresentationController?.preferredCornerRadius = 24
        }
    }

    private func buildHeader() {
        let title = UILabel()
        title.text = "章节目录"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = UIColor(hex: settings.readingTheme.textColor)

        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        close.tintColor = UIColor(hex: settings.readingTheme.textColor)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.heightAnchor.constraint(equalToConstant: 44).isActive = true

        view.addSubview(title)
        view.addSubview(close)
        [title, close].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func buildTable() {
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(hex: settings.readingTheme.textColor).withAlphaComponent(0.12)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chapter")
        tableView.rowHeight = 72
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        guard entries.indices.contains(currentEntryIndex) else { return }
        tableView.scrollToRow(at: IndexPath(row: currentEntryIndex, section: 0), at: .middle, animated: false)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
}

extension NativeReaderCatalogViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chapter", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        let isCurrent = indexPath.row == currentEntryIndex
        let textColor = UIColor(hex: settings.readingTheme.textColor)
        let accent = UIColor(hex: settings.readingTheme.accentColor)
        configuration.text = entries[indexPath.row].chapter.title
        configuration.textProperties.font = .systemFont(ofSize: 18, weight: isCurrent ? .semibold : .regular)
        configuration.textProperties.numberOfLines = 1
        configuration.textProperties.lineBreakMode = .byTruncatingTail
        configuration.textProperties.color = isCurrent ? accent : textColor
        if isCurrent, !currentPageText.isEmpty {
            configuration.secondaryText = currentPageText
            configuration.secondaryTextProperties.font = .systemFont(ofSize: 14)
            configuration.secondaryTextProperties.color = textColor.withAlphaComponent(0.56)
        }
        cell.contentConfiguration = configuration
        cell.backgroundColor = .clear
        cell.tintColor = accent
        cell.accessoryType = isCurrent ? .checkmark : .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.row]
        let targetIndex = entry.sourceIndices.contains(currentIndex) ? currentIndex : entry.sourceIndex
        onSelect?(targetIndex)
        dismiss(animated: true)
    }
}

final class NativeReaderSettingsSheet: UIViewController {
    enum Section { case theme, layout }

    private static let themeChoices = ReadingTheme.visibleThemes.map {
        (title: $0.displayName, theme: $0)
    }

    var onChange: ((ReadingSettings, ReaderNavigationMode) -> Void)?
    private var settings: ReadingSettings
    private var mode: ReaderNavigationMode
    private let section: Section
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let divider = UIView()
    private weak var themeScrollView: UIScrollView?
    private weak var fontScrollView: UIScrollView?

    private var accent: UIColor { UIColor(hex: settings.readingTheme.accentColor) }
    private var textColor: UIColor { UIColor(hex: settings.readingTheme.textColor) }
    private var panelColor: UIColor { UIColor(hex: settings.readingTheme.controlSurfaceColor) }
    private var sheetColor: UIColor { UIColor(hex: settings.readingTheme.panelColor) }
    private var dividerColor: UIColor { textColor.withAlphaComponent(0.12) }
    private var subtleTextColor: UIColor { textColor.withAlphaComponent(0.64) }

    init(settings: ReadingSettings, mode: ReaderNavigationMode, section: Section) {
        self.settings = settings
        self.mode = mode
        self.section = section
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildChrome()
        rebuildContent()
        applyThemeToSheet()
        configureSheetPresentation()
    }

    override var prefersStatusBarHidden: Bool { false }

    private func configureSheetPresentation() {
        guard #available(iOS 15.0, *), let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.preferredCornerRadius = 24
        if section == .theme {
            sheet.detents = [.medium()]
            sheet.selectedDetentIdentifier = .medium
            return
        }
        if #available(iOS 16.0, *) {
            let identifier = UISheetPresentationController.Detent.Identifier("readerLayout")
            sheet.detents = [
                .custom(identifier: identifier) { [weak self] context in
                    guard let self else { return context.maximumDetentValue * 0.62 }
                    self.view.layoutIfNeeded()
                    let contentHeight = self.stack.systemLayoutSizeFitting(
                        CGSize(width: max(self.view.bounds.width, 1), height: UIView.layoutFittingCompressedSize.height),
                        withHorizontalFittingPriority: .required,
                        verticalFittingPriority: .fittingSizeLevel
                    ).height
                    let chromeHeight: CGFloat = 84
                    let bottomInset = self.view.safeAreaInsets.bottom
                    return min(contentHeight + chromeHeight + bottomInset, context.maximumDetentValue * 0.9)
                }
            ]
            sheet.selectedDetentIdentifier = identifier
        } else {
            sheet.detents = [.medium()]
            sheet.selectedDetentIdentifier = .medium
        }
    }

    private func buildChrome() {
        titleLabel.text = section == .theme ? "主题设置" : "字体与布局"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        doneButton.setTitle("完成", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        scrollView.alwaysBounceVertical = true
        stack.axis = .vertical
        stack.spacing = 0
        scrollView.addSubview(stack)
        [titleLabel, doneButton, divider, scrollView].forEach(view.addSubview)
        [titleLabel, doneButton, divider, scrollView, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            doneButton.heightAnchor.constraint(equalToConstant: 44),
            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func rebuildContent() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        section == .theme ? buildTheme() : buildLayout()
        DispatchQueue.main.async { [weak self] in
            self?.scrollSelectedOptionIntoView()
        }
    }

    private func applyThemeToSheet() {
        view.backgroundColor = sheetColor
        titleLabel.textColor = textColor
        doneButton.tintColor = accent
        divider.backgroundColor = dividerColor
        view.tintColor = accent
    }

    private func buildTheme() {
        stack.addArrangedSubview(brightnessSection())
        stack.addArrangedSubview(themeSection())
        stack.addArrangedSubview(segmentedSection(
            title: "护眼滤镜",
            items: ["关闭", "暖黄", "薄荷"],
            selectedIndex: EyeCareFilter.allCases.firstIndex(of: settings.eyeCareFilter) ?? 0,
            action: #selector(eyeChanged(_:))
        ))
        stack.addArrangedSubview(segmentedSection(
            title: "翻页方式",
            items: ReaderNavigationMode.allCases.map(\.title),
            selectedIndex: ReaderNavigationMode.allCases.firstIndex(of: mode) ?? 1,
            action: #selector(modeChanged(_:))
        ))
    }

    private func buildLayout() {
        stack.addArrangedSubview(fontSection())
        stack.addArrangedSubview(stepperRow(
            title: "字号",
            value: Double(settings.fontSize),
            range: 12...32,
            step: 1,
            formatter: { "\(Int($0.rounded()))" },
            onChange: { [weak self] in self?.settings.fontSize = Int($0.rounded()); self?.notify() }
        ))
        stack.addArrangedSubview(stepperRow(
            title: "行距",
            value: settings.lineSpacing,
            range: 1.0...2.5,
            step: 0.1,
            formatter: { String(format: "%.1f", $0) },
            onChange: { [weak self] in self?.updateLineSpacing($0) }
        ))
        stack.addArrangedSubview(stepperRow(
            title: "段距",
            value: settings.paragraphSpacing ?? settings.lineSpacing,
            range: 1.0...3.0,
            step: 0.1,
            formatter: { String(format: "%.1f", $0) },
            onChange: { [weak self] in
                self?.settings.paragraphSpacing = $0
                self?.notify()
            }
        ))
        stack.addArrangedSubview(stepperRow(
            title: "左右边距",
            value: settings.pageMarginHorizontal,
            range: 5.0...20.0,
            step: 1,
            formatter: { "\(Int($0.rounded()))%" },
            onChange: { [weak self] in self?.settings.pageMarginHorizontal = $0; self?.notify() }
        ))
        stack.addArrangedSubview(stepperRow(
            title: "上下边距",
            value: settings.pageMarginVertical,
            range: 2.0...20.0,
            step: 1,
            formatter: { "\(Int($0.rounded()))%" },
            onChange: { [weak self] in self?.settings.pageMarginVertical = $0; self?.notify() }
        ))
    }

    private func brightnessSection() -> UIView {
        let container = sectionStack(title: "亮度")
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let minIcon = icon("sun.min")
        let maxIcon = icon("sun.max")
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = Float(settings.brightness)
        slider.minimumTrackTintColor = accent
        slider.maximumTrackTintColor = dividerColor
        slider.addTarget(self, action: #selector(brightnessChanged(_:)), for: .valueChanged)
        let value = UILabel()
        value.text = "\(Int((settings.brightness * 100).rounded()))%"
        value.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        value.textColor = subtleTextColor
        value.widthAnchor.constraint(equalToConstant: 48).isActive = true
        [minIcon, slider, maxIcon, value].forEach(row.addArrangedSubview)
        container.addArrangedSubview(row)
        return container
    }

    private func themeSection() -> UIView {
        let container = sectionStack(title: "阅读主题")
        let scroll = UIScrollView()
        themeScrollView = scroll
        scroll.showsHorizontalScrollIndicator = false
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        scroll.addSubview(row)
        [scroll, row].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        Self.themeChoices.enumerated().forEach { index, item in
            row.addArrangedSubview(themeButton(title: item.title, theme: item.theme, tag: index))
        }
        scroll.heightAnchor.constraint(equalToConstant: 84).isActive = true
        container.addArrangedSubview(scroll)
        return container
    }

    private func fontSection() -> UIView {
        let row = baseRow(height: 64)
        row.addArrangedSubview(rowLabel("字体"))
        let scroll = UIScrollView()
        fontScrollView = scroll
        scroll.showsHorizontalScrollIndicator = false
        let chips = UIStackView()
        chips.axis = .horizontal
        chips.spacing = 8
        scroll.addSubview(chips)
        [scroll, chips].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            chips.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            chips.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            chips.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            chips.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            chips.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        FontManager.shared.availableFonts.enumerated().forEach { index, fontName in
            chips.addArrangedSubview(fontChip(title: fontName, tag: index))
        }
        row.addArrangedSubview(scroll)
        return divided(row)
    }

    private func segmentedSection(title: String, items: [String], selectedIndex: Int, action: Selector) -> UIView {
        let container = sectionStack(title: title)
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selectedIndex
        control.selectedSegmentTintColor = panelColor
        control.backgroundColor = dividerColor.withAlphaComponent(0.35)
        control.setTitleTextAttributes([.foregroundColor: accent, .font: UIFont.systemFont(ofSize: 14, weight: .medium)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: textColor, .font: UIFont.systemFont(ofSize: 14)], for: .normal)
        control.addTarget(self, action: action, for: .valueChanged)
        control.heightAnchor.constraint(equalToConstant: 40).isActive = true
        container.addArrangedSubview(control)
        return container
    }

    private func stepperRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) -> UIView {
        let row = baseRow(height: 56)
        row.addArrangedSubview(rowLabel(title))
        row.addArrangedSubview(UIView())
        let stepper = NativeReaderValueStepper(
            value: value,
            range: range,
            step: step,
            formatter: formatter,
            tint: accent,
            textColor: textColor,
            borderColor: dividerColor
        )
        stepper.onChange = onChange
        row.addArrangedSubview(stepper)
        return divided(row)
    }

    private func sectionStack(title: String) -> UIStackView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12
        container.layoutMargins = UIEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
        container.isLayoutMarginsRelativeArrangement = true
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = textColor
        container.addArrangedSubview(label)
        return container
    }

    private func baseRow(height: CGFloat) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        row.isLayoutMarginsRelativeArrangement = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true
        return row
    }

    private func divided(_ content: UIView) -> UIView {
        let wrapper = UIView()
        let line = UIView()
        line.backgroundColor = dividerColor
        wrapper.addSubview(content)
        wrapper.addSubview(line)
        [content, line].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        return wrapper
    }

    private func rowLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = textColor
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        return label
    }

    private func icon(_ symbol: String) -> UIImageView {
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = subtleTextColor
        image.contentMode = .scaleAspectFit
        image.widthAnchor.constraint(equalToConstant: 24).isActive = true
        image.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return image
    }

    private func themeButton(title: String, theme: ReadingTheme, tag: Int) -> UIControl {
        let control = UIControl()
        control.tag = tag
        control.addTarget(self, action: #selector(themeSwatchTapped(_:)), for: .touchUpInside)
        control.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let swatch = UIView()
        swatch.backgroundColor = UIColor(hex: theme.backgroundColor)
        swatch.isUserInteractionEnabled = false
        swatch.layer.cornerRadius = 8
        swatch.layer.borderWidth = settings.readingTheme == theme ? 2 : 1
        swatch.layer.borderColor = (settings.readingTheme == theme ? accent : dividerColor).cgColor
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: settings.readingTheme == theme ? .semibold : .regular)
        label.textColor = settings.readingTheme == theme ? accent : textColor
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        let stack = UIStackView(arrangedSubviews: [swatch, label])
        stack.axis = .vertical
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        control.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        swatch.heightAnchor.constraint(equalToConstant: 48).isActive = true
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: control.topAnchor),
            stack.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: control.bottomAnchor)
        ])
        return control
    }

    private func fontChip(title: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = FontManager.shared.font(named: title, size: 14)
        button.setTitleColor(settings.fontFamily == title ? accent : textColor, for: .normal)
        button.backgroundColor = settings.fontFamily == title ? accent.withAlphaComponent(0.12) : panelColor
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = (settings.fontFamily == title ? accent : dividerColor).cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        button.addTarget(self, action: #selector(fontTapped(_:)), for: .touchUpInside)
        return button
    }

    private func notify() {
        ReadingSettingsRepository.shared.save(settings)
        mode.save()
        onChange?(settings, mode)
    }

    private func scrollSelectedOptionIntoView() {
        view.layoutIfNeeded()
        if let index = Self.themeChoices.firstIndex(where: { $0.theme == settings.readingTheme }),
           let scroll = themeScrollView {
            scrollOption(at: index, in: scroll)
        }
        if let index = FontManager.shared.availableFonts.firstIndex(of: settings.fontFamily),
           let scroll = fontScrollView {
            scrollOption(at: index, in: scroll)
        }
    }

    private func scrollOption(at index: Int, in scrollView: UIScrollView) {
        guard let stack = scrollView.subviews.compactMap({ $0 as? UIStackView }).first,
              stack.arrangedSubviews.indices.contains(index) else { return }
        let frame = stack.arrangedSubviews[index].convert(
            stack.arrangedSubviews[index].bounds,
            to: scrollView
        ).insetBy(dx: -12, dy: 0)
        scrollView.scrollRectToVisible(frame, animated: false)
    }

    /// 行距与段距是两个独立设置；修改行距时保留当前段距值。
    private func updateLineSpacing(_ value: Double) {
        settings.lineSpacing = min(max(value, 1), 2.5)
        notify()
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    @objc private func themeSwatchTapped(_ sender: UIControl) {
        guard Self.themeChoices.indices.contains(sender.tag) else { return }
        settings.readingTheme = Self.themeChoices[sender.tag].theme
        settings.backgroundColor = settings.readingTheme.backgroundColor
        notify()
        applyThemeToSheet()
        rebuildContent()
    }

    @objc private func fontTapped(_ sender: UIButton) {
        let fonts = FontManager.shared.availableFonts
        guard fonts.indices.contains(sender.tag) else { return }
        settings.fontFamily = fonts[sender.tag]
        notify()
        rebuildContent()
    }

    @objc private func brightnessChanged(_ sender: UISlider) {
        settings.brightness = Double(sender.value)
        notify()
        guard let row = sender.superview as? UIStackView,
              let value = row.arrangedSubviews.last as? UILabel else { return }
        value.text = "\(Int((settings.brightness * 100).rounded()))%"
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        mode = ReaderNavigationMode.allCases[sender.selectedSegmentIndex]
        notify()
    }

    @objc private func eyeChanged(_ sender: UISegmentedControl) {
        settings.eyeCareFilter = EyeCareFilter.allCases[sender.selectedSegmentIndex]
        notify()
    }
}

private final class NativeReaderValueStepper: UIView {
    var onChange: ((Double) -> Void)?
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let valueLabel = UILabel()
    private let range: ClosedRange<Double>
    private let step: Double
    private let formatter: (Double) -> String
    private var value: Double {
        didSet {
            value = min(max(value, range.lowerBound), range.upperBound)
            valueLabel.text = formatter(value)
            minus.isEnabled = value > range.lowerBound
            plus.isEnabled = value < range.upperBound
        }
    }

    init(
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String,
        tint: UIColor,
        textColor: UIColor,
        borderColor: UIColor
    ) {
        self.value = min(max(value, range.lowerBound), range.upperBound)
        self.range = range
        self.step = step
        self.formatter = formatter
        super.init(frame: .zero)
        build(tint: tint, textColor: textColor, borderColor: borderColor)
        valueLabel.text = formatter(self.value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(tint: UIColor, textColor: UIColor, borderColor: UIColor) {
        [minus, plus].forEach { button in
            button.titleLabel?.font = .systemFont(ofSize: 22, weight: .regular)
            button.tintColor = tint
            button.layer.cornerRadius = 8
            button.layer.borderWidth = 1
            button.layer.borderColor = borderColor.cgColor
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        minus.setTitle("−", for: .normal)
        plus.setTitle("+", for: .normal)
        minus.addTarget(self, action: #selector(decrease), for: .touchUpInside)
        plus.addTarget(self, action: #selector(increase), for: .touchUpInside)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        valueLabel.textColor = textColor.withAlphaComponent(0.72)
        valueLabel.textAlignment = .center
        valueLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let stack = UIStackView(arrangedSubviews: [minus, valueLabel, plus])
        stack.axis = .horizontal
        stack.alignment = .center
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

    @objc private func decrease() {
        value -= step
        onChange?(value)
    }

    @objc private func increase() {
        value += step
        onChange?(value)
    }
}
