import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


final class TransferSelectBooksViewController: UIViewController {
    private let device: LanDevice
    private var allBooks: [Book] = []
    private var selectedBooks: Set<String> = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let sendButton = LVButton(title: "发送 (0)", style: .primary)

    init(device: LanDevice) {
        self.device = device
        super.init(nibName: nil, bundle: nil)
        title = "选择书籍"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        allBooks = BookRepository.shared.getAll()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookCell")
        tableView.allowsMultipleSelection = true

        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        view.addSubviews(tableView, sendButton)
        [tableView, sendButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -16),

            sendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            sendButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 200),
            sendButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appThemeDidChange),
            name: .darkModeChanged,
            object: nil
        )
        applyAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyAppearance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appThemeDidChange() {
        applyAppearance()
    }

    private func applyAppearance() {
        let style = LVBookshelfModuleStyle.self
        view.backgroundColor = style.pageBackground
        tableView.backgroundColor = style.pageBackground
        sendButton.backgroundColor = style.accent
        sendButton.setTitleColor(
            style.accent.contrastingTextColor,
            for: .normal
        )
        tableView.reloadData()
    }

    @objc private func sendTapped() {
        guard !selectedBooks.isEmpty else { return }
        let books = allBooks.filter { selectedBooks.contains($0.id) }

        TransferManager.shared.sendBooks(books, to: device) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    let progressVC = TransferProgressViewController()
                    self?.present(progressVC, animated: true)
                case .failure(let error):
                    LVToast.show(message: error.localizedDescription, style: .error)
                }
            }
        }
    }
}

extension TransferSelectBooksViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { allBooks.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookCell", for: indexPath)
        let book = allBooks[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = book.title
        config.secondaryText = "\(book.author) · \(book.fileSizeDisplay)"
        config.textProperties.color = LVBookshelfModuleStyle.primaryText
        config.secondaryTextProperties.color = LVBookshelfModuleStyle.secondaryText
        cell.backgroundColor = LVBookshelfModuleStyle.cardBackground
        cell.contentConfiguration = config
        cell.accessoryType = selectedBooks.contains(book.id) ? .checkmark : .none
        cell.tintColor = LVBookshelfModuleStyle.accent
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let bookId = allBooks[indexPath.row].id
        if selectedBooks.contains(bookId) {
            selectedBooks.remove(bookId)
        } else {
            selectedBooks.insert(bookId)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
        sendButton.setTitle("发送 (\(selectedBooks.count))", for: .normal)
    }
}
