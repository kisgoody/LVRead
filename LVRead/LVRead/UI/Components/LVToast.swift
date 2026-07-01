import UIKit

final class LVToast {
    enum ToastStyle {
        case info, success, warning, error
        
        var backgroundColor: UIColor {
            switch self {
            case .info: return UIColor(hex: "#3B82F6")
            case .success: return UIColor(hex: "#10B981")
            case .warning: return UIColor(hex: "#F59E0B")
            case .error: return UIColor(hex: "#EF4444")
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    
    private static var currentToast: UIView?
    private static var currentIconView: UIImageView?
    private static var currentLabel: UILabel?
    
    static func show(message: String, style: ToastStyle = .info, duration: TimeInterval = 2.5) {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else { return }
        
        // Remove existing toast if any
        currentToast?.removeFromSuperview()
        
        let container = UIView()
        container.backgroundColor = style.backgroundColor
        container.layer.cornerRadius = 12
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: 4)
        container.layer.shadowRadius = 12
        container.layer.shadowOpacity = 0.15
        
        // Icon
        let iconView = UIImageView()
        iconView.image = UIImage(systemName: style.icon)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        
        // Message label
        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 2
        
        // Stack view
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        
        container.addSubview(stack)
        window.addSubview(container)
        
        // Layout
        container.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            container.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -48),
            
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        currentToast = container
        currentIconView = iconView
        currentLabel = label
        
        // Animation
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: 20).scaledBy(x: 0.9, y: 0.9)
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            container.alpha = 1
            container.transform = .identity
        }
        
        // Auto dismiss
        UIView.animate(withDuration: 0.3, delay: duration, options: .curveEaseIn) {
            container.alpha = 0
            container.transform = CGAffineTransform(translationX: 0, y: -10).scaledBy(x: 0.9, y: 0.9)
        } completion: { _ in
            container.removeFromSuperview()
            currentToast = nil
        }
    }
    
    // Convenience methods
    static func info(_ message: String, duration: TimeInterval = 2.5) {
        show(message: message, style: .info, duration: duration)
    }
    
    static func success(_ message: String, duration: TimeInterval = 2.0) {
        show(message: message, style: .success, duration: duration)
    }
    
    static func warning(_ message: String, duration: TimeInterval = 3.0) {
        show(message: message, style: .warning, duration: duration)
    }
    
    static func error(_ message: String, duration: TimeInterval = 3.5) {
        show(message: message, style: .error, duration: duration)
    }
}
