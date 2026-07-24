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


final class TransferDeviceListViewController: UIViewController {
    private var devices: [LanDevice] = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var emptyView = LVEmptyStateView(
        icon: "📡",
        title: "正在搜索附近设备...",
        subtitle: "请确保两台设备已连接同一 Wi-Fi",
        actionTitle: ""
    )
    private let scanButton = UIButton(type: .system)
    private var scanTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "同网传输"

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DeviceCell")

        emptyView.isHidden = true

        scanButton.setTitle("🔄 重新搜索", for: .normal)
        scanButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        scanButton.backgroundColor = .lvPrimary
        scanButton.setTitleColor(.white, for: .normal)
        scanButton.layer.cornerRadius = 8
        scanButton.addTarget(self, action: #selector(startScan), for: .touchUpInside)

        view.addSubviews(tableView, emptyView, scanButton)
        [tableView, emptyView, scanButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        tableView.fillSuperview()
        emptyView.centerInSuperview()
        NSLayoutConstraint.activate([
            scanButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            scanButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanButton.widthAnchor.constraint(equalToConstant: 160),
            scanButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        startScan()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appThemeDidChange),
            name: .darkModeChanged,
            object: nil
        )
        applyAppearance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanTimer?.invalidate()
        UDPDiscoveryService.shared.stop()
    }

    @objc private func appThemeDidChange() {
        applyAppearance()
    }

    private func applyAppearance() {
        view.backgroundColor = LVBookshelfModuleStyle.pageBackground
        tableView.backgroundColor = LVBookshelfModuleStyle.pageBackground
        scanButton.backgroundColor = LVBookshelfModuleStyle.accent
        scanButton.setTitleColor(
            LVBookshelfModuleStyle.accent.contrastingTextColor,
            for: .normal
        )
        tableView.reloadData()
    }

    @objc private func startScan() {
        devices.removeAll()
        tableView.reloadData()
        emptyView.isHidden = true

        UDPDiscoveryService.shared.onDeviceDiscovered = { [weak self] device in
            DispatchQueue.main.async {
                if let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx] = device
                } else {
                    self?.devices.append(device)
                }
                self?.emptyView.isHidden = !(self?.devices.isEmpty ?? true)
                self?.tableView.reloadData()
            }
        }

        UDPDiscoveryService.shared.start()

        // 10 second timeout
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.devices.isEmpty ?? true {
                    self?.emptyView.removeFromSuperview()
                    let newEmptyView = LVEmptyStateView(
                        icon: "📡",
                        title: "未发现附近设备",
                        subtitle: "请确保两台设备已连接同一 Wi-Fi 且均打开 LVRead",
                        actionTitle: ""
                    )
                    self?.emptyView = newEmptyView
                    self?.view.addSubview(newEmptyView)
                    newEmptyView.translatesAutoresizingMaskIntoConstraints = false
                    newEmptyView.centerInSuperview()
                    self?.emptyView.isHidden = false
                }
            }
        }
    }

    private func sendBooks(to device: LanDevice) {
        let selectVC = TransferSelectBooksViewController(device: device)
        navigationController?.pushViewController(selectVC, animated: true)
    }
}

extension TransferDeviceListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { devices.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath)
        let device = devices[indexPath.row]

        var config = UIListContentConfiguration.subtitleCell()
        config.text = device.deviceName
        config.secondaryText = "\(device.platform) · \(device.ipAddress)"
        config.image = UIImage(systemName: device.platform == "IOS" ? "iphone" : "desktopcomputer")
        config.textProperties.color = LVBookshelfModuleStyle.primaryText
        config.secondaryTextProperties.color = LVBookshelfModuleStyle.secondaryText
        config.imageProperties.tintColor = LVBookshelfModuleStyle.accent

        let statusDot = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        statusDot.backgroundColor = device.isOnline ? .lvAccent : .lvTextTertiary
        statusDot.layer.cornerRadius = 4
        cell.accessoryView = statusDot
        cell.backgroundColor = LVBookshelfModuleStyle.cardBackground
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        sendBooks(to: devices[indexPath.row])
    }
}
