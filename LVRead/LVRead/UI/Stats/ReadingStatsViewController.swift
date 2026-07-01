import UIKit

fileprivate extension UIView {
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


final class ReadingStatsViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "阅读统计"
        view.backgroundColor = .systemGroupedBackground

        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.spacing = 16

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        [scrollView, contentStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        scrollView.fillSuperview()
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40),
            contentStack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40)
        ])

        // Summary cards
        let summaryRow = UIStackView()
        summaryRow.axis = .horizontal
        summaryRow.distribution = .fillEqually
        summaryRow.spacing = 12

        summaryRow.addArrangedSubview(makeStatCard(title: "已读", value: "12", unit: "本", color: .lvPrimary))
        summaryRow.addArrangedSubview(makeStatCard(title: "阅读时长", value: "48", unit: "小时", color: .lvSecondary))
        summaryRow.addArrangedSubview(makeStatCard(title: "阅读页数", value: "3,842", unit: "页", color: .lvAccent))

        contentStack.addArrangedSubview(summaryRow)
        summaryRow.heightAnchor.constraint(equalToConstant: 100).isActive = true

        // Daily trend placeholder
        let dailyCard = makeSectionCard(title: "每日阅读趋势")
        let dailyLabel = UILabel()
        dailyLabel.text = "📊  阅读统计图表将在 v2.1 中呈现"
        dailyLabel.font = .systemFont(ofSize: 14)
        dailyLabel.textColor = .lvTextSecondary
        dailyLabel.textAlignment = .center
        dailyCard.addSubview(dailyLabel)
        dailyLabel.translatesAutoresizingMaskIntoConstraints = false
        dailyLabel.fillSuperview(padding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        dailyCard.heightAnchor.constraint(equalToConstant: 120).isActive = true
        contentStack.addArrangedSubview(dailyCard)

        // Bookmarks section
        let allBooks = BookRepository.shared.getAll()
        let bookmarkedBooks = allBooks.filter { !BookRepository.shared.getBookmarks(for: $0.id).isEmpty }

        if !bookmarkedBooks.isEmpty {
            let bookmarksCard = makeSectionCard(title: "书签与笔记")
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 8

            for book in bookmarkedBooks {
                let bookmarks = BookRepository.shared.getBookmarks(for: book.id)
                let label = UILabel()
                label.text = "📑 \(book.title) - \(bookmarks.count) 个书签"
                label.font = .systemFont(ofSize: 13)
                label.textColor = .lvTextPrimary
                stack.addArrangedSubview(label)
            }

            bookmarksCard.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.fillSuperview(padding: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
            contentStack.addArrangedSubview(bookmarksCard)
        }
    }

    private func makeStatCard(title: String, value: String, unit: String, color: UIColor) -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4
        card.layer.shadowOpacity = 0.06

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .lvTextSecondary
        titleLabel.textAlignment = .center

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        valueLabel.textColor = color
        valueLabel.textAlignment = .center

        let unitLabel = UILabel()
        unitLabel.text = unit
        unitLabel.font = .systemFont(ofSize: 11)
        unitLabel.textColor = .lvTextTertiary
        unitLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel, unitLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center

        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.centerInSuperview()
        return card
    }

    private func makeSectionCard(title: String) -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12

        let headerLabel = UILabel()
        headerLabel.text = title
        headerLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        headerLabel.textColor = .lvTextPrimary

        card.addSubview(headerLabel)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16)
        ])
        return card
    }
}
