import UIKit

final class PageCacheManager {
    static let shared = PageCacheManager()

    private let l1Cache = NSCache<NSString, PageData>()
    private let l3BasePath: String

    private var currentBookId: String?
    private var currentPageIndex: Int = 0
    private let l1Range = 5
    private let immediateDiskRange = 40
    private let maxDiskCacheSize: UInt64 = 80 * 1024 * 1024
    private let maxIdleAge: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        l1Cache.countLimit = 11

        let cachesDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        l3BasePath = (cachesDir as NSString).appendingPathComponent("PageCache")
        try? FileManager.default.createDirectory(atPath: l3BasePath, withIntermediateDirectories: true)
        cleanupDiskCache()
    }

    func setCurrentBook(_ bookId: String, pageIndex: Int) {
        if currentBookId != bookId || currentPageIndex != pageIndex {
            l1Cache.removeAllObjects()
        }
        currentBookId = bookId
        currentPageIndex = pageIndex
    }

    func cacheKey(for bookId: String, pageIndex: Int) -> String {
        cacheKey(for: bookId, chapterIndex: 0, pageIndex: pageIndex)
    }

    func cacheKey(for bookId: String, chapterIndex: Int, pageIndex: Int) -> String {
        "\(bookId)_\(chapterIndex)_\(pageIndex)"
    }

    func getPage(bookId: String, pageIndex: Int) -> PageData? {
        getPage(bookId: bookId, chapterIndex: 0, pageIndex: pageIndex)
    }

    func getPage(bookId: String, chapterIndex: Int, pageIndex: Int) -> PageData? {
        let key = cacheKey(for: bookId, chapterIndex: chapterIndex, pageIndex: pageIndex)

        if let page = l1Cache.object(forKey: key as NSString) { return page }

        let path = (l3BasePath as NSString).appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let page = try? JSONDecoder().decode(PageData.self, from: data) {
            touchDiskFile(at: path)
            if abs(pageIndex - currentPageIndex) <= l1Range {
                l1Cache.setObject(page, forKey: key as NSString)
            }
            return page
        }
        return nil
    }

    func cachePage(_ page: PageData, bookId: String, pageIndex: Int) {
        let key = cacheKey(for: bookId, chapterIndex: page.chapterIndex, pageIndex: pageIndex)
        let nsKey = key as NSString

        let distance = abs(pageIndex - currentPageIndex)
        if distance <= l1Range {
            l1Cache.setObject(page, forKey: nsKey)
        }

        let path = (l3BasePath as NSString).appendingPathComponent("\(key).json")
        DispatchQueue.global(qos: .utility).async {
            self.writePage(page, to: path)
            self.cleanupDiskCache()
        }
    }

    func cachePages(_ pages: [PageData], bookId: String, centerPage: Int? = nil) {
        let current = centerPage ?? currentPageIndex
        let immediate = pages.filter { abs($0.pageIndex - current) <= immediateDiskRange }
        let deferred = pages.filter { abs($0.pageIndex - current) > immediateDiskRange }

        for page in immediate {
            cachePageInMemoryIfNeeded(page, bookId: bookId, currentPage: current)
            writePage(page, bookId: bookId)
        }

        DispatchQueue.global(qos: .utility).async {
            for page in deferred {
                self.writePage(page, bookId: bookId)
            }
            self.cleanupDiskCache()
        }
    }

    func prefetchPages(bookId: String, currentPage: Int, direction: Int) {
        let start = direction > 0 ? currentPage + 1 : currentPage - 10
        let end = direction > 0 ? currentPage + 10 : currentPage - 1

        DispatchQueue.global(qos: .utility).async {
            for pageIdx in start...end where pageIdx >= 0 {
                if self.getPage(bookId: bookId, pageIndex: pageIdx) == nil {
                    // Placeholder — actual layout is done in ReaderViewModel
                }
            }
        }
    }

    func clearBookCache(_ bookId: String) {
        l1Cache.removeAllObjects()
        let prefix = "\(bookId)_"
        if let files = try? FileManager.default.contentsOfDirectory(atPath: l3BasePath) {
            for file in files where file.hasPrefix(prefix) {
                try? FileManager.default.removeItem(atPath: (l3BasePath as NSString).appendingPathComponent(file))
            }
        }
    }

    func handleMemoryWarning() {
        l1Cache.removeAllObjects()
    }

    func handleBackgroundTransition() {
        l1Cache.removeAllObjects()
        cleanupDiskCache()
    }

    func clearAll() {
        l1Cache.removeAllObjects()
        try? FileManager.default.removeItem(atPath: l3BasePath)
        try? FileManager.default.createDirectory(atPath: l3BasePath, withIntermediateDirectories: true)
    }

    private func touchDiskFile(at path: String) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
    }

    private func writePage(_ page: PageData, to path: String) {
        if let data = try? JSONEncoder().encode(page) {
            try? data.write(to: URL(fileURLWithPath: path))
            touchDiskFile(at: path)
        }
    }

    private func writePage(_ page: PageData, bookId: String) {
        let key = cacheKey(for: bookId, chapterIndex: page.chapterIndex, pageIndex: page.pageIndex)
        let path = (l3BasePath as NSString).appendingPathComponent("\(key).json")
        writePage(page, to: path)
    }

    private func cachePageInMemoryIfNeeded(_ page: PageData, bookId: String, currentPage: Int) {
        guard abs(page.pageIndex - currentPage) <= l1Range else { return }
        let key = cacheKey(for: bookId, chapterIndex: page.chapterIndex, pageIndex: page.pageIndex)
        l1Cache.setObject(page, forKey: key as NSString)
    }

    private func cleanupDiskCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: l3BasePath) else { return }

        let now = Date()
        var entries: [(path: String, size: UInt64, date: Date)] = []
        var totalSize: UInt64 = 0

        for file in files where file.hasSuffix(".json") {
            let path = (l3BasePath as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let date = attrs[.modificationDate] as? Date ?? .distantPast
            if now.timeIntervalSince(date) > maxIdleAge {
                try? fm.removeItem(atPath: path)
                continue
            }
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            entries.append((path, size, date))
            totalSize += size
        }

        guard totalSize > maxDiskCacheSize else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(atPath: entry.path)
            totalSize = totalSize > entry.size ? totalSize - entry.size : 0
            if totalSize <= maxDiskCacheSize { break }
        }
    }
}

final class PageData: Codable {
    let pageIndex: Int
    let startCharOffset: Int
    let endCharOffset: Int
    let content: String
    let chapterTitle: String
    let chapterIndex: Int

    init(pageIndex: Int, startCharOffset: Int, endCharOffset: Int, content: String, chapterTitle: String, chapterIndex: Int) {
        self.pageIndex = pageIndex
        self.startCharOffset = startCharOffset
        self.endCharOffset = endCharOffset
        self.content = content
        self.chapterTitle = chapterTitle
        self.chapterIndex = chapterIndex
    }
}

// MARK: - Extended API for WebSync

extension PageCacheManager {
    /// Returns the estimated total page count for a book based on cached pages
    func getCachedPageCount(bookId: String) -> Int {
        // Return a reasonable estimate based on cached pages
        // In production, this would come from the book's metadata
        return max(100, l1Cache.countLimit)
    }
    
    /// Get all cached page indices for a book
    func getCachedPageIndices(bookId: String) -> [Int] {
        // This would enumerate the cache in a full implementation
        return []
    }
}
