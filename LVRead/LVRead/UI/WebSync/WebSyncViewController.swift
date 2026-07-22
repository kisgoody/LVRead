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
    private let book: Book
    private let page: WebSyncServer.PageSnapshot
    private var session: WebSyncServer.Session?

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let qrImageView = UIImageView()
    private let urlLabel = UILabel()
    private let installButton = LVButton(title: "首次使用：安装安全证书", style: .primary)
    private let copyButton = LVButton(title: "复制链接", style: .outline)
    private let shareButton = LVButton(title: "分享链接", style: .outline)
    private let tipLabel = UILabel()
    private let connectionButton = UIButton(type: .system)

    init(book: Book, page: WebSyncServer.PageSnapshot) {
        self.book = book
        self.page = page
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
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

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 12
        statusLabel.clipsToBounds = true

        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.borderWidth = 1
        qrImageView.layer.borderColor = UIColor(white: 0.9, alpha: 1).cgColor
        qrImageView.layer.cornerRadius = 8

        urlLabel.text = "连接成功后显示访问地址"
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = .lvTextSecondary
        urlLabel.textAlignment = .center
        urlLabel.numberOfLines = 2
        urlLabel.isUserInteractionEnabled = true

        installButton.addTarget(self, action: #selector(showCertificateGuide), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(copyLink), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareLink), for: .touchUpInside)

        tipLabel.text = "电脑与手机需连接同一 Wi-Fi，并保持 LVRead 在前台\n根证书在每台电脑上只需安装一次"
        tipLabel.font = .systemFont(ofSize: 12)
        tipLabel.textColor = .lvTextTertiary
        tipLabel.textAlignment = .center
        tipLabel.numberOfLines = 0

        connectionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        connectionButton.layer.cornerRadius = 12
        connectionButton.addTarget(self, action: #selector(connectionTapped), for: .touchUpInside)
        connectionButton.accessibilityHint = "打开或断开电脑同步服务"

        let buttonStack = UIStackView(arrangedSubviews: [copyButton, shareButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        containerView.addSubviews(
            titleLabel, statusLabel, qrImageView, urlLabel, installButton,
            buttonStack, tipLabel, connectionButton
        )
        view.addSubview(containerView)

        [containerView, titleLabel, statusLabel, qrImageView, urlLabel, installButton,
         buttonStack, tipLabel, connectionButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        containerView.centerInSuperview(size: CGSize(width: 320, height: 568))
        NSLayoutConstraint.activate([

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 96),
            statusLabel.heightAnchor.constraint(equalToConstant: 24),

            qrImageView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            qrImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 152),
            qrImageView.heightAnchor.constraint(equalToConstant: 152),

            urlLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 12),
            urlLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            installButton.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 16),
            installButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            installButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            installButton.heightAnchor.constraint(equalToConstant: 44),

            buttonStack.topAnchor.constraint(equalTo: installButton.bottomAnchor, constant: 16),
            buttonStack.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            buttonStack.widthAnchor.constraint(equalToConstant: 272),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),

            tipLabel.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 16),
            tipLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            tipLabel.widthAnchor.constraint(equalToConstant: 260),
            connectionButton.topAnchor.constraint(equalTo: tipLabel.bottomAnchor, constant: 16),
            connectionButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            connectionButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            connectionButton.heightAnchor.constraint(equalToConstant: 44),
            connectionButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionStateChanged),
            name: .webSyncConnectionStateChanged,
            object: nil
        )
        updateConnectionState()
        if WebSyncServer.shared.connectionState != .disconnected {
            startConnection()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func copyLink() {
        guard let session else { return }
        UIPasteboard.general.string = session.readingURL.absoluteString
        LVToast.show(message: "链接已复制!", style: .success)
    }

    @objc private func shareLink() {
        guard let session else { return }
        let activityVC = UIActivityViewController(
            activityItems: [session.readingURL],
            applicationActivities: nil
        )
        present(activityVC, animated: true)
    }

    @objc private func showCertificateGuide() {
        guard let session else { return }
        let guide = CertificateSetupViewController(
            certificateURL: session.rootCertificateURL,
            hostName: session.hostName
        )
        present(guide, animated: true)
    }

    @objc private func connectionTapped() {
        switch WebSyncServer.shared.connectionState {
        case .disconnected:
            startConnection()
        case .connecting, .connected:
            WebSyncServer.shared.stop()
        }
    }

    @objc private func connectionStateChanged() { updateConnectionState() }

    private func startConnection() {
        WebSyncServer.shared.start(with: book, page: page) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let session):
                self.session = session
                self.qrImageView.image = self.generateQRCode(from: session.readingURL.absoluteString)
                self.urlLabel.text = session.readingURL.absoluteString
                self.updateConnectionState()
            case .failure(let error):
                if let startError = error as? WebSyncServer.StartError,
                   case .cancelled = startError { return }
                LVToast.show(message: error.localizedDescription, style: .error)
            }
        }
    }

    private func updateConnectionState() {
        let state = WebSyncServer.shared.connectionState
        statusLabel.text = "●  \(state.title)"
        connectionButton.setTitle(
            state == .disconnected ? "打开同步" : "关闭同步",
            for: .normal
        )
        let available = state != .disconnected && session != nil
        [installButton, copyButton, shareButton].forEach { $0.isEnabled = available }
        qrImageView.alpha = available ? 1 : 0.28
        let color: UIColor
        switch state {
        case .disconnected: color = .secondaryLabel
        case .connecting: color = .systemOrange
        case .connected: color = .systemGreen
        }
        statusLabel.textColor = color
        statusLabel.backgroundColor = color.withAlphaComponent(0.12)
        connectionButton.setTitleColor(state == .connected ? .systemRed : .white, for: .normal)
        connectionButton.backgroundColor = state == .connected
            ? UIColor.systemRed.withAlphaComponent(0.12)
            : UIColor.lvPrimary
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

/// First-use guide for installing the public LVRead root certificate on a PC.
final class CertificateSetupViewController: UIViewController {
    private let certificateURL: URL
    private let hostName: String

    private let titleLabel = UILabel()
    private let systemControl = UISegmentedControl(items: ["macOS", "Windows"])
    private let instructionLabel = UILabel()
    private let shareButton = LVButton(title: "发送根证书到电脑", style: .primary)
    private let closeButton = UIButton(type: .system)

    init(certificateURL: URL, hostName: String) {
        self.certificateURL = certificateURL
        self.hostName = hostName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.text = "安装 LVRead 安全证书"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        systemControl.selectedSegmentIndex = 0
        systemControl.addTarget(self, action: #selector(systemChanged), for: .valueChanged)

        instructionLabel.font = .systemFont(ofSize: 14)
        instructionLabel.textColor = .label
        instructionLabel.numberOfLines = 0

        shareButton.addTarget(self, action: #selector(shareCertificate), for: .touchUpInside)

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel, systemControl, instructionLabel, shareButton
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 24

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        view.addSubview(closeButton)
        scrollView.addSubview(contentStack)
        [scrollView, closeButton, contentStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 48),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            shareButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        updateInstructions()
    }

    @objc private func systemChanged() {
        updateInstructions()
    }

    private func updateInstructions() {
        if systemControl.selectedSegmentIndex == 0 {
            instructionLabel.text = """
            为什么需要安装：LVRead 使用 HTTPS 保护电脑与手机之间的阅读内容。本地证书用于让浏览器确认 lvread.local 确实由你的手机提供，避免每次访问都出现“不安全”警告。证书只需在这台电脑安装一次。

            只需安装一次：

            1. 点击下方“发送根证书到电脑”，通过 AirDrop 或文件保存到 Mac。
            2. 双击 LVRead-Root-CA.cer，打开“钥匙串访问”。
            3. 将证书加入“系统”钥匙串。
            4. 双击“LVRead Local Root CA”，展开“信任”。
            5. 将“使用此证书时”设为“始终信任”，输入管理员密码。
            6. 完全退出并重新打开浏览器。
            7. 打开 https://\(hostName) 的同步链接。
            """
        } else {
            instructionLabel.text = """
            为什么需要安装：LVRead 使用 HTTPS 保护电脑与手机之间的阅读内容。本地证书用于让浏览器确认 lvread.local 确实由你的手机提供，避免每次访问都出现“不安全”警告。证书只需在这台电脑安装一次。

            只需安装一次：

            1. 点击下方“发送根证书到电脑”，将 LVRead-Root-CA.cer 保存到 Windows。
            2. 双击证书，选择“安装证书”。
            3. 选择“本地计算机”。
            4. 选择“将所有证书放入下列存储”。
            5. 存储位置选择“受信任的根证书颁发机构”。
            6. 完成安装后，完全退出并重新打开浏览器。
            7. 打开 https://\(hostName) 的同步链接。
            """
        }
    }

    @objc private func shareCertificate() {
        let controller = UIActivityViewController(
            activityItems: [certificateURL],
            applicationActivities: nil
        )
        present(controller, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
