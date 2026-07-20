import UIKit
import PDFKit

final class NativeDocumentReaderViewController: UIViewController {
    private let book: Book
    private let initialChapterIndex: Int?
    private let initialPageOffset: Int
    private let persistsReadingProgress: Bool
    private var settings: ReadingSettings
    private var navigationMode = ReaderNavigationMode.load()
    private var chapters: [Chapter] = []
    private var pages: [NativeDocumentPage] = []
    private var chapterPageCounts: [Int: Int] = [:]
    private var currentIndex = 0
    private var loadVersion = 0
    private var preloadRadius = 6
    private var initialLoadStarted = false
    private var suppressWindowRefresh = false
    private var menuVisible = false
    private var isProgrammaticPageTurn = false
    private var isPageTransitioning = false
    private var pendingWindow: (pages: [NativeDocumentPage], target: Int)?
    private var activeReadingStartedAt: Date?
    private var visited: Set<String> = []

    private var pageViewController: UIPageViewController!
    private let continuousScrollView = UIScrollView()
    private let continuousStack = UIStackView()
    private let topStatus = UIView()
    private let bottomStatus = UIView()
    private let topMenu = UIView()
    private let bottomMenu = UIView()
    private let chapterLabel = UILabel()
    private let progressLabel = UILabel()
    private let timeLabel = UILabel()
    private let batteryView = LVBatteryView()
    private let menuTitle = UILabel()
    private let menuBookmarkButton = UIButton(type: .system)
    private let eyeCareOverlay = UIView()
    private let brightnessOverlay = UIView()
    private let skeleton = NativeDocumentSkeletonView()
    private let pullBookmarkReveal = UIView()
    private let pullBookmarkLabel = UILabel()

