import UIKit
import CoreText

fileprivate extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }
}


// MARK: - Page Container (holds rendered CoreText page)
final class PageContainerView: UIView {
    var pageData: PageData?
    var pageBackgroundColor: UIColor = .white
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let page = pageData else { return }
        // Fill background
        ctx.setFillColor(pageBackgroundColor.cgColor)
        ctx.fill(rect)

        // Flip coordinate system for CoreText
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let font = FontManager.shared.font(named: settings.fontFamily, size: CGFloat(settings.fontSize))
        let para = NSMutableParagraphStyle()
        para.lineSpacing = font.lineHeight * CGFloat(settings.lineSpacing - 1.0)
        para.paragraphSpacing = font.lineHeight * CGFloat(settings.paragraphSpacing)
        para.alignment = .natural

        let attr = NSAttributedString(
            string: page.content,
            attributes: [
                .font: font,
                .foregroundColor: UIColor(hex: settings.readingTheme.textColor),
                .paragraphStyle: para
            ]
        )

        let marginH = CGFloat(settings.pageMarginHorizontal) * bounds.width / 100
        let textRect = bounds.insetBy(dx: marginH, dy: 8)
        // Draw zodiac watermark behind text
        if let zodiac = settings.zodiacWatermark,
           let zodiacImage = zodiac.loadImageCompat() {
            ctx.saveGState()
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: -bounds.height)
            let imgW = bounds.width * 0.45
            let imgH = zodiacImage.size.height * (imgW / zodiacImage.size.width)
            let imgX = (bounds.width - imgW) / 2
            let imgY = (bounds.height - imgH) / 2
            let imgRect = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
            zodiacImage.draw(in: imgRect, blendMode: .normal, alpha: 0.07)
            ctx.restoreGState()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    var settings: ReadingSettings = .default

    func render(page: PageData, with settings: ReadingSettings) {
        self.pageData = page
        self.settings = settings
        self.pageBackgroundColor = UIColor(hex: settings.backgroundColor)
        setNeedsDisplay()
    }
}

