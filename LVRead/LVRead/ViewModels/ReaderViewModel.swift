import UIKit
import CoreText
import Foundation
import Combine

// MARK: - Reader ViewModel
//
// ⚠️ 遗留代码 (Legacy) — 已被 ContinuousReaderViewController 替代
//     ContinuousReaderViewController 使用 PageKey 模型正确实现了：
//     - 跨章节连续加载（makeWindow ±5 页窗口）
//     - previousKey/nextKey 跨章节翻页
//     - 翻页方向感知的缓存调度
//     本文件保留以维持编译，不再主动使用。
//     当前存在的问题：
//     - chapterPages 始终只操作 .first，不支持跨章节拼接
//     - 单章节页数不足时不会加载相邻章节

final class ReaderViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var currentPage: PageData?
    @Published private(set) var currentChapterTitle: String = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var totalPages: Int = 0
    @Published private(set) var currentPageIndex: Int = 0
    @Published private(set) var isLoading: Bool = false
    
    @Published var settings: ReadingSettings {
        didSet { saveSettings() }
    }
    
    @Published var isAutoReading: Bool = false
    @Published var autoReadSpeed: Int = 5

    // MARK: - Private Properties

    private let book: Book
    private var chapters: [Chapter] = []
    private var chapterPages: [[PageData]] = []
    private var currentChapterIndex: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private let bookRepository = BookRepository.shared
    private let settingsRepository = ReadingSettingsRepository.shared

    // MARK: - Initialization

    init(book: Book) {
        self.book = book
        self.settings = settingsRepository.load()
        self.currentChapterIndex = book.readingProgress.currentChapterIndex
        self.currentPageIndex = book.readingProgress.currentPageOffset
        
        loadChapters()
    }

    // MARK: - Public Methods

   func loadChapter(at index: Int) {
       guard index >= 0 && index < chapters.count else { return }
       
       isLoading = true
       
        let viewWidth = UIScreen.main.bounds.width
        let viewHeight = UIScreen.main.bounds.height - 200
        
       DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let chapter = self.chapters[index]
            let parser = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            
            do {
                let content = try parser.parseChapterContent(
                    filePath: self.book.resolvedFilePath(),
                    chapter: chapter,
                    encoding: self.book.encoding ?? "UTF-8"
                )
                
               let pages = self.paginateContent(
                   content,
                    viewWidth: viewWidth,
                    viewHeight: viewHeight
               )
                
                DispatchQueue.main.async {
                    self.chapterPages = [pages]
                    self.currentChapterIndex = index
                    self.currentPageIndex = 0
                    self.totalPages = pages.count
                    
                    if let firstPage = pages.first {
                        self.currentPage = firstPage
                        self.currentChapterTitle = chapter.title
                    }
                    
                    self.isLoading = false
                    self.updateProgress()
                    self.cachePages(pages)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    func goToNextPage() {
        guard let pages = chapterPages.first else { return }
        
       if currentPageIndex < pages.count - 1 {
           currentPageIndex += 1
            PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentPageIndex)
            currentPage = pages[currentPageIndex]
            updateProgress()
            prefetchNextChapter()
        }
    }

    func goToPrevPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentPageIndex)
            if let pages = chapterPages.first {
                currentPage = pages[currentPageIndex]
            }
            updateProgress()
        }
    }

    func goToNextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        loadChapter(at: currentChapterIndex + 1)
    }

    func goToPrevChapter() {
        guard currentChapterIndex > 0 else { return }
        loadChapter(at: currentChapterIndex - 1)
    }

    func goToChapter(at index: Int) {
        loadChapter(at: index)
    }

    // MARK: - Auto Read

    func toggleAutoRead() {
        isAutoReading.toggle()
    }

    // MARK: - Settings

    func applySettings() {
        // Trigger UI refresh for settings change
        objectWillChange.send()
    }

    // MARK: - Private Methods

    private func loadChapters() {
        chapters = bookRepository.getChapters(for: book.id)
        
        if chapters.isEmpty {
            // Create a default chapter if none exist
            chapters = [Chapter(bookId: book.id, title: "正文", level: 1, orderIndex: 0)]
        }
        
        loadChapter(at: currentChapterIndex)
    }

    private func paginateContent(_ content: String, viewWidth: CGFloat, viewHeight: CGFloat) -> [PageData] {
        let content = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: content)
        let marginH = CGFloat(settings.pageMarginHorizontal) * viewWidth / 100
        let pageW = viewWidth - marginH * 2
        
        let font = FontManager.shared.font(named: settings.fontFamily, size: CGFloat(settings.fontSize))
        let para = NSMutableParagraphStyle()
        let y = font.lineHeight * CGFloat(max(settings.lineSpacing - 1.0, 0))
        let paragraphValue = settings.paragraphSpacing ?? settings.lineSpacing
        let x = font.lineHeight * CGFloat(max(paragraphValue - 1.0, 0))
        para.lineSpacing = y
        para.paragraphSpacing = x - y
        para.alignment = .justified
        
        let attr = NSAttributedString(string: content, attributes: [.font: font, .paragraphStyle: para])
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        
        var pages: [PageData] = []
        var offset = 0
        let totalLen = attr.length
        
        while offset < totalLen {
            let rect = CGRect(x: 0, y: 0, width: pageW, height: max(viewHeight, 60))
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(offset, 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            
            guard visible.length > 0 else { break }
            
            let lo = String.Index(utf16Offset: visible.location, in: content)
            let hi = String.Index(utf16Offset: visible.location + visible.length, in: content)
            
            pages.append(PageData(
                pageIndex: pages.count,
                startCharOffset: visible.location,
                endCharOffset: visible.location + visible.length,
                content: String(content[lo..<hi]),
                chapterTitle: chapters[safe: currentChapterIndex]?.title ?? "",
                chapterIndex: currentChapterIndex
            ))
            
            offset = visible.location + visible.length
        }
        
        if pages.isEmpty {
            pages.append(PageData(
                pageIndex: 0,
                startCharOffset: 0,
                endCharOffset: 0,
                content: content,
                chapterTitle: chapters[safe: currentChapterIndex]?.title ?? "",
                chapterIndex: currentChapterIndex
            ))
        }
        
        return pages
    }

    private func updateProgress() {
        let total = chapterPages.first?.count ?? 0
        if total > 0 {
            progress = Double(currentPageIndex + 1) / Double(total) * 100
        }
        
        // Save progress to database
        bookRepository.updateProgress(
            bookId: book.id,
            progress: ReadingProgress(
                currentChapterIndex: currentChapterIndex,
                currentPageOffset: currentPageIndex,
                totalPages: total,
                progressPercent: progress,
                lastReadTimestamp: Date()
            )
        )
        
        // Notify web sync
        WebSyncServer.shared.notifyPageChanged(
            pageIndex: currentPageIndex,
            chapterTitle: currentChapterTitle,
            progressPercent: progress
        )
    }

    private func saveSettings() {
        settingsRepository.save(settings)
    }

    private func cachePages(_ pages: [PageData]) {
        PageCacheManager.shared.setCurrentBook(book.id, pageIndex: currentPageIndex)
        for page in pages {
            PageCacheManager.shared.cachePage(page, bookId: book.id, pageIndex: page.pageIndex)
        }
    }

   private func prefetchNextChapter() {
       let next = currentChapterIndex + 1
       guard next < chapters.count else { return }
       
        let viewWidth = UIScreen.main.bounds.width
        let viewHeight = UIScreen.main.bounds.height - 200
        
       DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let ch = self.chapters[next]
            let p = BookImportManager.shared.parserFor(format: self.book.fileFormat)
            
            if let c = try? p.parseChapterContent(
                filePath: self.book.resolvedFilePath(),
                chapter: ch,
                encoding: self.book.encoding ?? "UTF-8"
            ) {
                let pages = self.paginateContent(
                    c,
                    viewWidth: viewWidth,
                    viewHeight: viewHeight
                )
                self.cachePages(pages)
            }
        }
    }
}
