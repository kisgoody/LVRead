import UIKit

final class LVSlider: UIControl {
    var minimumValue: Float = 0 { didSet { updateThumbPosition() } }
    var maximumValue: Float = 1 { didSet { updateThumbPosition() } }
    var value: Float = 0.5 { didSet { updateThumbPosition() } }
    var step: Float = 0

    var valueChanged: ((Float) -> Void)?
    var valueLabel: String { String(format: "%.1f", value) }

    private let trackView = UIView()
    private let filledTrackView = UIView()
    private let thumbView = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        trackView.backgroundColor = UIColor(white: 0.85, alpha: 1)
        trackView.layer.cornerRadius = 2
        filledTrackView.backgroundColor = .lvPrimary
        filledTrackView.layer.cornerRadius = 2
        thumbView.backgroundColor = .white
        thumbView.layer.cornerRadius = 12
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 2)
        thumbView.layer.shadowRadius = 4
        thumbView.layer.shadowOpacity = 0.2

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .lvTextSecondary
        label.textAlignment = .center

        trackView.translatesAutoresizingMaskIntoConstraints = false
        filledTrackView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(trackView)
        addSubview(filledTrackView)
        addSubview(thumbView)
        addSubview(label)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        thumbView.addGestureRecognizer(pan)
        thumbView.isUserInteractionEnabled = true

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.heightAnchor.constraint(equalToConstant: 4),

            label.topAnchor.constraint(equalTo: trackView.bottomAnchor, constant: 10),
            label.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateThumbPosition()
    }

    private func updateThumbPosition() {
        guard bounds.width > 24 else { return }
        let ratio = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        let thumbX = ratio * (bounds.width - 24)
        thumbView.frame = CGRect(x: thumbX, y: bounds.midY - 12, width: 24, height: 24)
        filledTrackView.frame = CGRect(x: 0, y: bounds.midY - 2, width: thumbX + 12, height: 4)
        label.text = "\(Int(value))"
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let ratio = max(0, min(1, (location.x - 12) / (bounds.width - 24)))
        var newValue = minimumValue + Float(ratio) * (maximumValue - minimumValue)
        if step > 0 {
            newValue = round(newValue / step) * step
        }
        value = newValue
        valueChanged?(value)
        sendActions(for: .valueChanged)
    }
}
