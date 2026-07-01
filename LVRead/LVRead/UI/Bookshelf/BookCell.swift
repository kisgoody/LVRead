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
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let progressBar = UIProgressView()
    private let progressLabel = UILabel()
    private let sourceBadge = PaddedLabel()
    private let formatBadge = PaddedLabel()
    private let shadowView = UIView()
    private let zodiacBadge = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        // Shadow container (separate from contentView for better shadow rendering)
        shadowView.backgroundColor = .white
        shadowView.layer.cornerRadius = 16
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 4)
        shadowView.layer.shadowRadius = 12
        shadowView.layer.shadowOpacity = 0.1
        contentView.addSubview(shadowView)
        
        // Main container
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 16
        containerView.clipsToBounds = true
        contentView.addSubview(containerView)

        // Cover image
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 10
        coverImageView.backgroundColor = .lvSurfaceSecondary

        // Title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .lvTextPrimary
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        // Author
        authorLabel.font = .systemFont(ofSize: 12)
        authorLabel.textColor = .lvTextSecondary

        // Progress bar
        progressBar.trackTintColor = UIColor(hex: "#E5E7EB")
        progressBar.progressTintColor = .lvPrimary
        progressBar.layer.cornerRadius = 2
        progressBar.clipsToBounds = true

        // Progress label
        progressLabel.font = .systemFont(ofSize: 10, weight: .medium)
        progressLabel.textColor = .lvTextTertiary

        // Source badge
        sourceBadge.font = .systemFont(ofSize: 9, weight: .bold)
        sourceBadge.textColor = .white
        sourceBadge.layer.cornerRadius = 4
        sourceBadge.clipsToBounds = true
        sourceBadge.textAlignment = .center

        // Format badge
        formatBadge.font = .systemFont(ofSize: 9, weight: .bold)
        formatBadge.textColor = .white
        formatBadge.layer.cornerRadius = 4
        formatBadge.clipsToBounds = true
        formatBadge.textAlignment = .center

        // Add subviews
        containerView.addSubviews(coverImageView, titleLabel, authorLabel, progressBar, progressLabel, sourceBadge, formatBadge)

        // Zodiac badge (positioned in layoutSubviews)
        zodiacBadge.tag = 999
        zodiacBadge.contentMode = .scaleAspectFit
        zodiacBadge.alpha = 0.75
        containerView.addSubview(zodiacBadge)

        setupConstraints()
    }

    private func setupConstraints() {
        [shadowView, containerView, coverImageView, titleLabel, authorLabel, progressBar, progressLabel, sourceBadge, formatBadge].forEach {
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


            // Zodiac background fills the container

            // Source badge (top-left of cover)
            sourceBadge.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 8),
            sourceBadge.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor, constant: 8),
            sourceBadge.heightAnchor.constraint(equalToConstant: 18),

            // Format badge (below source)
            formatBadge.topAnchor.constraint(equalTo: sourceBadge.bottomAnchor, constant: 4),
            formatBadge.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor, constant: 8),
            formatBadge.heightAnchor.constraint(equalToConstant: 18),

            // Title
            titleLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            // Author
            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            authorLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            // Progress bar
            progressBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: progressLabel.leadingAnchor, constant: -8),
            progressBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            // Progress label
            progressLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            progressLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor)
        ])
    }

    func configure(with book: Book) {
        titleLabel.text = book.title
        authorLabel.text = book.author
        
        let progress = Float(book.readingProgress.progressPercent / 100.0)
        progressBar.progress = progress
        progressLabel.text = String(format: "%.0f%%", book.readingProgress.progressPercent)
        
        sourceBadge.text = " \(book.source.displayName) "
        formatBadge.text = " \(book.fileFormat.displayName) "

        // Badge colors
        sourceBadge.backgroundColor = UIColor(hex: book.source.displayColor)
        formatBadge.backgroundColor = UIColor(hex: book.fileFormat.badgeColor)

        // Zodiac watermark badge on cover
        let settings = ReadingSettingsRepository.shared.load()
        if let zodiac = settings.zodiacWatermark,
           let img = zodiac.loadImageCompat() {
            zodiacBadge.image = img
            zodiacBadge.isHidden = false
        } else {
            zodiacBadge.isHidden = true
        }

        // Load cover
        if let coverPath = book.resolvedCoverPath() {
            if let cachedImage = ImageCacheManager.shared.getImage(forKey: coverPath) {
                coverImageView.image = cachedImage
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    if let image = UIImage(contentsOfFile: coverPath) {
                        ImageCacheManager.shared.cacheImage(image, forKey: coverPath)
                        DispatchQueue.main.async {
                            self?.coverImageView.image = image
                        }
                    }
                }
            }
        } else {
            coverImageView.image = generatePlaceholderCover(for: book)
        }
    }

    private func generatePlaceholderCover(for book: Book) -> UIImage? {
        let size = CGSize(width: 120, height: 162)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Gradient based on file format
            let colors: [CGColor]
            switch book.fileFormat {
            case .epub: colors = [UIColor.lvPrimary.cgColor, UIColor.lvPrimaryLight.cgColor]
            case .pdf: colors = [UIColor.lvSecondary.cgColor, UIColor.lvSecondaryLight.cgColor]
            case .txt: colors = [UIColor.lvAccent.cgColor, UIColor.lvAccentLight.cgColor]
            case .mobi, .azw3: colors = [UIColor.categoryNovelStart.cgColor, UIColor.categoryNovelEnd.cgColor]
            }

            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            // Draw format icon
            let iconName: String
            switch book.fileFormat {
            case .epub: iconName = "book.closed.fill"
            case .pdf: iconName = "doc.text.fill"
            case .txt: iconName = "doc.plaintext.fill"
            case .mobi, .azw3: iconName = "books.vertical.fill"
            }
            
            if let icon = UIImage(systemName: iconName)?.withTintColor(.white.withAlphaComponent(0.3), renderingMode: .alwaysOriginal) {
                let iconSize: CGFloat = 36
                icon.draw(in: CGRect(x: (size.width - iconSize) / 2, y: size.height / 2 - iconSize / 2, width: iconSize, height: iconSize))
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !zodiacBadge.isHidden {
            let s: CGFloat = 28, p: CGFloat = 4
            zodiacBadge.frame = CGRect(
                x: coverImageView.frame.maxX - s - p,
                y: coverImageView.frame.maxY - s - p,
                width: s, height: s
            )
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = nil
        progressBar.progress = 0
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
