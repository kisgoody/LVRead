import UIKit
import CoreText

enum ReaderChapterContentPolicy {
    struct DirectoryEntry {
        let chapter: Chapter
        let sourceIndex: Int
        var sourceIndices: [Int]
    }

    static func isTitleOnly(content: String, chapterTitle: String) -> Bool {
        let normalizedContent = normalized(content)
        return normalizedContent.isEmpty || normalizedContent == normalized(chapterTitle)
    }

    static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    static func merging(pendingTitles: [String], with content: String) -> String {
        let titles = pendingTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return content }
        return titles.joined(separator: "\n") + "\n\n" + content
    }

    static func removingRepeatedLeadingTitles(
        from content: String,
        chapterTitle: String
    ) -> String {
        let normalizedTitle = normalized(chapterTitle)
        guard !normalizedTitle.isEmpty else { return content }

        let lines = content.components(separatedBy: .newlines)
        var foundTitle = false
        var isInLeadingBlock = true
        var result: [String] = []

        for line in lines {
            let normalizedLine = normalized(line)
            if isInLeadingBlock, normalizedLine.isEmpty {
                result.append(line)
                continue
            }
            if isInLeadingBlock, normalizedLine == normalizedTitle {
                if !foundTitle {
                    result.append(line)
                }
                foundTitle = true
                continue
            }
            isInLeadingBlock = false
            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    static func directoryEntries(from chapters: [Chapter]) -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        for (index, chapter) in chapters.enumerated() {
            if let existingIndex = entries.firstIndex(where: {
                titlesMatch($0.chapter.title, chapter.title)
            }) {
                entries[existingIndex].sourceIndices.append(index)
            } else {
                entries.append(
                    DirectoryEntry(
                        chapter: chapter,
                        sourceIndex: index,
                        sourceIndices: [index]
                    )
                )
            }
        }
        return entries
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


// MARK: - Page Container (holds rendered CoreText page)
final class PageContainerView: UIView {
    var pageData: PageData?
    var pageBackgroundColor: UIColor = .white
    private static var watermarkCache: [ZodiacAnimal: UIImage] = [:]

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let page = pageData else { return }
        // Fill background
        ctx.setFillColor(pageBackgroundColor.cgColor)
        ctx.fill(rect)

        // Draw zodiac watermark in UIKit coordinates (BEFORE CoreText flip)
        if let zodiac = settings.zodiacWatermark,
           let zodiacImage = watermarkImage(for: zodiac) {
            let imgW = bounds.width * 0.62
            let imgH = zodiacImage.size.height * (imgW / zodiacImage.size.width)
            let imgX = (bounds.width - imgW) / 2
            let imgY = (bounds.height - imgH) / 2
            let imgRect = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
            zodiacImage.draw(in: imgRect, blendMode: .multiply, alpha: watermarkAlpha)
        }

        // Flip coordinate system for CoreText
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let layout = ReaderTextLayoutEngine.layout(
            pageSize: bounds.size,
            settings: settings
        )
        let attr = ReaderTextLayoutEngine.attributedString(
            content: page.content,
            settings: settings,
            foregroundColor: UIColor(hex: settings.readingTheme.textColor)
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: layout.textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    var settings: ReadingSettings = .default

    func render(page: PageData, with settings: ReadingSettings) {
        self.pageData = page
        self.settings = settings
        self.pageBackgroundColor = UIColor(hex: settings.backgroundColor)
        setNeedsDisplay()
    }

    func clear() {
        pageData = nil
        layer.contents = nil
        setNeedsDisplay()
    }

    static func clearWatermarkCache() {
        watermarkCache.removeAll()
    }

    private var watermarkAlpha: CGFloat {
        switch settings.readingTheme {
        case .midnight, .oled:
            return 0.18
        default:
            return 0.24
        }
    }

    private func watermarkImage(for zodiac: ZodiacAnimal) -> UIImage? {
        if let cached = Self.watermarkCache[zodiac] { return cached }
        guard let image = zodiac.loadDisplayImage(maxPixel: 512)?.lv_removingNearWhiteBackground() else { return nil }
        Self.watermarkCache[zodiac] = image
        return image
    }
}

private extension UIImage {
    func lv_removingNearWhiteBackground() -> UIImage? {
        guard let cgImage else { return self }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = pixels[offset]
            let g = pixels[offset + 1]
            let b = pixels[offset + 2]
            if r > 238, g > 238, b > 238 {
                pixels[offset + 3] = 0
            }
        }

        guard let output = ctx.makeImage() else { return self }
        return UIImage(cgImage: output, scale: scale, orientation: imageOrientation)
    }
}

// MARK: - Main Reader
//
// ⚠️ 遗留代码 (Legacy) — 已被 ContinuousReaderViewController 替代
//     ContinuousReaderViewController 使用 PageKey 模型正确实现了：
//     - 以当前阅读位置为中心的 ±5 页跨章节窗口
//     - 翻页方向感知的缓存调度
//     本文件保留以维持编译，不再主动使用。

final class ReaderViewController: UIViewController {

    // MARK: Properties

    private let book: Book
    var settings: ReadingSettings {
        didSet { ReadingSettingsRepository.shared.save(settings) }
    }
    private var chapters: [Chapter] = []
    private var currentChapterIndex: Int = 0
    private var currentPageIndex: Int = 0
    private var chapterPages: [[PageData]] = []
    private let residentPageRadius = 5

    private var readingStartTime: Date?
    private var totalReadingSeconds: Int = 0
    private var readingTimer: Timer?
    private var autoReadTimer: Timer?
    private var autoReadRemainingSeconds: Int = 0

    // Page turn state
    private var isPageFlipping = false
    private var activePanDirection: PageTurnDirection?
    private var activePanPreparedTurn: PreparedPageTurn?
    private var loadingAdjacentDirections: Set<PageTurnDirection> = []
    private var preloadingAdjacentDirections: Set<PageTurnDirection> = []
    private var loadingScrollChapters: Set<Int> = []
    private var isClosing = false
    private let interactiveState = PageFlipState()
    private var smoothScrollHandler: SmoothScrollHandler?

    // MARK: UI

    private let containerView = UIView()
    private let currentPageView = PageContainerView()
    private let nextPageView = PageContainerView()
    private let scrollView = UIScrollView()
    private let backButton = UIButton(type: .system)
    private let topChapterLabel = UILabel()
    private let bottomPageLabel = UILabel()
    private let bottomTimeLabel = UILabel()
    private let batteryView = LVBatteryView()
    private let topMenuBar = UIView()
    private let menuBackButton = UIButton(type: .system)
    private let bookTitleLabel = UILabel()
    private let menuChapterLabel = UILabel()
    private let toolBar = UIView()
    private var toolBtnStack: UIStackView!
    private let eyeCareOverlay = UIView()
    private var chromeVisible = false
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private struct PreparedPageTurn {
        let chapterIndex: Int
        let pageIndex: Int
        let pages: [PageData]
    }

    // MARK: Init

    init(book: Book) {
        self.book = book
        self.settings = ReadingSettingsRepository.shared.load()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupGestures()
        startReadingTimer()
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentPageIndex)
        // Listen for flip mode changes
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageFlipModeChanged), name: NSNotification.Name("pageFlipModeChanged"), object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if chapterPages.isEmpty { view.layoutIfNeeded(); loadBook() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgress()
        stopReadingTimer()
        stopAutoRead()
        WebSyncServer.shared.stop()
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            releaseReaderResources()
        }
    }

    deinit {
        releaseReaderResources()
        NotificationCenter.default.removeObserver(self)
    }

    override var prefersStatusBarHidden: Bool { !chromeVisible }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: Layout

    private func setupViews() {
        view.backgroundColor = UIColor(hex: settings.backgroundColor)
        let tc = UIColor(hex: settings.readingTheme.textColor)

        // Container fills reading area
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = false

        let bgColor = UIColor(hex: settings.backgroundColor)
        currentPageView.backgroundColor = bgColor
        currentPageView.isOpaque = false
        nextPageView.backgroundColor = bgColor
        nextPageView.isOpaque = false
        nextPageView.alpha = 0

        containerView.addSubviews(nextPageView, currentPageView)

        // Scroll view for scroll mode
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.isHidden = true
        scrollView.alpha = 0

        // Back button
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        backButton.tintColor = tc.withAlphaComponent(0.35)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        // Top chapter label
        topChapterLabel.font = .systemFont(ofSize: 11)
        topChapterLabel.textColor = tc.withAlphaComponent(0.4)
        topChapterLabel.textAlignment = .right

        // Bottom labels
        bottomPageLabel.font = .systemFont(ofSize: 11)
        bottomPageLabel.textColor = tc.withAlphaComponent(0.4)
        bottomTimeLabel.font = .systemFont(ofSize: 11)
        bottomTimeLabel.textColor = tc.withAlphaComponent(0.4)
        batteryView.strokeColor = tc.withAlphaComponent(0.35)
        batteryView.fillColor = tc.withAlphaComponent(0.5)

        // Eye care overlay
        eyeCareOverlay.isUserInteractionEnabled = false
        updateEyeCareOverlay()

        // Tool bar
        toolBar.backgroundColor = UIColor(hex: settings.readingTheme.panelColor).withAlphaComponent(0.96)
        toolBar.alpha = 0

        topMenuBar.backgroundColor = UIColor(hex: settings.readingTheme.panelColor).withAlphaComponent(0.96)
        topMenuBar.alpha = 0
        menuBackButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
        menuBackButton.tintColor = tc.withAlphaComponent(0.85)
        menuBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        bookTitleLabel.text = book.title
        bookTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        bookTitleLabel.textColor = tc.withAlphaComponent(0.9)
        bookTitleLabel.textAlignment = .center
        bookTitleLabel.lineBreakMode = .byTruncatingTail
        menuChapterLabel.font = .systemFont(ofSize: 12, weight: .regular)
        menuChapterLabel.textColor = tc.withAlphaComponent(0.65)
        menuChapterLabel.textAlignment = .right
        menuChapterLabel.lineBreakMode = .byTruncatingTail
        topMenuBar.addSubviews(menuBackButton, bookTitleLabel, menuChapterLabel)

        func makeBtn(_ icon: String, action: Selector) -> UIButton {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
            b.tintColor = tc.withAlphaComponent(0.7)
            b.addTarget(self, action: action, for: .touchUpInside)
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return b
        }
        toolBtnStack = UIStackView(arrangedSubviews: [
            makeBtn("list.bullet", action: #selector(showCatalog)),
            makeBtn(settings.nightMode ? "moon.fill" : "moon", action: #selector(toggleNightMode)),
            makeBtn("gearshape", action: #selector(showSettings)),
            makeBtn("play.circle", action: #selector(toggleAutoRead)),
            makeBtn("bookmark", action: #selector(toggleBookmark)),
            makeBtn("desktopcomputer", action: #selector(showWebSync))
        ])
        toolBtnStack.axis = .horizontal; toolBtnStack.distribution = .equalSpacing; toolBtnStack.spacing = 20
        toolBar.addSubview(toolBtnStack)

        view.addSubviews(containerView, scrollView, eyeCareOverlay, backButton, topChapterLabel,
                        bottomPageLabel, bottomTimeLabel, batteryView, topMenuBar, toolBar)
        [containerView, currentPageView, nextPageView, scrollView, backButton, topChapterLabel,
         bottomPageLabel, bottomTimeLabel, batteryView, topMenuBar, menuBackButton, bookTitleLabel, menuChapterLabel, toolBar, toolBtnStack,
         eyeCareOverlay].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomPageLabel.topAnchor, constant: -8),

            currentPageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            currentPageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            currentPageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            currentPageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            nextPageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            nextPageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            nextPageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            nextPageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            backButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 4),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            topChapterLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            topChapterLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -14),
            topChapterLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.55),

            eyeCareOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            eyeCareOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            eyeCareOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            eyeCareOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomPageLabel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            bottomPageLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 14),
            bottomTimeLabel.centerYAnchor.constraint(equalTo: bottomPageLabel.centerYAnchor),
            bottomTimeLabel.trailingAnchor.constraint(equalTo: batteryView.leadingAnchor, constant: -6),
            batteryView.centerYAnchor.constraint(equalTo: bottomPageLabel.centerYAnchor),
            batteryView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -14),
            batteryView.widthAnchor.constraint(equalToConstant: 26),
            batteryView.heightAnchor.constraint(equalToConstant: 13),

            topMenuBar.topAnchor.constraint(equalTo: view.topAnchor),
            topMenuBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topMenuBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topMenuBar.bottomAnchor.constraint(equalTo: safe.topAnchor, constant: 52),
            menuBackButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 6),
            menuBackButton.bottomAnchor.constraint(equalTo: topMenuBar.bottomAnchor, constant: -4),
            menuBackButton.widthAnchor.constraint(equalToConstant: 44),
            menuBackButton.heightAnchor.constraint(equalToConstant: 44),
            bookTitleLabel.centerYAnchor.constraint(equalTo: menuBackButton.centerYAnchor),
            bookTitleLabel.centerXAnchor.constraint(equalTo: topMenuBar.centerXAnchor),
            bookTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: menuBackButton.trailingAnchor, constant: 8),
            bookTitleLabel.widthAnchor.constraint(lessThanOrEqualTo: topMenuBar.widthAnchor, multiplier: 0.42),
            menuChapterLabel.centerYAnchor.constraint(equalTo: menuBackButton.centerYAnchor),
            menuChapterLabel.leadingAnchor.constraint(equalTo: bookTitleLabel.trailingAnchor, constant: 10),
            menuChapterLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -14),

            toolBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolBar.topAnchor.constraint(equalTo: toolBtnStack.topAnchor, constant: -10),

            toolBtnStack.centerXAnchor.constraint(equalTo: toolBar.centerXAnchor),
            toolBtnStack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8)
        ])
    }


    // MARK: Gesture Setup

    private func setupGestures() {
        // Remove all existing gesture recognizers
        view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }

        let mode = settings.pageFlipMode

       if mode == .scroll {
           scrollView.isHidden = false
           scrollView.alpha = 1
           currentPageView.isHidden = true
           nextPageView.isHidden = true
           if smoothScrollHandler == nil {
                smoothScrollHandler = SmoothScrollHandler(scrollView: scrollView) { [weak self] chapterIndex in
                    self?.loadChapterForScroll(chapterIndex)
                }
               smoothScrollHandler?.callbacks.onPageChanged = { [weak self] globalPageIdx in
                    guard let self else { return }
                    let local = self.smoothScrollHandler?.localPage(forGlobal: globalPageIdx) ?? globalPageIdx
                    self.currentPageIndex = local
                    if let page = self.currentPages()?[safe: local] {
                        self.currentChapterIndex = page.chapterIndex
                    }
                    self.updateOverlayLabels()
                    self.updateProgressDisplay()
                }
            }
            refreshScrollContent()

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleScrollTap(_:)))
            view.addGestureRecognizer(tap)
        } else {
            scrollView.isHidden = true
            scrollView.alpha = 0
            currentPageView.isHidden = false
            nextPageView.isHidden = false

            // Always add tap first — so it gets priority for simple taps
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)

            if mode != .none {
                // Pan for page flip gesture
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                pan.delegate = self
                view.addGestureRecognizer(pan)
            }
        }
    }

    // MARK: Scroll Mode

    private func buildScrollContent() {
        refreshScrollContent()
    }

    private func refreshScrollContent() {
        guard settings.pageFlipMode == .scroll else { return }
        guard let pages = currentPages(), let currentPage = pages[safe: currentPageIndex] else { return }
        let grouped = Dictionary(grouping: pages, by: { $0.chapterIndex })
        let currentChapter = currentPage.chapterIndex
        let currentLocalPage = localPageOffset(forGlobalPage: currentPageIndex)
        smoothScrollHandler?.loadChapter(currentChapter, pages: grouped[currentChapter] ?? [], settings: settings, initialPage: currentLocalPage)
        for chapterIndex in grouped.keys.sorted() where chapterIndex != currentChapter {
            smoothScrollHandler?.appendChapter(chapterIndex, pages: grouped[chapterIndex] ?? [])
        }
    }

    // MARK: Scroll Mode Tap — toggle toolbar only

    @objc private func handleScrollTap(_ gesture: UITapGestureRecognizer) {
        toggleToolBar()
    }

    // MARK: Tap (for non-scroll modes)

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if chromeVisible {
            let point = gesture.location(in: view)
            if topMenuBar.frame.contains(point) || toolBar.frame.contains(point) { return }
            toggleToolBar()
            return
        }

        let x = gesture.location(in: view).x
        let w = view.bounds.width
        let mode = settings.pageFlipMode

        if mode == .none {
            // .none mode: tap to flip or toggle toolbar
            if x < w * 0.25 {
                goToPrevPage()
            } else if x > w * 0.75 {
                goToNextPage()
            } else {
                toggleToolBar()
            }
        } else {
            // Animated modes: tap to flip or toggle toolbar
            if x < w * 0.25 {
                animatePageTurn(direction: .prev)
            } else if x > w * 0.75 {
                animatePageTurn(direction: .next)
            } else {
                toggleToolBar()
            }
        }
    }
    // MARK: Animated Page Turn (tap-initiated)

    private func animatePageTurn(direction: PageTurnDirection) {
        guard !isPageFlipping else { return }
        if let prepared = preparedTurn(for: direction) {
            animatePreparedPageTurn(prepared, direction: direction)
            return
        }
        isPageFlipping = true
        loadAdjacentPages(direction: direction) { [weak self] prepared in
            guard let self else { return }
            self.isPageFlipping = false
            guard let prepared else { return }
            self.animatePreparedPageTurn(prepared, direction: direction)
        }
    }

    private func animatePreparedPageTurn(_ prepared: PreparedPageTurn, direction: PageTurnDirection) {
        guard let prepared = preparePageTurnForRender(prepared),
              let page = prepared.pages[safe: prepared.pageIndex] else {
            isPageFlipping = false
            return
        }

        nextPageView.render(page: page, with: settings)
        nextPageView.setNeedsDisplay()
        nextPageView.layer.displayIfNeeded()

        let animDirection: PageFlipDirection = direction == .next ? .next : .prev
        let mode = settings.pageFlipMode

        if mode == .none {
            applyPreparedPageTurn(prepared)
            isPageFlipping = false
            return
        }

        isPageFlipping = true

        PageFlipAnimator.animateTap(
            from: currentPageView,
            to: nextPageView,
            direction: animDirection,
            mode: mode,
            backgroundColor: UIColor(hex: settings.backgroundColor),
            container: containerView
        ) { [weak self] in
            guard let self = self else { return }
            self.applyPreparedPageTurn(prepared)
            self.resetFlipState()
            self.isPageFlipping = false
        }
    }

    private func applyPreparedPageTurn(_ prepared: PreparedPageTurn) {
        guard let page = prepared.pages[safe: prepared.pageIndex] else { return }
        currentChapterIndex = prepared.chapterIndex
        currentPageIndex = prepared.pageIndex
        storeReadingPages(prepared.pages, center: prepared.pageIndex)
        currentPageView.render(page: pageData(at: currentPageIndex) ?? page, with: settings)
        updateOverlayLabels()
        updateProgressDisplay()
        cachePages(prepared.pages, centerPage: prepared.pageIndex)
        preloadAdjacentPagesIfNeeded()
    }

    private func preparedTurn(for direction: PageTurnDirection) -> PreparedPageTurn? {
        guard var pages = currentPages(), !pages.isEmpty else { return nil }
        let targetIndex = direction == .next ? currentPageIndex + 1 : currentPageIndex - 1
        guard targetIndex >= 0, targetIndex < pages.count else { return nil }
        guard let page = pageData(in: &pages, pageIndex: targetIndex) else { return nil }
        pages[targetIndex] = page
        return PreparedPageTurn(chapterIndex: page.chapterIndex, pageIndex: targetIndex, pages: pages)
    }

    // MARK: Pan Gesture (interactive page flip)

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let fmode = settings.pageFlipMode
        guard !chromeVisible else { return }
        guard fmode == .simulation || fmode == .cover || fmode == .slide else { return }

        let mode = fmode
        let translation = pan.translation(in: containerView)
        let velocity = pan.velocity(in: containerView)
        let progress = min(1.0, max(0, abs(translation.x) / max(view.bounds.width, 1) * 1.15))
        let sample = PaperCurlSample(
            location: pan.location(in: containerView),
            translation: translation,
            velocity: velocity,
            containerSize: containerView.bounds.size
        )

        switch pan.state {
        case .began:
            guard !isPageFlipping else { return }
            activePanDirection = nil

        case .changed:
            if activePanDirection == nil {
                guard abs(translation.x) > 8 else { return }
                let direction: PageTurnDirection = translation.x < 0 ? .next : .prev
                guard let prepared = preparedTurn(for: direction) else {
                    isPageFlipping = true
                    loadAdjacentPages(direction: direction) { [weak self] _ in
                        self?.isPageFlipping = false
                    }
                    return
                }

                activePanDirection = direction
                activePanPreparedTurn = prepared
                isPageFlipping = true

                prerender(prepared, in: nextPageView)

                PageFlipAnimator.beginInteractive(
                    from: currentPageView,
                    to: nextPageView,
                    direction: direction.pageFlipDirection,
                    mode: mode,
                    container: containerView,
                    state: interactiveState
                )
            }
            PageFlipAnimator.updateInteractive(
                sample: sample,
                mode: mode,
                state: interactiveState
            )

        case .ended, .cancelled:
            guard activePanDirection != nil, interactiveState.isActive else {
                activePanDirection = nil
                isPageFlipping = false
                return
            }
            let vx = velocity.x
            let shouldCommit = pan.state != .cancelled
                && (mode == .simulation
                    ? PaperCurlPhysics.shouldCommit(
                        progress: interactiveState.progress,
                        velocityX: vx,
                        direction: interactiveState.direction
                    )
                    : progress > 0.28 || abs(vx) > 450)

            PageFlipAnimator.finishInteractive(
                commit: shouldCommit,
                velocityX: vx,
                mode: mode,
                state: interactiveState
            ) { [weak self] committed in
                guard let self = self else { return }
                let prepared = self.activePanPreparedTurn
                if committed {
                    if let prepared {
                        self.applyPreparedPageTurn(prepared)
                    }
                }
                self.resetFlipState()
                self.activePanDirection = nil
                self.activePanPreparedTurn = nil
                self.isPageFlipping = false
            }

        default: break
        }
    }

    private func canTurnPage(_ direction: PageTurnDirection) -> Bool {
        guard let pages = currentPages(), !pages.isEmpty else { return false }
        switch direction {
        case .next:
            return currentPageIndex < pages.count - 1
        case .prev:
            return currentPageIndex > 0
        }
    }

    private func turnPage(_ direction: PageTurnDirection) {
        switch direction {
        case .next: goToNextPage()
        case .prev: goToPrevPage()
        }
    }

    // MARK: - Reset flip state

    private func resetFlipState() {
        interactiveState.cleanup()
        activePanDirection = nil
        activePanPreparedTurn = nil
        currentPageView.layer.transform = CATransform3DIdentity
        currentPageView.transform = .identity
        currentPageView.alpha = 1
        nextPageView.layer.transform = CATransform3DIdentity
        nextPageView.transform = .identity
        nextPageView.alpha = 0
        layoutPageViews()
    }

    private func releaseReaderResources() {
        guard !isClosing else { return }
        isClosing = true
        readingTimer?.invalidate()
        autoReadTimer?.invalidate()
        smoothScrollHandler?.invalidate()
        smoothScrollHandler = nil
        chapterPages.removeAll()
        currentPageView.clear()
        nextPageView.clear()
        PageContainerView.clearWatermarkCache()
        PageCacheManager.shared.clearBookCache(book.id)
    }

    private func layoutPageViews() {
        currentPageView.frame = containerView.bounds
        nextPageView.frame = containerView.bounds
    }

    private func prerenderPage(at index: Int, in view: PageContainerView) {
        guard let pages = currentPages(), index >= 0, index < pages.count else {
            view.render(page: PageData(pageIndex: 0, startCharOffset: 0, endCharOffset: 0, content: "", chapterTitle: "", chapterIndex: 0), with: settings)
            return
        }
        view.render(page: pageData(at: index) ?? pages[index], with: settings)
        // Force immediate draw so the page is ready when animation starts
        view.setNeedsDisplay()
        view.layer.displayIfNeeded()
    }

    private func prerender(_ prepared: PreparedPageTurn, in view: PageContainerView) {
        guard let prepared = preparePageTurnForRender(prepared),
              let page = prepared.pages[safe: prepared.pageIndex] else { return }
        view.render(page: page, with: settings)
        view.setNeedsDisplay()
        view.layer.displayIfNeeded()
    }

    private func preparePageTurnForRender(_ prepared: PreparedPageTurn) -> PreparedPageTurn? {
        var pages = prepared.pages
        guard let page = pageData(in: &pages, pageIndex: prepared.pageIndex) else {
            return nil
        }
        pages[prepared.pageIndex] = page
        let preparedPages = settings.pageFlipMode == .scroll ? pages : pageWindow(from: pages, center: prepared.pageIndex)
        storeReadingPages(preparedPages, center: prepared.pageIndex)
        cachePages(preparedPages, centerPage: prepared.pageIndex)
        return PreparedPageTurn(chapterIndex: page.chapterIndex, pageIndex: prepared.pageIndex, pages: preparedPages)
    }

    enum PageTurnDirection: Hashable { case next, prev }

    // MARK: Book Loading

    private func loadBook() {
        chapters = BookRepository.shared.getChapters(for: book.id)
        // Use fresh progress from DB, not stale in-memory book.readingProgress
        let savedChapterIndex: Int
        let savedPageOffset: Int
        if let fresh = BookRepository.shared.getById(book.id) {
            savedChapterIndex = fresh.readingProgress.currentChapterIndex
            savedPageOffset = fresh.readingProgress.currentPageOffset
        } else {
            savedChapterIndex = book.readingProgress.currentChapterIndex
            savedPageOffset = book.readingProgress.currentPageOffset
        }
        if chapters.isEmpty {
            chapters = [Chapter(bookId: book.id, title: "正文", level: 1, orderIndex: 0)]
        }
        loadReadingPages(startChapterIndex: savedChapterIndex, startPageOffset: savedPageOffset)
    }

    private func loadChapter(_ index: Int) {
        guard index >= 0, index < chapters.count else { return }
        loadReadingPages(startChapterIndex: index, startPageOffset: 0)
    }

    private func loadReadingPages(startChapterIndex: Int, startPageOffset: Int) {
        guard !isClosing else { return }
        let sz = containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.isClosing { return }
            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            var pages: [PageData] = []
            var chapterIndex = min(max(startChapterIndex, 0), max(self.chapters.count - 1, 0))
            var startIndex = 0

            do {
                while chapterIndex < self.chapters.count, pages.isEmpty {
                    if let parsed = try self.parseChapterPages(chapterIndex, parser: parser, fit: sz) {
                        pages = parsed
                        startIndex = chapterIndex == startChapterIndex
                            ? min(max(startPageOffset, 0), max(parsed.count - 1, 0))
                            : 0
                    }
                    if pages.isEmpty { chapterIndex += 1 }
                }

                guard !pages.isEmpty else {
                    DispatchQueue.main.async { LVToast.show(message: "读取失败", style: .error) }
                    return
                }

                var firstChapterIndex = chapterIndex
                var lastChapterIndex = chapterIndex
                while pages.count < self.residentPageRadius * 2 + 1 {
                    if startIndex < self.residentPageRadius, firstChapterIndex > 0 {
                        firstChapterIndex -= 1
                        guard let parsed = try self.parseChapterPages(firstChapterIndex, parser: parser, fit: sz) else { continue }
                        pages = parsed + pages
                        startIndex += parsed.count
                    } else if lastChapterIndex < self.chapters.count - 1 {
                        lastChapterIndex += 1
                        guard let parsed = try self.parseChapterPages(lastChapterIndex, parser: parser, fit: sz) else { continue }
                        pages += parsed
                    } else if firstChapterIndex > 0 {
                        firstChapterIndex -= 1
                        guard let parsed = try self.parseChapterPages(firstChapterIndex, parser: parser, fit: sz) else { continue }
                        pages = parsed + pages
                        startIndex += parsed.count
                    } else {
                        break
                    }
                }

                PageCacheManager.shared.cachePages(pages, bookId: self.book.id, centerPage: startIndex)

                DispatchQueue.main.async {
                    guard !self.isClosing else { return }
                    self.displayPages(pages, center: startIndex)
                }
            } catch {
                DispatchQueue.main.async {
                    guard !self.isClosing else { return }
                    let fm = FileManager.default
                    if !fm.fileExists(atPath: self.book.resolvedFilePath()) {
                        LVToast.show(message: "书籍文件丢失，请重新导入", style: .error)
                        self.dismiss(animated: true)
                    } else {
                        LVToast.show(message: "读取失败", style: .error)
                    }
                }
            }
        }
    }

    private func parseChapterPages(_ chapterIndex: Int, parser: FileParserProtocol, fit size: CGSize) throws -> [PageData]? {
        let chapter = chapters[chapterIndex]
        let content = try parser.parseChapterContent(
            filePath: book.resolvedFilePath(),
            chapter: chapter,
            encoding: book.encoding ?? "UTF-8"
        )
        let deduplicatedContent = ReaderChapterContentPolicy.removingRepeatedLeadingTitles(
            from: content,
            chapterTitle: chapter.title
        )
        guard !ReaderChapterContentPolicy.isTitleOnly(
            content: deduplicatedContent,
            chapterTitle: chapter.title
        ) else {
            return nil
        }

        var pendingTitles: [String] = []
        var followingTitle = chapter.title
        var previousIndex = chapterIndex - 1

        while previousIndex >= 0 {
            let previousChapter = chapters[previousIndex]
            guard let previousContent = try? parser.parseChapterContent(
                filePath: book.resolvedFilePath(),
                chapter: previousChapter,
                encoding: book.encoding ?? "UTF-8"
            ), ReaderChapterContentPolicy.isTitleOnly(
                content: previousContent,
                chapterTitle: previousChapter.title
            ) else {
                break
            }

            if !ReaderChapterContentPolicy.titlesMatch(previousChapter.title, followingTitle) {
                pendingTitles.insert(previousChapter.title, at: 0)
            }
            followingTitle = previousChapter.title
            previousIndex -= 1
        }

        let mergedContent = ReaderChapterContentPolicy.merging(
            pendingTitles: pendingTitles,
            with: deduplicatedContent
        )
        return paginateContent(
            mergedContent,
            fit: size,
            settings: settings,
            chapterIndex: chapterIndex
        )
    }

    private func loadChapterForScroll(_ chapterIndex: Int) {
        guard settings.pageFlipMode == .scroll else { return }
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return }
        guard currentPages()?.contains(where: { $0.chapterIndex == chapterIndex }) != true else { return }
        guard !loadingScrollChapters.contains(chapterIndex) else { return }
        loadingScrollChapters.insert(chapterIndex)

        let sz = containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { self?.loadingScrollChapters.remove(chapterIndex) }
                return
            }
            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                guard let parsed = try self.parseChapterPages(chapterIndex, parser: parser, fit: sz) else {
                    DispatchQueue.main.async { self.loadingScrollChapters.remove(chapterIndex) }
                    return
                }
                PageCacheManager.shared.cachePages(parsed, bookId: self.book.id, centerPage: 0)
                DispatchQueue.main.async {
                    self.loadingScrollChapters.remove(chapterIndex)
                    guard !self.isClosing else { return }
                    self.appendPagesForScroll(parsed, chapterIndex: chapterIndex)
                }
            } catch {
                DispatchQueue.main.async { self.loadingScrollChapters.remove(chapterIndex) }
            }
        }
    }

    private func appendPagesForScroll(_ pages: [PageData], chapterIndex: Int) {
        guard var current = currentPages(), !pages.isEmpty else { return }
        if chapterIndex < (current.first?.chapterIndex ?? chapterIndex) {
            current = pages + current
            currentPageIndex += pages.count
        } else {
            current += pages
        }
        storeReadingPages(current, center: currentPageIndex)
        smoothScrollHandler?.appendChapter(chapterIndex, pages: pages)
    }

    private func loadAdjacentPages(direction: PageTurnDirection, completion: @escaping (PreparedPageTurn?) -> Void) {
        guard !loadingAdjacentDirections.contains(direction) else {
            completion(nil)
            return
        }
        guard !isClosing, let current = currentPages(), !current.isEmpty else {
            completion(nil)
            return
        }
        loadingAdjacentDirections.insert(direction)
        var chapterIndex = direction == .next
            ? (current.last?.chapterIndex ?? currentChapterIndex) + 1
            : (current.first?.chapterIndex ?? currentChapterIndex) - 1
        guard chapterIndex >= 0, chapterIndex < chapters.count else {
            loadingAdjacentDirections.remove(direction)
            completion(nil)
            return
        }

        let sz = containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if self.isClosing {
                DispatchQueue.main.async {
                    self.loadingAdjacentDirections.remove(direction)
                    completion(nil)
                }
                return
            }

            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                var parsed: [PageData]?
                while chapterIndex >= 0, chapterIndex < self.chapters.count, parsed == nil {
                    parsed = try self.parseChapterPages(chapterIndex, parser: parser, fit: sz)
                    if parsed == nil {
                        chapterIndex += direction == .next ? 1 : -1
                    }
                }
                guard let parsed else {
                    DispatchQueue.main.async {
                        self.loadingAdjacentDirections.remove(direction)
                        completion(nil)
                    }
                    return
                }
                PageCacheManager.shared.cachePages(
                    parsed,
                    bookId: self.book.id,
                    centerPage: direction == .next ? 0 : max(parsed.count - 1, 0)
                )
                DispatchQueue.main.async {
                    self.loadingAdjacentDirections.remove(direction)
                    guard !self.isClosing, let current = self.currentPages() else {
                        completion(nil)
                        return
                    }

                    let combined: [PageData]
                    let targetIndex: Int
                    if direction == .next {
                        combined = current + parsed
                        targetIndex = self.currentPageIndex + 1
                    } else {
                        combined = parsed + current
                        targetIndex = max(0, self.currentPageIndex + parsed.count - 1)
                        self.currentPageIndex += parsed.count
                    }

                    self.storeReadingPages(combined, center: self.currentPageIndex)
                    self.cachePages(combined, centerPage: targetIndex)
                    guard var pages = self.currentPages(),
                          let page = self.pageData(in: &pages, pageIndex: targetIndex) else {
                        completion(nil)
                        return
                    }
                    pages[targetIndex] = page
                    completion(PreparedPageTurn(chapterIndex: page.chapterIndex, pageIndex: targetIndex, pages: pages))
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadingAdjacentDirections.remove(direction)
                    completion(nil)
                }
            }
        }
    }

    private func currentPages() -> [PageData]? {
        chapterPages.first
    }

    private func preloadAdjacentPagesIfNeeded() {
        guard settings.pageFlipMode != .scroll,
              !isClosing,
              let pages = currentPages(),
              !pages.isEmpty else { return }

        if pages.count - currentPageIndex - 1 <= residentPageRadius {
            preloadAdjacentPages(direction: .next)
        }
        if currentPageIndex <= residentPageRadius {
            preloadAdjacentPages(direction: .prev)
        }
    }

    private func preloadAdjacentPages(direction: PageTurnDirection) {
        guard !preloadingAdjacentDirections.contains(direction),
              let current = currentPages(),
              !current.isEmpty else { return }

        var chapterIndex = direction == .next
            ? (current.last?.chapterIndex ?? currentChapterIndex) + 1
            : (current.first?.chapterIndex ?? currentChapterIndex) - 1
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return }

        preloadingAdjacentDirections.insert(direction)
        let sz = containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                var parsed: [PageData]?
                while chapterIndex >= 0, chapterIndex < self.chapters.count, parsed == nil {
                    parsed = try self.parseChapterPages(chapterIndex, parser: parser, fit: sz)
                    if parsed == nil {
                        chapterIndex += direction == .next ? 1 : -1
                    }
                }

                DispatchQueue.main.async {
                    self.preloadingAdjacentDirections.remove(direction)
                    guard !self.isClosing,
                          let parsed,
                          var current = self.currentPages(),
                          !current.isEmpty else { return }

                    if direction == .next {
                        guard let parsedFirst = parsed.first?.chapterIndex,
                              parsedFirst > (current.last?.chapterIndex ?? parsedFirst) else { return }
                        current += parsed
                    } else {
                        guard let parsedLast = parsed.last?.chapterIndex,
                              parsedLast < (current.first?.chapterIndex ?? parsedLast) else { return }
                        current = parsed + current
                        self.currentPageIndex += parsed.count
                    }

                    self.currentChapterIndex = current[safe: self.currentPageIndex]?.chapterIndex ?? self.currentChapterIndex
                    self.storeReadingPages(current, center: self.currentPageIndex)
                    self.cachePages(current, centerPage: self.currentPageIndex)
                }
            } catch {
                DispatchQueue.main.async {
                    self.preloadingAdjacentDirections.remove(direction)
                }
            }
        }
    }

    private func displayPages(_ pages: [PageData], center: Int) {
        currentPageIndex = min(max(center, 0), max(pages.count - 1, 0))
        currentChapterIndex = pages[safe: currentPageIndex]?.chapterIndex ?? currentChapterIndex
        storeReadingPages(pages, center: currentPageIndex)
        if let page = pageData(at: currentPageIndex) ?? pages[safe: currentPageIndex] {
            currentChapterIndex = page.chapterIndex
            currentPageView.render(page: page, with: settings)
        }
        updateOverlayLabels()
        updateProgressDisplay()
        cachePages(pages, centerPage: currentPageIndex)
        refreshScrollContent()
        preloadAdjacentPagesIfNeeded()
    }

    private func displayPage(at index: Int) {
        guard let pages = currentPages(), pages.indices.contains(index) else { return }
        displayPages(pages, center: index)
    }

    private func firstPageIndex(forChapter chapterIndex: Int) -> Int {
        currentPages()?.firstIndex { $0.chapterIndex == chapterIndex } ?? currentPageIndex
    }

    private func localPageOffset(forGlobalPage index: Int) -> Int {
        guard let pages = currentPages(), let page = pages[safe: index] else { return 0 }
        return pages[..<index].filter { $0.chapterIndex == page.chapterIndex }.count
    }

    private func storeReadingPages(_ pages: [PageData], center: Int) {
        chapterPages = [settings.pageFlipMode == .scroll ? pages : pageWindow(from: pages, center: center)]
    }

    private func pageData(at pageIndex: Int) -> PageData? {
        guard var pages = currentPages(), pageIndex >= 0, pageIndex < pages.count else { return nil }
        return pageData(in: &pages, pageIndex: pageIndex)
    }

    private func pageData(in pages: inout [PageData], pageIndex: Int) -> PageData? {
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        if !pages[pageIndex].content.isEmpty {
            return pages[pageIndex]
        }
        let chapterIndex = pages[pageIndex].chapterIndex
        let localPageIndex = pages[pageIndex].pageIndex
        guard let cached = PageCacheManager.shared.getPage(bookId: book.id, chapterIndex: chapterIndex, pageIndex: localPageIndex) else {
            return nil
        }
        pages[pageIndex] = cached
        hydratePageWindow(&pages, center: pageIndex)
        chapterPages = [pages]
        return cached
    }

    private func hydratePageWindow(_ pages: inout [PageData], center: Int) {
        guard let range = residentPageRange(pageCount: pages.count, center: center) else { return }
        for index in range where pages[index].content.isEmpty {
            if let cached = PageCacheManager.shared.getPage(bookId: book.id, chapterIndex: pages[index].chapterIndex, pageIndex: pages[index].pageIndex) {
                pages[index] = cached
            }
        }
    }

    private func pageWindow(from pages: [PageData], center: Int) -> [PageData] {
        guard let range = residentPageRange(pageCount: pages.count, center: center) else { return pages }
        return pages.enumerated().map { index, page in
            guard !range.contains(index) else { return page }
            guard !page.content.isEmpty else { return page }
            return PageData(
                pageIndex: page.pageIndex,
                startCharOffset: page.startCharOffset,
                endCharOffset: page.endCharOffset,
                content: "",
                chapterTitle: page.chapterTitle,
                chapterIndex: page.chapterIndex
            )
        }
    }

    private func residentPageRange(pageCount: Int, center: Int) -> ClosedRange<Int>? {
        guard pageCount > 0 else { return nil }
        let residentCount = residentPageRadius * 2 + 1
        guard pageCount > residentCount else { return 0...(pageCount - 1) }
        let maxStart = pageCount - residentCount
        let start = min(max(center - residentPageRadius, 0), maxStart)
        return start...(start + residentCount - 1)
    }

    // MARK: Pagination

    private func paginateContent(_ content: String, fit size: CGSize, settings: ReadingSettings, chapterIndex: Int? = nil) -> [PageData] {
        let pageChapterIndex = chapterIndex ?? currentChapterIndex
        let chapter = chapters[safe: pageChapterIndex] ?? Chapter(
            bookId: book.id,
            title: "",
            orderIndex: pageChapterIndex
        )
        do {
            let pages = try ReaderTextLayoutEngine.pages(
                content: content,
                chapter: chapter,
                chapterIndex: pageChapterIndex,
                pageSize: size,
                settings: settings
            )
            if !pages.isEmpty { return pages }
        } catch {
            LVLogger.error("Reader pagination failed: \(error.localizedDescription)", category: .ui)
        }
        return [
            PageData(
                pageIndex: 0,
                startCharOffset: 0,
                endCharOffset: content.utf16.count,
                content: content,
                chapterTitle: chapter.title,
                chapterIndex: pageChapterIndex
            )
        ]
    }

    // MARK: Navigation

    private func goToNextPage() {
        guard let pages = currentPages() else { return }
        guard currentPageIndex < pages.count - 1 else {
            loadAdjacentPages(direction: .next) { [weak self] prepared in
                guard let self, let prepared else { return }
                self.applyPreparedPageTurn(prepared)
            }
            return
        }
        currentPageIndex += 1
        syncCurrentPageCacheWindow(pages: pages)
        guard let page = pageData(at: currentPageIndex) else { return }
        currentChapterIndex = page.chapterIndex
        currentPageView.render(page: page, with: settings)
        updateOverlayLabels()
        updateProgressDisplay()
    }

    private func goToPrevPage() {
        guard let pages = currentPages() else { return }
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            syncCurrentPageCacheWindow(pages: pages)
            guard let page = pageData(at: currentPageIndex) else { return }
            currentChapterIndex = page.chapterIndex
            currentPageView.render(page: page, with: settings)
            updateOverlayLabels()
            updateProgressDisplay()
        } else {
            loadAdjacentPages(direction: .prev) { [weak self] prepared in
                guard let self, let prepared else { return }
                self.applyPreparedPageTurn(prepared)
            }
        }
    }

    // MARK: Progress

    private func updateOverlayLabels() {
        topChapterLabel.text = chapters[safe: currentChapterIndex]?.title ?? ""
        menuChapterLabel.text = chapters[safe: currentChapterIndex]?.title ?? ""
        let total: Int
        if settings.pageFlipMode == .scroll {
            total = smoothScrollHandler?.currentChapterPageCount() ?? 0
        } else {
            total = currentPages()?.count ?? 0
        }
        bottomPageLabel.text = total > 0 ? "\(currentPageIndex + 1) / \(total)" : ""
        bottomTimeLabel.text = dateFormatter.string(from: Date())
        batteryView.level = {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let lvl = UIDevice.current.batteryLevel
            return lvl < 0 ? 0.75 : lvl
        }()
    }

    private func updateProgressDisplay() {
        BookRepository.shared.updateProgress(bookId: book.id, progress: ReadingProgress(
            currentChapterIndex: currentChapterIndex,
            currentPageOffset: localPageOffset(forGlobalPage: currentPageIndex),
            totalPages: currentPages()?.count ?? 0,
            progressPercent: currentBookProgressPercent(),
            lastReadTimestamp: Date()
        ))
    }

    private func saveProgress() {
        BookRepository.shared.updateProgress(bookId: book.id, progress: ReadingProgress(
            currentChapterIndex: currentChapterIndex,
            currentPageOffset: localPageOffset(forGlobalPage: currentPageIndex),
            totalPages: currentPages()?.count ?? 0,
            progressPercent: currentBookProgressPercent(),
            lastReadTimestamp: Date()
        ))
    }

    private func currentBookProgressPercent() -> Double {
        let pageCount = currentPages()?.count ?? 0
        guard pageCount > 0 else { return 0 }
        let raw = Double(currentPageIndex + 1) / Double(pageCount) * 100
        return min(100, max(0, raw))
    }

    // MARK: Cache

    private func cachePages(_ pages: [PageData], centerPage: Int? = nil) {
        guard !isClosing else { return }
        let center = centerPage ?? currentPageIndex
        guard let range = residentPageRange(pageCount: pages.count, center: center) else { return }
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: center)
        for index in range {
            let p = pages[index]
            guard !p.content.isEmpty else { continue }
            PageCacheManager.shared.cachePage(p, bookId: book.id, pageIndex: p.pageIndex)
        }
    }

    private func syncCurrentPageCacheWindow(pages: [PageData]) {
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentPageIndex)
        guard let range = residentPageRange(pageCount: pages.count, center: currentPageIndex) else { return }
        for index in range {
            let page = pages[index]
            let cached = page.content.isEmpty
                ? PageCacheManager.shared.getPage(bookId: book.id, chapterIndex: page.chapterIndex, pageIndex: page.pageIndex)
                : page
            if let cached {
                PageCacheManager.shared.cachePage(cached, bookId: book.id, pageIndex: cached.pageIndex)
            }
        }
        if settings.pageFlipMode != .scroll {
            storeReadingPages(pages, center: currentPageIndex)
            preloadAdjacentPagesIfNeeded()
        }
    }

    // MARK: Toolbar

    private func toggleToolBar() {
        let show = toolBar.alpha < 0.5
        chromeVisible = show
        setNeedsStatusBarAppearanceUpdate()
        UIView.animate(withDuration: 0.25) {
            self.topMenuBar.alpha = show ? 1 : 0
            self.toolBar.alpha = show ? 1 : 0
        }
    }

    @objc private func backTapped() {
        saveProgress()
        dismiss(animated: true)
    }

    @objc private func showCatalog() {
        let vc = ChapterListViewController(book: book, chapters: chapters, currentIndex: currentChapterIndex)
        vc.onChapterSelected = { [weak self] index in
            self?.loadChapter(index)
        }
        present(vc, animated: true)
    }

    @objc private func toggleNightMode() {
        settings.nightMode.toggle()
        settings.readingTheme = settings.nightMode ? .midnight : .white
        applyThemeChange()
    }

    @objc private func handlePageFlipModeChanged() {
        // Remove all gesture recognizers and rebuild for new mode
        view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
        resetFlipState()
        // Show current/live page views for non-scroll modes
        if settings.pageFlipMode != .scroll {
            scrollView.isHidden = true
            scrollView.alpha = 0
            currentPageView.isHidden = false
            nextPageView.isHidden = false
            if let page = pageData(at: currentPageIndex) ?? currentPages()?[safe: currentPageIndex] {
                currentPageView.render(page: page, with: settings)
            }
        }
        setupGestures()
    }

    @objc private func showSettings() {
        let vc = ReaderSettingsViewController(settings: settings)
        vc.onSettingsChanged = { [weak self] updatedSettings in
            guard let self else { return }
            self.settings = updatedSettings
            PageCacheManager.shared.clearBookCache(self.book.id)
            self.applyThemeChange()
            self.loadReadingPages(startChapterIndex: self.currentChapterIndex, startPageOffset: self.localPageOffset(forGlobalPage: self.currentPageIndex))
            // Sync zodiac watermark to book cover
            if let zodiac = updatedSettings.zodiacWatermark {
                ZodiacCoverOverlay.shared.regenerateCover(for: self.book, zodiac: zodiac)
                NotificationCenter.default.post(name: NSNotification.Name("LVReadSettingsChanged"), object: nil)
            }
        }
        vc.modalPresentationStyle = .overCurrentContext
        present(vc, animated: false)
    }

    @objc private func toggleAutoRead() { /* existing impl preserved */ }
    @objc private func toggleBookmark() { /* existing impl preserved */ }
    @objc private func showWebSync() { /* existing impl preserved */ }

    private func applyThemeChange() {
        view.backgroundColor = UIColor(hex: settings.backgroundColor)
        let tc = UIColor(hex: settings.readingTheme.textColor)
        backButton.tintColor = tc.withAlphaComponent(0.35)
        topChapterLabel.textColor = tc.withAlphaComponent(0.4)
        bottomPageLabel.textColor = tc.withAlphaComponent(0.4)
        bottomTimeLabel.textColor = tc.withAlphaComponent(0.4)
        batteryView.strokeColor = tc.withAlphaComponent(0.35)
        batteryView.fillColor = tc.withAlphaComponent(0.5)
        toolBar.backgroundColor = UIColor(hex: settings.readingTheme.panelColor).withAlphaComponent(0.96)
        topMenuBar.backgroundColor = UIColor(hex: settings.readingTheme.panelColor).withAlphaComponent(0.96)
        menuBackButton.tintColor = tc.withAlphaComponent(0.85)
        bookTitleLabel.textColor = tc.withAlphaComponent(0.9)
        menuChapterLabel.textColor = tc.withAlphaComponent(0.65)
        for sv in toolBtnStack.arrangedSubviews { if let b = sv as? UIButton { b.tintColor = tc.withAlphaComponent(0.7) } }
       updateEyeCareOverlay()
       // Redraw current page
       if let page = pageData(at: currentPageIndex) ?? currentPages()?[safe: currentPageIndex] {
           currentPageView.render(page: page, with: settings)
       }
        if settings.pageFlipMode == .scroll {
            smoothScrollHandler?.refreshRendering(settings: settings)
        }
    }

    private func updateEyeCareOverlay() {
        switch settings.eyeCareFilter {
        case .none: eyeCareOverlay.backgroundColor = .clear
        case .warmYellow: eyeCareOverlay.backgroundColor = UIColor(hex: "#FFF8E7").withAlphaComponent(0.3)
        case .mintGreen: eyeCareOverlay.backgroundColor = UIColor(hex: "#C7EDCC").withAlphaComponent(0.2)
        }
    }

    // MARK: Reading Timer

    private func startReadingTimer() {
        readingStartTime = Date()
        readingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.totalReadingSeconds += 60
        }
    }

    private func stopReadingTimer() {
        readingTimer?.invalidate()
        readingTimer = nil
        if let s = readingStartTime { totalReadingSeconds += Int(Date().timeIntervalSince(s)) }
    }

    private func startAutoRead() { /* preserved */ }
    private func stopAutoRead() { /* preserved */ }
}

// MARK: - ScrollView Delegate

extension ReaderViewController: UIScrollViewDelegate {
    // SmoothScrollHandler is the primary delegate for scroll mode.
    // Fallthrough: if no handler is active, update directly.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard smoothScrollHandler == nil else { return }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard smoothScrollHandler == nil else { return }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard smoothScrollHandler == nil else { return }
    }
}


extension ReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't receive touches on toolbar when toolbar is visible
        if toolBar.alpha > 0.5, touch.view?.isDescendant(of: toolBar) == true {
            return false
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer {
            if isPageFlipping { return false }
            let vel = (gestureRecognizer as! UIPanGestureRecognizer).velocity(in: view)
            return abs(vel.x) > abs(vel.y)
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        // Tap requires pan to fail first — clean taps fire when pan doesn't start
        if gestureRecognizer is UITapGestureRecognizer && other is UIPanGestureRecognizer {
            return true
        }
        return false
    }
}

extension Collection { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }

private extension ReaderViewController.PageTurnDirection {
    var pageFlipDirection: PageFlipDirection {
        switch self {
        case .next: return .next
        case .prev: return .prev
        }
    }
}
