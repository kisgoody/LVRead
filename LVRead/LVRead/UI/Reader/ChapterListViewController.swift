import UIKit

final class ChapterListViewController: UIViewController {

    // MARK: - Properties

    private let entries: [ReaderChapterContentPolicy.DirectoryEntry]
    private let currentEntryIndex: Int?
    private let tableView = UITableView(frame: .zero, style: .plain)

    var onChapterSelected: ((Int) -> Void)?

    // MARK: - Init

    init(book: Book, chapters: [Chapter], currentIndex: Int) {
        let entries = ReaderChapterContentPolicy.directoryEntries(from: chapters)
        self.entries = entries
        self.currentEntryIndex = entries.firstIndex {
            $0.sourceIndices.contains(currentIndex)
        }
        super.init(nibName: nil, bundle: nil)
        title = "\u{76EE}\u{5F55} (\(entries.count)\u{7AE0})"
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

        if let currentEntryIndex {
            tableView.scrollToRow(
                at: IndexPath(row: currentEntryIndex, section: 0),
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
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let chapter = entries[indexPath.row].chapter

        cell.textLabel?.text = chapter.title
        cell.textLabel?.font = (chapter.level == 1)
            ? .systemFont(ofSize: 15, weight: .medium)
            : .systemFont(ofSize: 14, weight: .regular)
        cell.textLabel?.textColor = (indexPath.row == currentEntryIndex) ? .lvPrimary : .lvTextPrimary
        cell.indentationLevel = (chapter.level - 1) * 2
        cell.accessoryType = (indexPath.row == currentEntryIndex) ? .checkmark : .none
        cell.tintColor = .lvPrimary

        return cell
    }
}

// MARK: - UITableViewDelegate

extension ChapterListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onChapterSelected?(entries[indexPath.row].sourceIndex)
        dismiss(animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
}
