import UIKit
import CoreText

final class ContinuousReaderViewController: UIViewController {

    private struct PageKey: Hashable {
        let chapterIndex: Int
        let pageIndex: Int
    }

    private let book: Book
    private var settings: ReadingSettings {
        didSet { ReadingSettingsRepository.shared.save(settings) }
    }
    private var chapters: [Chapter] = []
    private var chapterPages: [Int: [PageData]] = [:]
    private var windowKeys: [PageKey] = []
    private var currentKey = PageKey(chapterIndex: 0, pageIndex: 0)
    private var loadGeneration = 0
    private var pendingLoadCenter: PageKey?
    private var isPageFlipping = false
    private var isClosing = false
    private var clockTimer: Timer?
    private var settingsReloadWorkItem: DispatchWorkItem?

    private let pageRadius = 5
    private let loaderQueue = DispatchQueue(label: "com.lvread.continuous-reader.loader", qos: .userInitiated)
    private let containerView = UIView()
    private let currentPageView = PageContainerView()
    private let nextPageView = PageContainerView()
    private let scrollView = UIScrollView()
    private let scrollStackView = UIStackView()
    private let loadingLabel = UILabel()
    private let chromeView = UIView()
    private let topBackButton = UIButton(type: .system)
    private let topLabel = UILabel()
    private let bottomLabel = UILabel()
    private let timeLabel = UILabel()
    private let batteryView = LVBatteryView()
    private let eyeCareOverlayView = UIView()
    private let brightnessOverlayView = UIView()
    private let flipState = PageFlipState()

    init(book: Book) {
        self.book = book
        self.settings = ReadingSettingsRepository.shared.load()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { chromeView.alpha < 0.5 }

    override func viewDidLoad() {
        super.viewDidLoad()
        chapters = BookRepository.shared.getChapters(for: book.id)
        if chapters.isEmpty {
            chapters = [Chapter(bookId: book.id, title: "正文", orderIndex: 0)]
        }
        setupUI()
        setupGestures()
        startClockTimer()
        loadWindow(
            chapterIndex: min(max(book.readingProgress.currentChapterIndex, 0), chapters.count - 1),
            pageIndex: max(book.readingProgress.currentPageOffset, 0),
            showLoading: true
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        currentPageView.frame = containerView.bounds
        nextPageView.frame = containerView.bounds
    }

    deinit {
        releaseReaderMemory()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(hex: settings.backgroundColor)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        currentPageView.translatesAutoresizingMaskIntoConstraints = false
        nextPageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollStackView.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        topBackButton.translatesAutoresizingMaskIntoConstraints = false
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        batteryView.translatesAutoresizingMaskIntoConstraints = false
        eyeCareOverlayView.translatesAutoresizingMaskIntoConstraints = false
        brightnessOverlayView.translatesAutoresizingMaskIntoConstraints = false

        containerView.clipsToBounds = true
        eyeCareOverlayView.isUserInteractionEnabled = false
        brightnessOverlayView.isUserInteractionEnabled = false
        view.addSubview(containerView)
        containerView.addSubview(currentPageView)
        containerView.addSubview(nextPageView)
        nextPageView.alpha = 0

        scrollView.isHidden = true
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        scrollStackView.axis = .vertical
        scrollStackView.spacing = 0
        scrollView.addSubview(scrollStackView)
        containerView.addSubview(scrollView)

        loadingLabel.text = "正在加载..."
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.textColor = UIColor(hex: settings.readingTheme.textColor).withAlphaComponent(0.55)
        view.addSubview(loadingLabel)

        configureChrome()
        view.addSubview(chromeView)
        view.addSubview(topBackButton)
        view.addSubview(topLabel)
        view.addSubview(bottomLabel)
        view.addSubview(timeLabel)
        view.addSubview(batteryView)
        view.addSubview(eyeCareOverlayView)
        view.addSubview(brightnessOverlayView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),

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
            scrollStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            scrollStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            scrollStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            scrollStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            chromeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chromeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chromeView.heightAnchor.constraint(equalToConstant: 92),

            topBackButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 7),
            topBackButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            topBackButton.widthAnchor.constraint(equalToConstant: 28),
            topBackButton.heightAnchor.constraint(equalToConstant: 22),
            topLabel.centerYAnchor.constraint(equalTo: topBackButton.centerYAnchor),
            topLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topBackButton.trailingAnchor, constant: 12),
            topLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),

            bottomLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            bottomLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: bottomLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: batteryView.leadingAnchor, constant: -8),
            batteryView.centerYAnchor.constraint(equalTo: bottomLabel.centerYAnchor),
            batteryView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            batteryView.widthAnchor.constraint(equalToConstant: 26),
            batteryView.heightAnchor.constraint(equalToConstant: 13),

            eyeCareOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            eyeCareOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            eyeCareOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            eyeCareOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            brightnessOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            brightnessOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            brightnessOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            brightnessOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyTheme()
    }

    private func configureChrome() {
        chromeView.alpha = 0
        chromeView.backgroundColor = UIColor(hex: settings.readingTheme.panelColor)

        topBackButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        topBackButton.setPreferredSymbolConfiguration(.init(pointSize: 13, weight: .medium), forImageIn: .normal)
        topBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fill
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        chromeView.addSubview(stack)

        let items: [(String, Selector)] = [
            ("chevron.left", #selector(backTapped)),
            ("list.bullet", #selector(catalogTapped)),
            ("moon", #selector(nightTapped)),
            ("paintpalette", #selector(themeSettingsTapped)),
            ("textformat.size", #selector(layoutSettingsTapped))
        ]

        for item in items {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: item.0), for: .normal)
            button.tintColor = UIColor(hex: settings.readingTheme.textColor)
            button.addTarget(self, action: item.1, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 54).isActive = true
            stack.addArrangedSubview(button)
            if item.0 == "chevron.left" {
                button.widthAnchor.constraint(equalToConstant: 64).isActive = true
            } else {
                button.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 1 / 4, constant: -16).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: chromeView.topAnchor, constant: 10)
        ])

        topLabel.font = .systemFont(ofSize: 12, weight: .medium)
        topLabel.textAlignment = .right
        topLabel.numberOfLines = 1
        bottomLabel.font = .systemFont(ofSize: 12, weight: .regular)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.textAlignment = .right
    }

    private func setupGestures() {
        view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
        scrollView.isHidden = settings.pageFlipMode != .scroll
        currentPageView.isHidden = settings.pageFlipMode == .scroll
        nextPageView.isHidden = settings.pageFlipMode == .scroll

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        if settings.pageFlipMode != .scroll, settings.pageFlipMode != .none {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)
        }
    }

    private func loadWindow(chapterIndex: Int, pageIndex: Int, showLoading: Bool, anchorCharOffset: Int? = nil) {
        guard !isClosing else { return }
        let requestedCenter = PageKey(chapterIndex: chapterIndex, pageIndex: pageIndex)
        if pendingLoadCenter == requestedCenter { return }
        pendingLoadCenter = requestedCenter
        loadGeneration += 1
        let generation = loadGeneration
        let knownPages = chapterPages
        let targetSize = pageSize()
        let layoutSettings = settings
        if showLoading { loadingLabel.isHidden = false }

        loaderQueue.async { [weak self] in
            guard let self else { return }
            var cache = knownPages
            var targetPageIndex = pageIndex
            if let anchorCharOffset,
               self.ensureChapter(chapterIndex, pageSize: targetSize, settings: layoutSettings, cache: &cache),
               let pages = cache[chapterIndex],
               !pages.isEmpty {
                targetPageIndex = self.pageIndex(containing: anchorCharOffset, in: pages)
            }
            guard let window = self.makeWindow(
                centerChapter: chapterIndex,
                centerPage: targetPageIndex,
                pageSize: targetSize,
                settings: layoutSettings,
                cache: &cache
            ) else {
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.pendingLoadCenter = nil
                    self.loadingLabel.text = "加载失败"
                }
                return
            }

            DispatchQueue.main.async {
                guard generation == self.loadGeneration, !self.isClosing else { return }
                self.pendingLoadCenter = nil
                self.chapterPages = self.trimmedCache(cache, keeping: window.keys)
                self.windowKeys = window.keys
                self.currentKey = window.center
                self.loadingLabel.isHidden = true
                self.renderCurrentPage()
                self.rebuildScrollPages(keepOffset: false)
                self.cacheResidentPages()
                self.saveProgress()
            }
        }
    }

    private func pageIndex(containing charOffset: Int, in pages: [PageData]) -> Int {
        if let index = pages.firstIndex(where: { page in
            charOffset >= page.startCharOffset && charOffset < max(page.endCharOffset, page.startCharOffset + 1)
        }) {
            return index
        }
        if let index = pages.lastIndex(where: { $0.startCharOffset <= charOffset }) {
            return index
        }
        return 0
    }

    private func makeWindow(
        centerChapter: Int,
        centerPage: Int,
        pageSize: CGSize,
        settings: ReadingSettings,
        cache: inout [Int: [PageData]]
    ) -> (keys: [PageKey], center: PageKey)? {
        guard let readableCenter = readableCenter(
            nearChapter: centerChapter,
            pageIndex: centerPage,
            pageSize: pageSize,
            settings: settings,
            cache: &cache
        ),
              let centerPages = cache[readableCenter.chapterIndex],
              !centerPages.isEmpty else { return nil }

        let clampedPage = min(max(readableCenter.pageIndex, 0), centerPages.count - 1)
        let center = PageKey(chapterIndex: readableCenter.chapterIndex, pageIndex: clampedPage)
        var left: [PageKey] = []
        var right: [PageKey] = []
        var cursor = center

        for _ in 0..<pageRadius {
            guard let previous = previousKey(before: cursor, pageSize: pageSize, settings: settings, cache: &cache) else { break }
            left.insert(previous, at: 0)
            cursor = previous
        }

        cursor = center
        for _ in 0..<pageRadius {
            guard let next = nextKey(after: cursor, pageSize: pageSize, settings: settings, cache: &cache) else { break }
            right.append(next)
            cursor = next
        }

        while left.count + 1 + right.count < pageRadius * 2 + 1,
              let next = nextKey(after: right.last ?? center, pageSize: pageSize, settings: settings, cache: &cache) {
            right.append(next)
        }

        while left.count + 1 + right.count < pageRadius * 2 + 1,
              let previous = previousKey(before: left.first ?? center, pageSize: pageSize, settings: settings, cache: &cache) {
            left.insert(previous, at: 0)
        }

        return (left + [center] + right, center)
    }

    private func readableCenter(
        nearChapter chapterIndex: Int,
        pageIndex: Int,
        pageSize: CGSize,
        settings: ReadingSettings,
        cache: inout [Int: [PageData]]
    ) -> PageKey? {
        if ensureChapter(chapterIndex, pageSize: pageSize, settings: settings, cache: &cache),
           let pages = cache[chapterIndex],
           !pages.isEmpty {
            return PageKey(chapterIndex: chapterIndex, pageIndex: min(max(pageIndex, 0), pages.count - 1))
        }

        for distance in 1...max(chapters.count, 1) {
            let next = chapterIndex + distance
            if ensureChapter(next, pageSize: pageSize, settings: settings, cache: &cache),
               let pages = cache[next],
               !pages.isEmpty {
                return PageKey(chapterIndex: next, pageIndex: 0)
            }

            let previous = chapterIndex - distance
            if ensureChapter(previous, pageSize: pageSize, settings: settings, cache: &cache),
               let pages = cache[previous],
               !pages.isEmpty {
                return PageKey(chapterIndex: previous, pageIndex: max(pages.count - 1, 0))
            }
        }

        return nil
    }

    private func ensureChapter(_ index: Int, pageSize: CGSize, settings: ReadingSettings, cache: inout [Int: [PageData]]) -> Bool {
        guard chapters.indices.contains(index) else { return false }
        if let pages = cache[index], !pages.isEmpty { return true }

        let chapter = chapters[index]
        let parser = BookImportManager.shared.parserFor(format: book.fileFormat)
        do {
            let content = try parser.parseChapterContent(
                filePath: book.resolvedFilePath(),
                chapter: chapter,
                encoding: book.encoding ?? "UTF-8"
            )
            let pages = readablePages(
                from: paginate(content: content, chapter: chapter, chapterIndex: index, pageSize: pageSize, settings: settings),
                chapter: chapter
            )
            cache[index] = pages
            return !pages.isEmpty
        } catch {
            cache[index] = [
                PageData(
                    pageIndex: 0,
                    startCharOffset: 0,
                    endCharOffset: 0,
                    content: "本章加载失败",
                    chapterTitle: chapter.title,
                    chapterIndex: index
                )
            ]
            return true
        }
    }

    private func paginate(content: String, chapter: Chapter, chapterIndex: Int, pageSize: CGSize, settings: ReadingSettings) -> [PageData] {
        let text = content.isEmpty ? " " : content
        do {
            return try ReaderTextLayoutEngine.pages(
                content: text,
                chapter: chapter,
                chapterIndex: chapterIndex,
                pageSize: pageSize,
                settings: settings
            )
        } catch {
            LVLogger.error("Continuous reader pagination failed: \(error.localizedDescription)", category: .ui)
            return [
                PageData(
                    pageIndex: 0,
                    startCharOffset: 0,
                    endCharOffset: text.utf16.count,
                    content: text,
                    chapterTitle: chapter.title,
                    chapterIndex: chapterIndex
                )
            ]
        }
    }

    private func readablePages(from pages: [PageData], chapter: Chapter) -> [PageData] {
        let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = pages.filter { page in
            let content = page.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { return false }
            return chapterTitle.isEmpty || content != chapterTitle
        }
        return filtered.enumerated().map { index, page in
            PageData(
                pageIndex: index,
                startCharOffset: page.startCharOffset,
                endCharOffset: page.endCharOffset,
                content: page.content,
                chapterTitle: page.chapterTitle,
                chapterIndex: page.chapterIndex
            )
        }
    }

    private func previousKey(before key: PageKey, pageSize: CGSize, settings: ReadingSettings, cache: inout [Int: [PageData]]) -> PageKey? {
        if key.pageIndex > 0 {
            return PageKey(chapterIndex: key.chapterIndex, pageIndex: key.pageIndex - 1)
        }
        var chapter = key.chapterIndex - 1
        while chapter >= 0 {
            if ensureChapter(chapter, pageSize: pageSize, settings: settings, cache: &cache),
               let pages = cache[chapter],
               !pages.isEmpty {
                return PageKey(chapterIndex: chapter, pageIndex: pages.count - 1)
            }
            chapter -= 1
        }
        return nil
    }

    private func nextKey(after key: PageKey, pageSize: CGSize, settings: ReadingSettings, cache: inout [Int: [PageData]]) -> PageKey? {
        if let pages = cache[key.chapterIndex], key.pageIndex < pages.count - 1 {
            return PageKey(chapterIndex: key.chapterIndex, pageIndex: key.pageIndex + 1)
        }
        var chapter = key.chapterIndex + 1
        while chapter < chapters.count {
            if ensureChapter(chapter, pageSize: pageSize, settings: settings, cache: &cache),
               let pages = cache[chapter],
               !pages.isEmpty {
                return PageKey(chapterIndex: chapter, pageIndex: 0)
            }
            chapter += 1
        }
        return nil
    }

    private func move(_ direction: PageFlipDirection, animated: Bool) {
        guard !isPageFlipping, !isClosing else { return }
        let targetIndex = direction == .next
            ? (windowKeys.firstIndex(of: currentKey) ?? 0) + 1
            : (windowKeys.firstIndex(of: currentKey) ?? 0) - 1

        guard windowKeys.indices.contains(targetIndex) else {
            loadWindow(chapterIndex: currentKey.chapterIndex, pageIndex: currentKey.pageIndex, showLoading: false)
            return
        }

        let targetKey = windowKeys[targetIndex]
        guard let targetPage = page(for: targetKey) else { return }

        isPageFlipping = true
        nextPageView.render(page: targetPage, with: settings)
        nextPageView.setNeedsDisplay()
        nextPageView.layer.displayIfNeeded()

        let finish = { [weak self] in
            guard let self else { return }
            self.currentKey = targetKey
            self.renderCurrentPage()
            self.isPageFlipping = false
            self.loadWindow(chapterIndex: targetKey.chapterIndex, pageIndex: targetKey.pageIndex, showLoading: false)
        }

        if !animated || settings.pageFlipMode == .none {
            finish()
            return
        }

        PageFlipAnimator.animateTap(
            from: currentPageView,
            to: nextPageView,
            direction: direction,
            mode: settings.pageFlipMode,
            backgroundColor: UIColor(hex: settings.backgroundColor),
            container: containerView,
            completion: {
                self.applySimulationConfig()
                finish()
            }
        )
    }

    private func applySimulationConfig() {
        guard settings.pageFlipMode == .simulation else { return }
        SimulationAnimator.config = SimulationConfig(
            curlIntensity: CGFloat(settings.simulationCurlIntensity),
            shadowOpacity: CGFloat(settings.simulationShadowOpacity),
            animationDuration: settings.simulationDuration,
            springDamping: CGFloat(settings.simulationSpringDamping),
            initialVelocity: 0.5
        )
    }

    private func renderCurrentPage() {
        guard let page = page(for: currentKey) else { return }
        currentPageView.transform = .identity
        currentPageView.alpha = 1
        nextPageView.transform = .identity
        nextPageView.alpha = 0
        currentPageView.render(page: page, with: settings)
        updateLabels(page: page)
        applyTheme()
    }

    private func rebuildScrollPages(keepOffset: Bool) {
        guard settings.pageFlipMode == .scroll else { return }
        let oldOffset = scrollView.contentOffset
        scrollStackView.arrangedSubviews.forEach {
            scrollStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for key in windowKeys {
            guard let page = page(for: key) else { continue }
            let pageView = PageContainerView()
            pageView.translatesAutoresizingMaskIntoConstraints = false
            pageView.render(page: page, with: settings)
            scrollStackView.addArrangedSubview(pageView)
            pageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor).isActive = true
        }

        view.layoutIfNeeded()
        if keepOffset {
            scrollView.setContentOffset(oldOffset, animated: false)
        } else if let centerIndex = windowKeys.firstIndex(of: currentKey) {
            scrollView.setContentOffset(CGPoint(x: 0, y: CGFloat(centerIndex) * scrollView.bounds.height), animated: false)
        }
    }

    private func page(for key: PageKey) -> PageData? {
        chapterPages[key.chapterIndex]?[safe: key.pageIndex]
    }

    private func pageSize() -> CGSize {
        let bounds = containerView.bounds
        if bounds.width > 0, bounds.height > 0 { return bounds.size }
        return UIScreen.main.bounds.size
    }

    private func trimmedCache(_ cache: [Int: [PageData]], keeping keys: [PageKey]) -> [Int: [PageData]] {
        let chaptersToKeep = Set(keys.map(\.chapterIndex))
        return cache.filter { chaptersToKeep.contains($0.key) }
    }

    private func cacheResidentPages() {
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentKey.pageIndex)
        for key in windowKeys {
            guard let page = page(for: key) else { continue }
            PageCacheManager.shared.cachePage(page, bookId: book.id, pageIndex: page.pageIndex)
        }
    }

    private func saveProgress() {
        let progress = progressPercent()
        BookRepository.shared.updateProgress(
            bookId: book.id,
            progress: ReadingProgress(
                currentChapterIndex: currentKey.chapterIndex,
                currentPageOffset: currentKey.pageIndex,
                totalPages: max(book.readingProgress.totalPages, windowKeys.count),
                progressPercent: progress,
                lastReadTimestamp: Date()
            )
        )
        WebSyncServer.shared.notifyPageChanged(
            pageIndex: currentKey.pageIndex,
            chapterTitle: chapters[safe: currentKey.chapterIndex]?.title ?? "",
            progressPercent: progress
        )
    }

    private func progressPercent() -> Double {
        guard !chapters.isEmpty else { return 0 }
        let chapterBase = Double(currentKey.chapterIndex) / Double(chapters.count)
        let pageCount = Double(chapterPages[currentKey.chapterIndex]?.count ?? max(currentKey.pageIndex + 1, 1))
        let pagePart = Double(currentKey.pageIndex) / max(pageCount, 1) / Double(chapters.count)
        return min(100, max(0, (chapterBase + pagePart) * 100))
    }

    private func updateLabels(page: PageData) {
        topLabel.text = page.chapterTitle
        bottomLabel.text = "\(page.pageIndex + 1)/\(chapterPages[page.chapterIndex]?.count ?? page.pageIndex + 1)"
        timeLabel.text = currentTimeText()
    }

    private func applyTheme() {
        let background = UIColor(hex: settings.backgroundColor)
        let textColor = UIColor(hex: settings.readingTheme.textColor)
        view.backgroundColor = background
        containerView.backgroundColor = background
        scrollView.backgroundColor = background
        chromeView.backgroundColor = UIColor(hex: settings.readingTheme.panelColor)
        topBackButton.tintColor = textColor.withAlphaComponent(0.65)
        applyTint(textColor.withAlphaComponent(0.78), in: chromeView)
        topLabel.textColor = textColor.withAlphaComponent(0.42)
        bottomLabel.textColor = textColor.withAlphaComponent(0.42)
        timeLabel.textColor = textColor.withAlphaComponent(0.42)
        batteryView.strokeColor = textColor.withAlphaComponent(0.36)
        batteryView.fillColor = textColor.withAlphaComponent(0.52)
        if settings.eyeCareFilter == .none {
            eyeCareOverlayView.backgroundColor = .clear
        } else {
            eyeCareOverlayView.backgroundColor = UIColor(hex: settings.eyeCareFilter.filterColor)
                .withAlphaComponent(CGFloat(settings.eyeCareFilter.overlayAlpha))
        }
        brightnessOverlayView.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(max(0, min(1, 1 - settings.brightness))))
        view.bringSubviewToFront(eyeCareOverlayView)
        view.bringSubviewToFront(brightnessOverlayView)
    }

    private func applyTint(_ color: UIColor, in view: UIView) {
        if let button = view as? UIButton {
            button.tintColor = color
        }
        view.subviews.forEach { applyTint(color, in: $0) }
    }

    private func currentTimeText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func startClockTimer() {
        timeLabel.text = currentTimeText()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.timeLabel.text = self?.currentTimeText()
        }
    }

    private func toggleChrome() {
        let show = chromeView.alpha < 0.5
        scrollView.isScrollEnabled = !show
        let hiddenTransform = CGAffineTransform(translationX: 0, y: max(chromeView.bounds.height, 1))
        if show {
            view.bringSubviewToFront(chromeView)
            view.bringSubviewToFront(eyeCareOverlayView)
            view.bringSubviewToFront(brightnessOverlayView)
            chromeView.transform = hiddenTransform
            chromeView.alpha = 0
        }
        UIView.animate(withDuration: 0.24, delay: 0, options: [show ? .curveEaseOut : .curveEaseIn, .beginFromCurrentState]) {
            self.chromeView.alpha = show ? 1 : 0
            self.chromeView.transform = show ? .identity : hiddenTransform
        } completion: { _ in
            if show {
                self.chromeView.transform = .identity
            }
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    private func releaseReaderMemory() {
        isClosing = true
        loadGeneration += 1
        clockTimer?.invalidate()
        clockTimer = nil
        settingsReloadWorkItem?.cancel()
        settingsReloadWorkItem = nil
        chapterPages.removeAll()
        windowKeys.removeAll()
        currentPageView.clear()
        nextPageView.clear()
        scrollStackView.arrangedSubviews.forEach {
            scrollStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        PageContainerView.clearWatermarkCache()
        PageCacheManager.shared.clearBookCache(book.id)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if chromeView.alpha > 0.5 {
            if !chromeView.frame.contains(location) {
                toggleChrome()
            }
            return
        }
        if settings.pageFlipMode == .scroll {
            toggleChrome()
            return
        }
        let third = view.bounds.width / 3
        if location.x < third {
            move(.prev, animated: true)
        } else if location.x > third * 2 {
            move(.next, animated: true)
        } else {
            toggleChrome()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard chromeView.alpha < 0.5, settings.pageFlipMode != .scroll, settings.pageFlipMode != .none else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            applySimulationConfig()
            let direction: PageFlipDirection = velocity.x < 0 ? .next : .prev
            let targetIndex = direction == .next
                ? (windowKeys.firstIndex(of: currentKey) ?? 0) + 1
                : (windowKeys.firstIndex(of: currentKey) ?? 0) - 1
            guard windowKeys.indices.contains(targetIndex),
                  let page = page(for: windowKeys[targetIndex]) else { return }
            nextPageView.render(page: page, with: settings)
            nextPageView.layer.displayIfNeeded()
            PageFlipAnimator.beginInteractive(
                from: currentPageView,
                to: nextPageView,
                direction: direction,
                mode: settings.pageFlipMode,
                container: containerView,
                state: flipState
            )
        case .changed:
            let progress = min(1, abs(translation.x) / max(view.bounds.width, 1))
            PageFlipAnimator.updateInteractive(progress: progress, mode: settings.pageFlipMode, state: flipState)
        case .ended, .cancelled:
            let shouldCommit = abs(translation.x) > view.bounds.width * 0.24 || abs(velocity.x) > 650
            let targetIndex = flipState.direction == .next
                ? (windowKeys.firstIndex(of: currentKey) ?? 0) + 1
                : (windowKeys.firstIndex(of: currentKey) ?? 0) - 1
            PageFlipAnimator.finishInteractive(commit: shouldCommit, mode: settings.pageFlipMode, state: flipState) { [weak self] committed in
                guard let self else { return }
                if committed, self.windowKeys.indices.contains(targetIndex) {
                    let target = self.windowKeys[targetIndex]
                    self.currentKey = target
                    self.renderCurrentPage()
                    self.loadWindow(chapterIndex: target.chapterIndex, pageIndex: target.pageIndex, showLoading: false)
                } else {
                    self.renderCurrentPage()
                }
            }
        default:
            break
        }
    }

    @objc private func backTapped() {
        saveProgress()
        releaseReaderMemory()
        if let navigationController, navigationController.viewControllers.contains(self) {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func catalogTapped() {
        let vc = ChapterListViewController(book: book, chapters: chapters, currentIndex: currentKey.chapterIndex)
        vc.onChapterSelected = { [weak self] index in
            self?.loadWindow(chapterIndex: index, pageIndex: 0, showLoading: true)
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    @objc private func nightTapped() {
        settings.nightMode.toggle()
        settings.readingTheme = settings.nightMode ? .midnight : .white
        settings.backgroundColor = settings.readingTheme.backgroundColor
        renderCurrentPage()
        rebuildScrollPages(keepOffset: true)
    }

    @objc private func themeSettingsTapped() {
        presentSettings(mode: .theme)
    }

    @objc private func layoutSettingsTapped() {
        presentSettings(mode: .layout)
    }

    private func presentSettings(mode: ReaderSettingsViewController.PanelMode) {
        let vc = ReaderSettingsViewController(settings: settings, mode: mode)
        vc.onSettingsChanged = { [weak self] newSettings in
            self?.applySettings(newSettings)
        }
        vc.modalPresentationStyle = .overCurrentContext
        present(vc, animated: false)
    }

    private func applySettings(_ newSettings: ReadingSettings) {
        let anchorOffset = page(for: currentKey)?.startCharOffset
        settings = newSettings
        pendingLoadCenter = nil
        loadGeneration += 1
        setupGestures()
        applyTheme()
        renderCurrentPage()
        rebuildScrollPages(keepOffset: true)

        settingsReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isClosing else { return }
            self.chapterPages.removeAll()
            self.pendingLoadCenter = nil
            self.loadWindow(
                chapterIndex: self.currentKey.chapterIndex,
                pageIndex: self.currentKey.pageIndex,
                showLoading: false,
                anchorCharOffset: anchorOffset
            )
        }
        settingsReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }
}

extension ContinuousReaderViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard chromeView.alpha < 0.5,
              settings.pageFlipMode == .scroll,
              scrollView.bounds.height > 0,
              !windowKeys.isEmpty else { return }
        let index = min(max(Int(round(scrollView.contentOffset.y / scrollView.bounds.height)), 0), windowKeys.count - 1)
        let key = windowKeys[index]
        if key != currentKey {
            currentKey = key
            if let page = page(for: key) {
                updateLabels(page: page)
                saveProgress()
            }
        }

        if index >= windowKeys.count - 3 || index <= 2 {
            loadWindow(chapterIndex: currentKey.chapterIndex, pageIndex: currentKey.pageIndex, showLoading: false)
        }
    }
}

extension ContinuousReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if chromeView.alpha > 0.5, touch.view?.isDescendant(of: chromeView) == true {
            return false
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        if isPageFlipping || chromeView.alpha > 0.5 { return false }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }
}
