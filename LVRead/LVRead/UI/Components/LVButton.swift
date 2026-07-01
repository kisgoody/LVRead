import UIKit

final class LVButton: UIButton {
    enum Style {
        case primary, secondary, outline, ghost, danger
        
        var backgroundColor: UIColor {
            switch self {
            case .primary: return .lvPrimary
            case .secondary: return .lvSecondary
            case .outline, .ghost: return .clear
            case .danger: return .lvError
            }
        }
        
        var titleColor: UIColor {
            switch self {
            case .primary, .secondary, .danger: return .white
            case .outline, .ghost: return .lvPrimary
            }
        }
        
        var borderColor: UIColor? {
            switch self {
            case .outline: return .lvPrimary
            default: return nil
            }
        }
    }

    enum Size {
        case small, medium, large
        
        var height: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 44
            case .large: return 52
            }
        }
        
        var font: UIFont {
            switch self {
            case .small: return .systemFont(ofSize: 13, weight: .semibold)
            case .medium: return .systemFont(ofSize: 15, weight: .semibold)
            case .large: return .systemFont(ofSize: 17, weight: .semibold)
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 10
            case .large: return 12
            }
        }
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 20
            case .large: return 24
            }
        }
    }

    var lvStyle: Style = .primary {
        didSet { applyStyle() }
    }
    
    var lvSize: Size = .medium {
        didSet { applyStyle() }
    }

    private var activityIndicator: UIActivityIndicatorView?

    init(title: String, style: Style = .primary, size: Size = .medium) {
        super.init(frame: .zero)
        self.lvStyle = style
        self.lvSize = size
        setTitle(title, for: .normal)
        setupButton()
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupButton() {
        contentEdgeInsets = UIEdgeInsets(top: 0, left: lvSize.horizontalPadding, bottom: 0, right: lvSize.horizontalPadding)
        titleLabel?.font = lvSize.font
        
        // Add shadow for primary buttons
        layer.shadowColor = UIColor.lvPrimary.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
    }

    private func applyStyle() {
        layer.cornerRadius = lvSize.cornerRadius
        backgroundColor = lvStyle.backgroundColor
        setTitleColor(lvStyle.titleColor, for: .normal)
        setTitleColor(lvStyle.titleColor.withAlphaComponent(0.6), for: .highlighted)
        setTitleColor(lvStyle.titleColor.withAlphaComponent(0.4), for: .disabled)
        
        if let borderColor = lvStyle.borderColor {
            layer.borderWidth = 1.5
            layer.borderColor = borderColor.cgColor
            layer.shadowOpacity = 0
        } else if lvStyle == .primary || lvStyle == .secondary || lvStyle == .danger {
            layer.shadowColor = lvStyle.backgroundColor.cgColor
            layer.shadowOpacity = 0.3
        } else {
            layer.shadowOpacity = 0
        }
        
        contentEdgeInsets = UIEdgeInsets(top: 0, left: lvSize.horizontalPadding, bottom: 0, right: lvSize.horizontalPadding)
        titleLabel?.font = lvSize.font
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
                self.alpha = self.isHighlighted ? 0.9 : 1.0
            }
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1.0 : 0.5
        }
    }
    
    // MARK: - Loading State
    
    func setLoading(_ loading: Bool) {
        isUserInteractionEnabled = !loading
        titleLabel?.alpha = loading ? 0 : 1
        
        if loading {
            if activityIndicator == nil {
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.color = lvStyle.titleColor
                indicator.hidesWhenStopped = true
                addSubview(indicator)
                indicator.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                    indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
                activityIndicator = indicator
            }
            activityIndicator?.startAnimating()
        } else {
            activityIndicator?.stopAnimating()
        }
    }
}

// MARK: - Convenience Initializers
extension LVButton {
    static func primary(_ title: String, size: Size = .medium) -> LVButton {
        return LVButton(title: title, style: .primary, size: size)
    }
    
    static func secondary(_ title: String, size: Size = .medium) -> LVButton {
        return LVButton(title: title, style: .secondary, size: size)
    }
    
    static func outline(_ title: String, size: Size = .medium) -> LVButton {
        return LVButton(title: title, style: .outline, size: size)
    }
    
    static func ghost(_ title: String, size: Size = .medium) -> LVButton {
        return LVButton(title: title, style: .ghost, size: size)
    }
    
    static func danger(_ title: String, size: Size = .medium) -> LVButton {
        return LVButton(title: title, style: .danger, size: size)
    }
}
