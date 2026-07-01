import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
    func fillSuperview(padding: UIEdgeInsets = .zero) {
        guard let superview = superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        topAnchor.constraint(equalTo: superview.topAnchor, constant: padding.top).isActive = true
        leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: padding.left).isActive = true
        bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -padding.bottom).isActive = true
        trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -padding.right).isActive = true
    }
    func centerInSuperview(size: CGSize = .zero) {
        guard let superview = superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        centerXAnchor.constraint(equalTo: superview.centerXAnchor).isActive = true
        centerYAnchor.constraint(equalTo: superview.centerYAnchor).isActive = true
        if size.width > 0 { widthAnchor.constraint(equalToConstant: size.width).isActive = true }
        if size.height > 0 { heightAnchor.constraint(equalToConstant: size.height).isActive = true }
    }
}


final class TransferProgressViewController: UIViewController {
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let progressView = UIProgressView()
    private let percentLabel = UILabel()
    private let speedLabel = UILabel()
    private let cancelButton = LVButton(title: "取消传输", style: .outline)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        let container = UIView()
        container.backgroundColor = .white
        container.layer.cornerRadius = 16

        iconLabel.text = "📤"
        iconLabel.font = .systemFont(ofSize: 48)
        iconLabel.textAlignment = .center

        titleLabel.text = "正在传输..."
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .lvTextPrimary
        titleLabel.textAlignment = .center

        progressView.progressTintColor = .lvPrimary
        progressView.trackTintColor = UIColor(white: 0.9, alpha: 1)
        progressView.progress = 0

        percentLabel.text = "0%"
        percentLabel.font = .systemFont(ofSize: 36, weight: .bold)
        percentLabel.textColor = .lvPrimary
        percentLabel.textAlignment = .center

        speedLabel.text = "准备中..."
        speedLabel.font = .systemFont(ofSize: 13)
        speedLabel.textColor = .lvTextSecondary
        speedLabel.textAlignment = .center

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        container.addSubviews(iconLabel, titleLabel, progressView, percentLabel, speedLabel, cancelButton)
        view.addSubview(container)

        [container, iconLabel, titleLabel, progressView, percentLabel, speedLabel, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        container.centerInSuperview(size: CGSize(width: 280, height: 320))
        NSLayoutConstraint.activate([

            iconLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            iconLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            progressView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            percentLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            percentLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            speedLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 4),
            speedLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            cancelButton.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 20),
            cancelButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 140)
        ])

        TransferManager.shared.delegate = self
    }

    func updateProgress(_ progress: Double, transferred: Int64, total: Int64, speed: Int64) {
        progressView.progress = Float(progress)
        percentLabel.text = "\(Int(progress * 100))%"
        speedLabel.text = "\(ByteCountFormatter.string(fromByteCount: speed, countStyle: .file))/s"
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

extension TransferProgressViewController: TransferManagerDelegate {
    func transferManager(_ manager: TransferManager, didUpdateProgress task: TransferTask) {
        DispatchQueue.main.async { [weak self] in
            self?.updateProgress(task.progress, transferred: task.transferredBytes, total: task.totalBytes, speed: 0)
        }
    }

    func transferManager(_ manager: TransferManager, didComplete task: TransferTask) {
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(animated: true) {
                LVToast.show(message: "传输完成!", style: .success)
                NotificationCenter.default.post(name: .bookImported, object: nil)
            }
        }
    }

    func transferManager(_ manager: TransferManager, didFail task: TransferTask, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(animated: true) {
                LVToast.show(message: error.localizedDescription, style: .error)
            }
        }
    }
}
