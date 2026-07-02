import UIKit

/// Smooth, free-scrolling vertical reader.
/// Pages from the current chapter are laid out continuously. When the user
/// scrolls near the end, the next chapter is appended for seamless reading.
final class SmoothScrollHandler: NSObject {

    private struct PageKey: Hashable {
        let chapter: Int
        let page: Int
    }

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
    private var pageFrames: [PageKey: CGRect] = [:]
    private var visiblePageViews: [PageKey: PageContainerView] = [:]
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
        let insertedBeforeCurrent = currentChapterIdx >= 0 && index < currentChapterIdx
        let previousOffset = scrollView.contentOffset.y

        chapterPages[index] = pages
        updateChapterIndices()

        guard layoutPageHeight > 0 else { return }
        let pageWidth = contentView.frame.width
        let pageHeight = layoutPageHeight

        if insertedBeforeCurrent {
            let insertedHeight = pages.reduce(CGFloat(0)) { $0 + height(for: $1, pageWidth: pageWidth, maxHeight: pageHeight) }
            rebuildPages(pageWidth: pageWidth, pageHeight: pageHeight)
            scrollView.contentOffset = CGPoint(x: 0, y: previousOffset + insertedHeight)
            updateVisiblePages()
            return
        }
        rebuildPages(pageWidth: pageWidth, pageHeight: pageHeight)
    }

    func invalidate() {
        if scrollView.delegate === self {
            scrollView.delegate = nil
        }
        visiblePageViews.values.forEach { $0.removeFromSuperview() }
        visiblePageViews.removeAll()
        pageFrames.removeAll()
        chapterPages.removeAll()
        chapterStartIndices.removeAll()
        chapterEndIndices.removeAll()
        totalPages = 0
        needsChapterLoad = nil
    }

    /// Refresh rendering without rebuilding layout.
    func refreshRendering(settings: ReadingSettings) {
        self.settings = settings
        for pv in visiblePageViews.values {
            if let pd = pv.pageData {
                pv.render(page: pd, with: settings)
            }
        }
    }

    func scrollToChapter(_ index: Int, page: Int, animated: Bool) {
        guard let startIdx = chapterStartIndices[index] else { return }
        let targetY = contentOffsetY(forChapter: index, page: page)
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
        visiblePageViews.values.forEach { $0.removeFromSuperview() }
        visiblePageViews.removeAll()
        let pageWidth = scrollView.bounds.width
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0, pageWidth > 0 else { return }
        layoutPageHeight = pageHeight

        rebuildPages(pageWidth: pageWidth, pageHeight: pageHeight)

        // Jump to initial position
        guard let startIdx = chapterStartIndices[initialChapter] else { return }
        let targetY = contentOffsetY(forChapter: initialChapter, page: initialPage)
        scrollView.contentOffset = CGPoint(x: 0, y: targetY)
        currentChapterIdx = initialChapter
        trackedPageIndex = startIdx + initialPage
        trackedChapterIndex = initialChapter
    }

    private func rebuildPages(pageWidth: CGFloat, pageHeight: CGFloat) {
        pageFrames.removeAll()
        var yOffset: CGFloat = 0

        for chIdx in chapterPages.keys.sorted() {
            guard let pages = chapterPages[chIdx] else { continue }
            for (pageIndex, page) in pages.enumerated() {
                let pageHeightForContent = height(for: page, pageWidth: pageWidth, maxHeight: pageHeight)
                pageFrames[PageKey(chapter: chIdx, page: pageIndex)] = CGRect(
                    x: 0,
                    y: yOffset,
                    width: pageWidth,
                    height: pageHeightForContent
                )
                yOffset += pageHeightForContent
            }
        }

        contentView.frame = CGRect(x: 0, y: 0, width: pageWidth, height: yOffset)
        scrollView.contentSize = CGSize(width: pageWidth, height: yOffset)
        for key in Array(visiblePageViews.keys) {
            guard let frame = pageFrames[key] else {
                visiblePageViews[key]?.removeFromSuperview()
                visiblePageViews[key] = nil
                continue
            }
            visiblePageViews[key]?.frame = frame
        }
        updateVisiblePages()
    }

    private func updateVisiblePages() {
        guard scrollView.bounds.height > 0 else { return }
        let preloadHeight = scrollView.bounds.height * 2.5
        let visibleRect = CGRect(
            x: 0,
            y: scrollView.contentOffset.y - preloadHeight,
            width: scrollView.bounds.width,
            height: scrollView.bounds.height + preloadHeight * 2
        )
        let needed = Set(pageFrames.compactMap { key, frame in
            frame.intersects(visibleRect) ? key : nil
        })

        for key in Array(visiblePageViews.keys) where !needed.contains(key) {
            visiblePageViews[key]?.removeFromSuperview()
            visiblePageViews[key] = nil
        }

        let orderedKeys = needed.sorted {
            (pageFrames[$0]?.minY ?? 0) < (pageFrames[$1]?.minY ?? 0)
        }
        for key in orderedKeys {
            guard visiblePageViews[key] == nil,
                  let frame = pageFrames[key],
                  let page = chapterPages[key.chapter]?[safe: key.page] else { continue }
            let pageView = PageContainerView()
            pageView.frame = frame
            pageView.render(page: page, with: settings)
            contentView.addSubview(pageView)
            visiblePageViews[key] = pageView
        }
    }

    private func globalPageToChapter(_ globalPage: Int) -> Int {
        for (ch, start) in chapterStartIndices {
            if let end = chapterEndIndices[ch], globalPage >= start, globalPage <= end {
                return ch
            }
        }
        return currentChapterIdx
    }

    private func contentOffsetY(forChapter chapter: Int, page: Int) -> CGFloat {
        if let frame = pageFrames[PageKey(chapter: chapter, page: page)] {
            return frame.minY
        }
        let pageWidth = max(contentView.frame.width, scrollView.bounds.width)
        let maxHeight = max(layoutPageHeight, scrollView.bounds.height)
        var y: CGFloat = 0

        for chIdx in chapterPages.keys.sorted() {
            guard let pages = chapterPages[chIdx] else { continue }
            if chIdx == chapter {
                for pageData in pages.prefix(max(0, min(page, pages.count))) {
                    y += height(for: pageData, pageWidth: pageWidth, maxHeight: maxHeight)
                }
                return y
            }
            y += pages.reduce(CGFloat(0)) { $0 + height(for: $1, pageWidth: pageWidth, maxHeight: maxHeight) }
        }
        return y
    }

    private func height(for page: PageData, pageWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let marginH = CGFloat(settings.pageMarginHorizontal) * pageWidth / 100
        let textWidth = max(1, pageWidth - marginH * 2)
        let font = FontManager.shared.font(named: settings.fontFamily, size: CGFloat(settings.fontSize))
        let para = NSMutableParagraphStyle()
        para.lineSpacing = font.lineHeight * CGFloat(settings.lineSpacing - 1.0)
        para.paragraphSpacing = font.lineHeight * CGFloat(settings.paragraphSpacing)
        para.alignment = .natural
        let attr = NSAttributedString(string: page.content, attributes: [.font: font, .paragraphStyle: para])
        let rect = attr.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let verticalPadding: CGFloat = 28
        return min(maxHeight, max(80, ceil(rect.height) + verticalPadding))
    }

    private func globalPage(at y: CGFloat) -> Int {
        var global = 0

        for chIdx in chapterPages.keys.sorted() {
            guard let pages = chapterPages[chIdx] else { continue }
            for pageIndex in pages.indices {
                if let frame = pageFrames[PageKey(chapter: chIdx, page: pageIndex)], y < frame.maxY {
                    return max(0, min(totalPages - 1, global))
                }
                global += 1
            }
        }

        return max(0, totalPages - 1)
    }
}

// MARK: - UIScrollViewDelegate

extension SmoothScrollHandler: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisiblePages()
        guard layoutPageHeight > 0, totalPages > 0 else { return }
        let pageHeight = layoutPageHeight

        let centerY = scrollView.contentOffset.y + pageHeight / 2
        let globalPage = globalPage(at: centerY)

        if globalPage != trackedPageIndex {
            trackedPageIndex = globalPage
            let ch = globalPageToChapter(globalPage)
            if ch != trackedChapterIndex {
                trackedChapterIndex = ch
                currentChapterIdx = ch
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
