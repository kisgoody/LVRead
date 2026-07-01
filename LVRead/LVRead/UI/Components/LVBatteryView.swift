import UIKit

/// Custom skeuomorphic horizontal battery view.
/// Appearance: rounded rectangle outline with a small positive nub on the right,
/// internal fill level animated on change.
final class LVBatteryView: UIView {

    var level: Float = 0.75 {
        didSet { updateFill() }
    }

    var strokeColor: UIColor = .white {
        didSet { outlineLayer.strokeColor = strokeColor.cgColor }
    }

    var fillColor: UIColor = .white {
        didSet { fillLayer.backgroundColor = fillColor.cgColor }
    }

    private let outlineLayer = CAShapeLayer()
    private let fillLayer = CALayer()
    private let nubLayer = CAShapeLayer()
    private let capLayer = CAShapeLayer() // positive terminal cap

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        outlineLayer.fillColor = UIColor.clear.cgColor
        outlineLayer.lineWidth = 1.5
        outlineLayer.strokeColor = strokeColor.cgColor
        layer.addSublayer(outlineLayer)

        nubLayer.fillColor = UIColor.clear.cgColor
        nubLayer.lineWidth = 1.5
        nubLayer.strokeColor = strokeColor.cgColor
        layer.addSublayer(nubLayer)

        capLayer.fillColor = UIColor.clear.cgColor
        capLayer.lineWidth = 1.5
        capLayer.strokeColor = strokeColor.cgColor
        layer.addSublayer(capLayer)

        fillLayer.backgroundColor = fillColor.cgColor
        layer.addSublayer(fillLayer)

        updateFill()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let bodyW = w - 5   // reserve 5pt for the nub
        let cornerRadius: CGFloat = 3

        // Body outline
        let bodyRect = CGRect(x: 0, y: 1, width: bodyW, height: h - 2)
        let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: cornerRadius)
        outlineLayer.path = bodyPath.cgPath

        // Positive nub (right side)
        let nubH = h * 0.35
        let nubY = (h - nubH) / 2
        let nubRect = CGRect(x: bodyW, y: nubY, width: 3.5, height: nubH)
        let nubPath = UIBezierPath(roundedRect: nubRect, cornerRadius: 1)
        nubLayer.path = nubPath.cgPath

        // Positive cap (smaller rectangle at the very right)
        let capH = h * 0.20
        let capY = (h - capH) / 2
        let capRect = CGRect(x: bodyW + 1, y: capY, width: 1.5, height: capH)
        let capPath = UIBezierPath(roundedRect: capRect, cornerRadius: 0.5)
        capLayer.path = capPath.cgPath

        updateFill()
    }

    private func updateFill() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let bodyW = w - 5
        let padding: CGFloat = 3
        let fillW = (bodyW - padding * 2) * CGFloat(max(0, min(1, level)))
        let fillH = h - 2 - padding * 2
        let cornerRadius: CGFloat = 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = CGRect(x: padding, y: padding + 1, width: max(fillW, cornerRadius), height: fillH)
        fillLayer.cornerRadius = cornerRadius
        CATransaction.commit()
    }
}
