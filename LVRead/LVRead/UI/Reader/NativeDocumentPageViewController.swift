import UIKit

protocol NativeDocumentPageDelegate: AnyObject {
    func documentPageDidTapBack()
    func documentPageDidTapCenter()
    func documentPageDidTapEdge(forward: Bool)
    func documentPage(_ controller: NativeDocumentPageViewController, didUpdatePull distance: CGFloat)
    func documentPage(_ controller: NativeDocumentPageViewController, didFinishPull shouldToggleBookmark: Bool)
    func documentPage(_ controller: NativeDocumentPageViewController, didLongPress text: String)
    func documentPageDidTapComment(_ controller: NativeDocumentPageViewController)
}

final class NativeDocumentPageViewController: UIViewController {
    let page: NativeDocumentPage
    weak var delegate: NativeDocumentPageDelegate?
    private let settings: ReadingSettings
    private let allowsPullBookmark: Bool
    private let progressText: String
    private let timeText: String
    private let batteryLevel: Float
    private let readingSafeAreaInsets: UIEdgeInsets
    private let canvas = NativeCoreTextView()
    private let backButton = UIButton(type: .system)
    private let chapterLabel = UILabel()
    private let progressLabel = UILabel()
    private let timeLabel = UILabel()
    private let batteryView = LVBatteryView()
    private let bookmark = UIImageView(image: UIImage(systemName: "bookmark.fill"))
    private let comment = UIButton(type: .system)
    private var pullDistance: CGFloat = 0
    private var isBookmarked: Bool