    init(
        book: Book,
        initialChapterIndex: Int? = nil,
        initialPageOffset: Int = 0,
        persistsReadingProgress: Bool = true
    ) {
        self.book = book
        self.initialChapterIndex = initialChapterIndex
        self.initialPageOffset = initialPageOffset
        self.persistsReadingProgress = persistsReadingProgress
        settings = ReadingSettingsRepository.shared.load()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncWithAppTheme()
        buildInterface()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDarkModeChanged),
            name: .darkModeChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webSyncPageTurnRequested(_:)),
            name: .webSyncPageTurnRequested,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !initialLoadStarted, readingSize.width > 0 else { return }
        initialLoadStarted = true
        loadBook()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        resumeReadingTimerIfNeeded()
        if syncWithAppTheme() {
            applyAppearance()
            refreshVisiblePages()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resumeReadingTimerIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgress()
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        flushActiveReadingInterval(recordPages: true)
        loadVersion += 1
        pages.removeAll()
        continuousStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func resumeReadingTimerIfNeeded() {
        guard activeReadingStartedAt == nil,
              UIApplication.shared.applicationState == .active,
              viewIfLoaded?.window != nil else { return }
        activeReadingStartedAt = Date()
    }

    private func flushActiveReadingInterval(recordPages: Bool) {
        let pagesRead = recordPages ? visited.count : 0
        if let start = activeReadingStartedAt {
            ReadingStatsRepository.shared.recordActiveInterval(
                bookId: book.id,
                from: start,
                to: Date(),
                pages: pagesRead
            )
        } else if pagesRead > 0 {
            ReadingStatsRepository.shared.addPagesRead(pagesRead)
        }
        activeReadingStartedAt = nil
        if recordPages { visited.removeAll() }
    }

    @objc private func appWillResignActive() {
        flushActiveReadingInterval(recordPages: false)
    }

    @objc private func appDidBecomeActive() {
        resumeReadingTimerIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        switch settings.readingTheme {
        case .bookshelfNight, .midnight, .oled:
            return .lightContent
        default:
            if #available(iOS 13.0, *) { return .darkContent }
            return .default
        }
    }

    override var prefersStatusBarHidden: Bool {
        !menuVisible && presentedViewController == nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        preloadRadius = 3
        guard let page = currentPage else { return }
        loadWindow(
            chapterIndex: page.chapterIndex,
            pageIndex: page.pageIndex,
            characterOffset: page.startOffset,
            showSkeleton: false
        )
    }

    private var currentPage: NativeDocumentPage? {
        pages.indices.contains(currentIndex) ? pages[currentIndex] : nil
    }

    private var readingSize: CGSize {
        navigationMode == .continuousVertical
            ? continuousScrollView.bounds.size
            : pageViewController.view.bounds.size
    }

    private func makePageViewController() -> UIPageViewController {
        let style: UIPageViewController.TransitionStyle =
            navigationMode == .simulation ? .pageCurl : .scroll
        let orientation: UIPageViewController.NavigationOrientation =
            navigationMode == .vertical ? .vertical : .horizontal
        var options: [UIPageViewController.OptionsKey: Any] = [.interPageSpacing: 0]
        if navigationMode == .simulation {
            options[.spineLocation] = NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)
        }
        let controller = UIPageViewController(
            transitionStyle: style,
            navigationOrientation: orientation,
            options: options
        )
        controller.isDoubleSided = navigationMode == .simulation
        controller.dataSource = self
        controller.delegate = self
        return controller
    }

    private func buildInterface() {
        buildPersistentStatus()
        pageViewController = makePageViewController()
        installPageViewController()
        buildContinuousReader()
        buildMenus()

        eyeCareOverlay.isUserInteractionEnabled = false
        brightnessOverlay.isUserInteractionEnabled = false
        view.addSubview(eyeCareOverlay)
        view.addSubview(brightnessOverlay)
        view.addSubview(skeleton)
        eyeCareOverlay.translatesAutoresizingMaskIntoConstraints = false
        brightnessOverlay.translatesAutoresizingMaskIntoConstraints = false
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            eyeCareOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            eyeCareOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            eyeCareOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            eyeCareOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            brightnessOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            brightnessOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            brightnessOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            brightnessOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            skeleton.topAnchor.constraint(equalTo: topStatus.bottomAnchor),
            skeleton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeleton.bottomAnchor.constraint(equalTo: bottomStatus.topAnchor)
        ])
        applyAppearance()
        updateReaderVisibility()
    }

    private func buildPersistentStatus() {
        let back = iconButton("chevron.left", label: "返回", action: #selector(backTapped))
        chapterLabel.font = .systemFont(ofSize: 13, weight: .medium)
        chapterLabel.textAlignment = .right
        chapterLabel.lineBreakMode = .byTruncatingTail
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        topStatus.addSubview(back)
        topStatus.addSubview(chapterLabel)
        bottomStatus.addSubview(progressLabel)
        bottomStatus.addSubview(timeLabel)
        bottomStatus.addSubview(batteryView)
        view.addSubview(topStatus)
        view.addSubview(bottomStatus)
        pullBookmarkReveal.backgroundColor = UIColor(hex: settings.readingTheme.panelColor)
        pullBookmarkReveal.alpha = 0
        pullBookmarkLabel.text = "下拉设置书签"
        pullBookmarkLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        pullBookmarkLabel.textColor = UIColor(hex: settings.readingTheme.textColor)
        pullBookmarkLabel.textAlignment = .right
        let pullStack = UIStackView(arrangedSubviews: [pullBookmarkLabel])
        pullStack.axis = .horizontal
        pullStack.alignment = .center
        view.insertSubview(pullBookmarkReveal, at: 0)
        pullBookmarkReveal.addSubview(pullStack)
        topStatus.isHidden = true
        bottomStatus.isHidden = true
        [topStatus, bottomStatus, back, chapterLabel, progressLabel, timeLabel, batteryView,
         pullBookmarkReveal, pullStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            pullBookmarkReveal.topAnchor.constraint(equalTo: view.topAnchor),
            pullBookmarkReveal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pullBookmarkReveal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pullBookmarkReveal.heightAnchor.constraint(equalToConstant: 104),
            pullStack.trailingAnchor.constraint(equalTo: pullBookmarkReveal.trailingAnchor, constant: -24),
            pullStack.bottomAnchor.constraint(equalTo: pullBookmarkReveal.bottomAnchor, constant: -16),
            topStatus.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topStatus.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topStatus.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topStatus.heightAnchor.constraint(equalToConstant: 44),
            back.leadingAnchor.constraint(equalTo: topStatus.leadingAnchor, constant: 8),
            back.centerYAnchor.constraint(equalTo: topStatus.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            chapterLabel.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 8),
            chapterLabel.trailingAnchor.constraint(equalTo: topStatus.trailingAnchor, constant: -16),
            chapterLabel.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            bottomStatus.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStatus.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStatus.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomStatus.heightAnchor.constraint(equalToConstant: 40),
            progressLabel.leadingAnchor.constraint(equalTo: bottomStatus.leadingAnchor, constant: 16),
            progressLabel.centerYAnchor.constraint(equalTo: bottomStatus.centerYAnchor),
            batteryView.trailingAnchor.constraint(equalTo: bottomStatus.trailingAnchor, constant: -16),
            batteryView.centerYAnchor.constraint(equalTo: bottomStatus.centerYAnchor),
            batteryView.widthAnchor.constraint(equalToConstant: 26),
            batteryView.heightAnchor.constraint(equalToConstant: 13),
            timeLabel.trailingAnchor.constraint(equalTo: batteryView.leadingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: batteryView.centerYAnchor)
        ])
    }

    private func installPageViewController() {
        addChild(pageViewController)
        view.insertSubview(pageViewController.view, belowSubview: topStatus)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)
        setNativePagingEnabled(navigationMode != .none)
    }

    private func replacePageViewController() {
        pageViewController.willMove(toParent: nil)
        pageViewController.view.removeFromSuperview()
        pageViewController.removeFromParent()
        pageViewController = makePageViewController()
        if let controllers = pageControllers(at: currentIndex) {
            pageViewController.setViewControllers(
                controllers,
                direction: .forward,
                animated: false
            )
        }
        installPageViewController()
        [topStatus, bottomStatus, topMenu, bottomMenu, eyeCareOverlay, brightnessOverlay, skeleton]
            .forEach(view.bringSubviewToFront)
    }

    private func setNativePagingEnabled(_ enabled: Bool) {
        pageViewController.gestureRecognizers.forEach { $0.isEnabled = enabled }
        pageViewController.view.subviews
            .compactMap { $0 as? UIScrollView }
            .forEach {
                $0.isScrollEnabled = enabled
                $0.panGestureRecognizer.isEnabled = enabled
            }
    }

    private func buildContinuousReader() {
        continuousScrollView.delegate = self
        continuousScrollView.alwaysBounceVertical = true
        continuousScrollView.showsVerticalScrollIndicator = false
        continuousStack.axis = .vertical
        continuousStack.spacing = 0
        continuousScrollView.addSubview(continuousStack)
        view.insertSubview(continuousScrollView, belowSubview: topStatus)
        continuousScrollView.translatesAutoresizingMaskIntoConstraints = false
        continuousStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            continuousScrollView.topAnchor.constraint(equalTo: topStatus.bottomAnchor),
            continuousScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            continuousScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            continuousScrollView.bottomAnchor.constraint(equalTo: bottomStatus.topAnchor),
            continuousStack.topAnchor.constraint(equalTo: continuousScrollView.contentLayoutGuide.topAnchor),
            continuousStack.leadingAnchor.constraint(equalTo: continuousScrollView.contentLayoutGuide.leadingAnchor),
            continuousStack.trailingAnchor.constraint(equalTo: continuousScrollView.contentLayoutGuide.trailingAnchor),
            continuousStack.bottomAnchor.constraint(equalTo: continuousScrollView.contentLayoutGuide.bottomAnchor),
            continuousStack.widthAnchor.constraint(equalTo: continuousScrollView.frameLayoutGuide.widthAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(continuousTapped(_:)))
        continuousScrollView.addGestureRecognizer(tap)
    }

    private func buildMenus() {
        let menuBack = iconButton("chevron.left", label: "返回", action: #selector(backTapped))
        let share = iconButton("desktopcomputer", label: "分享到PC端", action: #selector(shareTapped))
        menuBookmarkButton.setImage(UIImage(systemName: "bookmark"), for: .normal)
        menuBookmarkButton.accessibilityLabel = "添加或取消书签"
        menuBookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
        menuTitle.text = book.title
        menuTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        menuTitle.textAlignment = .center
        menuTitle.lineBreakMode = .byTruncatingTail
        topMenu.addSubview(menuBack)
        topMenu.addSubview(menuTitle)
        topMenu.addSubview(menuBookmarkButton)
        topMenu.addSubview(share)
        let stack = UIStackView(arrangedSubviews: [
            menuButton("目录", "list.bullet", #selector(catalogTapped)),
            menuButton("夜间", "moon", #selector(nightTapped)),
            menuButton("主题", "circle.lefthalf.filled", #selector(themeTapped)),
            menuButton("布局", "rectangle.split.2x2", #selector(layoutTapped))
        ])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        bottomMenu.addSubview(stack)
        view.addSubview(topMenu)
        view.addSubview(bottomMenu)
        [topMenu, bottomMenu, menuBack, menuTitle, menuBookmarkButton, share, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            topMenu.topAnchor.constraint(equalTo: view.topAnchor),
            topMenu.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topMenu.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topMenu.heightAnchor.constraint(equalToConstant: 96),
            menuBack.leadingAnchor.constraint(equalTo: topMenu.leadingAnchor, constant: 16),
            menuBack.bottomAnchor.constraint(equalTo: topMenu.bottomAnchor, constant: -8),
            menuBack.widthAnchor.constraint(equalToConstant: 44),
            menuBack.heightAnchor.constraint(equalToConstant: 44),
            share.trailingAnchor.constraint(equalTo: topMenu.trailingAnchor, constant: -16),
            share.bottomAnchor.constraint(equalTo: menuBack.bottomAnchor),
            share.widthAnchor.constraint(equalToConstant: 44),
            share.heightAnchor.constraint(equalToConstant: 44),
            menuBookmarkButton.trailingAnchor.constraint(equalTo: share.leadingAnchor, constant: -8),
            menuBookmarkButton.centerYAnchor.constraint(equalTo: share.centerYAnchor),
            menuBookmarkButton.widthAnchor.constraint(equalToConstant: 44),
            menuBookmarkButton.heightAnchor.constraint(equalToConstant: 44),
            menuTitle.leadingAnchor.constraint(equalTo: menuBack.trailingAnchor, constant: 8),
            menuTitle.trailingAnchor.constraint(equalTo: menuBookmarkButton.leadingAnchor, constant: -8),
            menuTitle.centerYAnchor.constraint(equalTo: menuBack.centerYAnchor),
            bottomMenu.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomMenu.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomMenu.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomMenu.heightAnchor.constraint(equalToConstant: 96),
            stack.topAnchor.constraint(equalTo: bottomMenu.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: bottomMenu.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bottomMenu.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalToConstant: 64)
        ])
        topMenu.alpha = 0
        bottomMenu.alpha = 0
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func menuButton(_ title: String, _ symbol: String, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        button.imageView?.contentMode = .scaleAspectFit
        button.imageEdgeInsets = UIEdgeInsets(top: -18, left: 14, bottom: 0, right: -14)
        button.titleEdgeInsets = UIEdgeInsets(top: 26, left: -14, bottom: 0, right: 14)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityLabel = title
        return button
    }

    private func applyAppearance() {
        let background = UIColor(hex: settings.readingTheme.backgroundColor)
        let foreground = UIColor(hex: settings.readingTheme.textColor)
        let panel = UIColor(hex: settings.readingTheme.panelColor).withAlphaComponent(0.98)
        view.backgroundColor = background
        pageViewController.view.backgroundColor = background
        pageViewController.view.subviews.forEach { $0.backgroundColor = background }
        topStatus.backgroundColor = background
        bottomStatus.backgroundColor = background
        topMenu.backgroundColor = panel
        bottomMenu.backgroundColor = panel
        pullBookmarkReveal.backgroundColor = panel
        pullBookmarkLabel.textColor = foreground
        [chapterLabel, progressLabel, timeLabel, menuTitle].forEach { $0.textColor = foreground }
        batteryView.strokeColor = foreground.withAlphaComponent(0.7)
        batteryView.fillColor = foreground.withAlphaComponent(0.8)
        eyeCareOverlay.backgroundColor = UIColor(hex: settings.eyeCareFilter.filterColor)
            .withAlphaComponent(CGFloat(settings.eyeCareFilter.overlayAlpha))
        let relativeBrightness = min(max(settings.brightness, 0), 1)
        brightnessOverlay.backgroundColor = UIColor.black.withAlphaComponent(
            CGFloat(1 - relativeBrightness)
        )
        view.tintColor = UIColor(hex: settings.readingTheme.accentColor)
        applyTint(UIColor(hex: settings.readingTheme.textColor), in: topMenu)
        applyTint(UIColor(hex: settings.readingTheme.textColor), in: bottomMenu)
        updateBookmarkButton()
        setNeedsStatusBarAppearanceUpdate()
    }

    private func applyTint(_ color: UIColor, in root: UIView) {
        root.tintColor = color
        root.subviews.forEach { applyTint(color, in: $0) }
    }

    private func updateReaderVisibility() {
        let continuous = navigationMode == .continuousVertical
        continuousScrollView.isHidden = !continuous
        pageViewController.view.isHidden = continuous
        topStatus.isHidden = !continuous
        bottomStatus.isHidden = !continuous
    }

    private func loadBook() {
        chapters = BookRepository.shared.getChapters(for: book.id)
        if chapters.isEmpty {
            chapters = [Chapter(bookId: book.id, title: "正文", orderIndex: 0)]
        }
        let progress = BookRepository.shared.getById(book.id)?.readingProgress ?? book.readingProgress
        let startChapter = initialChapterIndex ?? progress.currentChapterIndex
        let startPage = initialChapterIndex == nil ? progress.currentPageOffset : initialPageOffset
        loadWindow(
            chapterIndex: min(max(startChapter, 0), chapters.count - 1),
            pageIndex: max(0, startPage),
            characterOffset: nil,
            showSkeleton: false
        )
    }

    private func loadWindow(
        chapterIndex: Int,
        pageIndex: Int,
        characterOffset: Int?,
        showSkeleton: Bool
    ) {
        guard chapters.indices.contains(chapterIndex), readingSize.width > 0 else { return }
        loadVersion += 1
        let version = loadVersion
        if showSkeleton {
            skeleton.start()
            pageViewController.view.isUserInteractionEnabled = false
            continuousScrollView.isUserInteractionEnabled = false
        }
        let size = readingSize
        let readingSafeAreaInsets = view.safeAreaInsets
        let snapshotSettings = settings
        let snapshotChapters = chapters
        let isContinuous = navigationMode == .continuousVertical
        let continuousTextInsets = isContinuous
            ? NativeDocumentTypography.continuousInsets(size: size, settings: snapshotSettings)
            : nil
        let radius = navigationMode == .continuousVertical ? max(preloadRadius, 6) : preloadRadius
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.book.fileFormat == .pdf {
                do {
                    guard let document = PDFDocument(url: URL(fileURLWithPath: self.book.resolvedFilePath())),
                          document.pageCount > 0 else {
                        throw NativeDocumentReaderError.emptyContent
                    }
                    let center = min(max(pageIndex, 0), document.pageCount - 1)
                    let lower = max(0, center - radius)
                    let upper = min(document.pageCount - 1, center + radius)
                    var pdfPages: [NativeDocumentPage] = []
                    for index in lower...upper {
                        guard let pdfPage = document.page(at: index) else { continue }
                        let thumbnail = pdfPage.thumbnail(
                            of: CGSize(width: max(size.width, 1), height: max(size.height, 1)),
                            for: .mediaBox
                        )
                        pdfPages.append(
                            NativeDocumentPage(
                                chapterIndex: 0,
                                pageIndex: index,
                                chapterTitle: "PDF",
                                startOffset: 0,
                                endOffset: 0,
                                text: "",
                                image: thumbnail
                            )
                        )
                    }
                    DispatchQueue.main.async {
                        guard version == self.loadVersion else { return }
                        self.chapterPageCounts[0] = document.pageCount
                        self.apply(window: pdfPages, target: center - lower)
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard version == self.loadVersion else { return }
                        self.presentLoadError(error)
                    }
                }
                return
            }
            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            do {
                var cache: [Int: [NativeDocumentPage]] = [:]
                var contentCache: [Int: String] = [:]

                func cleanedContent(_ index: Int) throws -> String {
                    if let cached = contentCache[index] { return cached }
                    let chapter = snapshotChapters[index]
                    var text = try parser.parseChapterContent(
                        filePath: self.book.resolvedFilePath(),
                        chapter: chapter,
                        encoding: self.book.encoding ?? "UTF-8"
                    )
                    text = NativeDocumentSanitizer.removeDuplicateHeading(
                        from: text,
                        title: chapter.title
                    )
                    text = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: text)
                    contentCache[index] = text
                    return text
                }

                func resolvedContent(_ index: Int) throws -> String {
                    let chapter = snapshotChapters[index]
                    let content = try cleanedContent(index)
                    guard !ReaderChapterContentPolicy.isTitleOnly(
                        content: content,
                        chapterTitle: chapter.title
                    ) else {
                        return ""
                    }

                    var pendingTitles: [String] = []
                    var followingTitle = chapter.title
                    var previousIndex = index - 1
                    while previousIndex >= 0 {
                        let previousChapter = snapshotChapters[previousIndex]
                        let previousContent = try cleanedContent(previousIndex)
                        guard ReaderChapterContentPolicy.isTitleOnly(
                            content: previousContent,
                            chapterTitle: previousChapter.title
                        ) else {
                            break
                        }
                        if !ReaderChapterContentPolicy.titlesMatch(
                            previousChapter.title,
                            followingTitle
                        ) {
                            pendingTitles.insert(previousChapter.title, at: 0)
                        }
                        followingTitle = previousChapter.title
                        previousIndex -= 1
                    }

                    return ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(
                        in: ReaderChapterContentPolicy.merging(
                            pendingTitles: pendingTitles,
                            with: content
                        )
                    )
                }

                func parse(_ index: Int) throws -> [NativeDocumentPage] {
                    if let value = cache[index] { return value }
                    let chapter = snapshotChapters[index]
                    let text = try resolvedContent(index)
                    guard !text.isEmpty else {
                        cache[index] = []
                        return []
                    }
                    let value = try NativeDocumentPaginator.pages(
                        text: text,
                        chapter: chapter,
                        chapterIndex: index,
                        size: size,
                        safeAreaInsets: isContinuous ? .zero : readingSafeAreaInsets,
                        textInsets: continuousTextInsets,
                        settings: snapshotSettings
                    )
                    cache[index] = value
                    return value
                }

                var resolvedChapter = chapterIndex
                var centerPages = try parse(resolvedChapter)
                while centerPages.isEmpty, resolvedChapter + 1 < snapshotChapters.count {
                    resolvedChapter += 1
                    centerPages = try parse(resolvedChapter)
                }
                guard !centerPages.isEmpty else { throw NativeDocumentReaderError.emptyContent }
                let localTarget: Int
                if let characterOffset {
                    localTarget = centerPages.firstIndex {
                        characterOffset >= $0.startOffset && characterOffset < $0.endOffset
                    } ?? min(pageIndex, centerPages.count - 1)
                } else {
                    localTarget = min(pageIndex, centerPages.count - 1)
                }
                var combined = centerPages
                var target = localTarget
                var previous = resolvedChapter - 1
                var next = resolvedChapter + 1
                while target < radius, previous >= 0 {
                    let value = try parse(previous)
                    combined = value + combined
                    target += value.count
                    previous -= 1
                }
                while combined.count - target - 1 < radius, next < snapshotChapters.count {
                    combined += try parse(next)
                    next += 1
                }
                let pageCounts = cache.mapValues(\.count)
                DispatchQueue.main.async {
                    guard version == self.loadVersion else { return }
                    self.chapterPageCounts.merge(pageCounts) { _, new in new }
                    self.apply(window: combined, target: target)
                }
            } catch {
                DispatchQueue.main.async {
                    guard version == self.loadVersion else { return }
                    self.presentLoadError(error)
                }
            }
        }
    }

    private func apply(window: [NativeDocumentPage], target: Int) {
        guard !isPageTransitioning else {
            pendingWindow = (window, target)
            return
        }
        suppressWindowRefresh = true
        let continuousHeight = max(continuousScrollView.bounds.height, 1)
        let previousPageID = currentPage?.id
        let previousIntraPageOffset = navigationMode == .continuousVertical
            ? continuousScrollView.contentOffset.y - CGFloat(currentIndex) * continuousHeight
            : 0
        let cachedPages = window.map {
            PageData(
                pageIndex: $0.pageIndex,
                startCharOffset: $0.startOffset,
                endCharOffset: $0.endOffset,
                content: $0.text,
                chapterTitle: $0.chapterTitle,
                chapterIndex: $0.chapterIndex
            )
        }
        PageCacheManager.shared.cachePages(cachedPages, bookId: book.id, centerPage: target)
        pages = window
        currentIndex = previousPageID.flatMap { id in window.firstIndex(where: { $0.id == id }) } ?? target
        if navigationMode == .continuousVertical {
            renderContinuousWindow(target: currentIndex, intraPageOffset: previousIntraPageOffset)
        } else if let controllers = pageControllers(at: currentIndex) {
            pageViewController.setViewControllers(controllers, direction: .forward, animated: false)
        }
        skeleton.stop()
        pageViewController.view.isUserInteractionEnabled = true
        continuousScrollView.isUserInteractionEnabled = true
        settleOnCurrentPage()
        suppressWindowRefresh = false
    }

    private func makePageController(at index: Int) -> NativeDocumentPageViewController? {
        guard pages.indices.contains(index) else { return nil }
        let page = pages[index]
        let bookmark = BookRepository.shared.getBookmark(
            at: book.id,
            chapterIndex: page.chapterIndex,
            pageOffset: page.pageIndex
        ) != nil
        let hasComment = highlight(for: page) != nil
        UIDevice.current.isBatteryMonitoringEnabled = true
        let controller = NativeDocumentPageViewController(
            page: page,
            settings: settings,
            bookmarked: bookmark,
            hasComment: hasComment,
            allowsPullBookmark: allowsPullBookmark,
            progressText: progressText(for: page),
            timeText: DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short),
            batteryLevel: max(0, UIDevice.current.batteryLevel),
            readingSafeAreaInsets: view.safeAreaInsets
        )
        controller.delegate = self
        return controller
    }

    private func makeBackPageController(at index: Int) -> NativeDocumentPageBackViewController? {
        guard pages.indices.contains(index) else { return nil }
        return NativeDocumentPageBackViewController(
            page: pages[index],
            settings: settings,
            readingSafeAreaInsets: view.safeAreaInsets
        )
    }

    private func pageControllers(
        at index: Int,
        previouslyDisplayedIndex: Int? = nil,
        animated: Bool = false
    ) -> [UIViewController]? {
        guard let front = makePageController(at: index) else { return nil }
        guard navigationMode == .simulation, animated else { return [front] }
        let backIndex = previouslyDisplayedIndex ?? index
        guard let back = makeBackPageController(at: backIndex) else { return nil }
        // .min 书脊静态设置只显示一个正面；双面动画额外需要前一页背面。
        return [front, back]
    }

    private func progressText(for page: NativeDocumentPage) -> String {
        "\(page.pageIndex + 1)/\(chapterPageCounts[page.chapterIndex] ?? page.pageIndex + 1)"
    }

    private func renderContinuousWindow(target: Int, intraPageOffset: CGFloat = 0) {
        continuousStack.arrangedSubviews.forEach {
            continuousStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let height = max(continuousScrollView.bounds.height, 1)
        let textInsets = NativeDocumentTypography.continuousInsets(
            size: CGSize(width: continuousScrollView.bounds.width, height: height),
            settings: settings
        )
        for page in pages {
            let canvas = NativeCoreTextView()
            canvas.page = page
            canvas.settings = settings
            canvas.readingSafeAreaInsets = .zero
            canvas.textInsets = textInsets
            canvas.heightAnchor.constraint(equalToConstant: height).isActive = true
            continuousStack.addArrangedSubview(canvas)
        }
        view.layoutIfNeeded()
        continuousScrollView.setContentOffset(
            CGPoint(x: 0, y: max(0, CGFloat(target) * height + intraPageOffset)),
            animated: false
        )
    }

    private func refreshVisiblePages() {
        guard !isPageTransitioning else { return }
        if navigationMode == .continuousVertical {
            let height = max(continuousScrollView.bounds.height, 1)
            let intraPageOffset = continuousScrollView.contentOffset.y - CGFloat(currentIndex) * height
            renderContinuousWindow(target: currentIndex, intraPageOffset: intraPageOffset)
        } else if let controllers = pageControllers(at: currentIndex) {
            pageViewController.setViewControllers(controllers, direction: .forward, animated: false)
        }
    }

    private func settleOnCurrentPage() {
        guard let page = currentPage else { return }
        visited.insert(page.id)
        chapterLabel.text = page.chapterTitle
        progressLabel.text = progressText(for: page)
        timeLabel.text = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryView.level = max(0, UIDevice.current.batteryLevel)
        updateBookmarkButton()
        WebSyncServer.shared.updateCurrentPage(bookId: book.id, page: webSyncSnapshot(for: page))
        saveProgress()
        let reloadMargin = min(3, max(1, pages.count / 3))
        if !suppressWindowRefresh,
           currentIndex < reloadMargin || currentIndex >= pages.count - reloadMargin {
            loadWindow(
                chapterIndex: page.chapterIndex,
                pageIndex: page.pageIndex,
                characterOffset: page.startOffset,
                showSkeleton: false
            )
        }
    }

    private func saveProgress() {
        guard persistsReadingProgress, let page = currentPage else { return }
        let chapterFraction = Double(page.pageIndex + 1)
            / Double(max(chapterPageCounts[page.chapterIndex] ?? page.pageIndex + 1, 1))
        let percent = (Double(page.chapterIndex) + chapterFraction)
            / Double(max(chapters.count, 1)) * 100
        BookRepository.shared.updateProgress(
            bookId: book.id,
            progress: ReadingProgress(
                currentChapterIndex: page.chapterIndex,
                currentPageOffset: page.pageIndex,
                totalPages: chapterPageCounts[page.chapterIndex] ?? page.pageIndex + 1,
                progressPercent: min(100, max(0, percent)),
                lastReadTimestamp: Date()
            )
        )
    }

    private func toggleMenu() {
        menuVisible.toggle()
        updatePagingInteraction()
        setNeedsStatusBarAppearanceUpdate()
        UIView.animate(withDuration: 0.2) {
            self.topMenu.alpha = self.menuVisible ? 1 : 0
            self.bottomMenu.alpha = self.menuVisible ? 1 : 0
        }
    }

    private func updatePagingInteraction() {
        let enabled = !menuVisible && presentedViewController == nil
        setNativePagingEnabled(enabled && navigationMode != .none)
        continuousScrollView.isScrollEnabled = enabled
    }

    private func turnPage(
        forward: Bool,
        animated: Bool,
        allowWhileSyncPresented: Bool = false
    ) {
        let canTurnWithPresentedController = presentedViewController == nil
            || (allowWhileSyncPresented && presentedViewController is WebSyncViewController)
        guard !menuVisible,
              canTurnWithPresentedController,
              !isProgrammaticPageTurn,
              !isPageTransitioning else { return }
        let target = currentIndex + (forward ? 1 : -1)
        guard let controllers = pageControllers(
            at: target,
            previouslyDisplayedIndex: currentIndex,
            animated: animated
        ) else { return }
        isProgrammaticPageTurn = true
        isPageTransitioning = animated
        pageViewController.setViewControllers(
            controllers,
            direction: forward ? .forward : .reverse,
            animated: animated
        ) { [weak self] completed in
            guard let self else { return }
            self.isProgrammaticPageTurn = false
            self.isPageTransitioning = false
            if completed, animated {
                self.currentIndex = target
            }
            self.finishPageTransition(settle: completed && animated)
        }
        if !animated {
            currentIndex = target
            settleOnCurrentPage()
            isProgrammaticPageTurn = false
        }
    }

    @objc private func webSyncPageTurnRequested(_ notification: Notification) {
        guard let forward = notification.userInfo?["forward"] as? Bool,
              let requestedBookId = notification.userInfo?["bookId"] as? String,
              requestedBookId == book.id else { return }
        if navigationMode == .continuousVertical {
            let target = currentIndex + (forward ? 1 : -1)
            guard pages.indices.contains(target) else { return }
            continuousScrollView.setContentOffset(
                CGPoint(x: 0, y: CGFloat(target) * max(continuousScrollView.bounds.height, 1)),
                animated: true
            )
        } else {
            turnPage(
                forward: forward,
                animated: navigationMode != .none,
                allowWhileSyncPresented: true
            )
        }
    }

    private func finishPageTransition(settle: Bool) {
        if let pendingWindow {
            self.pendingWindow = nil
            apply(window: pendingWindow.pages, target: pendingWindow.target)
        } else if settle {
            settleOnCurrentPage()
        }
    }

    @discardableResult
    private func syncWithAppTheme() -> Bool {
        let theme = DarkModeManager.shared.currentTheme
        guard settings.readingTheme != theme else { return false }
        settings.readingTheme = theme
        settings.nightMode = theme.isDarkAppearance
        settings.backgroundColor = theme.backgroundColor
        ReadingSettingsRepository.shared.save(settings)
        return true
    }

    @objc private func appDarkModeChanged() {
        guard syncWithAppTheme() else { return }
        applyAppearance()
        refreshVisiblePages()
        WebSyncServer.shared.notifySettingsChanged(settings)
        guard let page = currentPage else { return }
        loadWindow(
            chapterIndex: page.chapterIndex,
            pageIndex: page.pageIndex,
            characterOffset: page.startOffset,
            showSkeleton: false
        )
    }

    private func highlight(for page: NativeDocumentPage) -> Highlight? {
        BookRepository.shared.getHighlights(for: book.id).first {
            $0.chapterIndex == page.chapterIndex && $0.pageOffset == page.pageIndex
        }
    }

    private func editComment(pageController: NativeDocumentPageViewController, selectedText: String?) {
        let page = pageController.page
        let existing = highlight(for: page)
        let selected = String((selectedText ?? existing?.text ?? page.text).prefix(500))
        let alert = UIAlertController(title: existing == nil ? "添加评论" : "修改评论", message: selected, preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "评论不能为空，最多1000字"
            $0.text = existing?.note
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let note = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else {
                LVToast.show(message: "评论内容不能为空", style: .error)
                return
            }
            if let existing { BookRepository.shared.deleteHighlight(existing.id) }
            BookRepository.shared.insertHighlight(
                Highlight(
                    bookId: self.book.id,
                    chapterIndex: page.chapterIndex,
                    pageOffset: page.pageIndex,
                    startCharOffset: page.startOffset,
                    endCharOffset: min(page.endOffset, page.startOffset + selected.utf16.count),
                    text: selected,
                    color: "#E8784A",
                    note: String(note.prefix(1000))
                )
            )
            pageController.setCommentVisible(true)
            LVToast.show(message: "评论已保存", style: .success)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func toggleBookmark(_ controller: NativeDocumentPageViewController) {
        let page = controller.page
        toggleBookmark(page: page)
        controller.setBookmarked(isBookmarked(page))
    }

    private func toggleBookmark(page: NativeDocumentPage) {
        if let bookmark = BookRepository.shared.getBookmark(
            at: book.id,
            chapterIndex: page.chapterIndex,
            pageOffset: page.pageIndex
        ) {
            BookRepository.shared.deleteBookmark(bookmark.id)
        } else {
            BookRepository.shared.insertBookmark(
                Bookmark(
                    bookId: book.id,
                    chapterIndex: page.chapterIndex,
                    pageOffset: page.pageIndex,
                    chapterTitle: page.chapterTitle,
                    snippet: String(page.text.prefix(80))
                )
            )
        }
        updateBookmarkButton()
    }

    private var allowsPullBookmark: Bool {
        navigationMode == .simulation || navigationMode == .horizontal || navigationMode == .none
    }

    private func isBookmarked(_ page: NativeDocumentPage) -> Bool {
        BookRepository.shared.getBookmark(
            at: book.id,
            chapterIndex: page.chapterIndex,
            pageOffset: page.pageIndex
        ) != nil
    }

    private func updateBookmarkButton() {
        let bookmarked = currentPage.map(isBookmarked) ?? false
        let image = UIImage(systemName: bookmarked ? "bookmark.fill" : "bookmark")
        menuBookmarkButton.setImage(image, for: .normal)
    }

    private func showSettings(section: NativeReaderSettingsSheet.Section) {
        let sheet = NativeReaderSettingsSheet(settings: settings, mode: navigationMode, section: section)
        sheet.onChange = { [weak self] settings, mode in
            guard let self, let page = self.currentPage else { return }
            let previousSettings = self.settings
            if previousSettings.readingTheme != settings.readingTheme {
                DarkModeManager.shared.selectReadingTheme(settings.readingTheme)
            }
            let modeChanged = self.navigationMode != mode
            let brightnessOnly = !modeChanged
                && self.differsOnlyInBrightness(previousSettings, settings)
            self.settings = settings
            self.navigationMode = mode
            self.applyAppearance()
            guard !brightnessOnly else { return }
            if modeChanged {
                self.replacePageViewController()
                self.updateReaderVisibility()
            } else if !self.pages.isEmpty {
                self.refreshVisiblePages()
            }
            self.loadWindow(
                chapterIndex: page.chapterIndex,
                pageIndex: page.pageIndex,
                characterOffset: page.startOffset,
                showSkeleton: false
            )
        }
        present(sheet, animated: true)
    }

    private func differsOnlyInBrightness(
        _ previous: ReadingSettings,
        _ updated: ReadingSettings
    ) -> Bool {
        var normalizedPrevious = previous
        normalizedPrevious.brightness = updated.brightness
        return normalizedPrevious == updated
    }

    private func presentLoadError(_ error: Error) {
        skeleton.stop()
        let fileExists = FileManager.default.fileExists(atPath: book.resolvedFilePath())
        let title = fileExists
            ? (error is NativeDocumentReaderError ? "该章节暂无可阅读内容" : "文件解析失败")
            : "文件已被移动或删除"
        let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "返回书架", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }

    @objc private func catalogTapped() {
        guard let page = currentPage else { return }
        let total = chapterPageCounts[page.chapterIndex] ?? page.pageIndex + 1
        let current = "当前 \(page.pageIndex + 1) / \(total)"
        let catalog = NativeReaderCatalogViewController(
            chapters: chapters,
            currentIndex: page.chapterIndex,
            currentPageText: current,
            settings: settings
        )
        catalog.onSelect = { [weak self] index in
            self?.loadWindow(chapterIndex: index, pageIndex: 0, characterOffset: nil, showSkeleton: false)
        }
        present(catalog, animated: true)
    }

    @objc private func nightTapped() {
        DarkModeManager.shared.setNightMode(!DarkModeManager.shared.isDarkMode)
    }

    @objc private func themeTapped() { showSettings(section: .theme) }
    @objc private func layoutTapped() { showSettings(section: .layout) }

    @objc private func bookmarkTapped() {
        guard let page = currentPage else { return }
        toggleBookmark(page: page)
        refreshVisiblePages()
    }

    @objc private func shareTapped() {
        guard let page = currentPage else { return }
        WebSyncServer.shared.start(with: book, page: webSyncSnapshot(for: page)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let session):
                self.present(WebSyncViewController(session: session), animated: true)
            case .failure(let error):
                LVToast.show(message: error.localizedDescription, style: .error)
            }
        }
    }

    private func webSyncSnapshot(for page: NativeDocumentPage) -> WebSyncServer.PageSnapshot {
        WebSyncServer.PageSnapshot(
            pageIndex: page.pageIndex,
            content: page.text,
            chapterTitle: page.chapterTitle,
            chapterIndex: page.chapterIndex,
            totalPages: max(chapterPageCounts[page.chapterIndex] ?? 1, 1)
        )
    }

    @objc private func continuousTapped(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: continuousScrollView).x
        if x >= view.bounds.width * 0.3, x <= view.bounds.width * 0.7 {
            toggleMenu()
        }
    }
}

extension NativeDocumentReaderViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        guard !isProgrammaticPageTurn else { return }
        isPageTransitioning = true
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard !menuVisible, presentedViewController == nil else { return nil }
        if navigationMode == .simulation,
           let back = viewController as? NativeDocumentPageBackViewController,
           let index = pages.firstIndex(where: { $0.id == back.page.id }) {
            return makePageController(at: index)
        }
        guard let page = viewController as? NativeDocumentPageViewController,
              let index = pages.firstIndex(where: { $0.id == page.page.id }) else { return nil }
        return navigationMode == .simulation
            ? makeBackPageController(at: index - 1)
            : makePageController(at: index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard !menuVisible, presentedViewController == nil else { return nil }
        if navigationMode == .simulation,
           let back = viewController as? NativeDocumentPageBackViewController,
           let index = pages.firstIndex(where: { $0.id == back.page.id }) {
            return makePageController(at: index + 1)
        }
        guard let page = viewController as? NativeDocumentPageViewController,
              let index = pages.firstIndex(where: { $0.id == page.page.id }) else { return nil }
        return navigationMode == .simulation
            ? makeBackPageController(at: index)
            : makePageController(at: index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard !isProgrammaticPageTurn else { return }
        isPageTransitioning = false
        let visible = pageViewController.viewControllers?
            .compactMap { $0 as? NativeDocumentPageViewController }
            .first
        let index = visible.flatMap { visible in
            pages.firstIndex(where: { $0.id == visible.page.id })
        }
        if completed, let index {
            currentIndex = index
        }
        finishPageTransition(settle: completed && index != nil)
    }
}

extension NativeDocumentReaderViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard navigationMode == .continuousVertical,
              !suppressWindowRefresh,
              scrollView.bounds.height > 0,
              !pages.isEmpty else { return }
        let index = min(
            max(Int((scrollView.contentOffset.y + scrollView.bounds.height / 2) / scrollView.bounds.height), 0),
            pages.count - 1
        )
        if index != currentIndex {
            currentIndex = index
            settleOnCurrentPage()
        }
    }
}

