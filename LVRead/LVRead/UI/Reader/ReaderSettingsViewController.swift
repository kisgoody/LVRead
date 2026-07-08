import UIKit

private var readerSettingsSliderValueLabelKey: UInt8 = 0

final class ReaderSettingsViewController: UIViewController {

    enum PanelMode {
        case theme
        case layout
    }

    private var settings: ReadingSettings
    private let mode: PanelMode
    var onSettingsChanged: ((ReadingSettings) -> Void)?

    // MARK: - Views
    private let dimmingView = UIView()
    private let containerView = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var containerHeightConstraint: NSLayoutConstraint?
    private weak var themeScrollView: UIScrollView?
    private weak var zodiacScrollView: UIScrollView?
    private var didPositionThemeSelection = false
    private var didPositionZodiacSelection = false
    private var didAnimateIn = false
    private var isDismissingPanel = false
    private let maxHightValue: CGFloat = 2 / 5

    init(settings: ReadingSettings, mode: PanelMode = .theme) {
        self.settings = settings
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView.backgroundColor = .clear
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        containerView.backgroundColor = panelColor
        containerView.layer.cornerRadius = 16
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.12
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOffset = CGSize(width: 0, height: -2)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

//        let initialHeight = mode == .layout ? UIScreen.main.bounds.height * maxHightValue : 220
        let initialHeight = UIScreen.main.bounds.height * maxHightValue
        let height = containerView.heightAnchor.constraint(equalToConstant: initialHeight)
        height.priority = .defaultHigh
        containerHeightConstraint = height
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            height,
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: maxHightValue),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 30),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        scrollView.scrollIndicatorInsets = scrollView.contentInset

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPanel))
        dimmingView.addGestureRecognizer(tap)

//        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
//        containerView.addGestureRecognizer(pan)

        buildSections()
        updateMenuColors()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.layoutIfNeeded()