    init(
        page: NativeDocumentPage,
        settings: ReadingSettings,
        bookmarked: Bool,
        hasComment: Bool,
        allowsPullBookmark: Bool,
        progressText: String,
        timeText: String,
        batteryLevel: Float,
        readingSafeAreaInsets: UIEdgeInsets
    ) {
        self.page = page
        self.settings = settings
        self.allowsPullBookmark = allowsPullBookmark
        self.progressText = progressText
        self.timeText = timeText
        self.batteryLevel = batteryLevel
        self.readingSafeAreaInsets = readingSafeAreaInsets
        self.isBookmarked = bookmarked
        super.init(nibName: nil, bundle: nil)
        bookmark.isHidden = !bookmarked
        comment.isHidden = !hasComment
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        canvas.page = page
        canvas.settings = settings
        canvas.readingSafeAreaInsets = readingSafeAreaInsets
        let pageBackground = UIColor(hex: settings.readingTheme.backgroundColor)
        view.backgroundColor = pageBackground
        canvas.backgroundColor = pageBackground
        let foreground = UIColor(hex: settings.readingTheme.textColor)
        let backConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfiguration), for: .normal)
        backButton.tintColor = foreground
        backButton.accessibilityLabel = "返回"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        chapterLabel.text = page.chapterTitle
        chapterLabel.font = .systemFont(ofSize: 13, weight: .medium)
        chapterLabel.textAlignment = .right
        chapterLabel.textColor = foreground
        chapterLabel.lineBreakMode = .byTruncatingTail
        progressLabel.text = progressText
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        progressLabel.textColor = foreground.withAlphaComponent(0.72)
        timeLabel.text = timeText
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = foreground.withAlphaComponent(0.72)
        batteryView.strokeColor = foreground.withAlphaComponent(0.7)
        batteryView.fillColor = foreground.withAlphaComponent(0.8)
        batteryView.level = batteryLevel
        bookmark.tintColor = UIColor(hex: settings.readingTheme.accentColor)
        comment.setImage(UIImage(systemName: "text.bubble.fill"), for: .normal)
        comment.tintColor = UIColor(hex: settings.readingTheme.accentColor)
        comment.accessibilityLabel = "查看或修改评论"
        comment.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)
        view.addSubview(canvas)
        view.addSubview(backButton)
        view.addSubview(chapterLabel)
        view.addSubview(progressLabel)
        view.addSubview(timeLabel)
        view.addSubview(batteryView)
        view.addSubview(bookmark)
        view.addSubview(comment)
        [canvas, backButton, chapterLabel, progressLabel, timeLabel, batteryView, bookmark, comment].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: readingSafeAreaInsets.top
            ),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: NativeDocumentTypography.topReadingStatusHeight),
            chapterLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            chapterLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            chapterLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            chapterLabel.heightAnchor.constraint(equalTo: backButton.heightAnchor),
            progressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progressLabel.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -(readingSafeAreaInsets.bottom + 8)
            ),
            batteryView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            batteryView.centerYAnchor.constraint(equalTo: progressLabel.centerYAnchor),
            batteryView.widthAnchor.constraint(equalToConstant: 26),
            batteryView.heightAnchor.constraint(equalToConstant: 13),
            timeLabel.trailingAnchor.constraint(equalTo: batteryView.leadingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: progressLabel.centerYAnchor),
            // 阅读状态下系统状态栏隐藏，书签使用其顶部空间，避免遮挡页眉章节名。
            bookmark.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            bookmark.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            bookmark.widthAnchor.constraint(equalToConstant: 24),
            bookmark.heightAnchor.constraint(equalToConstant: 32),
            comment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            comment.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            comment.widthAnchor.constraint(equalToConstant: 44),
            comment.heightAnchor.constraint(equalToConstant: 44)
        ])
        configureGestures()
    }

    func setBookmarked(_ value: Bool) {
        isBookmarked = value
        bookmark.isHidden = !value
    }

    func setPullBookmarkPreviewVisible(_ visible: Bool) {
        bookmark.isHidden = !(isBookmarked || visible)
    }
    func setCommentVisible(_ value: Bool) { comment.isHidden = !value }

    private func configureGestures() {
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pulled(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let ratio = gesture.location(in: view).x / max(view.bounds.width, 1)
        if ratio < 0.3 {
            delegate?.documentPageDidTapEdge(forward: false)
        } else if ratio > 0.7 {
            delegate?.documentPageDidTapEdge(forward: true)
        } else {
            delegate?.documentPageDidTapCenter()
        }
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let text = canvas.paragraph(at: gesture.location(in: canvas)) else { return }
        delegate?.documentPage(self, didLongPress: String(text.prefix(500)))
    }

    @objc private func pulled(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            pullDistance = max(0, gesture.translation(in: view).y)
            delegate?.documentPage(self, didUpdatePull: pullDistance)
        case .ended:
            delegate?.documentPage(self, didFinishPull: pullDistance >= 72)
            pullDistance = 0
        case .cancelled, .failed:
            delegate?.documentPage(self, didFinishPull: false)
            pullDistance = 0
        default:
            break
        }
    }

    @objc private func commentTapped() { delegate?.documentPageDidTapComment(self) }

    @objc private func backTapped() { delegate?.documentPageDidTapBack() }
}

/// UIPageViewController 仿真翻页的显式纸张背面。
/// 使用当前主题的协调色，并透印当前页而非下一页的文字。
final class NativeDocumentPageBackViewController: UIViewController {
    let page: NativeDocumentPage
    private let settings: ReadingSettings
    private let readingSafeAreaInsets: UIEdgeInsets
    private let canvas = NativeCoreTextView()

    init(page: NativeDocumentPage, settings: ReadingSettings, readingSafeAreaInsets: UIEdgeInsets) {
        self.page = page
        self.settings = settings
        self.readingSafeAreaInsets = readingSafeAreaInsets
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let backColor = UIColor(hex: settings.readingTheme.pageBackColor)
        view.backgroundColor = backColor
        view.isOpaque = true

        canvas.page = page
        canvas.settings = settings
        canvas.readingSafeAreaInsets = readingSafeAreaInsets
        canvas.backgroundColor = backColor
        canvas.isOpaque = true
        canvas.alpha = settings.readingTheme.pageBackTextOpacity
        canvas.transform = CGAffineTransform(scaleX: -1, y: 1)
        view.addSubview(canvas)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        accessibilityElementsHidden = true
    }
}

extension NativeDocumentPageViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard allowsPullBookmark else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
    }
}
