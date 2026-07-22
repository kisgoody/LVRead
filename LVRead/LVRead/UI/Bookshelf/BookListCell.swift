import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


final class BookListCell: UITableViewCell {
    static let reuseIdentifier = "BookListCell"

    private let cardView = UIView()
    private let coverImageView = UIImageView()
    private let coverSpineView = UIView()
    private let coverTitleLabel = UILabel()
    private let coverMarkView = UIView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressBar = UIProgressView()
    private let sourceBadge = UILabel()
    private let detailLabel = UILabel()
    private let bookActionButton = UIButton(type: .system)
    private let zodiacBadge = UIImageView()
    private var representedBookId: String?
    private var syncConnected = false
    var onSyncTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        accessoryType = .disclosureIndicator
        accessoryType = .none
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = UIColor(hex: "#FFFDF8").withAlphaComponent(0.92)
        cardView.layer.cornerRadius = 8
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor(hex: "#E3DBCF").cgColor
        cardView.layer.shadowColor = UIColor(hex: "#2A221A").cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 10)
        cardView.layer.shadowRadius = 24
        cardView.layer.shadowOpacity = 0.06
        contentView.addSubview(cardView)

        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 6
        coverImageView.backgroundColor = UIColor(hex: "#236D67")
        coverImageView.layer.shadowColor = UIColor(hex: "#24211D").cgColor
        coverImageView.layer.shadowOffset = CGSize(width: 0, height: 10)
        coverImageView.layer.shadowRadius = 20
        coverImageView.layer.shadowOpacity = 0.18

        coverSpineView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        coverTitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        coverTitleLabel.textColor = .white
        coverTitleLabel.numberOfLines = 3
        coverMarkView.backgroundColor = UIColor.white.withAlphaComponent(0.72)
        coverMarkView.layer.cornerRadius = 2

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = UIColor(hex: "#24211D")
        titleLabel.numberOfLines = 2

        authorLabel.font = .systemFont(ofSize: 13)
        authorLabel.textColor = UIColor(hex: "#7C746B")

        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = UIColor(hex: "#7C746B")

        progressBar.trackTintColor = UIColor(white: 0.9, alpha: 1)
        progressBar.progressTintColor = UIColor(hex: "#236D67")

        sourceBadge.font = .systemFont(ofSize: 12, weight: .bold)
        sourceBadge.textAlignment = .center
        sourceBadge.layer.cornerRadius = 11.5
        sourceBadge.clipsToBounds = true
        sourceBadge.backgroundColor = UIColor(hex: "#DCEFEB")
        sourceBadge.textColor = UIColor(hex: "#236D67")

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = UIColor(hex: "#7C746B")

        bookActionButton.setImage(UIImage(systemName: "desktopcomputer"), for: .normal)
        bookActionButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium),
            forImageIn: .normal
        )
        bookActionButton.tintColor = UIColor(hex: "#24211D")
        bookActionButton.backgroundColor = .clear
        bookActionButton.accessibilityHint = "打开电脑端同步阅读"
        bookActionButton.addTarget(self, action: #selector(syncTapped), for: .touchUpInside)

        coverImageView.addSubviews(coverSpineView, coverTitleLabel, coverMarkView)
        cardView.addSubviews(coverImageView, titleLabel, authorLabel, progressLabel, progressBar, sourceBadge, detailLabel, bookActionButton)
        [cardView, coverImageView, coverSpineView, coverTitleLabel, coverMarkView, titleLabel, authorLabel, progressLabel, progressBar, sourceBadge, detailLabel, bookActionButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            coverImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 11),
            coverImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 74),
            coverImageView.heightAnchor.constraint(equalToConstant: 96),

            coverSpineView.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
            coverSpineView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            coverSpineView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
            coverSpineView.widthAnchor.constraint(equalToConstant: 9),
            coverTitleLabel.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor, constant: 16),
            coverTitleLabel.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -8),
            coverTitleLabel.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 13),
            coverMarkView.leadingAnchor.constraint(equalTo: coverTitleLabel.leadingAnchor),
            coverMarkView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -14),
            coverMarkView.widthAnchor.constraint(equalToConstant: 24),
            coverMarkView.heightAnchor.constraint(equalToConstant: 4),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: bookActionButton.leadingAnchor, constant: -12),

            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            authorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            authorLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            sourceBadge.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sourceBadge.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -15),
            sourceBadge.heightAnchor.constraint(equalToConstant: 23),
            sourceBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),

            progressBar.leadingAnchor.constraint(equalTo: sourceBadge.trailingAnchor, constant: 8),
            progressBar.centerYAnchor.constraint(equalTo: sourceBadge.centerYAnchor),
            progressBar.widthAnchor.constraint(equalToConstant: 54),
            progressBar.heightAnchor.constraint(equalToConstant: 3),

            progressLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            progressLabel.leadingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: 8),

            detailLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: progressLabel.trailingAnchor, constant: 8),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: bookActionButton.leadingAnchor, constant: -8),

            bookActionButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            bookActionButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -11),
            bookActionButton.widthAnchor.constraint(equalToConstant: 44),
            bookActionButton.heightAnchor.constraint(equalToConstant: 44),

        ])

        // Zodiac watermark over the whole cover (positioned in layoutSubviews)
        zodiacBadge.tag = 999
        zodiacBadge.contentMode = .scaleAspectFill
        zodiacBadge.clipsToBounds = true
        zodiacBadge.alpha = 0.32
        cardView.addSubview(zodiacBadge)
    }

    func applyAppearance() {
        let isDark = DarkModeManager.shared.isDarkMode
        let surface = LVBookshelfModuleStyle.cardBackground
        let text = LVBookshelfModuleStyle.primaryText
        let secondary = LVBookshelfModuleStyle.secondaryText
        let divider = LVBookshelfModuleStyle.divider
        cardView.backgroundColor = surface
        cardView.layer.borderColor = divider.cgColor
        cardView.layer.shadowColor = (isDark ? UIColor.black : UIColor(hex: "#2A221A")).cgColor
        titleLabel.textColor = text
        authorLabel.textColor = secondary
        progressLabel.textColor = secondary
        detailLabel.textColor = secondary
        sourceBadge.backgroundColor = LVBookshelfModuleStyle.accent.withAlphaComponent(0.14)
        sourceBadge.textColor = LVBookshelfModuleStyle.accent
        progressBar.trackTintColor = divider
        progressBar.progressTintColor = LVBookshelfModuleStyle.accent
        bookActionButton.tintColor = syncConnected ? LVBookshelfModuleStyle.accent : secondary.withAlphaComponent(0.62)
        bookActionButton.backgroundColor = .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !zodiacBadge.isHidden {
            zodiacBadge.frame = coverImageView.frame
        }
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
        let formatOffset: Int
        switch book.fileFormat {
        case .txt: formatOffset = 0
        case .epub: formatOffset = 1
        case .pdf: formatOffset = 2
        case .mobi: formatOffset = 3
        case .azw3: formatOffset = 4
        }
        let titleValue = book.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette = palettes[(titleValue + formatOffset) % palettes.count]
        return (UIColor(hex: palette.0), UIColor(hex: palette.1), UIColor(hex: palette.2))
    }

    private func makeCoverBackground(for book: Book) -> UIImage {
        let colors = coverPalette(for: book)
        let size = CGSize(width: 74, height: 96)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cgContext = context.cgContext
            let cgColors = [colors.0.cgColor, colors.1.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors,
                locations: [0, 1]
            ) else { return }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.1).cgColor)
            cgContext.fill(CGRect(x: 16, y: 0, width: 1, height: size.height))

            cgContext.setFillColor(colors.2.withAlphaComponent(0.22).cgColor)
            cgContext.move(to: CGPoint(x: size.width, y: 0))
            cgContext.addLine(to: CGPoint(x: size.width, y: 36))
            cgContext.addLine(to: CGPoint(x: 38, y: size.height))
            cgContext.addLine(to: CGPoint(x: 20, y: size.height))
            cgContext.closePath()
            cgContext.fillPath()

            cgContext.setStrokeColor(colors.2.withAlphaComponent(0.45).cgColor)
            cgContext.setLineWidth(1)
            cgContext.stroke(CGRect(x: 24, y: 70, width: 25, height: 1))
        }
    }

    func configure(with book: Book, syncConnected: Bool = false) {
        representedBookId = book.id
        self.syncConnected = syncConnected
        titleLabel.text = book.title
        coverTitleLabel.text = book.title
        let percent = book.readingProgress.progressPercent
        authorLabel.text = "\(book.author) · \(percent > 0 ? "已读 \(Int(percent))%" : "尚未开始")"
        progressBar.progress = Float(percent / 100.0)
        progressLabel.text = book.progressPercentDisplay
        if percent >= 100 {
            detailLabel.text = "已读完"
        } else if percent > 0 {
            detailLabel.text = "阅读中"
        } else {
            detailLabel.text = "待读"
        }
        sourceBadge.text = "  \(book.fileFormat.displayName)  "

        zodiacBadge.image = nil
        zodiacBadge.isHidden = true
        coverImageView.image = makeCoverBackground(for: book)
        coverImageView.backgroundColor = .clear
        bookActionButton.accessibilityLabel = "《\(book.title)》电脑同步，\(syncConnected ? "已连接" : "未连接")"
        applyAppearance()
    }

    @objc private func syncTapped() { onSyncTapped?() }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedBookId = nil
        syncConnected = false
        onSyncTapped = nil
        coverImageView.image = nil
        coverTitleLabel.text = nil
        coverImageView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        progressBar.progress = 0
        zodiacBadge.image = nil
        zodiacBadge.isHidden = true
    }
}