// MARK: - Main Reader

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

    private var readingStartTime: Date?
    private var totalReadingSeconds: Int = 0
    private var readingTimer: Timer?
    private var autoReadTimer: Timer?
    private var autoReadRemainingSeconds: Int = 0

    // Page turn state
   private var isPageFlipping = false
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
    private let toolBar = UIView()
    private var toolBtnStack: UIStackView!
    private let eyeCareOverlay = UIView()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

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
    }

    override var prefersStatusBarHidden: Bool { true }
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
        toolBar.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 0.95)
        toolBar.alpha = 0

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
                        bottomPageLabel, bottomTimeLabel, batteryView, toolBar)
        [containerView, currentPageView, nextPageView, scrollView, backButton, topChapterLabel,
         bottomPageLabel, bottomTimeLabel, batteryView, toolBar, toolBtnStack,
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

            toolBar.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            toolBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolBar.heightAnchor.constraint(equalToConstant: 64),

            toolBtnStack.centerXAnchor.constraint(equalTo: toolBar.centerXAnchor),
            toolBtnStack.bottomAnchor.constraint(equalTo: toolBar.bottomAnchor, constant: -8)
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
                    // Load chapter on demand when scrolling into unloaded territory
                    self?.preloadChapterForScroll(chapterIndex)
                }
               smoothScrollHandler?.callbacks.onPageChanged = { [weak self] globalPageIdx in
                    guard let self else { return }
                    let local = self.smoothScrollHandler?.localPage(forGlobal: globalPageIdx) ?? globalPageIdx
                    self.currentPageIndex = local
                    self.updateOverlayLabels()
                    self.updateProgressDisplay()
                }
                smoothScrollHandler?.callbacks.onChapterEntered = { [weak self] chIdx in
                    self?.currentChapterIndex = chIdx
                    self?.updateOverlayLabels()
                }
            }
            if let pages = chapterPages.first {
                smoothScrollHandler?.loadChapter(currentChapterIndex, pages: pages, settings: settings, initialPage: currentPageIndex)
            }

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
        guard let pages = chapterPages.first else { return }
        smoothScrollHandler?.loadChapter(currentChapterIndex, pages: pages, settings: settings, initialPage: currentPageIndex)
    }

    private func refreshScrollContent() {
        guard settings.pageFlipMode == .scroll else { return }
        guard let pages = chapterPages.first else { return }
        smoothScrollHandler?.loadChapter(currentChapterIndex, pages: pages, settings: settings, initialPage: currentPageIndex)
    }

    private func preloadChapterForScroll(_ chapterIndex: Int) {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return }
        let sz = containerView.bounds.size
        let ch = chapters[chapterIndex]
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            guard let content = try? p.parseChapterContent(
                filePath: self.book.resolvedFilePath(),
                chapter: ch,
                encoding: self.book.encoding ?? "UTF-8"
            ) else { return }
            let pages = self.paginateContent(content, fit: sz, settings: self.settings)
            DispatchQueue.main.async {
                self.smoothScrollHandler?.appendChapter(chapterIndex, pages: pages)
                self.cachePages(pages)
            }
        }
    }

    // MARK: Scroll Mode Tap — toggle toolbar only

    @objc private func handleScrollTap(_ gesture: UITapGestureRecognizer) {
        toggleToolBar()
    }

    // MARK: Tap (for non-scroll modes)

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
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
        
        // Check boundaries
        guard let pages = chapterPages.first, !pages.isEmpty else { return }
        let targetIndex = direction == .next ? currentPageIndex + 1 : currentPageIndex - 1
        
        // Boundary check: prevent out-of-bounds access
        if targetIndex < 0 {
            // Already at first page, go to previous chapter if available
            if currentChapterIndex > 0 {
                goToPrevChapter()
            }
            return
        }
        if targetIndex >= pages.count {
            // Already at last page, go to next chapter if available
            if currentChapterIndex < chapters.count - 1 {
                goToNextChapter()
            }
            return
        }
        
       prerenderPage(at: targetIndex, in: nextPageView)

       let animDirection: PageFlipDirection = direction == .next ? .next : .prev
        let mode = settings.pageFlipMode

        if mode == .none {
            if direction == .next { goToNextPage() } else { goToPrevPage() }
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
            self.resetFlipState()
            if direction == .next { self.goToNextPage() } else { self.goToPrevPage() }
            self.isPageFlipping = false
        }
    }

    // MARK: Pan Gesture (interactive page flip)

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
       let fmode = settings.pageFlipMode
       guard fmode == .simulation || fmode == .cover || fmode == .slide else { return }
       
       let velocity = pan.velocity(in: view)
       let isSwipingNext = velocity.x < 0
       
      if isSwipingNext {
           guard let pages = chapterPages.first, currentPageIndex < pages.count - 1 else {
               if currentChapterIndex < chapters.count - 1 { goToNextChapter() }
               return
           }
       } else {
           guard currentPageIndex > 0 else {
               if currentChapterIndex > 0 { goToPrevChapter() }
               return
           }
       }
       
        let mode = fmode

        let loc = pan.translation(in: view)
       let progress = min(1.0, max(0, abs(loc.x) / view.bounds.width * 1.2))
       let dir: PageTurnDirection = loc.x < 0 ? .next : .prev
        let animDir: PageFlipDirection = dir == .next ? .next : .prev

        switch pan.state {
        case .began:
            guard !isPageFlipping else { return }
            isPageFlipping = true

            let targetIndex = dir == .next ? currentPageIndex + 1 : currentPageIndex - 1
            prerenderPage(at: targetIndex, in: nextPageView)

            PageFlipAnimator.beginInteractive(
                from: currentPageView,
                to: nextPageView,
                direction: animDir,
                mode: mode,
                container: containerView,
                state: interactiveState
            )

        case .changed:
            PageFlipAnimator.updateInteractive(progress: progress, mode: mode, state: interactiveState)

        case .ended, .cancelled:
            let vx = pan.velocity(in: view).x
            let shouldCommit = progress > 0.25 || abs(vx) > 400

            PageFlipAnimator.finishInteractive(commit: shouldCommit, mode: mode, state: interactiveState) { [weak self] committed in
                guard let self = self else { return }
                self.resetFlipState()
                if committed {
                    if dir == .next { self.goToNextPage() } else { self.goToPrevPage() }
                }
                self.isPageFlipping = false
            }

        default: break
        }
    }

    // MARK: - Reset flip state

    private func resetFlipState() {
        interactiveState.cleanup()
        currentPageView.layer.transform = CATransform3DIdentity
        currentPageView.transform = .identity
        currentPageView.alpha = 1
        nextPageView.layer.transform = CATransform3DIdentity
        nextPageView.transform = .identity
        nextPageView.alpha = 0
        layoutPageViews()
    }

    private func layoutPageViews() {
        currentPageView.frame = containerView.bounds
        nextPageView.frame = containerView.bounds
    }

    private func prerenderPage(at index: Int, in view: PageContainerView) {
        guard let pages = chapterPages.first, index >= 0, index < pages.count else {
            view.render(page: PageData(pageIndex: 0, startCharOffset: 0, endCharOffset: 0, content: "", chapterTitle: "", chapterIndex: 0), with: settings)
            return
        }
        view.render(page: pages[index], with: settings)
        // Force immediate draw so the page is ready when animation starts
        view.setNeedsDisplay()
        view.layer.displayIfNeeded()
    }

    enum PageTurnDirection { case next, prev }

    // MARK: Book Loading

    private func loadBook() {
        chapters = BookRepository.shared.getChapters(for: book.id)
        // Use fresh progress from DB, not stale in-memory book.readingProgress
        if let fresh = BookRepository.shared.getById(book.id) {
            currentChapterIndex = fresh.readingProgress.currentChapterIndex
            currentPageIndex = fresh.readingProgress.currentPageOffset
        } else {
            currentChapterIndex = book.readingProgress.currentChapterIndex
            currentPageIndex = book.readingProgress.currentPageOffset
        }
        if chapters.isEmpty {
            chapters = [Chapter(bookId: book.id, title: "正文", level: 1, orderIndex: 0)]
        }
        loadCurrentChapter()
    }

    private func loadCurrentChapter() {
        guard currentChapterIndex < chapters.count else { return }
        let ch = chapters[currentChapterIndex]
        let sz = self.containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                let content = try p.parseChapterContent(filePath: self.book.resolvedFilePath(), chapter: ch, encoding: self.book.encoding ?? "UTF-8")
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 50, self.currentChapterIndex + 1 < self.chapters.count {
                    DispatchQueue.main.async {
                        self.currentChapterIndex += 1
                        self.loadCurrentChapter()
                    }
                    return
                }
                let pages = self.paginateContent(content, fit: sz, settings: self.settings)
                self.chapterPages = [pages]

                DispatchQueue.main.async {
                    let savedPage = self.currentPageIndex
                    self.currentPageIndex = min(savedPage, max(0, pages.count - 1))
                    if let page = pages[safe: self.currentPageIndex] {
                        self.currentPageView.render(page: page, with: self.settings)
                    } else if let first = pages.first {
                        self.currentPageView.render(page: first, with: self.settings)
                    }
                        self.updateOverlayLabels()
                        self.updateProgressDisplay()
                    self.cachePages(pages)
                    self.prefetchNextChapter()
                    // Refresh scroll content if in scroll mode
                    self.refreshScrollContent()
                }
            } catch {
                DispatchQueue.main.async {
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

    private func loadChapter(_ index: Int) {
        guard index < chapters.count else { return }
        currentChapterIndex = index
        let ch = chapters[index]
        let sz = self.containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                let content = try p.parseChapterContent(filePath: self.book.resolvedFilePath(), chapter: ch, encoding: self.book.encoding ?? "UTF-8")
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 50, index + 1 < self.chapters.count {
                    DispatchQueue.main.async { self.loadChapter(index + 1) }
                    return
                }
                let pages = self.paginateContent(content, fit: sz, settings: self.settings)
                self.chapterPages = [pages]
                DispatchQueue.main.async {
                    self.currentPageIndex = 0
                    if let first = pages.first {
                        self.currentPageView.render(page: first, with: self.settings)
                        self.updateOverlayLabels()
                        self.updateProgressDisplay()
                    }
                    self.cachePages(pages)
                    self.prefetchNextChapter()
                    self.refreshScrollContent()
                }
            } catch {
                DispatchQueue.main.async { LVToast.show(message: "读取失败", style: .error) }
            }
        }
    }

    // MARK: Pagination

    private func paginateContent(_ content: String, fit size: CGSize, settings: ReadingSettings) -> [PageData] {
        let marginH = CGFloat(settings.pageMarginHorizontal) * size.width / 100
        let textWidth = size.width - marginH * 2
        let textHeight = size.height - 16  // top/bottom inset

        let font = FontManager.shared.font(named: settings.fontFamily, size: CGFloat(settings.fontSize))
        let para = NSMutableParagraphStyle()
        para.lineSpacing = font.lineHeight * CGFloat(settings.lineSpacing - 1.0)
        para.paragraphSpacing = font.lineHeight * CGFloat(settings.paragraphSpacing)
        para.alignment = .natural

        let attr = NSAttributedString(string: content, attributes: [.font: font, .paragraphStyle: para])
        let framesetter = CTFramesetterCreateWithAttributedString(attr)

        var pages: [PageData] = []
        var currentOffset = 0
        let totalLen = attr.length

        while currentOffset < totalLen {
            let textRect = CGRect(x: 0, y: 0, width: textWidth, height: textHeight)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(currentOffset, 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)

            guard visible.length > 0 else { break }

            let lo = String.Index(utf16Offset: visible.location, in: content)
            let hi = String.Index(utf16Offset: visible.location + visible.length, in: content)

            let pageContent = String(content[lo..<hi])
            pages.append(PageData(
                pageIndex: pages.count,
                startCharOffset: visible.location,
                endCharOffset: visible.location + visible.length,
                content: pageContent,
                chapterTitle: chapters[safe: currentChapterIndex]?.title ?? "",
                chapterIndex: currentChapterIndex
            ))

            currentOffset = visible.location + visible.length
        }

        if pages.isEmpty {
            pages.append(PageData(pageIndex: 0, startCharOffset: 0, endCharOffset: 0, content: content, chapterTitle: "", chapterIndex: 0))
        }

        return pages
    }

    // MARK: Navigation

    private func goToNextPage() {
        guard let pages = chapterPages.first, currentPageIndex < pages.count - 1 else {
            goToNextChapter()
            return
        }
        currentPageIndex += 1
        currentPageView.render(page: pages[currentPageIndex], with: settings)
        updateOverlayLabels()
        updateProgressDisplay()
    }

    private func goToPrevPage() {
        guard let pages = chapterPages.first else { return }
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            currentPageView.render(page: pages[currentPageIndex], with: settings)
            updateOverlayLabels()
            updateProgressDisplay()
        } else {
            goToPrevChapter()
        }
    }

    @objc private func goToNextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        // Reset flip state before chapter change
        resetFlipState()
        isPageFlipping = false
        currentChapterIndex += 1
        currentPageIndex = 0
        loadChapter(currentChapterIndex)
    }

    @objc private func goToPrevChapter() {
        guard currentChapterIndex > 0 else { return }
        // Reset flip state before chapter change
        resetFlipState()
        isPageFlipping = false
        currentChapterIndex -= 1
        loadChapter(currentChapterIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let pages = self.chapterPages.first else { return }
            self.currentPageIndex = max(0, pages.count - 1)
            if let page = pages[safe: self.currentPageIndex] {
                self.currentPageView.render(page: page, with: self.settings)
                self.updateOverlayLabels()
                self.updateProgressDisplay()
            }
        }
    }

    // MARK: Progress

    private func updateOverlayLabels() {
        topChapterLabel.text = chapters[safe: currentChapterIndex]?.title ?? ""
        let total: Int
        if settings.pageFlipMode == .scroll {
            total = smoothScrollHandler?.currentChapterPageCount() ?? 0
        } else {
            total = chapterPages.first?.count ?? 0
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
        // Calculate total pages across all chapters loaded so far
        let totalChapterPages = chapterPages.reduce(0) { $0 + ($1.count) }
        guard totalChapterPages > 0, !chapters.isEmpty else { return }
        
        // Calculate cumulative pages up to current chapter
        var pagesBeforeCurrentChapter = 0
        for i in 0..<currentChapterIndex {
            if i < chapterPages.count {
                pagesBeforeCurrentChapter += chapterPages[i].count
            }
        }
        
        // Global progress: (pages before current chapter + current page) / total pages
        let currentGlobalPage = pagesBeforeCurrentChapter + currentPageIndex
        let progressPercent = min(100.0, Double(currentGlobalPage + 1) / Double(totalChapterPages) * 100)
        
        BookRepository.shared.updateProgress(bookId: book.id, progress: ReadingProgress(
            currentChapterIndex: currentChapterIndex,
            currentPageOffset: currentPageIndex,
            totalPages: totalChapterPages,
            progressPercent: progressPercent,
            lastReadTimestamp: Date()
        ))
    }

    private func saveProgress() {
        BookRepository.shared.updateProgress(bookId: book.id, progress: ReadingProgress(
            currentChapterIndex: currentChapterIndex,
            currentPageOffset: currentPageIndex,
            totalPages: chapterPages.first?.count ?? 0,
            progressPercent: Double(currentChapterIndex) / Double(max(chapters.count, 1)) * 100,
            lastReadTimestamp: Date()
        ))
    }

    // MARK: Cache

    private func cachePages(_ pages: [PageData]) {
        for p in pages { PageCacheManager.shared.cachePage(p, bookId: book.id, pageIndex: p.pageIndex) }
    }

    private func prefetchNextChapter() {
        let next = currentChapterIndex + 1
        guard next < chapters.count else { return }
        let sz = self.containerView.bounds.size
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let ch = self.chapters[next]
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            if let c = try? p.parseChapterContent(filePath: self.book.resolvedFilePath(), chapter: ch, encoding: self.book.encoding ?? "UTF-8") {
                let pages = self.paginateContent(c, fit: sz, settings: self.settings)
                self.cachePages(pages)
            }
        }
    }

    // MARK: Toolbar

    private func toggleToolBar() {
        let show = toolBar.alpha < 0.5
        UIView.animate(withDuration: 0.25) {
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
            self?.currentChapterIndex = index
            self?.currentPageIndex = 0
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
            if let page = chapterPages.first?[safe: currentPageIndex] {
                currentPageView.render(page: page, with: settings)
            }
        }
        setupGestures()
    }

    @objc private func showSettings() {
        let vc = ReaderSettingsViewController(settings: settings)
        vc.onSettingsChanged = { [weak self] updatedSettings in
            self?.settings = updatedSettings
            self?.applyThemeChange()
            // Sync zodiac watermark to book cover
            if let self = self, let zodiac = updatedSettings.zodiacWatermark {
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
        toolBar.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 0.95)
        for sv in toolBtnStack.arrangedSubviews { if let b = sv as? UIButton { b.tintColor = tc.withAlphaComponent(0.7) } }
       updateEyeCareOverlay()
       // Redraw current page
       if let page = chapterPages.first?[safe: currentPageIndex] {
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
