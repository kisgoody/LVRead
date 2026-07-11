import Foundation

final class BookRepository {
    static let shared = BookRepository()
    private let db = DatabaseManager.shared

    private init() {}

    // MARK: - Insert
    func insert(_ book: Book) -> Result<Book, LVError> {
        print("[DEBUG] BookRepository.insert: title=(book.title), filePath=(book.filePath)")
        let sql = """
        INSERT OR REPLACE INTO books (id, title, author, cover_image_path, file_path, file_hash,
            file_size, file_format, source, encoding, category, current_chapter_index,
            current_page_offset, total_pages, progress_percent, last_read_timestamp,
            is_favorite, custom_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let success = db.execute(sql, params: [
            book.id, book.title, book.author, book.coverImagePath ?? NSNull(),
            book.filePath, book.fileHash, book.fileSize, book.fileFormat.rawValue,
            book.source.rawValue, book.encoding ?? NSNull(), book.category ?? NSNull(),
            book.readingProgress.currentChapterIndex, book.readingProgress.currentPageOffset,
            book.readingProgress.totalPages, book.readingProgress.progressPercent,
            book.readingProgress.lastReadTimestamp.timeIntervalSince1970,
            book.isFavorite ? 1 : 0, book.customOrder,
            book.createdAt.timeIntervalSince1970, book.updatedAt.timeIntervalSince1970
        ])
        return success ? .success(book) : .failure(.databaseError)
    }

    // MARK: - Delete
    func delete(_ bookId: String) -> Result<Void, LVError> {
        guard let book = getById(bookId) else {
            return .failure(.fileNotFound)
        }
        
        var fileDeleteError: Error?
        
        let resolvedPath = book.resolvedFilePath()
        // Delete book file from sandbox
        if FileManager.default.fileExists(atPath: resolvedPath) {
            do {
                try FileManager.default.removeItem(atPath: resolvedPath)
            } catch {
                fileDeleteError = error
                print("⚠️ Failed to delete book file: \(error)")
            }
        }
        
        // Delete cover image if exists
        if let coverPath = book.resolvedCoverPath(),
           FileManager.default.fileExists(atPath: coverPath) {
            try? FileManager.default.removeItem(atPath: coverPath)
            ImageCacheManager.shared.removeImage(forKey: coverPath)
        }
        
        // Clear derived cache for this book
        PageCacheManager.shared.clearBookCache(bookId)
        ImageCacheManager.shared.clearBookCache(bookId)
        
        // Delete DB record (cascades to chapters, bookmarks, highlights)
        let dbSuccess = db.execute("DELETE FROM books WHERE id = ?;", params: [bookId])
        
        // If file deletion failed but DB succeeded, report partial success
        // But we should still warn the user
        if !dbSuccess {
            return .failure(.databaseError)
        }
        
        if fileDeleteError != nil {
            // File might still exist, mark it for cleanup later
            // For now return success but log the issue
            print("⚠️ Book deleted from DB but file cleanup failed")
        }
        
        return .success(())
    }

    func deleteBatch(_ bookIds: [String]) -> Result<Void, LVError> {
        for id in bookIds {
            _ = delete(id)
        }
        return .success(())
    }

    // MARK: - Update
    func update(_ book: Book) -> Result<Book, LVError> {
        var mutableBook = book
        mutableBook.updatedAt = Date()
        let success = db.execute("""
            UPDATE books SET title = ?, author = ?, cover_image_path = ?, file_path = ?,
                encoding = ?, category = ?, is_favorite = ?, custom_order = ?, updated_at = ?
            WHERE id = ?;
        """, params: [
            mutableBook.title,
            mutableBook.author,
            mutableBook.coverImagePath ?? NSNull(),
            mutableBook.filePath,
            mutableBook.encoding ?? NSNull(),
            mutableBook.category ?? NSNull(),
            mutableBook.isFavorite ? 1 : 0,
            mutableBook.customOrder,
            mutableBook.updatedAt.timeIntervalSince1970,
            mutableBook.id
        ])
        return success ? .success(mutableBook) : .failure(.databaseError)
    }

    func updateProgress(bookId: String, progress: ReadingProgress) {
        db.execute("""
            UPDATE books SET current_chapter_index = ?, current_page_offset = ?,
            total_pages = ?, progress_percent = ?, last_read_timestamp = ?
            WHERE id = ?;
        """, params: [progress.currentChapterIndex, progress.currentPageOffset,
                     progress.totalPages, progress.progressPercent,
                     progress.lastReadTimestamp.timeIntervalSince1970, bookId])
    }

    func updateCover(bookId: String, coverPath: String?) -> Result<Void, LVError> {
        db.execute("UPDATE books SET cover_image_path = ?, updated_at = ? WHERE id = ?;",
                   params: [coverPath ?? NSNull(), Date().timeIntervalSince1970, bookId])
        return .success(())
    }

    // MARK: - Query
    func getById(_ bookId: String) -> Book? {
        let rows = db.query("SELECT * FROM books WHERE id = ?;", params: [bookId])
        return rows.first.map { mapBook($0) }
    }

    func getByHash(_ fileHash: String) -> Book? {
        let rows = db.query("SELECT * FROM books WHERE file_hash = ?;", params: [fileHash])
        return rows.first.map { mapBook($0) }
    }

    func getAll(sortBy: BookSortType = .recentRead, ascending: Bool = false) -> [Book] {
        let orderClause = sortSQL(sortBy, ascending: ascending)
        let rows = db.query("SELECT * FROM books ORDER BY \(orderClause);")
        return rows.map { mapBook($0) }
    }

    func search(_ query: String) -> [Book] {
        let pattern = "%\(query)%"
        let rows = db.query(
            "SELECT * FROM books WHERE title LIKE ? OR author LIKE ? ORDER BY last_read_timestamp DESC;",
            params: [pattern, pattern]
        )
        return rows.map { mapBook($0) }
    }

    func getFiltered(progressFilter: ReadingProgressFilter? = nil,
                     sourceFilter: BookSource? = nil,
                     formatFilter: FileFormat? = nil,
                     category: String? = nil) -> [Book] {
        var conditions: [String] = []
        var params: [Any] = []

        if let pf = progressFilter {
            switch pf {
            case .unread:
                conditions.append("progress_percent = 0")
            case .reading:
                conditions.append("progress_percent > 0 AND progress_percent < 100")
            case .finished:
                conditions.append("progress_percent >= 100")
            default: break
            }
        }
        if let sf = sourceFilter {
            conditions.append("source = ?")
            params.append(sf.rawValue)
        }
        if let ff = formatFilter {
            conditions.append("file_format = ?")
            params.append(ff.rawValue)
        }
        if let cat = category {
            conditions.append("category = ?")
            params.append(cat)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT * FROM books \(whereClause) ORDER BY last_read_timestamp DESC;"
        return db.query(sql, params: params).map { mapBook($0) }
    }

    func getPaged(offset: Int, limit: Int = 50) -> [Book] {
        let rows = db.query("SELECT * FROM books ORDER BY custom_order ASC, updated_at DESC LIMIT ? OFFSET ?;",
                           params: [limit, offset])
        return rows.map { mapBook($0) }
    }

    var totalCount: Int {
        let rows = db.query("SELECT COUNT(*) as cnt FROM books;")
        return Int(rows.first?["cnt"] as? Int64 ?? 0)
    }

    // MARK: - Chapter helpers
    func insertChapters(_ chapters: [Chapter]) {
        for chapter in chapters {
            db.execute("""
                INSERT OR REPLACE INTO chapters (id, book_id, title, level, order_index,
                    start_offset, end_offset, page_count, internal_href)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, params: [chapter.id, chapter.bookId, chapter.title, chapter.level,
                         chapter.orderIndex, chapter.startOffset, chapter.endOffset,
                         chapter.pageCount, chapter.internalHref ?? NSNull()])
        }
    }

    func getChapters(for bookId: String) -> [Chapter] {
        let rows = db.query("SELECT * FROM chapters WHERE book_id = ? ORDER BY order_index ASC;",
                           params: [bookId])
        return rows.map(mapChapter)
    }

    // MARK: - Bookmark helpers
    func insertBookmark(_ bookmark: Bookmark) {
        db.execute("""
            INSERT OR REPLACE INTO bookmarks (id, book_id, chapter_index, page_offset,
                chapter_title, snippet, created_at) VALUES (?, ?, ?, ?, ?, ?, ?);
        """, params: [bookmark.id, bookmark.bookId, bookmark.chapterIndex,
                     bookmark.pageOffset, bookmark.chapterTitle, bookmark.snippet,
                     bookmark.createdAt.timeIntervalSince1970])
    }

    func deleteBookmark(_ bookmarkId: String) {
        db.execute("DELETE FROM bookmarks WHERE id = ?;", params: [bookmarkId])
    }

    func getBookmarks(for bookId: String) -> [Bookmark] {
        let rows = db.query(
            "SELECT * FROM bookmarks WHERE book_id = ? ORDER BY created_at DESC;",
            params: [bookId]
        )
        return rows.map(mapBookmark)
    }

    func getBookmark(at bookId: String, chapterIndex: Int, pageOffset: Int) -> Bookmark? {
        let rows = db.query(
            "SELECT * FROM bookmarks WHERE book_id = ? AND chapter_index = ? AND page_offset = ?;",
            params: [bookId, chapterIndex, pageOffset]
        )
        return rows.first.map(mapBookmark)
    }

    // MARK: - Highlight helpers
    func insertHighlight(_ highlight: Highlight) {
        db.execute("""
            INSERT OR REPLACE INTO highlights (id, book_id, chapter_index, page_offset,
                start_char_offset, end_char_offset, text, color, note, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, params: [highlight.id, highlight.bookId, highlight.chapterIndex,
                     highlight.pageOffset, highlight.startCharOffset, highlight.endCharOffset,
                     highlight.text, highlight.color, highlight.note ?? NSNull(),
                     highlight.createdAt.timeIntervalSince1970])
    }

    func deleteHighlight(_ highlightId: String) {
        db.execute("DELETE FROM highlights WHERE id = ?;", params: [highlightId])
    }

    func getHighlights(for bookId: String) -> [Highlight] {
        let rows = db.query(
            "SELECT * FROM highlights WHERE book_id = ? ORDER BY created_at DESC;",
            params: [bookId]
        )
        return rows.map(mapHighlight)
    }

    // MARK: - Helpers
    private func toInt(_ row: [String: Any], _ key: String, default: Int = 0) -> Int {
        Int(row[key] as? Int64 ?? Int64(`default`))
    }

    // MARK: - Mapping
    private func mapBook(_ row: [String: Any]) -> Book {
        Book(
            id: row["id"] as? String ?? UUID().uuidString,
            title: row["title"] as? String ?? "",
            author: row["author"] as? String ?? "未知作者",
            coverImagePath: row["cover_image_path"] as? String,
            filePath: row["file_path"] as? String ?? "",
            fileHash: row["file_hash"] as? String ?? "",
            fileSize: row["file_size"] as? Int64 ?? 0,
            fileFormat: FileFormat(rawValue: row["file_format"] as? String ?? "TXT") ?? .txt,
            source: BookSource(rawValue: row["source"] as? String ?? "LOCAL_FILE") ?? .localFile,
            encoding: row["encoding"] as? String,
            category: row["category"] as? String,
            readingProgress: ReadingProgress(
                currentChapterIndex: toInt(row, "current_chapter_index"),
                currentPageOffset: toInt(row, "current_page_offset"),
                totalPages: toInt(row, "total_pages"),
                progressPercent: row["progress_percent"] as? Double ?? 0.0,
                lastReadTimestamp: Date(timeIntervalSince1970: row["last_read_timestamp"] as? Double ?? 0)
            ),
            createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0),
            isFavorite: (row["is_favorite"] as? Int64 ?? 0) != 0,
            customOrder: toInt(row, "custom_order")
        )
    }

    private func mapChapter(_ row: [String: Any]) -> Chapter {
        Chapter(
            id: row["id"] as? String ?? UUID().uuidString,
            bookId: row["book_id"] as? String ?? "",
            title: row["title"] as? String ?? "",
            level: toInt(row, "level", default: 1),
            orderIndex: toInt(row, "order_index"),
            startOffset: row["start_offset"] as? Int64 ?? 0,
            endOffset: row["end_offset"] as? Int64 ?? 0,
            pageCount: toInt(row, "page_count"),
            internalHref: row["internal_href"] as? String
        )
    }

    private func mapBookmark(_ row: [String: Any]) -> Bookmark {
        Bookmark(
            id: row["id"] as? String ?? UUID().uuidString,
            bookId: row["book_id"] as? String ?? "",
            chapterIndex: toInt(row, "chapter_index"),
            pageOffset: toInt(row, "page_offset"),
            chapterTitle: row["chapter_title"] as? String ?? "",
            snippet: row["snippet"] as? String ?? "",
            createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0)
        )
    }

    private func mapHighlight(_ row: [String: Any]) -> Highlight {
        Highlight(
            id: row["id"] as? String ?? UUID().uuidString,
            bookId: row["book_id"] as? String ?? "",
            chapterIndex: toInt(row, "chapter_index"),
            pageOffset: toInt(row, "page_offset"),
            startCharOffset: toInt(row, "start_char_offset"),
            endCharOffset: toInt(row, "end_char_offset"),
            text: row["text"] as? String ?? "",
            color: row["color"] as? String ?? "#FFD700",
            note: row["note"] as? String,
            createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0)
        )
    }

    private func sortSQL(_ sort: BookSortType, ascending: Bool) -> String {
        let dir = ascending ? "ASC" : "DESC"
        switch sort {
        case .recentRead: return "last_read_timestamp \(dir)"
        case .recentImport: return "created_at \(dir)"
        case .title: return "title \(dir)"
        case .fileSize: return "file_size \(dir)"
        case .custom: return "custom_order ASC"
        }
    }
}

enum BookSortType: String, CaseIterable {
    case recentRead = "最近阅读"
    case recentImport = "最近导入"
    case title = "书名 A-Z"
    case fileSize = "文件大小"
    case custom = "自定义排序"
}

// Error type used by repositories
enum LVError: Error, LocalizedError {
    case fileNotFound
    case formatUnsupported
    case parseFailed
    case encodingDetectionFailed
    case duplicateFile
    case networkTimeout
    case transferFailed
    case storageFull
    case databaseError
    case importTimeout

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "文件已被移动或删除"
        case .formatUnsupported: return "暂不支持该文件格式"
        case .parseFailed: return "文件解析失败，文件可能已损坏"
        case .encodingDetectionFailed: return "无法识别文件编码，已使用UTF-8"
        case .duplicateFile: return "该书已存在"
        case .networkTimeout: return "连接超时，请检查网络"
        case .transferFailed: return "传输中断，请重试"
        case .storageFull: return "设备存储空间不足"
        case .databaseError: return "数据存储异常"
        case .importTimeout: return "导入超时，请尝试分割文件后重新导入"
        }
    }
}

// Helper operator
infix operator |>: AdditionPrecedence
func |><T, U>(lhs: T, rhs: (T) -> U) -> U { rhs(lhs) }
