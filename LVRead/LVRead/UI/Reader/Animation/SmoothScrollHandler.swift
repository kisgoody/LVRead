import UIKit

/// Smooth, free-scrolling vertical reader.
/// Pages from the current chapter are laid out continuously. When the user
/// scrolls near the end, the next chapter is appended for seamless reading.
final class SmoothScrollHandler: NSObject {

    struct Callbacks {
        var onPageChanged: ((Int) -> Void)?
        var onChapterEntered: ((Int) -> Void)?    // chapter index just entered
        var onChapterLeft: ((Int, Bool) -> Void)? // (chapter index, goingNext)
    }

    // MARK: - Properties

    private let scrollView: UIScrollView
    private let contentView = UIView()

    /// All loaded page data, keyed by chapter index.
    private var chapterPages: [Int: [PageData]] = [:]
    private var chapterStartIndices: [Int: Int] = [:]  // chapter -> first page global index
    private var chapterEndIndices: [Int: Int] = [:]    // chapter -> last page global index
    private var settings: ReadingSettings = .default
    private var totalPages: Int = 0
    private var currentChapterIdx: Int = -1
    private var layoutPageHeight: CGFloat = 0
    private var needsChapterLoad: ((Int) -> Void)?  // callback to load a chapter

    private(set) var trackedPageIndex: Int = 0
    private(set) var trackedChapterIndex: Int = -1

    var callbacks = Callbacks()

    // MARK: - Init

    init(scrollView: UIScrollView, chapterLoader: @escaping (Int) -> Void) {
        self.scrollView = scrollView
        self.needsChapterLoad = chapterLoader
        super.init()
        scrollView.delegate = self
        scrollView.isPagingEnabled = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.clipsToBounds = true
        scrollView.addSubview(contentView)
    }

    // MARK: - Layout

    func loadChapter(_ index: Int, pages: [PageData], settings: ReadingSettings, initialPage: Int) {
        self.settings = settings
        currentChapterIdx = index

        // Store chapter data
        chapterPages[index] = pages
        updateChapterIndices()

        rebuildContent(initialChapter: index, initialPage: initialPage)

        // Prefetch next chapter if not already loaded
        if chapterPages[index + 1] == nil {
            needsChapterLoad?(index + 1)
        }
    }

    /// Append a preloaded chapter to the scroll content.
    func appendChapter(_ index: Int, pages: [PageData]) {
        guard !pages.isEmpty, chapterPages[index] == nil else { return }
        guard let baseIdx = chapterEndIndices[currentChapterIdx] else { return }

        chapterPages[index] = pages
        updateChapterIndices()

        guard layoutPageHeight > 0 else { return }
        let pageWidth = contentView.frame.width
        let pageHeight = layoutPageHeight

        let startY = contentView.frame.height

        for (i, page) in pages.enumerated() {
            let frame = CGRect(x: 0, y: startY + CGFloat(i) * pageHeight, width: pageWidth, height: pageHeight)
            let pageView = PageContainerView()
            pageView.frame = frame
            pageView.render(page: page, with: settings)
            contentView.addSubview(pageView)
        }

        let newHeight = startY + CGFloat(pages.count) * pageHeight
        contentView.frame = CGRect(x: 0, y: 0, width: pageWidth, height: newHeight)
        scrollView.contentSize = CGSize(width: pageWidth, height: newHeight)
        totalPages += pages.count
    }

    /// Refresh rendering without rebuilding layout.
    func refreshRendering(settings: ReadingSettings) {
        self.settings = settings
        for sv in contentView.subviews {
            if let pv = sv as? PageContainerView, let pd = pv.pageData {
                pv.render(page: pd, with: settings)
            }
        }
    }

    func scrollToChapter(_ index: Int, page: Int, animated: Bool) {
        guard let startIdx = chapterStartIndices[index] else { return }
        let targetY = CGFloat(startIdx + page) * layoutPageHeight
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentChapterIdx = index
        trackedPageIndex = startIdx + page
        trackedChapterIndex = index
    }

    /// Convert global page index to local page within the current chapter.
    func localPage(forGlobal global: Int) -> Int {
        guard let start = chapterStartIndices[trackedChapterIndex] else { return global }
        return max(0, global - start)
    }

    /// Total pages in the currently tracked chapter, or 0.
    func currentChapterPageCount() -> Int {
        guard let pages = chapterPages[trackedChapterIndex] else { return 0 }
        return pages.count
    }

    // MARK: - Private

    private func updateChapterIndices() {
        chapterStartIndices.removeAll()
        chapterEndIndices.removeAll()
        var offset = 0
        let sorted = chapterPages.keys.sorted()
        for idx in sorted {
            guard let pages = chapterPages[idx] else { continue }
            chapterStartIndices[idx] = offset
            chapterEndIndices[idx] = offset + pages.count - 1
            offset += pages.count
        }
        totalPages = offset
    }

    private func rebuildContent(initialChapter: Int, initialPage: Int) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let pageWidth = scrollView.bounds.width
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0, pageWidth > 0 else { return }
        layoutPageHeight = pageHeight

        var yOffset: CGFloat = 0
        let sorted = chapterPages.keys.sorted()

        for chIdx in sorted {
            guard let pages = chapterPages[chIdx] else { continue }
            for page in pages {
                let pv = PageContainerView()
                pv.frame = CGRect(x: 0, y: yOffset, width: pageWidth, height: pageHeight)
                pv.render(page: page, with: settings)
                contentView.addSubview(pv)
                yOffset += pageHeight
            }
        }

        contentView.frame = CGRect(x: 0, y: 0, width: pageWidth, height: yOffset)
        scrollView.contentSize = CGSize(width: pageWidth, height: yOffset)

        // Jump to initial position
        guard let startIdx = chapterStartIndices[initialChapter] else { return }
        let targetY = CGFloat(startIdx + initialPage) * pageHeight
        scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        currentChapterIdx = initialChapter
        trackedPageIndex = startIdx + initialPage
        trackedChapterIndex = initialChapter
    }

    private func globalPageToChapter(_ globalPage: Int) -> Int {
        for (ch, start) in chapterStartIndices {
            if let end = chapterEndIndices[ch], globalPage >= start, globalPage <= end {
                return ch
            }
        }
        return currentChapterIdx
    }
}

// MARK: - UIScrollViewDelegate

extension SmoothScrollHandler: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard layoutPageHeight > 0, totalPages > 0 else { return }
        let pageHeight = layoutPageHeight

        let centerY = scrollView.contentOffset.y + pageHeight / 2
        let globalPage = max(0, min(totalPages - 1, Int(centerY / pageHeight)))

        if globalPage != trackedPageIndex {
            trackedPageIndex = globalPage
            let ch = globalPageToChapter(globalPage)
            if ch != trackedChapterIndex {
                trackedChapterIndex = ch
                callbacks.onChapterEntered?(ch)
                // Prefetch next chapter
                if chapterPages[ch + 1] == nil {
                    needsChapterLoad?(ch + 1)
                }
            }
            callbacks.onPageChanged?(globalPage)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
        let overScroll = scrollView.contentOffset.y - maxOffset

        if overScroll > 120 {
            // Scrolled significantly past last page — trigger chapter load if available
            let nextCh = currentChapterIdx + 1
            if chapterPages[nextCh] == nil {
                needsChapterLoad?(nextCh)
            }
        }
        if scrollView.contentOffset.y < -120 {
            let prevCh = currentChapterIdx - 1
            if prevCh >= 0, chapterPages[prevCh] == nil {
                needsChapterLoad?(prevCh)
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Already handled by scrollViewDidScroll
    }
}
