import UIKit

/// A reusable card component with consistent styling
final class LVCard: UIView {
    enum CardStyle {
        case elevated
        case outlined
        case filled
    }
    
    private let style: CardStyle
    
    init(style: CardStyle = .elevated) {
        self.style = style
        super.init(frame: .zero)
        setupCard()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    
    private func setupCard() {
        layer.cornerRadius = 16
        
        switch style {
        case .elevated:
            backgroundColor = .lvSurface
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowRadius = 8
            layer.shadowOpacity = 0.08
            
        case .outlined:
            backgroundColor = .lvSurface
            layer.borderWidth = 1
            layer.borderColor = UIColor.lvDivider.cgColor
            
        case .filled:
            backgroundColor = .lvSurfaceSecondary
            layer.shadowOpacity = 0
        }
    }
    
    // MARK: - Tap Feedback
    
    private var tapHandler: (() -> Void)?
    
    func onTap(_ handler: @escaping () -> Void) {
        tapHandler = handler
        isUserInteractionEnabled = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }
    
    @objc private func handleTap() {
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            self.alpha = 0.9
        } completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.transform = .identity
                self.alpha = 1.0
            }
            self.tapHandler?()
        }
    }
}

/// Shared four-dimension reading overview used by Profile and Reading Statistics.
final class LVReadingOverviewMetricsView: UIView {
    private let timeLabel = UILabel()
    private let paceLabel = UILabel()
    private let pagesLabel = UILabel()
    private let wordsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildInterface()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func update(with summary: ReadingPaceSummary, animated: Bool = false) {
        let changes = { [self] in
            timeLabel.text = Self.durationText(summary.effectiveSeconds)
            paceLabel.text = summary.wordsPerMinute.map { LF("%d 字/分钟", $0) } ?? L("--")
            pagesLabel.text = LF("%d 页", summary.pages)
            wordsLabel.text = LF("%d 字", summary.words)
            accessibilityValue = [
                "\(L("有效阅读时长"))：\(timeLabel.text ?? "--")",
                "\(L("阅读节奏"))：\(paceLabel.text ?? "--")",
                "\(L("阅读页数"))：\(pagesLabel.text ?? "--")",
                "\(L("阅读字数"))：\(wordsLabel.text ?? "--")"
            ].joined(separator: "，")
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.transition(
            with: self,
            duration: 0.2,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func buildInterface() {
        let firstRow = makeRow([
            makeMetric(valueLabel: timeLabel, title: L("有效阅读时长")),
            makeMetric(valueLabel: paceLabel, title: L("阅读节奏"))
        ])
        let secondRow = makeRow([
            makeMetric(valueLabel: pagesLabel, title: L("阅读页数")),
            makeMetric(valueLabel: wordsLabel, title: L("阅读字数"))
        ])
        let stack = UIStackView(arrangedSubviews: [firstRow, secondRow])
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
        isAccessibilityElement = true
        accessibilityLabel = L("阅读概览")
    }

    private func makeRow(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        return row
    }

    private func makeMetric(valueLabel: UILabel, title: String) -> UIView {
        valueLabel.font = .systemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = LVBookshelfModuleStyle.adaptivePrimaryText
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.65
        let captionLabel = UILabel()
        captionLabel.text = title
        captionLabel.font = .systemFont(ofSize: 12)
        captionLabel.textColor = LVBookshelfModuleStyle.adaptiveSecondaryText
        captionLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 4
        let container = UIView()
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

    private static func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        return hours > 0 ? LF("%d 小时 %d 分钟", hours, minutes) : LF("%d 分钟", minutes)
    }
}

// MARK: - Loading Shimmer View
final class LVShimmerView: UIView {
    private let gradientLayer = CAGradientLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupShimmer()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    
    private func setupShimmer() {
        backgroundColor = .lvSurfaceSecondary
        layer.cornerRadius = 8
        clipsToBounds = true
        
        gradientLayer.colors = [
            UIColor.lvSurfaceSecondary.cgColor,
            UIColor.lvSurface.cgColor,
            UIColor.lvSurfaceSecondary.cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradientLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
        
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = bounds.width * 2
        animation.duration = 1.5
        animation.repeatCount = .infinity
        gradientLayer.add(animation, forKey: "shimmer")
    }
    
    func startAnimating() {
        isHidden = false
    }
    
    func stopAnimating() {
        isHidden = true
        gradientLayer.removeAllAnimations()
    }
}
