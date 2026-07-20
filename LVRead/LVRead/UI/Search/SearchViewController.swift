import UIKit

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


final class SearchViewController: UIViewController {

    // MARK: - UI Components

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyView = LVEmptyStateView(icon: "🔍", title: "没有找到匹配的书籍")

    // MARK: - Properties

    private var results: [Book] = []
    private var searchWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "搜索"

        searchBar.placeholder = "搜索书名、作者..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.becomeFirstResponder()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(BookListCell.self, forCellReuseIdentifier: BookListCell.reuseIdentifier)
        tableView.rowHeight = 100
        tableView.keyboardDismissMode = .onDrag

        emptyView.isHidden = true

        view.addSubviews(searchBar, tableView, emptyView)
        [searchBar, tableView, emptyView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
        searchBar.searchTextField.backgroundColor = style.cardBackground
        searchBar.searchTextField.textColor = style.primaryText
        searchBar.searchTextField.tintColor = style.accent
        tableView.reloadData()
    }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            let r = BookRepository.shared.search(searchText)
            DispatchQueue.main.async {
                self?.results = r
                self?.emptyView.isHidden = !r.isEmpty
                self?.tableView.reloadData()
            }
        }
        searchWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: BookListCell.reuseIdentifier,
            for: indexPath
        ) as! BookListCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let book = results[indexPath.row]
        let readerVC = NativeDocumentReaderViewController(book: book)
        readerVC.modalPresentationStyle = .fullScreen
        present(readerVC, animated: true)
    }
}
