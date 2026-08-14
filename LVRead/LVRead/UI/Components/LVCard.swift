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
