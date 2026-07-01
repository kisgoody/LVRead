import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


final class BookListCell: UITableViewCell {
    static let reuseIdentifier = "BookListCell"

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressBar = UIProgressView()
    private let sourceBadge = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        accessoryType = .disclosureIndicator
        selectionStyle = .none


        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 4
        coverImageView.backgroundColor = UIColor(white: 0.95, alpha: 1)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .lvTextPrimary

        authorLabel.font = .systemFont(ofSize: 13)
        authorLabel.textColor = .lvTextSecondary

        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = .lvTextTertiary

        progressBar.trackTintColor = UIColor(white: 0.9, alpha: 1)
        progressBar.progressTintColor = .lvPrimary

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .lvTextTertiary


        [coverImageView, titleLabel, authorLabel, progressLabel, progressBar, sourceBadge, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            coverImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 56),
            coverImageView.heightAnchor.constraint(equalToConstant: 75),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            authorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            sourceBadge.centerYAnchor.constraint(equalTo: authorLabel.centerYAnchor),
            sourceBadge.leadingAnchor.constraint(equalTo: authorLabel.trailingAnchor, constant: 8),
            sourceBadge.heightAnchor.constraint(equalToConstant: 16),

            progressBar.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.widthAnchor.constraint(equalToConstant: 80),
            progressBar.heightAnchor.constraint(equalToConstant: 3),

            progressLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            progressLabel.leadingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: 8),

            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

        ])
    }

    func configure(with book: Book) {
        titleLabel.text = book.title
        authorLabel.text = book.author
        progressBar.progress = Float(book.readingProgress.progressPercent / 100.0)
        progressLabel.text = book.progressPercentDisplay
        detailLabel.text = book.fileSizeDisplay
        sourceBadge.text = book.source.displayName
        sourceBadge.textColor = UIColor(hex: book.source.displayColor)

        // Zodiac watermark badge on cover
        let settings = ReadingSettingsRepository.shared.load()
        let zodiacOverlay: UIImageView? = {
            guard let zodiac = settings.zodiacWatermark,
                  let img = zodiac.loadImageCompat() else { return nil }
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFit
            iv.alpha = 0.75
            iv.translatesAutoresizingMaskIntoConstraints = false
            return iv
        }()

        coverImageView.subviews.forEach { if $0.tag == 999 { $0.removeFromSuperview() } }
        if let overlay = zodiacOverlay {
            overlay.tag = 999
            coverImageView.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -2),
                overlay.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -2),
                overlay.widthAnchor.constraint(equalToConstant: 20),
                overlay.heightAnchor.constraint(equalToConstant: 20)
            ])
        }

        if let coverPath = book.resolvedCoverPath() {
            if let cached = ImageCacheManager.shared.getImage(forKey: coverPath) {
                coverImageView.image = cached
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
            coverImageView.backgroundColor = UIColor(hex: book.source.displayColor).withAlphaComponent(0.2)
        }
    }
}
