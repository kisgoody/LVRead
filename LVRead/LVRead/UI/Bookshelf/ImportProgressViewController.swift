import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


final class ImportProgressViewController: UIViewController {

    // MARK: - UI Components

    private let containerView = UIView()
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let progressView = UIProgressView()
    private let percentLabel = UILabel()
    private let statusLabel = UILabel()
    private let fileNameLabel = UILabel()
    private let fileSizeLabel = UILabel()
    private let cancelButton = LVButton(title: "取消", style: .outline)

    // MARK: - Callbacks

    var onCancel: (() -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 16

        iconLabel.text = "📖"
        iconLabel.font = .systemFont(ofSize: 48)
        iconLabel.textAlignment = .center

        titleLabel.text = "正在导入书籍..."
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .lvTextPrimary
        titleLabel.textAlignment = .center

        progressView.progressTintColor = .lvPrimary
        progressView.trackTintColor = UIColor(white: 0.9, alpha: 1)
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true

        percentLabel.font = .systemFont(ofSize: 36, weight: .bold)
        percentLabel.textColor = .lvPrimary
        percentLabel.textAlignment = .center
        percentLabel.text = "0%"

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .lvTextSecondary
        statusLabel.textAlignment = .center
        statusLabel.text = "正在准备..."

        fileNameLabel.font = .systemFont(ofSize: 12)
        fileNameLabel.textColor = .lvTextTertiary
        fileNameLabel.textAlignment = .center

        fileSizeLabel.font = .systemFont(ofSize: 12)
        fileSizeLabel.textColor = .lvTextTertiary
        fileSizeLabel.textAlignment = .center

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        containerView.addSubviews(
            iconLabel, titleLabel, progressView, percentLabel,
            statusLabel, fileNameLabel, fileSizeLabel, cancelButton
        )
        view.addSubview(containerView)

        [containerView, iconLabel, titleLabel, progressView, percentLabel,
         statusLabel, fileNameLabel, fileSizeLabel, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),

            iconLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            iconLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            progressView.heightAnchor.constraint(equalToConstant: 8),

            percentLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            percentLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 4),
            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            fileNameLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            fileNameLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 2),
            fileSizeLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            cancelButton.topAnchor.constraint(equalTo: fileSizeLabel.bottomAnchor, constant: 20),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 120),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24)
        ])
    }

    // MARK: - Public

    func updateProgress(_ progress: Float, statusText: String) {
        progressView.progress = progress
        percentLabel.text = "\(Int(progress * 100))%"
        statusLabel.text = statusText
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onCancel?()
        dismiss(animated: true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Block tap outside to dismiss — user must use cancel button
    }
}
