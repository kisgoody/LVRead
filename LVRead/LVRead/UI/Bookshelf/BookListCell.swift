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
    private let zodiacBadge = UIImageView()
    private var representedBookId: String?

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
            contentView.addSubview($0)
        }
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

        // Zodiac watermark over the whole cover (positioned in layoutSubviews)
        zodiacBadge.tag = 999
        zodiacBadge.contentMode = .scaleAspectFill
        zodiacBadge.clipsToBounds = true
        zodiacBadge.alpha = 0.32
        contentView.addSubview(zodiacBadge)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !zodiacBadge.isHidden {
            zodiacBadge.frame = coverImageView.frame
        }
    }

    func configure(with book: Book) {
        representedBookId = book.id
        titleLabel.text = book.title
        authorLabel.text = book.author
        progressBar.progress = Float(book.readingProgress.progressPercent / 100.0)
        progressLabel.text = book.progressPercentDisplay
        detailLabel.text = book.fileSizeDisplay
        sourceBadge.text = book.source.displayName
        sourceBadge.textColor = UIColor(hex: book.source.displayColor)

        zodiacBadge.image = nil
        zodiacBadge.isHidden = true
        coverImageView.image = nil
        coverImageView.backgroundColor = UIColor(hex: book.source.displayColor).withAlphaComponent(0.2)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedBookId = nil
        coverImageView.image = nil
        coverImageView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        progressBar.progress = 0
        zodiacBadge.image = nil
        zodiacBadge.isHidden = true
    }
}