//        updatePreferredHeight()
        view.layoutIfNeeded()
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(translationX: 0, y: max(containerView.bounds.height, 1))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.containerView.alpha = 1
            self.containerView.transform = .identity
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
//        updatePreferredHeight()
        if !didPositionThemeSelection {
            didPositionThemeSelection = true
            scrollThemeToSelection(animated: false)
        }
        if !didPositionZodiacSelection {
            didPositionZodiacSelection = true
            scrollZodiacToSelection(animated: false)
        }
    }

    @objc private func dismissPanel() {
        animateDismiss()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                containerView.transform = CGAffineTransform(translationX: 0, y: translation.y)
            }
        case .ended, .cancelled:
            if translation.y > containerView.bounds.height * 0.25 || gesture.velocity(in: view).y > 600 {
                animateDismiss()
            } else {
                UIView.animate(withDuration: 0.25) { self.containerView.transform = .identity }
            }
        default: break
        }
    }

    private func animateDismiss() {
        guard !isDismissingPanel else { return }
        isDismissingPanel = true
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.containerView.alpha = 0
            self.containerView.transform = CGAffineTransform(
                translationX: 0,
                y: max(self.containerView.bounds.height + self.view.safeAreaInsets.bottom, 1)
            )
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }

    private func buildSections() {
        switch mode {
        case .theme:
            contentStack.addArrangedSubview(makeSettingRow(title: "阅读主题", control: makeThemeGrid()))
            contentStack.addArrangedSubview(makeSettingRow(title: "护眼滤镜", control: makeEyeCareRow()))
            contentStack.addArrangedSubview(makeBrightnessRow())
            contentStack.addArrangedSubview(makeSettingRow(title: "生肖水印", control: makeZodiacPickerRow()))
            contentStack.addArrangedSubview(makeSettingRow(title: "翻页方式", control: makeFlipModeRow()))
        case .layout:
            contentStack.addArrangedSubview(makeFontFamilyRow())
            contentStack.addArrangedSubview(makeFontSizeRow())
            contentStack.addArrangedSubview(makeLineSpacingRow())
            contentStack.addArrangedSubview(makeParagraphSpacingRow())
            contentStack.addArrangedSubview(makeMarginHorizontalRow())
            contentStack.addArrangedSubview(makeMarginVerticalRow())
        }
        updatePreferredHeight()
    }

    private func updatePreferredHeight() {
        guard view.bounds.height > 0, contentStack.bounds.width > 0 else { return }
        let targetSize = CGSize(width: contentStack.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let contentHeight = contentStack.systemLayoutSizeFitting(targetSize).height
        let chromeHeight: CGFloat = 14 + 12 + view.safeAreaInsets.bottom
        let maxHeight = view.bounds.height * maxHightValue
//        let preferredHeight = mode == .layout ? maxHeight : min(max(contentHeight + chromeHeight + 20, 120), maxHeight)
        let preferredHeight = maxHeight
        if abs((containerHeightConstraint?.constant ?? 0) - preferredHeight) > 1 {
            containerHeightConstraint?.constant = preferredHeight
            scrollView.isScrollEnabled = contentHeight + chromeHeight > maxHeight
        }
    }

    private func makeLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont(name: "STKaiti", size: 12) ?? .systemFont(ofSize: 12)
        l.textColor = primaryTextColor.withAlphaComponent(0.82)
        return l
    }

    private func makeSettingRow(title: String, control: UIView) -> UIView {
        let container = UIView()
        let label = makeLabel(title)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        container.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private var accentColor: UIColor {
        UIColor(hex: settings.readingTheme.accentColor)
    }

    private var primaryTextColor: UIColor {
        UIColor(hex: settings.readingTheme.textColor)
    }

    private var secondaryTextColor: UIColor {
        primaryTextColor.withAlphaComponent(0.62)
    }

    private var panelColor: UIColor {
        UIColor(hex: settings.readingTheme.panelColor).withAlphaComponent(0.96)
    }

    private var controlSurfaceColor: UIColor {
        UIColor(hex: settings.readingTheme.controlSurfaceColor).withAlphaComponent(0.78)
    }

    private var separatorColor: UIColor {
        primaryTextColor.withAlphaComponent(0.18)
    }

    private func styleSlider(_ slider: UISlider) {
        slider.minimumTrackTintColor = accentColor
        slider.maximumTrackTintColor = separatorColor
        slider.thumbTintColor = accentColor
    }

    private func updateMenuColors() {
        containerView.backgroundColor = panelColor
        updateColors(in: contentStack)
    }

    private func updateColors(in view: UIView) {
        if let label = view as? UILabel {
            if label.accessibilityIdentifier == "themeLabel" {
                return
            }
            label.textColor = label.font.pointSize >= 14 ? secondaryTextColor : primaryTextColor.withAlphaComponent(0.82)
        } else if let button = view as? UIButton {
            if button.accessibilityIdentifier == "zodiacButton" || button.accessibilityIdentifier == "fontButton" {
                return
            }
            if let accessibilityLabel = button.accessibilityLabel,
               Self.themeChoices.contains(where: { $0.displayName == accessibilityLabel }) {
                return
            }
            button.tintColor = primaryTextColor
            if button.currentTitle != nil {
                button.setTitleColor(primaryTextColor, for: .normal)
            }
            if button.layer.borderWidth > 0 {
                button.layer.borderColor = separatorColor.cgColor
            }
        } else if let slider = view as? UISlider {
            styleSlider(slider)
        } else if let segmented = view as? UISegmentedControl {
            segmented.selectedSegmentTintColor = accentColor.withAlphaComponent(0.22)
            segmented.setTitleTextAttributes([.foregroundColor: primaryTextColor], for: .normal)
            segmented.setTitleTextAttributes([.foregroundColor: accentColor], for: .selected)
        }

        view.subviews.forEach { updateColors(in: $0) }
    }

    private func makeSliderRow(
        title: String,
        valueText: String,
        minText: String,
        maxText: String,
        range: ClosedRange<Float>,
        value: Float,
        valueWidth: CGFloat,
        action: Selector
    ) -> UIView {
        let container = UIView()
        let label = makeLabel(title)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let valueLabel = UILabel()
        valueLabel.text = valueText
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = primaryTextColor
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: valueWidth).isActive = true

        let slider = UISlider()
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = value
        styleSlider(slider)
        slider.addTarget(self, action: action, for: .valueChanged)

        let mini = UILabel()
        mini.text = minText
        mini.font = .systemFont(ofSize: 10)
        mini.textColor = secondaryTextColor

        let maxi = UILabel()
        maxi.text = maxText
        maxi.font = .systemFont(ofSize: 10)
        maxi.textColor = secondaryTextColor

        let row = UIStackView(arrangedSubviews: [label, mini, slider, maxi, valueLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        container.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 36)
        ])
        objc_setAssociatedObject(slider, &readerSettingsSliderValueLabelKey, valueLabel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return container
    }

    private func notifyChange() {
        onSettingsChanged?(settings)
    }

    // MARK: - Theme Grid

    private func makeThemeGrid() -> UIView {
        let container = UIView()
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        themeScrollView = scroll
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 14
        stack.alignment = .top

        for (index, theme) in Self.themeChoices.enumerated() {
            stack.addArrangedSubview(makeThemeItem(theme: theme, index: index))
        }

        container.addSubview(scroll)
        scroll.addSubview(stack)
        [container, scroll, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 76),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        return container
    }

    private static let themeChoices: [ReadingTheme] = [.white, .bookshelf, .warmYellow, .mint, .latte, .midnight, .oled]

    private func makeThemeItem(theme: ReadingTheme, index: Int) -> UIView {
        let item = UIStackView()
        item.axis = .vertical
        item.alignment = .center
        item.spacing = 5

        let button = UIButton(type: .system)
        button.backgroundColor = UIColor(hex: theme.backgroundColor)
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.layer.borderWidth = theme == settings.readingTheme ? 3 : 1
        button.layer.borderColor = (theme == settings.readingTheme ? accentColor : separatorColor).cgColor
        button.tag = index
        button.accessibilityLabel = theme.displayName
        button.addTarget(self, action: #selector(themeTapped(_:)), for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let label = UILabel()
        label.text = theme.displayName
        label.font = .systemFont(ofSize: 10, weight: theme == settings.readingTheme ? .semibold : .regular)
        label.textColor = theme == settings.readingTheme ? accentColor : secondaryTextColor
        label.textAlignment = .center
        label.accessibilityIdentifier = "themeLabel"

        item.addArrangedSubview(button)
        item.addArrangedSubview(label)
        item.widthAnchor.constraint(equalToConstant: 58).isActive = true
        return item
    }

    @objc private func themeTapped(_ sender: UIButton) {
        guard sender.tag < Self.themeChoices.count else { return }
        settings.readingTheme = Self.themeChoices[sender.tag]
        settings.backgroundColor = Self.themeChoices[sender.tag].backgroundColor
        containerView.backgroundColor = panelColor
        updateMenuColors()
        notifyChange()
        scrollThemeToSelection(animated: true)
        if let stack = sender.superview?.superview as? UIStackView {
            for case let item as UIStackView in stack.arrangedSubviews {
                guard let btn = item.arrangedSubviews.first as? UIButton,
                      let label = item.arrangedSubviews.last as? UILabel else { continue }
                let selected = btn == sender
                btn.layer.borderWidth = selected ? 3 : 1
                btn.layer.borderColor = (selected ? accentColor : separatorColor).cgColor
                label.textColor = selected ? accentColor : secondaryTextColor
                label.font = .systemFont(ofSize: 10, weight: selected ? .semibold : .regular)
            }
        }
    }

    private func scrollThemeToSelection(animated: Bool) {
        guard let index = Self.themeChoices.firstIndex(of: settings.readingTheme) else { return }
        scrollToItem(index: index, itemWidth: 58, spacing: 14, in: themeScrollView, animated: animated)
    }

    // MARK: - Eye Care

    private func makeEyeCareRow() -> UIView {
        let items = EyeCareFilter.allCases.map { $0.displayName }
        let seg = UISegmentedControl(items: items)
        seg.selectedSegmentIndex = EyeCareFilter.allCases.firstIndex(of: settings.eyeCareFilter) ?? 0
        seg.addTarget(self, action: #selector(eyeCareChanged(_:)), for: .valueChanged)
        let c = UIView(); c.addSubview(seg)
        [c, seg].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: c.topAnchor), seg.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            seg.trailingAnchor.constraint(equalTo: c.trailingAnchor), seg.bottomAnchor.constraint(equalTo: c.bottomAnchor),
            seg.heightAnchor.constraint(equalToConstant: 32)
        ])
        return c
    }

    @objc private func eyeCareChanged(_ seg: UISegmentedControl) {
        let all = EyeCareFilter.allCases
        guard seg.selectedSegmentIndex < all.count else { return }
        settings.eyeCareFilter = all[seg.selectedSegmentIndex]
        notifyChange()
    }

    // MARK: - Brightness

    private func makeBrightnessRow() -> UIView {
        makeSliderRow(
            title: "亮度",
            valueText: "\(Int(settings.brightness * 100))%",
            minText: "30%",
            maxText: "100%",
            range: 0.3...1.0,
            value: Float(settings.brightness),
            valueWidth: 44,
            action: #selector(brightnessChanged(_:))
        )
    }

    @objc private func brightnessChanged(_ slider: UISlider) {
        settings.brightness = Double(round(slider.value * 100) / 100)
        slider.value = Float(settings.brightness)
        if let label = objc_getAssociatedObject(slider, &readerSettingsSliderValueLabelKey) as? UILabel {
            label.text = "\(Int(settings.brightness * 100))%"
        }
        notifyChange()
    }

    // MARK: - Flip Mode (2-column grid with plain UIButton)

    private func makeFlipModeRow() -> UIView {
        let container = UIView()
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        let modes: [PageFlipMode] = [.simulation, .cover, .slide, .scroll, .none]
        let icons = ["book.pages", "rectangle.portrait.on.rectangle.portrait", "arrow.left.and.right", "arrow.up.and.down", "rectangle.portrait"]
        let names = modes.map { $0.displayName }

        for index in modes.indices {
            stack.addArrangedSubview(makeFlipButton(mode: modes[index], icon: icons[index], name: names[index]))
        }

        container.addSubview(scroll)
        scroll.addSubview(stack)
        [container, scroll, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 42),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 3),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -3),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -6)
        ])
        return container
    }

    private func makeFlipButton(mode: PageFlipMode, icon: String, name: String) -> UIButton {
        let isSelected = mode == settings.pageFlipMode
        let b = UIButton(type: .system)
        b.setTitle("  \(name)", for: .normal)
        b.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)), for: .normal)
        b.tintColor = isSelected ? accentColor : primaryTextColor
        b.setTitleColor(isSelected ? accentColor : primaryTextColor, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 11)
        b.backgroundColor = isSelected ? accentColor.withAlphaComponent(0.14) : controlSurfaceColor
        b.layer.cornerRadius = 8
        b.layer.borderWidth = isSelected ? 1.5 : 0.5
        b.layer.borderColor = isSelected ? accentColor.cgColor : separatorColor.cgColor
        b.tag = mode.hashValue
        b.addTarget(self, action: #selector(flipModeTapped(_:)), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 92).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }

    @objc private func flipModeTapped(_ sender: UIButton) {
        let modes: [PageFlipMode] = [.simulation, .cover, .slide, .scroll, .none]
        guard let mode = modes.first(where: { $0.hashValue == sender.tag }) else { return }
        settings.pageFlipMode = mode
        notifyChange()
        // Update all buttons
        if let stack = sender.superview as? UIStackView {
            for v in stack.arrangedSubviews {
                guard let btn = v as? UIButton else { continue }
                let sel = modes.contains(where: { $0.hashValue == btn.tag && $0 == mode })
                btn.tintColor = sel ? accentColor : primaryTextColor
                btn.setTitleColor(sel ? accentColor : primaryTextColor, for: .normal)
                btn.backgroundColor = sel ? accentColor.withAlphaComponent(0.14) : controlSurfaceColor
                btn.layer.borderWidth = sel ? 1.5 : 0.5
                btn.layer.borderColor = sel ? accentColor.cgColor : separatorColor.cgColor
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("pageFlipModeChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
    }

    // MARK: - Font Size

    private func makeFontSizeRow() -> UIView {
        makeSliderRow(
            title: "字号",
            valueText: "\(settings.fontSize)",
            minText: "12",
            maxText: "28",
            range: 12...28,
            value: Float(settings.fontSize),
            valueWidth: 32,
            action: #selector(fontSizeChanged(_:))
        )
    }

    @objc private func fontSizeChanged(_ slider: UISlider) {
        settings.fontSize = Int(round(slider.value))
        slider.value = Float(settings.fontSize)
        if let label = objc_getAssociatedObject(slider, &readerSettingsSliderValueLabelKey) as? UILabel {
            label.text = "\(settings.fontSize)"
        }
        notifyChange()
    }

    // MARK: - Font Family

    private func makeFontFamilyRow() -> UIView {
        let container = UIView()
        let label = makeLabel("字体")
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let fonts = FontManager.shared.availableFonts
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        for (index, font) in fonts.enumerated() {
            let button = makeFontButton(title: font, index: index)
            stack.addArrangedSubview(button)
        }

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(stack)
        let row = UIStackView(arrangedSubviews: [label, scroll])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        container.addSubview(row)
        [container, row, label, scroll, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        return container
    }

    private func makeFontButton(title: String, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index
        button.accessibilityIdentifier = "fontButton"
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
        button.addTarget(self, action: #selector(fontButtonTapped(_:)), for: .touchUpInside)
        updateFontButton(button, selected: title == settings.fontFamily)
        return button
    }

    private func updateFontButton(_ button: UIButton, selected: Bool) {
        button.backgroundColor = selected ? accentColor.withAlphaComponent(0.16) : UIColor.white.withAlphaComponent(0.08)
        button.layer.borderColor = (selected ? accentColor : UIColor(hex: settings.readingTheme.textColor).withAlphaComponent(0.16)).cgColor
        button.setTitleColor(selected ? accentColor : primaryTextColor, for: .normal)
    }

    @objc private func fontButtonTapped(_ button: UIButton) {
        let fonts = FontManager.shared.availableFonts
        guard button.tag < fonts.count else { return }
        settings.fontFamily = fonts[button.tag]
        if let stack = button.superview as? UIStackView {
            for case let fontButton as UIButton in stack.arrangedSubviews {
                updateFontButton(fontButton, selected: fontButton.tag == button.tag)
            }
        }
        notifyChange()
    }

    // MARK: - Line Spacing

    private func makeLineSpacingRow() -> UIView {
        makeSliderRow(
            title: "行间距",
            valueText: String(format: "%.1f", settings.lineSpacing),
            minText: "1.0",
            maxText: "3.0",
            range: 1.0...3.0,
            value: Float(settings.lineSpacing),
            valueWidth: 36,
            action: #selector(lineSpacingChanged(_:))
        )
    }

    @objc private func lineSpacingChanged(_ slider: UISlider) {
        settings.lineSpacing = Double(round(slider.value * 10) / 10)
        slider.value = Float(settings.lineSpacing)
        if let label = objc_getAssociatedObject(slider, &readerSettingsSliderValueLabelKey) as? UILabel {
            label.text = String(format: "%.1f", settings.lineSpacing)
        }
        notifyChange()
    }

    // MARK: - Paragraph Spacing

    private func makeParagraphSpacingRow() -> UIView {
        makeSliderRow(
            title: "段间距",
            valueText: String(format: "%.1f", settings.paragraphSpacing),
            minText: "0.5",
            maxText: "3.0",
            range: 0.5...3.0,
            value: Float(settings.paragraphSpacing),
            valueWidth: 36,
            action: #selector(paragraphSpacingChanged(_:))
        )
    }

    @objc private func paragraphSpacingChanged(_ slider: UISlider) {
        settings.paragraphSpacing = Double(round(slider.value * 10) / 10)
        slider.value = Float(settings.paragraphSpacing)
        if let label = objc_getAssociatedObject(slider, &readerSettingsSliderValueLabelKey) as? UILabel {
            label.text = String(format: "%.1f", settings.paragraphSpacing)
        }
        notifyChange()
    }

    // MARK: - Horizontal Margin

    private func makeMarginHorizontalRow() -> UIView {
        makeSliderRow(
            title: "左右边距",
            valueText: "\(Int(settings.pageMarginHorizontal))%",
            minText: "5%",
            maxText: "20%",
            range: 5...20,
            value: Float(settings.pageMarginHorizontal),
            valueWidth: 40,
            action: #selector(marginHorizontalChanged(_:))
        )
    }

    @objc private func marginHorizontalChanged(_ slider: UISlider) {
        settings.pageMarginHorizontal = Double(round(slider.value))
        slider.value = Float(settings.pageMarginHorizontal)
        if let label = objc_getAssociatedObject(slider, &readerSettingsSliderValueLabelKey) as? UILabel {
            label.text = "\(Int(settings.pageMarginHorizontal))%"
        }
        notifyChange()
    }

    // MARK: - Vertical Margin

    private func makeMarginVerticalRow() -> UIView {
        makeSliderRow(
            title: "上下边距",
            valueText: "\(Int(settings.pageMarginVertical))%",
            minText: "2%",
            maxText: "15%",
            range: 2...15,
            value: Float(settings.pageMarginVertical),
            valueWidth: 40,
            action: #selector(marginVerticalChanged(_:))
        )
    }

    @objc private func marginVerticalChanged(_ slider: UISlider) {
        settings.pageMarginVertical = Double(round(slider.value))
        slider.value = Float(settings.pageMarginVertical)
        if let label = objc_getAssociatedObject(slider, &readerSettingsSliderValueLabelKey) as? UILabel {
            label.text = "\(Int(settings.pageMarginVertical))%"
        }
        notifyChange()
    }

    // MARK: - Zodiac Watermark

    private func makeZodiacPickerRow() -> UIView {
        let container = UIView()
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        zodiacScrollView = scroll
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let allAnimals = ZodiacAnimal.allCases
        for animal in allAnimals {
            let btn = UIButton(type: .system)
            btn.tag = allAnimals.firstIndex(of: animal) ?? 0
            btn.accessibilityIdentifier = "zodiacButton"
            btn.accessibilityLabel = animal.chineseName

            // Show zodiac image as button content
            if let img = animal.loadImageCompat() {
                btn.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            } else {
                btn.setTitle(animal.chineseName, for: .normal)
                btn.setTitleColor(primaryTextColor, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 13)
            }
            btn.imageView?.contentMode = .scaleAspectFit
            btn.imageEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            btn.clipsToBounds = true
            btn.layer.masksToBounds = true
            btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 44).isActive = true

            // Highlight selected
            if animal == settings.zodiacWatermark {
                btn.layer.borderWidth = 2.5
                btn.layer.borderColor = accentColor.cgColor
                btn.layer.cornerRadius = 8
                btn.backgroundColor = accentColor.withAlphaComponent(0.12)
            } else {
                btn.layer.borderWidth = 0.5
                btn.layer.borderColor = separatorColor.cgColor
                btn.layer.cornerRadius = 8
                btn.backgroundColor = controlSurfaceColor
            }

            btn.addTarget(self, action: #selector(zodiacTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 56),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.heightAnchor, constant: -8)
        ])

        return container
    }

    @objc private func zodiacTapped(_ sender: UIButton) {
        let allAnimals = ZodiacAnimal.allCases
        guard sender.tag < allAnimals.count else { return }
        let selected = allAnimals[sender.tag]
        settings.zodiacWatermark = selected
        notifyChange()
        scrollZodiacToSelection(animated: true)

        // Update all buttons
        if let stack = sender.superview as? UIStackView {
            for v in stack.arrangedSubviews {
                guard let btn = v as? UIButton else { continue }
                let sel = btn.tag == sender.tag
                btn.layer.borderWidth = sel ? 2.5 : 0.5
                btn.layer.borderColor = sel ? accentColor.cgColor : separatorColor.cgColor
                btn.backgroundColor = sel ? accentColor.withAlphaComponent(0.12) : controlSurfaceColor
            }
        }

        // Post notification so book cover cells refresh
        NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
    }

    private func scrollZodiacToSelection(animated: Bool) {
        let selected = settings.zodiacWatermark ?? ZodiacAnimal.currentYearZodiac()
        guard let index = ZodiacAnimal.allCases.firstIndex(of: selected) else { return }
        scrollToItem(index: index, itemWidth: 44, spacing: 10, in: zodiacScrollView, animated: animated)
    }

    private func scrollToItem(index: Int, itemWidth: CGFloat, spacing: CGFloat, in scrollView: UIScrollView?, animated: Bool) {
        guard let scrollView, scrollView.bounds.width > 0 else { return }
        let centerX = CGFloat(index) * (itemWidth + spacing) + itemWidth / 2
        let targetX = centerX - scrollView.bounds.width / 2
        let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        scrollView.setContentOffset(CGPoint(x: min(max(targetX, 0), maxX), y: 0), animated: animated)
    }

}
