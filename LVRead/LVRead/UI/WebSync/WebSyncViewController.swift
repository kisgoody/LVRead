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


final class WebSyncViewController: UIViewController {
    private let url: String

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let qrImageView = UIImageView()
    private let urlLabel = UILabel()
    private let copyButton = LVButton(title: "复制链接", style: .primary)
    private let shareButton = LVButton(title: "分享链接", style: .outline)
    private let tipLabel = UILabel()

    init(url: String) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 20

        titleLabel.text = "📱 电脑端同步阅读"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .lvTextPrimary
        titleLabel.textAlignment = .center

        // Generate QR code
        qrImageView.image = generateQRCode(from: url)
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.borderWidth = 1
        qrImageView.layer.borderColor = UIColor(white: 0.9, alpha: 1).cgColor
        qrImageView.layer.cornerRadius = 8

        urlLabel.text = url
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = .lvTextSecondary
        urlLabel.textAlignment = .center
        urlLabel.numberOfLines = 2
        urlLabel.isUserInteractionEnabled = true

        copyButton.addTarget(self, action: #selector(copyLink), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareLink), for: .touchUpInside)

        tipLabel.text = "确保电脑与手机连接同一 Wi-Fi\n在电脑浏览器中打开上述链接即可同步阅读"
        tipLabel.font = .systemFont(ofSize: 12)
        tipLabel.textColor = .lvTextTertiary
        tipLabel.textAlignment = .center
        tipLabel.numberOfLines = 0

        let buttonStack = UIStackView(arrangedSubviews: [copyButton, shareButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        containerView.addSubviews(titleLabel, qrImageView, urlLabel, buttonStack, tipLabel)
        view.addSubview(containerView)

        [containerView, titleLabel, qrImageView, urlLabel, buttonStack, tipLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        containerView.centerInSuperview(size: CGSize(width: 320, height: 480))
        NSLayoutConstraint.activate([

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            qrImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            qrImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 200),
            qrImageView.heightAnchor.constraint(equalToConstant: 200),

            urlLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 12),
            urlLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 20),
            buttonStack.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            buttonStack.widthAnchor.constraint(equalToConstant: 260),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),

            tipLabel.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 16),
            tipLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            tipLabel.widthAnchor.constraint(equalToConstant: 260),
            tipLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24)
        ])
    }

    @objc private func copyLink() {
        UIPasteboard.general.string = url
        LVToast.show(message: "链接已复制!", style: .success)
    }

    @objc private func shareLink() {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let scale = 200.0 / outputImage.extent.size.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaled = outputImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first?.location(in: view) ?? .zero
        if !containerView.frame.contains(location) {
            dismiss(animated: true)
        }
    }
}
