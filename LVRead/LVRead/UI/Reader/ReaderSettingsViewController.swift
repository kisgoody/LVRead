import UIKit

final class ReaderSettingsViewController: UIViewController {

    private var settings: ReadingSettings
    var onSettingsChanged: ((ReadingSettings) -> Void)?

    // MARK: - Classical palette
    private enum C {
        static let ricePaper = UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1)
        static let inkText = UIColor(hex: "#3D3226")
        static let inkMuted = UIColor(hex: "#8B7355")
        static let cinnabar = UIColor(hex: "#C41E3A")
        static let trackBg = UIColor(hex: "#D4C5B2")
        static let thumbColor = UIColor(hex: "#A83A2A")
    }

    // MARK: - Views
    private let dimmingView = UIView()
    private let containerView = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    init(settings: ReadingSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        containerView.backgroundColor = C.ricePaper.withAlphaComponent(0.92)
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
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.65),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPanel))
        dimmingView.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        containerView.addGestureRecognizer(pan)

        buildSections()
    }

    @objc private func dismissPanel() {
        dismiss(animated: true)
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
                dismiss(animated: true)
            } else {
                UIView.animate(withDuration: 0.25) { self.containerView.transform = .identity }
            }
        default: break
        }
    }

    private func buildSections() {
        contentStack.addArrangedSubview(makeSectionHeader("阅读主题"))
        contentStack.addArrangedSubview(makeThemeGrid())
        contentStack.addArrangedSubview(makeSectionHeader("护眼滤镜"))
        contentStack.addArrangedSubview(makeEyeCareRow())
        contentStack.addArrangedSubview(makeSectionHeader("生肖水印"))
        contentStack.addArrangedSubview(makeZodiacPickerRow())
        contentStack.addArrangedSubview(makeSectionHeader("翻页方式"))
        contentStack.addArrangedSubview(makeFlipModeRow())
        contentStack.addArrangedSubview(makeSectionHeader("字体设置"))
        contentStack.addArrangedSubview(makeFontSizeRow())
        contentStack.addArrangedSubview(makeFontFamilyRow())
        contentStack.addArrangedSubview(makeLineSpacingRow())
        contentStack.addArrangedSubview(makeParagraphSpacingRow())
        contentStack.addArrangedSubview(makeMarginHorizontalRow())
        contentStack.addArrangedSubview(makeMarginVerticalRow())
    }

    private func makeSectionHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont(name: "STKaiti", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        label.textColor = C.inkMuted
        return label
    }

    private func makeLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont(name: "STKaiti", size: 12) ?? .systemFont(ofSize: 12)
        l.textColor = C.inkText.withAlphaComponent(0.8)
        return l
    }

    private func styleSlider(_ slider: UISlider, tint: UIColor = C.cinnabar, thumb: UIColor = C.thumbColor) {
        slider.minimumTrackTintColor = tint
        slider.maximumTrackTintColor = C.trackBg
        slider.thumbTintColor = thumb
    }

    private func notifyChange() {
        onSettingsChanged?(settings)
    }

    // MARK: - Theme Grid

    private func makeThemeGrid() -> UIView {
        let container = UIView()
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 8
        grid.distribution = .fillEqually

        let themes: [ReadingTheme] = [.white, .warmYellow, .mint, .latte, .midnight, .oled]
        let names = themes.map { $0.displayName }

        for rowIndex in stride(from: 0, to: themes.count, by: 3) {
            let row = UIStackView()
            row.axis = .horizontal; row.spacing = 8; row.distribution = .fillEqually
            for i in rowIndex..<min(rowIndex + 3, themes.count) {
                let t = themes[i]
                let b = UIButton(type: .system)
                b.backgroundColor = UIColor(hex: t.backgroundColor)
                b.layer.cornerRadius = 12
                b.layer.borderWidth = t == settings.readingTheme ? 2.5 : 0
                b.layer.borderColor = C.cinnabar.cgColor
                b.setTitle(names[i], for: .normal)
                b.setTitleColor(UIColor(hex: t.textColor), for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 11)
                b.heightAnchor.constraint(equalToConstant: 36).isActive = true
                b.tag = themes.firstIndex(of: t) ?? 0
                b.addTarget(self, action: #selector(themeTapped(_:)), for: .touchUpInside)
                row.addArrangedSubview(b)
            }
            grid.addArrangedSubview(row)
        }

        container.addSubview(grid)
        [container, grid].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    @objc private func themeTapped(_ sender: UIButton) {
        let themes: [ReadingTheme] = [.white, .warmYellow, .mint, .latte, .midnight, .oled]
        guard sender.tag < themes.count else { return }
        settings.readingTheme = themes[sender.tag]
        settings.backgroundColor = themes[sender.tag].backgroundColor
        notifyChange()
        if let grid = sender.superview?.superview as? UIStackView {
            for row in grid.arrangedSubviews {
                if let rowStack = row as? UIStackView {
                    for v in rowStack.arrangedSubviews {
                        (v as? UIButton)?.layer.borderWidth = v == sender ? 2.5 : 0
                    }
                }
            }
        }
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

    // MARK: - Flip Mode (2-column grid with plain UIButton)

    private func makeFlipModeRow() -> UIView {
        let container = UIView()
        let grid = UIStackView()
        grid.axis = .vertical; grid.spacing = 6; grid.distribution = .fillEqually

        let modes: [PageFlipMode] = [.simulation, .cover, .slide, .scroll, .none]
        let icons = ["book.pages", "rectangle.portrait.on.rectangle.portrait", "arrow.left.and.right", "arrow.up.and.down", "rectangle.portrait"]
        let names = modes.map { $0.displayName }

        // Row 1: simulation + cover
        let row1 = UIStackView()
        row1.axis = .horizontal; row1.spacing = 6; row1.distribution = .fillEqually
        row1.addArrangedSubview(makeFlipButton(mode: modes[0], icon: icons[0], name: names[0]))
        row1.addArrangedSubview(makeFlipButton(mode: modes[1], icon: icons[1], name: names[1]))
        grid.addArrangedSubview(row1)

        // Row 2: slide + scroll
        let row2 = UIStackView()
        row2.axis = .horizontal; row2.spacing = 6; row2.distribution = .fillEqually
        row2.addArrangedSubview(makeFlipButton(mode: modes[2], icon: icons[2], name: names[2]))
        row2.addArrangedSubview(makeFlipButton(mode: modes[3], icon: icons[3], name: names[3]))
        grid.addArrangedSubview(row2)

        // Row 3: none (single)
        let row3 = UIStackView()
        row3.axis = .horizontal; row3.spacing = 6; row3.distribution = .fillEqually
        row3.addArrangedSubview(makeFlipButton(mode: modes[4], icon: icons[4], name: names[4]))
        let spacer = UIView()
        row3.addArrangedSubview(spacer)
        grid.addArrangedSubview(row3)

        container.addSubview(grid)
        [container, grid].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeFlipButton(mode: PageFlipMode, icon: String, name: String) -> UIButton {
        let isSelected = mode == settings.pageFlipMode
        let b = UIButton(type: .system)
        b.setTitle("  \(name)", for: .normal)
        b.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)), for: .normal)
        b.tintColor = isSelected ? C.cinnabar : C.inkText
        b.setTitleColor(isSelected ? C.cinnabar : C.inkText, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 11)
        b.backgroundColor = isSelected ? C.cinnabar.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.5)
        b.layer.cornerRadius = 8
        b.layer.borderWidth = isSelected ? 1.5 : 0.5
        b.layer.borderColor = isSelected ? C.cinnabar.cgColor : C.trackBg.cgColor
        b.tag = mode.hashValue
        b.addTarget(self, action: #selector(flipModeTapped(_:)), for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }

    @objc private func flipModeTapped(_ sender: UIButton) {
        let modes: [PageFlipMode] = [.simulation, .cover, .slide, .scroll, .none]
        guard let mode = modes.first(where: { $0.hashValue == sender.tag }) else { return }
        settings.pageFlipMode = mode
        notifyChange()
        // Update all buttons
        if let grid = sender.superview?.superview as? UIStackView {
            for row in grid.arrangedSubviews {
                if let rowStack = row as? UIStackView {
                    for v in rowStack.arrangedSubviews {
                        guard let btn = v as? UIButton else { continue }
                        let sel = modes.contains(where: { $0.hashValue == btn.tag && $0 == mode })
                        btn.tintColor = sel ? C.cinnabar : C.inkText
                        btn.setTitleColor(sel ? C.cinnabar : C.inkText, for: .normal)
                        btn.backgroundColor = sel ? C.cinnabar.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.5)
                        btn.layer.borderWidth = sel ? 1.5 : 0.5
                        btn.layer.borderColor = sel ? C.cinnabar.cgColor : C.trackBg.cgColor
                    }
                }
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("pageFlipModeChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
    }

    // MARK: - Font Size

    private func makeFontSizeRow() -> UIView {
        let container = UIView()
        let label = makeLabel("字号")
        let valueLabel = UILabel()
        valueLabel.text = "\(settings.fontSize)"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = C.inkText
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let slider = UISlider()
        slider.minimumValue = 12; slider.maximumValue = 28; slider.value = Float(settings.fontSize)
        styleSlider(slider)
        slider.addTarget(self, action: #selector(fontSizeChanged(_:)), for: .valueChanged)

        let mini = UILabel(); mini.text = "12"; mini.font = .systemFont(ofSize: 10); mini.textColor = C.inkMuted
        let maxi = UILabel(); maxi.text = "28"; maxi.font = .systemFont(ofSize: 10); maxi.textColor = C.inkMuted

        let row = UIStackView(arrangedSubviews: [label, mini, slider, maxi, valueLabel])
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        container.addSubview(row)
        [container, label, mini, slider, maxi, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 36)
        ])
        objc_setAssociatedObject(slider, "valueLabel", valueLabel, .OBJC_ASSOCIATION_RETAIN)
        return container
    }

    @objc private func fontSizeChanged(_ slider: UISlider) {
        settings.fontSize = Int(round(slider.value))
        slider.value = Float(settings.fontSize)
        if let label = objc_getAssociatedObject(slider, "valueLabel") as? UILabel {
            label.text = "\(settings.fontSize)"
        }
        notifyChange()
    }

    // MARK: - Font Family

    private func makeFontFamilyRow() -> UIView {
        let container = UIView()
        let label = makeLabel("字体")
        let fonts = FontManager.shared.availableFonts
        let seg = UISegmentedControl(items: fonts)
        seg.selectedSegmentIndex = fonts.firstIndex(of: settings.fontFamily) ?? 0
        seg.addTarget(self, action: #selector(fontFamilyChanged(_:)), for: .valueChanged)
        container.addSubview(label); container.addSubview(seg)
        [container, label, seg].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            seg.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            seg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            seg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            seg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            seg.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }

    @objc private func fontFamilyChanged(_ seg: UISegmentedControl) {
        let fonts = FontManager.shared.availableFonts
        guard seg.selectedSegmentIndex < fonts.count else { return }
        settings.fontFamily = fonts[seg.selectedSegmentIndex]
        notifyChange()
    }

    // MARK: - Line Spacing

    private func makeLineSpacingRow() -> UIView {
        let container = UIView()
        let label = makeLabel("行间距")
        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.1f", settings.lineSpacing)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = C.inkText
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let slider = UISlider()
        slider.minimumValue = 1.0; slider.maximumValue = 3.0; slider.value = Float(settings.lineSpacing)
        styleSlider(slider)
        slider.addTarget(self, action: #selector(lineSpacingChanged(_:)), for: .valueChanged)

        let mini = UILabel(); mini.text = "1.0"; mini.font = .systemFont(ofSize: 10); mini.textColor = C.inkMuted
        let maxi = UILabel(); maxi.text = "3.0"; maxi.font = .systemFont(ofSize: 10); maxi.textColor = C.inkMuted

        let row = UIStackView(arrangedSubviews: [label, mini, slider, maxi, valueLabel])
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        container.addSubview(row)
        [container, label, mini, slider, maxi, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 36)
        ])
        objc_setAssociatedObject(slider, "valueLabel", valueLabel, .OBJC_ASSOCIATION_RETAIN)
        return container
    }

    @objc private func lineSpacingChanged(_ slider: UISlider) {
        settings.lineSpacing = Double(round(slider.value * 10) / 10)
        slider.value = Float(settings.lineSpacing)
        if let label = objc_getAssociatedObject(slider, "valueLabel") as? UILabel {
            label.text = String(format: "%.1f", settings.lineSpacing)
        }
        notifyChange()
    }

    // MARK: - Paragraph Spacing

    private func makeParagraphSpacingRow() -> UIView {
        let container = UIView()
        let label = makeLabel("段间距")
        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.1f", settings.paragraphSpacing)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = C.inkText
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let slider = UISlider()
        slider.minimumValue = 0.5; slider.maximumValue = 3.0; slider.value = Float(settings.paragraphSpacing)
        styleSlider(slider)
        slider.addTarget(self, action: #selector(paragraphSpacingChanged(_:)), for: .valueChanged)

        let mini = UILabel(); mini.text = "0.5"; mini.font = .systemFont(ofSize: 10); mini.textColor = C.inkMuted
        let maxi = UILabel(); maxi.text = "3.0"; maxi.font = .systemFont(ofSize: 10); maxi.textColor = C.inkMuted

        let row = UIStackView(arrangedSubviews: [label, mini, slider, maxi, valueLabel])
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        container.addSubview(row)
        [container, label, mini, slider, maxi, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 36)
        ])
        objc_setAssociatedObject(slider, "valueLabel", valueLabel, .OBJC_ASSOCIATION_RETAIN)
        return container
    }

    @objc private func paragraphSpacingChanged(_ slider: UISlider) {
        settings.paragraphSpacing = Double(round(slider.value * 10) / 10)
        slider.value = Float(settings.paragraphSpacing)
        if let label = objc_getAssociatedObject(slider, "valueLabel") as? UILabel {
            label.text = String(format: "%.1f", settings.paragraphSpacing)
        }
        notifyChange()
    }

    // MARK: - Horizontal Margin

    private func makeMarginHorizontalRow() -> UIView {
        let container = UIView()
        let label = makeLabel("左右边距")
        let valueLabel = UILabel()
        valueLabel.text = "\(Int(settings.pageMarginHorizontal))%"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = C.inkText
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let slider = UISlider()
        slider.minimumValue = 5; slider.maximumValue = 20; slider.value = Float(settings.pageMarginHorizontal)
        styleSlider(slider)
        slider.addTarget(self, action: #selector(marginHorizontalChanged(_:)), for: .valueChanged)

        let mini = UILabel(); mini.text = "5%"; mini.font = .systemFont(ofSize: 10); mini.textColor = C.inkMuted
        let maxi = UILabel(); maxi.text = "20%"; maxi.font = .systemFont(ofSize: 10); maxi.textColor = C.inkMuted

        let row = UIStackView(arrangedSubviews: [label, mini, slider, maxi, valueLabel])
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        container.addSubview(row)
        [container, label, mini, slider, maxi, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 36)
        ])
        objc_setAssociatedObject(slider, "valueLabel", valueLabel, .OBJC_ASSOCIATION_RETAIN)
        return container
    }

    @objc private func marginHorizontalChanged(_ slider: UISlider) {
        settings.pageMarginHorizontal = Double(round(slider.value))
        slider.value = Float(settings.pageMarginHorizontal)
        if let label = objc_getAssociatedObject(slider, "valueLabel") as? UILabel {
            label.text = "\(Int(settings.pageMarginHorizontal))%"
        }
        notifyChange()
    }

    // MARK: - Vertical Margin

    private func makeMarginVerticalRow() -> UIView {
        let container = UIView()
        let label = makeLabel("上下边距")
        let valueLabel = UILabel()
        valueLabel.text = "\(Int(settings.pageMarginVertical))%"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = C.inkText
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let slider = UISlider()
        slider.minimumValue = 2; slider.maximumValue = 15; slider.value = Float(settings.pageMarginVertical)
        styleSlider(slider)
        slider.addTarget(self, action: #selector(marginVerticalChanged(_:)), for: .valueChanged)

        let mini = UILabel(); mini.text = "2%"; mini.font = .systemFont(ofSize: 10); mini.textColor = C.inkMuted
        let maxi = UILabel(); maxi.text = "15%"; maxi.font = .systemFont(ofSize: 10); maxi.textColor = C.inkMuted

        let row = UIStackView(arrangedSubviews: [label, mini, slider, maxi, valueLabel])
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        container.addSubview(row)
        [container, label, mini, slider, maxi, valueLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 36)
        ])
        objc_setAssociatedObject(slider, "valueLabel", valueLabel, .OBJC_ASSOCIATION_RETAIN)
        return container
    }

    @objc private func marginVerticalChanged(_ slider: UISlider) {
        settings.pageMarginVertical = Double(round(slider.value))
        slider.value = Float(settings.pageMarginVertical)
        if let label = objc_getAssociatedObject(slider, "valueLabel") as? UILabel {
            label.text = "\(Int(settings.pageMarginVertical))%"
        }
        notifyChange()
    }

    // MARK: - Zodiac Watermark

    private func makeZodiacPickerRow() -> UIView {
        let container = UIView()
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
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

            // Show zodiac image as button content
            if let img = animal.loadImageCompat() {
                btn.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            } else {
                btn.setTitle(animal.chineseName, for: .normal)
                btn.setTitleColor(C.inkText, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 13)
            }
            btn.imageView?.contentMode = .scaleAspectFit
            btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 44).isActive = true

            // Highlight selected
            if animal == settings.zodiacWatermark {
                btn.layer.borderWidth = 2.5
                btn.layer.borderColor = C.cinnabar.cgColor
                btn.layer.cornerRadius = 8
                btn.backgroundColor = C.cinnabar.withAlphaComponent(0.1)
            } else {
                btn.layer.borderWidth = 0.5
                btn.layer.borderColor = C.trackBg.cgColor
                btn.layer.cornerRadius = 8
                btn.backgroundColor = UIColor.white.withAlphaComponent(0.5)
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

        // Update all buttons
        if let stack = sender.superview as? UIStackView {
            for v in stack.arrangedSubviews {
                guard let btn = v as? UIButton else { continue }
                let sel = btn.tag == sender.tag
                btn.layer.borderWidth = sel ? 2.5 : 0.5
                btn.layer.borderColor = sel ? C.cinnabar.cgColor : C.trackBg.cgColor
                btn.backgroundColor = sel ? C.cinnabar.withAlphaComponent(0.1) : UIColor.white.withAlphaComponent(0.5)
            }
        }

        // Post notification so book cover cells refresh
        NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
    }

}
