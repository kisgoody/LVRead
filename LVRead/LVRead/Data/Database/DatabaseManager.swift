import Foundation
import SQLite3

final class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
   private let dbQueue = DispatchQueue(label: "com.lvread.database", qos: .userInitiated)
    private let dbQueueKey = DispatchSpecificKey<Bool>()
    // Use a separate lock for DB operations to prevent illegal multi-threaded access
    // dbOperationLock removed - using queue-based synchronization instead

    private init() {}

    var databasePath: String {
        let documentsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return (documentsDir as NSString).appendingPathComponent("lvread.sqlite")
    }

   func initialize() {
        dbQueue.setSpecific(key: dbQueueKey, value: true)
        // Note: sqlite3_config is unavailable in Swift (variadic C function)
        // SQLite is compiled with thread safety by default on iOS
        // We achieve thread safety through our queue-based serialization
        
        dbQueue.sync {
            if sqlite3_open(databasePath, &db) != SQLITE_OK {
                print("❌ Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            
            // Enable WAL mode for better concurrent read performance
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            // Set busy timeout for lock contention
            sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
            
            createTables()
            runMigrations()
        }
    }

    // MARK: - Public: thread-safe via dbQueue

    /// Execute a SQL statement. Thread-safe and reentrant-safe.
    func execute(_ sql: String, params: [Any] = []) -> Bool {
        if DispatchQueue.getSpecific(key: dbQueueKey) == true {
            return executeUnsafe(sql, params: params)
        } else {
            return dbQueue.sync { executeUnsafe(sql, params: params) }
        }
    }

    /// Execute a query. Thread-safe and reentrant-safe.
    func query(_ sql: String, params: [Any] = []) -> [[String: Any]] {
        if DispatchQueue.getSpecific(key: dbQueueKey) == true {
            return queryUnsafe(sql, params: params)
        } else {
            return dbQueue.sync { queryUnsafe(sql, params: params) }
        }
    }

    // MARK: - Private: unsafe — must already be inside dbQueue

    /// Caller must hold `dbQueue` (called from within `dbQueue.sync { }` only).
    /// Thread safety is ensured by the queue and the execute/query wrapper.
    @discardableResult
    private func executeUnsafe(_ sql: String, params: [Any] = []) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ SQL error: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        defer { sqlite3_finalize(statement) }

        bindParams(statement, params)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// Caller must hold `dbQueue` (called from within `dbQueue.sync { }` only).
    /// Thread safety is ensured by the queue and the execute/query wrapper.
    private func queryUnsafe(_ sql: String, params: [Any] = []) -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        bindParams(statement, params)

        var results: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(statement)
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(statement, i))
                case SQLITE_NULL:
                    row[name] = nil
                default:
                    row[name] = nil
                }
            }
            results.append(row)
        }
        return results
    }

    private func bindParams(_ statement: OpaquePointer?, _ params: [Any]) {
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case let text as String:
                sqlite3_bind_text(statement, idx, (text as NSString).utf8String, -1, nil)
            case let num as Int64:
                sqlite3_bind_int64(statement, idx, num)
            case let num as Int:
                sqlite3_bind_int64(statement, idx, Int64(num))
            case let num as UInt:
                sqlite3_bind_int64(statement, idx, Int64(num))
            case let num as Int32:
                sqlite3_bind_int64(statement, idx, Int64(num))
            case let num as Double:
                sqlite3_bind_double(statement, idx, num)
            case let num as Float:
                sqlite3_bind_double(statement, idx, Double(num))
            case let num as Bool:
                sqlite3_bind_int64(statement, idx, num ? 1 : 0)
            case is NSNull:
                sqlite3_bind_null(statement, idx)
            case let data as Data:
                data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    sqlite3_bind_blob(statement, idx, bytes.baseAddress, Int32(data.count), nil)
                }
            default:
                print("⚠️ DatabaseManager: Unhandled parameter type \(type(of: param)) at index \(index)")
                sqlite3_bind_null(statement, idx)
            }
        }
    }

    // MARK: - Schema

    private func createTables() {
        let booksSQL = """
        CREATE TABLE IF NOT EXISTS books (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT DEFAULT '未知作者',
            cover_image_path TEXT,
            file_path TEXT NOT NULL,
            file_hash TEXT NOT NULL UNIQUE,
            file_size INTEGER NOT NULL,
            file_format TEXT NOT NULL,
            source TEXT NOT NULL,
            encoding TEXT,
            category TEXT,
            current_chapter_index INTEGER DEFAULT 0,
            current_page_offset INTEGER DEFAULT 0,
            total_pages INTEGER DEFAULT 0,
            progress_percent REAL DEFAULT 0.0,
            last_read_timestamp REAL DEFAULT 0,
            is_favorite INTEGER DEFAULT 0,
            custom_order INTEGER DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        let chaptersSQL = """
        CREATE TABLE IF NOT EXISTS chapters (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            title TEXT NOT NULL,
            level INTEGER DEFAULT 1,
            order_index INTEGER NOT NULL,
            start_offset INTEGER DEFAULT 0,
            end_offset INTEGER DEFAULT 0,
            page_count INTEGER DEFAULT 0,
            internal_href TEXT,
            FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
        );
        """

        let bookmarksSQL = """
        CREATE TABLE IF NOT EXISTS bookmarks (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            chapter_index INTEGER NOT NULL,
            page_offset INTEGER NOT NULL,
            chapter_title TEXT DEFAULT '',
            snippet TEXT DEFAULT '',
            created_at REAL NOT NULL,
            FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
        );
        """

        let highlightsSQL = """
        CREATE TABLE IF NOT EXISTS highlights (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            chapter_index INTEGER NOT NULL,
            page_offset INTEGER NOT NULL,
            start_char_offset INTEGER NOT NULL,
            end_char_offset INTEGER NOT NULL,
            text TEXT NOT NULL,
            color TEXT DEFAULT '#FFD700',
            note TEXT,
            created_at REAL NOT NULL,
            FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
        );
        """

        let statsSQL = """
        CREATE TABLE IF NOT EXISTS reading_stats (
            id INTEGER PRIMARY KEY DEFAULT 1,
            total_books_read INTEGER DEFAULT 0,
            total_reading_time_seconds INTEGER DEFAULT 0,
            total_pages_read INTEGER DEFAULT 0,
            daily_data TEXT DEFAULT '{}',
            weekly_data TEXT DEFAULT '{}'
        );
        """

        for sql in [booksSQL, chaptersSQL, bookmarksSQL, highlightsSQL, statsSQL] {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }

        // Use unsafe variants — we are already inside dbQueue.sync
        executeUnsafe("PRAGMA foreign_keys = ON;")

        let stats = queryUnsafe("SELECT id FROM reading_stats LIMIT 1;")
        if stats.isEmpty {
            executeUnsafe("INSERT INTO reading_stats (id) VALUES (1);")
        }
    }

    private func runMigrations() {}

    deinit {
        if let db = db { sqlite3_close(db) }
    }
}
