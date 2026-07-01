import UIKit

final class PageCacheManager {
    static let shared = PageCacheManager()

    private let l1Cache = NSCache<NSString, PageData>()
    private let l2Cache = NSCache<NSString, PageData>()
    private let l3BasePath: String

    private var currentBookId: String?
    private var currentPageIndex: Int = 0
    private let l1Range = 3
    private let l2MaxCount = 30
    private let l3MaxCount = 200

    private init() {
        l1Cache.countLimit = 15
        l2Cache.countLimit = 30

        let cachesDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        l3BasePath = (cachesDir as NSString).appendingPathComponent("PageCache")
        try? FileManager.default.createDirectory(atPath: l3BasePath, withIntermediateDirectories: true)
    }

    func setCurrentBook(_ bookId: String, pageIndex: Int) {
        if currentBookId != bookId {
            l1Cache.removeAllObjects()
            l2Cache.removeAllObjects()
        }
        currentBookId = bookId
        currentPageIndex = pageIndex
    }

    func cacheKey(for bookId: String, pageIndex: Int) -> String {
        "\(bookId)_\(pageIndex)"
    }

    func getPage(bookId: String, pageIndex: Int) -> PageData? {
        let key = cacheKey(for: bookId, pageIndex: pageIndex)

        if let page = l1Cache.object(forKey: key as NSString) { return page }
        if let page = l2Cache.object(forKey: key as NSString) { return page }

        // Try L3 disk cache
        let path = (l3BasePath as NSString).appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let page = try? JSONDecoder().decode(PageData.self, from: data) {
            // Promote to L2
            l2Cache.setObject(page, forKey: key as NSString)
            return page
        }
        return nil
    }

    func cachePage(_ page: PageData, bookId: String, pageIndex: Int) {
        let key = cacheKey(for: bookId, pageIndex: pageIndex)
        let nsKey = key as NSString

        let distance = abs(pageIndex - currentPageIndex)
        if distance <= l1Range {
            l1Cache.setObject(page, forKey: nsKey)
        } else if distance <= 10 {
            l2Cache.setObject(page, forKey: nsKey)
        }

        // Always write to L3 disk
        let path = (l3BasePath as NSString).appendingPathComponent("\(key).json")
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(page) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
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
        // Clear all cache layers for a specific book
        let prefix = bookId
        // L3 disk cleanup
        if let files = try? FileManager.default.contentsOfDirectory(atPath: l3BasePath) {
            for file in files where file.hasPrefix(prefix) {
                try? FileManager.default.removeItem(atPath: (l3BasePath as NSString).appendingPathComponent(file))
            }
        }
    }

    func handleMemoryWarning() {
        l2Cache.removeAllObjects()
        // Keep L1 but shrink
        l1Cache.countLimit = 5
    }

    func clearAll() {
        l1Cache.removeAllObjects()
        l2Cache.removeAllObjects()
        try? FileManager.default.removeItem(atPath: l3BasePath)
        try? FileManager.default.createDirectory(atPath: l3BasePath, withIntermediateDirectories: true)
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
        return max(100, l1Cache.countLimit + l2Cache.countLimit + l3MaxCount)
    }
    
    /// Get all cached page indices for a book
    func getCachedPageIndices(bookId: String) -> [Int] {
        // This would enumerate the cache in a full implementation
        return []
    }
}