extension NativeDocumentReaderViewController: NativeDocumentPageDelegate {
    func documentPageDidTapBack() { backTapped() }

    func documentPageDidTapCenter() { toggleMenu() }

    func documentPageDidTapEdge(forward: Bool) {
        guard !menuVisible, presentedViewController == nil else { return }
        switch navigationMode {
        case .simulation, .horizontal:
            turnPage(forward: forward, animated: true)
        case .none:
            turnPage(forward: forward, animated: false)
        case .vertical, .continuousVertical:
            break
        }
    }

    func documentPage(_ controller: NativeDocumentPageViewController, didUpdatePull distance: CGFloat) {
        guard allowsPullBookmark, !menuVisible, presentedViewController == nil else { return }
        let translation = min(max(distance, 0), 96)
        controller.view.transform = CGAffineTransform(translationX: 0, y: translation)
        pullBookmarkReveal.alpha = min(1, translation / 56)
        let reachedThreshold = translation >= 72
        pullBookmarkLabel.text = reachedThreshold ? "松开设置书签" : "下拉设置书签"
        controller.setPullBookmarkPreviewVisible(reachedThreshold)
    }

    func documentPage(_ controller: NativeDocumentPageViewController, didFinishPull shouldToggleBookmark: Bool) {
        let canToggle = !menuVisible && presentedViewController == nil
        if shouldToggleBookmark && canToggle {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            toggleBookmark(controller)
        }
        controller.setPullBookmarkPreviewVisible(false)
        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            controller.view.transform = .identity
            self.pullBookmarkReveal.alpha = 0
        }
    }

    func documentPage(_ controller: NativeDocumentPageViewController, didLongPress text: String) {
        editComment(pageController: controller, selectedText: text)
    }

    func documentPageDidTapComment(_ controller: NativeDocumentPageViewController) {
        editComment(pageController: controller, selectedText: nil)
    }
}

private enum NativeDocumentReaderError: LocalizedError {
    case emptyContent
    var errorDescription: String? { "没有可显示的正文" }
}

private final class NativeDocumentSkeletonView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        backgroundColor = .systemBackground
        stack.axis = .vertical
        stack.spacing = 16
        for _ in 0..<10 {
            let line = UIView()
            line.backgroundColor = .secondarySystemFill
            line.layer.cornerRadius = 6
            line.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(line)
        }
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 64),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        ])
        accessibilityLabel = "正在加载正文"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        isHidden = false
        UIView.animate(withDuration: 0.8, delay: 0, options: [.autoreverse, .repeat]) {
            self.stack.alpha = 0.4
        }
    }

    func stop() {
        layer.removeAllAnimations()
        stack.layer.removeAllAnimations()
        stack.alpha = 1
        isHidden = true
    }
}
