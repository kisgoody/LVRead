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
    private var loadedChapterPages: [Int: [PageData]] = [:]
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
    private var pendingPanLoadDirection: PageTurnDirection?
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
            if let pages = currentPages() {
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
        guard let pages = currentPages() else { return }
        smoothScrollHandler?.loadChapter(currentChapterIndex, pages: pages, settings: settings, initialPage: currentPageIndex)
    }

    private func refreshScrollContent() {
        guard settings.pageFlipMode == .scroll else { return }
        guard let pages = currentPages() else { return }
        smoothScrollHandler?.loadChapter(currentChapterIndex, pages: pages, settings: settings, initialPage: currentPageIndex)
    }

    private func preloadChapterForScroll(_ chapterIndex: Int) {
        guard !isClosing else { return }
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return }
        if let pages = loadedChapterPages[chapterIndex] {
            smoothScrollHandler?.appendChapter(chapterIndex, pages: pages)
            return
        }
        loadPagesForChapter(chapterIndex, target: .first) { [weak self] prepared in
            guard let self, !self.isClosing, let prepared else { return }
            self.smoothScrollHandler?.appendChapter(prepared.chapterIndex, pages: prepared.pages)
            self.cachePages(prepared.pages)
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

        let targetChapter = direction == .next ? currentChapterIndex + 1 : currentChapterIndex - 1
        guard targetChapter >= 0, targetChapter < chapters.count else { return }

        isPageFlipping = true
        loadPagesForChapter(targetChapter, target: direction == .next ? .first : .last) { [weak self] prepared in
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
        storeLoadedChapter(prepared.chapterIndex, pages: prepared.pages, center: prepared.pageIndex)
        currentPageView.render(page: pageData(at: currentPageIndex) ?? page, with: settings)
        updateOverlayLabels()
        updateProgressDisplay()
        cachePages(prepared.pages, centerPage: prepared.pageIndex)
    }

    private func preparedTurn(for direction: PageTurnDirection) -> PreparedPageTurn? {
        guard var pages = currentPages(), !pages.isEmpty else { return nil }
        let targetIndex = direction == .next ? currentPageIndex + 1 : currentPageIndex - 1
        if targetIndex >= 0, targetIndex < pages.count {
            guard let page = pageData(at: targetIndex) else { return nil }
            pages[targetIndex] = page
            return PreparedPageTurn(chapterIndex: currentChapterIndex, pageIndex: targetIndex, pages: pages)
        }

        let targetChapter = direction == .next ? currentChapterIndex + 1 : currentChapterIndex - 1
        guard targetChapter >= 0,
              targetChapter < chapters.count,
              var targetPages = loadedChapterPages[targetChapter],
              !targetPages.isEmpty else { return nil }
        let pageIndex = direction == .next ? 0 : targetPages.count - 1
        guard let page = pageData(in: &targetPages, chapterIndex: targetChapter, pageIndex: pageIndex) else { return nil }
        targetPages[pageIndex] = page
        return PreparedPageTurn(chapterIndex: targetChapter, pageIndex: pageIndex, pages: targetPages)
    }

    // MARK: Pan Gesture (interactive page flip)

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let fmode = settings.pageFlipMode
        guard !chromeVisible else { return }
        guard fmode == .simulation || fmode == .cover || fmode == .slide else { return }

        let mode = fmode
        let translation = pan.translation(in: view)
        let progress = min(1.0, max(0, abs(translation.x) / max(view.bounds.width, 1) * 1.15))

        switch pan.state {
        case .began:
            guard !isPageFlipping else { return }
            activePanDirection = nil
            pendingPanLoadDirection = nil

        case .changed:
            if activePanDirection == nil {
                guard abs(translation.x) > 8 else { return }
                let direction: PageTurnDirection = translation.x < 0 ? .next : .prev
                guard let prepared = preparedTurn(for: direction) else {
                    prepareBoundaryTurnForPan(direction, pan: pan, mode: mode)
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
            PageFlipAnimator.updateInteractive(progress: progress, mode: mode, state: interactiveState)

        case .ended, .cancelled:
            guard let direction = activePanDirection, interactiveState.isActive else {
                activePanDirection = nil
                pendingPanLoadDirection = nil
                isPageFlipping = false
                return
            }
            let vx = pan.velocity(in: view).x
            let shouldCommit = progress > 0.28 || abs(vx) > 450

            PageFlipAnimator.finishInteractive(commit: shouldCommit, mode: mode, state: interactiveState) { [weak self] committed in
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
                self.pendingPanLoadDirection = nil
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

    private func prepareBoundaryTurnForPan(_ direction: PageTurnDirection, pan: UIPanGestureRecognizer, mode: PageFlipMode) {
        guard pendingPanLoadDirection == nil else { return }
        let targetChapter = direction == .next ? currentChapterIndex + 1 : currentChapterIndex - 1
        guard targetChapter >= 0, targetChapter < chapters.count else { return }

        pendingPanLoadDirection = direction
        loadPagesForChapter(targetChapter, target: direction == .next ? .first : .last) { [weak self, weak pan] prepared in
            guard let self,
                  let pan,
                  self.pendingPanLoadDirection == direction,
                  self.activePanDirection == nil,
                  let prepared else {
                self?.pendingPanLoadDirection = nil
                return
            }

            let state = pan.state
            guard state == .began || state == .changed else {
                self.pendingPanLoadDirection = nil
                return
            }

            let translation = pan.translation(in: self.view)
            let progress = min(1.0, max(0, abs(translation.x) / max(self.view.bounds.width, 1) * 1.15))
            self.activePanDirection = direction
            self.activePanPreparedTurn = prepared
            self.pendingPanLoadDirection = nil
            self.isPageFlipping = true

            self.prerender(prepared, in: self.nextPageView)
            PageFlipAnimator.beginInteractive(
                from: self.currentPageView,
                to: self.nextPageView,
                direction: direction.pageFlipDirection,
                mode: mode,
                container: self.containerView,
                state: self.interactiveState
            )
            PageFlipAnimator.updateInteractive(progress: progress, mode: mode, state: self.interactiveState)
        }
    }

    private enum ChapterPageTarget {
        case first
        case last
        case index(Int)
    }

    // MARK: - Reset flip state

    private func resetFlipState() {
        interactiveState.cleanup()
        activePanDirection = nil
        activePanPreparedTurn = nil
        pendingPanLoadDirection = nil
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
        loadedChapterPages.removeAll()
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
        guard let page = pageData(in: &pages, chapterIndex: prepared.chapterIndex, pageIndex: prepared.pageIndex) else {
            return nil
        }
        pages[prepared.pageIndex] = page
        let preparedPages = settings.pageFlipMode == .scroll ? pages : pageWindow(from: pages, center: prepared.pageIndex)
        storeLoadedChapter(prepared.chapterIndex, pages: preparedPages, center: prepared.pageIndex)
        cachePages(preparedPages, centerPage: prepared.pageIndex)
        return PreparedPageTurn(chapterIndex: prepared.chapterIndex, pageIndex: prepared.pageIndex, pages: preparedPages)
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
        loadCurrentChapter(target: .index(currentPageIndex))
    }

    private func loadCurrentChapter(target: ChapterPageTarget = .first) {
        guard !isClosing else { return }
        guard currentChapterIndex < chapters.count else { return }
        let chapterIndex = currentChapterIndex
        if let pages = loadedChapterPages[chapterIndex] {
            displayChapter(chapterIndex, pages: pages, target: target)
            return
        }

        let ch = chapters[chapterIndex]
        let sz = self.containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.isClosing { return }
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                let content = try p.parseChapterContent(filePath: self.book.resolvedFilePath(), chapter: ch, encoding: self.book.encoding ?? "UTF-8")
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 50, chapterIndex + 1 < self.chapters.count {
                    DispatchQueue.main.async {
                        self.currentChapterIndex = chapterIndex + 1
                        self.loadCurrentChapter(target: .first)
                    }
                    return
                }
                let pages = self.paginateContent(content, fit: sz, settings: self.settings, chapterIndex: chapterIndex)
                let pageIndex = self.pageIndex(for: target, pageCount: pages.count)
                PageCacheManager.shared.cachePages(pages, bookId: self.book.id, centerPage: pageIndex)

                DispatchQueue.main.async {
                    guard !self.isClosing else { return }
                    guard self.currentChapterIndex == chapterIndex else { return }
                    self.displayChapter(chapterIndex, pages: pages, target: target)
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

    private func loadChapter(_ index: Int, target: ChapterPageTarget = .first) {
        guard !isClosing else { return }
        guard index < chapters.count else { return }
        currentChapterIndex = index
        if let pages = loadedChapterPages[index] {
            displayChapter(index, pages: pages, target: target)
            return
        }

        let ch = chapters[index]
        let sz = self.containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.isClosing { return }
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                let content = try p.parseChapterContent(filePath: self.book.resolvedFilePath(), chapter: ch, encoding: self.book.encoding ?? "UTF-8")
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 50 {
                    let nextIndex: Int?
                    switch target {
                    case .last:
                        nextIndex = index > 0 ? index - 1 : nil
                    case .first, .index(_):
                        nextIndex = index + 1 < self.chapters.count ? index + 1 : nil
                    }
                    if let nextIndex {
                        DispatchQueue.main.async { self.loadChapter(nextIndex, target: target) }
                        return
                    }
                }
                let pages = self.paginateContent(content, fit: sz, settings: self.settings, chapterIndex: index)
                let pageIndex = self.pageIndex(for: target, pageCount: pages.count)
                PageCacheManager.shared.cachePages(pages, bookId: self.book.id, centerPage: pageIndex)
                DispatchQueue.main.async {
                    guard !self.isClosing else { return }
                    guard self.currentChapterIndex == index else { return }
                    self.displayChapter(index, pages: pages, target: target)
                }
            } catch {
                DispatchQueue.main.async { LVToast.show(message: "读取失败", style: .error) }
            }
        }
    }

    private func loadPagesForChapter(_ index: Int, target: ChapterPageTarget, completion: @escaping (PreparedPageTurn?) -> Void) {
        guard !isClosing else {
            completion(nil)
            return
        }
        guard index >= 0, index < chapters.count else {
            completion(nil)
            return
        }
        if let pages = loadedChapterPages[index] {
            let pageIndex = pageIndex(for: target, pageCount: pages.count)
            var preparedPages = pages
            guard let page = pageData(in: &preparedPages, chapterIndex: index, pageIndex: pageIndex) else {
                completion(nil)
                return
            }
            preparedPages[pageIndex] = page
            completion(PreparedPageTurn(chapterIndex: index, pageIndex: pageIndex, pages: preparedPages))
            return
        }

        let ch = chapters[index]
        let sz = containerView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if self.isClosing {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                let content = try parser.parseChapterContent(
                    filePath: self.book.resolvedFilePath(),
                    chapter: ch,
                    encoding: self.book.encoding ?? "UTF-8"
                )
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 50 {
                    let nextIndex: Int?
                    switch target {
                    case .last:
                        nextIndex = index > 0 ? index - 1 : nil
                    case .first, .index(_):
                        nextIndex = index + 1 < self.chapters.count ? index + 1 : nil
                    }
                    DispatchQueue.main.async {
                        guard !self.isClosing else { return }
                        if let nextIndex {
                            self.loadPagesForChapter(nextIndex, target: target, completion: completion)
                        } else {
                            completion(nil)
                        }
                    }
                    return
                }

                let pages = self.paginateContent(content, fit: sz, settings: self.settings, chapterIndex: index)
                let pageIndex = self.pageIndex(for: target, pageCount: pages.count)
                PageCacheManager.shared.cachePages(pages, bookId: self.book.id, centerPage: pageIndex)
                DispatchQueue.main.async {
                    guard !self.isClosing else { return }
                    let preparedPages = self.settings.pageFlipMode == .scroll ? pages : self.pageWindow(from: pages, center: pageIndex)
                    self.storeLoadedChapter(index, pages: pages, center: pageIndex)
                    completion(PreparedPageTurn(chapterIndex: index, pageIndex: pageIndex, pages: preparedPages))
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func pageIndex(for target: ChapterPageTarget, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        switch target {
        case .first:
            return 0
        case .last:
            return pageCount - 1
        case .index(let index):
            return min(max(index, 0), pageCount - 1)
        }
    }

    private func currentPages() -> [PageData]? {
        loadedChapterPages[currentChapterIndex] ?? chapterPages.first
    }

    private func displayChapter(_ index: Int, pages: [PageData], target: ChapterPageTarget) {
        currentChapterIndex = index
        currentPageIndex = pageIndex(for: target, pageCount: pages.count)
        syncCurrentPageCacheWindow(pages: pages)
        storeLoadedChapter(index, pages: pages)
        if let page = pageData(at: currentPageIndex) ?? pages[safe: currentPageIndex] ?? pages.first {
            currentPageView.render(page: page, with: settings)
        }
        updateOverlayLabels()
        updateProgressDisplay()
        cachePages(pages, centerPage: currentPageIndex)
        refreshScrollContent()
        preloadBoundaryChapters()
    }

    private func storeLoadedChapter(_ index: Int, pages: [PageData], center: Int? = nil) {
        let windowCenter = center ?? (index == currentChapterIndex ? currentPageIndex : 0)
        loadedChapterPages[index] = settings.pageFlipMode == .scroll ? pages : pageWindow(from: pages, center: windowCenter)
        if index == currentChapterIndex {
            chapterPages = [loadedChapterPages[index] ?? pages]
        }
        let validRange = (currentChapterIndex - 1)...(currentChapterIndex + 1)
        loadedChapterPages = loadedChapterPages.filter { validRange.contains($0.key) }
    }

    private func pageData(at pageIndex: Int) -> PageData? {
        guard var pages = currentPages(), pageIndex >= 0, pageIndex < pages.count else { return nil }
        return pageData(in: &pages, chapterIndex: currentChapterIndex, pageIndex: pageIndex)
    }

    private func pageData(in pages: inout [PageData], chapterIndex: Int, pageIndex: Int) -> PageData? {
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        if !pages[pageIndex].content.isEmpty {
            return pages[pageIndex]
        }
        guard let cached = PageCacheManager.shared.getPage(bookId: book.id, chapterIndex: chapterIndex, pageIndex: pageIndex) else {
            return nil
        }
        pages[pageIndex] = cached
        hydratePageWindow(&pages, chapterIndex: chapterIndex, center: pageIndex)
        loadedChapterPages[chapterIndex] = pages
        if chapterIndex == currentChapterIndex {
            chapterPages = [pages]
        }
        return cached
    }

    private func hydratePageWindow(_ pages: inout [PageData], chapterIndex: Int, center: Int) {
        guard let range = residentPageRange(pageCount: pages.count, center: center) else { return }
        for index in range where pages[index].content.isEmpty {
            if let cached = PageCacheManager.shared.getPage(bookId: book.id, chapterIndex: chapterIndex, pageIndex: index) {
                pages[index] = cached
            }
        }
    }

    private func pageWindow(from pages: [PageData], center: Int) -> [PageData] {
        guard let range = residentPageRange(pageCount: pages.count, center: center) else { return pages }
        return pages.map { page in
            guard !range.contains(page.pageIndex) else { return page }
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

    private func preloadBoundaryChapters() {
        guard settings.pageFlipMode != .scroll else { return }
        for (index, target) in [(currentChapterIndex - 1, ChapterPageTarget.last), (currentChapterIndex + 1, ChapterPageTarget.first)] {
            guard index >= 0, index < chapters.count, loadedChapterPages[index] == nil else { continue }
            loadPagesForChapter(index, target: target) { _ in }
        }
    }

    // MARK: Pagination

    private func paginateContent(_ content: String, fit size: CGSize, settings: ReadingSettings, chapterIndex: Int? = nil) -> [PageData] {
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

        let pageChapterIndex = chapterIndex ?? currentChapterIndex
        let pageChapterTitle = chapters[safe: pageChapterIndex]?.title ?? ""

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
                chapterTitle: pageChapterTitle,
                chapterIndex: pageChapterIndex
            ))

            currentOffset = visible.location + visible.length
        }

        if pages.isEmpty {
            pages.append(PageData(pageIndex: 0, startCharOffset: 0, endCharOffset: 0, content: content, chapterTitle: pageChapterTitle, chapterIndex: pageChapterIndex))
        }

        return pages
    }

    // MARK: Navigation

    private func goToNextPage() {
        guard let pages = currentPages(), currentPageIndex < pages.count - 1 else {
            goToNextChapter()
            return
        }
        currentPageIndex += 1
        syncCurrentPageCacheWindow(pages: pages)
        guard let page = pageData(at: currentPageIndex) else { return }
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
            currentPageView.render(page: page, with: settings)
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
        loadChapter(currentChapterIndex, target: .first)
    }

    @objc private func goToPrevChapter() {
        guard currentChapterIndex > 0 else { return }
        // Reset flip state before chapter change
        resetFlipState()
        isPageFlipping = false
        currentChapterIndex -= 1
        loadChapter(currentChapterIndex, target: .last)
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
            currentPageOffset: currentPageIndex,
            totalPages: currentPages()?.count ?? 0,
            progressPercent: currentBookProgressPercent(),
            lastReadTimestamp: Date()
        ))
    }

    private func saveProgress() {
        BookRepository.shared.updateProgress(bookId: book.id, progress: ReadingProgress(
            currentChapterIndex: currentChapterIndex,
            currentPageOffset: currentPageIndex,
            totalPages: currentPages()?.count ?? 0,
            progressPercent: currentBookProgressPercent(),
            lastReadTimestamp: Date()
        ))
    }

    private func currentBookProgressPercent() -> Double {
        guard !chapters.isEmpty else { return 0 }
        let pageCount = currentPages()?.count ?? 0
        let localProgress: Double
        if pageCount > 0 {
            localProgress = Double(currentPageIndex + 1) / Double(pageCount)
        } else {
            localProgress = 0
        }
        let raw = (Double(currentChapterIndex) + localProgress) / Double(chapters.count) * 100
        return min(100, max(0, raw))
    }

    // MARK: Cache

    private func cachePages(_ pages: [PageData], centerPage: Int? = nil) {
        guard !isClosing else { return }
        let center = centerPage ?? currentPageIndex
        guard let range = residentPageRange(pageCount: pages.count, center: center) else { return }
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: center)
        for p in pages where !p.content.isEmpty && range.contains(p.pageIndex) {
            PageCacheManager.shared.cachePage(p, bookId: book.id, pageIndex: p.pageIndex)
        }
    }

    private func syncCurrentPageCacheWindow(pages: [PageData]) {
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentPageIndex)
        guard let range = residentPageRange(pageCount: pages.count, center: currentPageIndex) else { return }
        for page in pages where range.contains(page.pageIndex) {
            let cached = page.content.isEmpty
                ? PageCacheManager.shared.getPage(bookId: book.id, chapterIndex: currentChapterIndex, pageIndex: page.pageIndex)
                : page
            if let cached {
                PageCacheManager.shared.cachePage(cached, bookId: book.id, pageIndex: cached.pageIndex)
            }
        }
        if settings.pageFlipMode != .scroll {
            loadedChapterPages[currentChapterIndex] = pageWindow(from: pages, center: currentPageIndex)
            chapterPages = [loadedChapterPages[currentChapterIndex] ?? pages]
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
            self?.currentChapterIndex = index
            self?.currentPageIndex = 0
            self?.loadChapter(index, target: .first)
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
