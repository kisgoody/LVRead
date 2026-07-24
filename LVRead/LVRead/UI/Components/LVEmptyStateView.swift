import UIKit

final class LVEmptyStateView: UIView {
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = LVButton(title: "", style: .primary, size: .medium)

    var onAction: (() -> Void)?

    init(icon: String = "book.closed", title: String, subtitle: String = "", actionTitle: String = "") {
        super.init(frame: .zero)
        setupView(icon: icon, title: title, subtitle: subtitle, actionTitle: actionTitle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupView(icon: String, title: String, subtitle: String, actionTitle: String) {
        // Icon
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .light)

        // Title
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        // Subtitle
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.isHidden = subtitle.isEmpty
        applyAppearance()

        // Content stack
        let contentStack = UIStackView(arrangedSubviews: [iconImageView, titleLabel, subtitleLabel])
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .center

        addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48)
        ])

        // Icon styling
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 72),
            iconImageView.heightAnchor.constraint(equalToConstant: 72)
        ])

        // Action button
        if !actionTitle.isEmpty {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            addSubview(actionButton)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                actionButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                actionButton.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 28),
                actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
                actionButton.heightAnchor.constraint(equalToConstant: 48)
            ])
        }

        // Subtle floating animation on icon
        let floatAnimation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        floatAnimation.values = [-4, 4, -4]
        floatAnimation.keyTimes = [0, 0.5, 1]
        floatAnimation.duration = 3.0
        floatAnimation.repeatCount = .infinity
        floatAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconImageView.layer.add(floatAnimation, forKey: "gentleFloat")
    }

    @objc private func actionTapped() {
        onAction?()
    }
    
    // Update methods for dynamic content
    func updateTitle(_ title: String) {
        titleLabel.text = title
    }
    
    func updateSubtitle(_ subtitle: String) {
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
    }
    
    func updateIcon(_ systemName: String) {
        iconImageView.image = UIImage(systemName: systemName)
    }

    func applyAppearance() {
        iconImageView.tintColor = LVBookshelfModuleStyle.accent.withAlphaComponent(0.65)
        titleLabel.textColor = LVBookshelfModuleStyle.primaryText
        subtitleLabel.textColor = LVBookshelfModuleStyle.secondaryText
    }
}
