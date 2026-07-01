import UIKit

final class ChapterListViewController: UIViewController {

    // MARK: - Properties

    private let chapters: [Chapter]
    private let currentIndex: Int
    private let tableView = UITableView(frame: .zero, style: .plain)

    var onChapterSelected: ((Int) -> Void)?

    // MARK: - Init

    init(book: Book, chapters: [Chapter], currentIndex: Int) {
        self.chapters = chapters
        self.currentIndex = currentIndex
        super.init(nibName: nil, bundle: nil)
        title = "\u{76EE}\u{5F55} (\(chapters.count)\u{7AE0})"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "\u{5173}\u{95ED}",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if currentIndex < chapters.count {
            tableView.scrollToRow(
                at: IndexPath(row: currentIndex, section: 0),
                at: .middle,
                animated: false
            )
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ChapterListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chapters.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let chapter = chapters[indexPath.row]

        cell.textLabel?.text = chapter.title
        cell.textLabel?.font = (chapter.level == 1)
            ? .systemFont(ofSize: 15, weight: .medium)
            : .systemFont(ofSize: 14, weight: .regular)
        cell.textLabel?.textColor = (indexPath.row == currentIndex) ? .lvPrimary : .lvTextPrimary
        cell.indentationLevel = (chapter.level - 1) * 2
        cell.accessoryType = (indexPath.row == currentIndex) ? .checkmark : .none
        cell.tintColor = .lvPrimary

        return cell
    }
}

// MARK: - UITableViewDelegate

extension ChapterListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onChapterSelected?(indexPath.row)
        dismiss(animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
}
