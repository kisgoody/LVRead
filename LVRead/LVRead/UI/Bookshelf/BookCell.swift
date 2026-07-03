import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


final class BookCell: UICollectionViewCell {
    static let reuseIdentifier = "BookCell"

    private let containerView = UIView()
    private let coverImageView = UIImageView()
    private let coverSpineView = UIView()
    private let coverTitleLabel = UILabel()
    private let coverMarkView = UIView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let progressBar = UIProgressView()
    private let progressLabel = UILabel()
    private let sourceBadge = PaddedLabel()
    private let formatBadge = PaddedLabel()
    private let shadowView = UIView()
    private let zodiacBadge = UIImageView()
    private var representedBookId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        // Shadow container (separate from contentView for better shadow rendering)
        shadowView.backgroundColor = UIColor(hex: "#FFFDF8").withAlphaComponent(0.92)
        shadowView.layer.cornerRadius = 8
        shadowView.layer.shadowColor = UIColor(hex: "#2A221A").cgColor
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 10)
        shadowView.layer.shadowRadius = 24
        shadowView.layer.shadowOpacity = 0.06
        contentView.addSubview(shadowView)
        
        // Main container
        containerView.backgroundColor = UIColor(hex: "#FFFDF8").withAlphaComponent(0.92)
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor(hex: "#E3DBCF").cgColor
        containerView.clipsToBounds = true
        contentView.addSubview(containerView)

        // Cover image
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 6
        coverImageView.backgroundColor = UIColor(hex: "#236D67")

        coverSpineView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        coverTitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        coverTitleLabel.textColor = .white
        coverTitleLabel.numberOfLines = 3
        coverMarkView.backgroundColor = UIColor.white.withAlphaComponent(0.72)
        coverMarkView.layer.cornerRadius = 2

        // Title
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        // Author
        authorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        authorLabel.textColor = UIColor.white.withAlphaComponent(0.76)
        authorLabel.numberOfLines = 1

        // Progress bar
        progressBar.trackTintColor = UIColor(hex: "#E3DBCF")
        progressBar.progressTintColor = UIColor(hex: "#236D67")
        progressBar.layer.cornerRadius = 2
        progressBar.clipsToBounds = true

        // Progress label
        progressLabel.font = .systemFont(ofSize: 10, weight: .medium)
        progressLabel.textColor = UIColor(hex: "#7C746B")

        // Source badge
        sourceBadge.font = .systemFont(ofSize: 9, weight: .bold)
        sourceBadge.textColor = UIColor(hex: "#7C746B")
        sourceBadge.layer.cornerRadius = 9
        sourceBadge.clipsToBounds = true
        sourceBadge.textAlignment = .center
        sourceBadge.backgroundColor = .clear

        // Format badge
        formatBadge.font = .systemFont(ofSize: 9, weight: .bold)
        formatBadge.textColor = UIColor(hex: "#7C746B")
        formatBadge.layer.cornerRadius = 9
        formatBadge.clipsToBounds = true
        formatBadge.textAlignment = .center
        formatBadge.backgroundColor = .clear

        // Add subviews
        coverImageView.addSubviews(coverSpineView, coverTitleLabel, titleLabel, authorLabel, coverMarkView)
        containerView.addSubviews(coverImageView, progressBar, progressLabel, sourceBadge, formatBadge)

        // Zodiac watermark over the whole cover (positioned in layoutSubviews)
        zodiacBadge.tag = 999
        zodiacBadge.contentMode = .scaleAspectFill
        zodiacBadge.clipsToBounds = true
        zodiacBadge.alpha = 0.32
        containerView.addSubview(zodiacBadge)

        setupConstraints()
    }

    private func setupConstraints() {
        [shadowView, containerView, coverImageView, coverSpineView, coverTitleLabel, coverMarkView, titleLabel, authorLabel, progressBar, progressLabel, sourceBadge, formatBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            // Shadow view
            shadowView.topAnchor.constraint(equalTo: contentView.topAnchor),
            shadowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Container
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Cover
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 1.35),

            coverSpineView.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
            coverSpineView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            coverSpineView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
            coverSpineView.widthAnchor.constraint(equalToConstant: 10),
            coverTitleLabel.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor, constant: 18),
            coverTitleLabel.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -10),
            coverTitleLabel.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: coverTitleLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: coverTitleLabel.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: authorLabel.topAnchor, constant: -5),
            authorLabel.leadingAnchor.constraint(equalTo: coverTitleLabel.leadingAnchor),
            authorLabel.trailingAnchor.constraint(equalTo: coverTitleLabel.trailingAnchor),
            authorLabel.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -24),
            coverMarkView.leadingAnchor.constraint(equalTo: coverTitleLabel.leadingAnchor),
            coverMarkView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -14),
            coverMarkView.widthAnchor.constraint(equalToConstant: 25),
            coverMarkView.heightAnchor.constraint(equalToConstant: 4),

            // Zodiac background fills the container

            // Progress bar
            progressBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: progressLabel.leadingAnchor, constant: -8),
            progressBar.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 10),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            // Progress label
            progressLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            progressLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            sourceBadge.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6),
            sourceBadge.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            sourceBadge.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            sourceBadge.heightAnchor.constraint(equalToConstant: 18),
            formatBadge.centerYAnchor.constraint(equalTo: sourceBadge.centerYAnchor),
            formatBadge.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            formatBadge.heightAnchor.constraint(equalToConstant: 18),
            formatBadge.leadingAnchor.constraint(greaterThanOrEqualTo: sourceBadge.trailingAnchor, constant: 6)
        ])
    }

    func configure(with book: Book) {
        representedBookId = book.id
        titleLabel.text = book.title
        coverTitleLabel.text = book.fileFormat.displayName
        authorLabel.text = book.author
        
        let progress = Float(book.readingProgress.progressPercent / 100.0)
        progressBar.progress = progress
        progressLabel.text = String(format: "%.0f%%", book.readingProgress.progressPercent)
        
        sourceBadge.text = "第\(book.readingProgress.currentChapterIndex + 1)章"
        formatBadge.text = book.fileSizeDisplay

        zodiacBadge.image = nil
        zodiacBadge.isHidden = true
        coverImageView.image = generatePlaceholderCover(for: book)
    }

    private func coverPalette(for book: Book) -> (UIColor, UIColor, UIColor) {
        let palettes: [(String, String, String)] = [
            ("#236D67", "#2D425D", "#DCEFEB"),
            ("#2D425D", "#8B6C3A", "#F2D48A"),
            ("#7B5141", "#236D67", "#F0B89B"),
            ("#33425B", "#C2933D", "#F7E5A6"),
            ("#24211D", "#7B5141", "#E3DBCF"),
            ("#365B4F", "#24211D", "#DCEFEB")
        ]
        let formatOffset = FileFormat.allCases.firstIndex(of: book.fileFormat) ?? 0
        let titleValue = book.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette = palettes[(titleValue + formatOffset) % palettes.count]
        return (UIColor(hex: palette.0), UIColor(hex: palette.1), UIColor(hex: palette.2))
    }

    private func generatePlaceholderCover(for book: Book) -> UIImage? {
        let size = CGSize(width: 120, height: 162)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let palette = coverPalette(for: book)
            let colors = [palette.0.cgColor, palette.1.cgColor]

            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            ctx.cgContext.setFillColor(palette.2.withAlphaComponent(0.2).cgColor)
            ctx.cgContext.move(to: CGPoint(x: size.width, y: 0))
            ctx.cgContext.addLine(to: CGPoint(x: size.width, y: 54))
            ctx.cgContext.addLine(to: CGPoint(x: 62, y: size.height))
            ctx.cgContext.addLine(to: CGPoint(x: 34, y: size.height))
            ctx.cgContext.closePath()
            ctx.cgContext.fillPath()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !zodiacBadge.isHidden {
            zodiacBadge.frame = coverImageView.frame
            containerView.bringSubviewToFront(sourceBadge)
            containerView.bringSubviewToFront(formatBadge)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedBookId = nil
        coverImageView.image = nil
        coverTitleLabel.text = nil
        progressBar.progress = 0
        zodiacBadge.image = nil
        zodiacBadge.isHidden = true
    }
    
    // MARK: - Selection Animation
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }
}

// MARK: - Padded Label for badges
final class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
    
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let superSize = super.sizeThatFits(size)
        return CGSize(
            width: superSize.width + textInsets.left + textInsets.right,
            height: superSize.height + textInsets.top + textInsets.bottom
        )
    }
}
