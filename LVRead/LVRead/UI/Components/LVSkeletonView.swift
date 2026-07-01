import UIKit

final class LVSkeletonView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    convenience init() {
        self.init(frame: .zero)
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.9, alpha: 0.5)
        layer.cornerRadius = 4
        clipsToBounds = true

        gradientLayer.colors = [
            UIColor(white: 0.85, alpha: 0.5).cgColor,
            UIColor(white: 0.95, alpha: 0.5).cgColor,
            UIColor(white: 0.85, alpha: 0.5).cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradientLayer)

        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = -bounds.width
        anim.toValue = bounds.width
        anim.duration = 1.5
        anim.repeatCount = .infinity
        gradientLayer.add(anim, forKey: "skeleton")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

final class LVSkeletonCell: UIView {
    private let coverSkeleton = LVSkeletonView()
    private let titleSkeleton = LVSkeletonView()
    private let authorSkeleton = LVSkeletonView()
    private let progressSkeleton = LVSkeletonView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        [coverSkeleton, titleSkeleton, authorSkeleton, progressSkeleton].forEach {
            addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            coverSkeleton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            coverSkeleton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            coverSkeleton.widthAnchor.constraint(equalToConstant: 90),
            coverSkeleton.heightAnchor.constraint(equalToConstant: 120),

            titleSkeleton.topAnchor.constraint(equalTo: coverSkeleton.bottomAnchor, constant: 8),
            titleSkeleton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleSkeleton.widthAnchor.constraint(equalToConstant: 80),
            titleSkeleton.heightAnchor.constraint(equalToConstant: 16),

            authorSkeleton.topAnchor.constraint(equalTo: titleSkeleton.bottomAnchor, constant: 4),
            authorSkeleton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            authorSkeleton.widthAnchor.constraint(equalToConstant: 60),
            authorSkeleton.heightAnchor.constraint(equalToConstant: 12),

            progressSkeleton.topAnchor.constraint(equalTo: authorSkeleton.bottomAnchor, constant: 6),
            progressSkeleton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            progressSkeleton.widthAnchor.constraint(equalToConstant: 90),
            progressSkeleton.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}
