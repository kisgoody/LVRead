import Foundation
import Network
import Security
import UIKit

extension Notification.Name {
    static let webSyncPageTurnRequested = Notification.Name("webSyncPageTurnRequested")
    static let webSyncConnectionStateChanged = Notification.Name("webSyncConnectionStateChanged")
}

enum WebSyncConnectionState: String, Equatable {
    case disconnected
    case connecting
    case connected

    var title: String {
        switch self {
        case .disconnected: return "同步已关闭"
        case .connecting: return "等待连接"
        case .connected: return "连接成功"
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected: return "wifi.slash"
        case .connecting: return "wifi"
        case .connected: return "wifi.circle.fill"
        }
    }

    func isActive(for bookID: String, activeBookID: String?) -> Bool {
        self == .connected && activeBookID == bookID
    }
}

// MARK: - Web Sync Server

/// A minimal embedded HTTPS server that provides a web reader interface
/// for syncing reading progress, pages, chapters, and settings.
final class WebSyncServer {

    struct Session {
        let readingURL: URL
        let rootCertificateURL: URL
        let rootFingerprint: String
        let hostName: String
    }

    struct PageSnapshot: Codable, Equatable {
        let pageIndex: Int
        let content: String
        let chapterTitle: String
        let chapterIndex: Int
        let totalPages: Int
    }

    private struct StoredSnapshot: Codable {
        let page: PageSnapshot
        let updatedAt: Date
    }

    private struct SSEClient {
        let connection: NWConnection
        let bookId: String
    }

    enum StartError: LocalizedError {
        case alreadyStarting
        case missingLocalAddress
        case missingPort
        case invalidURL
        case certificate(String)
        case listener(String)
        case cancelled
        case noSavedSession

        var errorDescription: String? {
            switch self {
            case .alreadyStarting: return "同步服务正在启动，请稍后重试"
            case .missingLocalAddress: return "无法获取手机的 Wi-Fi 地址"
            case .missingPort: return "无法分配同步服务端口"
            case .invalidURL: return "无法生成同步链接"
            case .certificate(let message): return "无法加载 HTTPS 证书：\(message)"
            case .listener(let message): return "同步服务启动失败：\(message)"
            case .cancelled: return "同步服务已停止"
            case .noSavedSession: return "请先打开一本书并开启电脑同步"
            }
        }
    }

    public static let shared = WebSyncServer()

    private enum StorageKey {
        static let bookTokens = "web_sync_book_tokens_v1"
        static let snapshots = "web_sync_snapshots_v1"
        static let autoResumeEnabled = "web_sync_auto_resume_enabled_v1"
        static let fixedPort: UInt16 = 8989
    }

    private var listener: NWListener?
    private var serverPort: UInt16 = 0
    private var isRunning = false
    private var _connectionState = WebSyncConnectionState.disconnected
    private var _activeBookID: String?
    private let stateLock = NSLock()
    private var startCompletion: ((Result<Session, Error>) -> Void)?
    private let hostPublisher = BonjourHostPublisher()

    /// The URL that a web browser should connect to.
    public private(set) var serverURL: String = ""

    /// The current book being synced.
    private var currentBook: Book?
    private var currentPageIndex: Int = 0
    private var currentPageSnapshot: PageSnapshot?

    /// SSE client connections keyed by a connection identifier.
    private var sseConnections: [UUID: SSEClient] = [:]
    private let sseLock = NSLock()

    private let serverQueue = DispatchQueue(label: "com.lvread.webSyncServer", qos: .utility)

    var connectionState: WebSyncConnectionState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _connectionState
    }

    var activeBookID: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _activeBookID
    }

    func isConnected(to bookID: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _connectionState.isActive(for: bookID, activeBookID: _activeBookID)
    }

    func savedPageSnapshot(for bookID: String) -> PageSnapshot? {
        if let saved = storedSnapshots()[bookID]?.page { return saved }
        guard let book = BookRepository.shared.getById(bookID) else { return nil }
        let chapterIndex = book.readingProgress.currentChapterIndex
        let pageIndex = book.readingProgress.currentPageOffset
        guard let cached = PageCacheManager.shared.getPage(
            bookId: bookID,
            chapterIndex: chapterIndex,
            pageIndex: pageIndex
        ) else { return nil }
        return PageSnapshot(
            pageIndex: cached.pageIndex,
            content: cached.content,
            chapterTitle: cached.chapterTitle,
            chapterIndex: cached.chapterIndex,
            totalPages: max(
                PageCacheManager.shared.getCachedPageIndices(
                    bookId: bookID,
                    chapterIndex: cached.chapterIndex
                ).count,
                cached.pageIndex + 1
            )
        )
    }

    /// Notification observers.
    private var pageObserver: NSObjectProtocol?
    private var chapterObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    // MARK: - Public API

    /// Starts the shared HTTPS listener and returns the stable link for this book.
    public func start(
        with book: Book,
        page: PageSnapshot,
        completion: @escaping (Result<Session, Error>) -> Void
    ) {
        UserDefaults.standard.set(true, forKey: StorageKey.autoResumeEnabled)
        serverQueue.async { [weak self] in
            self?.startOnQueue(with: book, page: page, completion: completion)
        }
    }

    private func startOnQueue(
        with book: Book,
        page: PageSnapshot,
        completion: @escaping (Result<Session, Error>) -> Void
    ) {
        storeSnapshot(page, for: book.id)
        let token = stableToken(for: book.id)
        currentBook = book
        setActiveBookID(book.id)
        currentPageIndex = page.pageIndex
        currentPageSnapshot = page

        if isRunning {
            if let identity = try? WebSyncIdentityManager.shared.makeIdentity(),
               let url = readingURL(hostName: identity.hostName, token: token) {
                serverURL = url.absoluteString
                let session = Session(
                    readingURL: url,
                    rootCertificateURL: identity.rootCertificateURL,
                    rootFingerprint: identity.rootFingerprint,
                    hostName: identity.hostName
                )
                DispatchQueue.main.async { completion(.success(session)) }
            } else {
                DispatchQueue.main.async { completion(.failure(StartError.alreadyStarting)) }
            }
            return
        }

        isRunning = true
        setConnectionState(.connecting)
        serverURL = ""
        startCompletion = completion

        guard let ip = UDPDiscoveryService.shared.getLocalIP() else {
            print("[WebSyncServer] Cannot determine local IP")
            stopOnQueue(startError: .missingLocalAddress)
            return
        }

        do {
            let identity = try WebSyncIdentityManager.shared.makeIdentity()
            try hostPublisher.start(hostName: identity.hostName, ipv4Address: ip)
            let params = try makeTLSParameters(identity: identity.secIdentity)
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .wifi

            guard let port = NWEndpoint.Port(rawValue: StorageKey.fixedPort) else {
                stopOnQueue(startError: .missingPort)
                return
            }
            let newListener = try NWListener(using: params, on: port)
            newListener.service = NWListener.Service(
                name: "LVRead-\(identity.hostName.dropFirst("lvread-".count).prefix(8))",
                type: "_lvread._tcp"
            )
            listener = newListener

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self, let newListener, self.listener === newListener else { return }
                switch state {
                case .ready:
                    guard let port = newListener.port?.rawValue else {
                        self.stopOnQueue(startError: .missingPort)
                        return
                    }
                    self.serverPort = port
                    guard let url = self.readingURL(hostName: identity.hostName, token: token) else {
                        self.stopOnQueue(startError: .invalidURL)
                        return
                    }
                    self.serverURL = url.absoluteString
                    // Listener ready only means the service is available. The browser is
                    // considered connected after its SSE channel is established.
                    self.setConnectionState(.connecting)
                    self.setupObservers()
                    self.completeStart(with: .success(Session(
                        readingURL: url,
                        rootCertificateURL: identity.rootCertificateURL,
                        rootFingerprint: identity.rootFingerprint,
                        hostName: identity.hostName
                    )))
                    print("[WebSyncServer] Ready at \(self.serverURL)")
                case .waiting(let error):
                    print("[WebSyncServer] Listener waiting: \(error)")
                    // `.waiting` is recoverable and is commonly reported while iOS moves
                    // the app to the background. Keep the listener alive for auto-recovery.
                    self.setConnectionState(.connecting)
                case .failed(let error):
                    print("[WebSyncServer] Listener failed: \(error)")
                    self.stopOnQueue(startError: .listener(error.localizedDescription))
                case .cancelled:
                    print("[WebSyncServer] Listener cancelled")
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: serverQueue)
            serverQueue.asyncAfter(deadline: .now() + 5) { [weak self, weak newListener] in
                guard let self, let newListener,
                      self.listener === newListener,
                      self.startCompletion != nil else { return }
                self.stopOnQueue(startError: .listener("启动超时"))
            }
        } catch let error as WebSyncIdentityManager.IdentityError {
            print("[WebSyncServer] Failed to create HTTPS identity: \(error)")
            stopOnQueue(startError: .certificate(error.localizedDescription))
        } catch {
            print("[WebSyncServer] Failed to start: \(error)")
            stopOnQueue(startError: .listener(error.localizedDescription))
        }
    }

    /// Stops the server and closes all connections.
    public func stop() {
        UserDefaults.standard.set(false, forKey: StorageKey.autoResumeEnabled)
        serverQueue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue(startError: StartError = .cancelled) {
        isRunning = false
        setConnectionState(.disconnected)
        let activeListener = listener
        listener = nil
        activeListener?.cancel()

        sseLock.lock()
        let activeConnections = sseConnections.values.map(\.connection)
        sseConnections.removeAll()
        sseLock.unlock()
        activeConnections.forEach { $0.cancel() }

        removeObservers()
        hostPublisher.stop()
        completeStart(with: .failure(startError))
        serverURL = ""
        serverPort = 0
        currentBook = nil
        setActiveBookID(nil)
        currentPageSnapshot = nil
    }

    func updateCurrentPage(bookId: String, page: PageSnapshot) {
        serverQueue.async { [weak self] in
            guard let self else { return }
            self.storeSnapshot(page, for: bookId)
            guard self.isRunning else { return }
            if self.currentBook?.id != bookId {
                self.currentBook = BookRepository.shared.getById(bookId)
                self.setActiveBookID(bookId)
            }
            self.currentPageIndex = page.pageIndex
            self.currentPageSnapshot = page
            let percent = self.progressPercent(bookId: bookId, page: page)
            self.notifyPageChanged(
                pageIndex: page.pageIndex,
                chapterTitle: page.chapterTitle,
                progressPercent: percent,
                bookId: bookId
            )
        }
    }

    /// Restarts the fixed listener using the latest linked book when the user left sync enabled.
    func resumeSavedSessionIfNeeded(restartListener: Bool = false) {
        guard UserDefaults.standard.bool(forKey: StorageKey.autoResumeEnabled) else { return }
        if restartListener {
            serverQueue.async { [weak self] in
                guard let self else { return }
                if self.isRunning {
                    // iOS may leave the listener marked running after suspending its socket.
                    // Recreate it on foreground without changing the user's saved switch.
                    self.stopOnQueue()
                }
                self.startSavedSessionOnQueue { _ in }
            }
            return
        }
        startSavedSession { _ in }
    }

    func startSavedSession(completion: @escaping (Result<Session, Error>) -> Void) {
        UserDefaults.standard.set(true, forKey: StorageKey.autoResumeEnabled)
        serverQueue.async { [weak self] in
            self?.startSavedSessionOnQueue(completion: completion)
        }
    }

    private func startSavedSessionOnQueue(
        completion: @escaping (Result<Session, Error>) -> Void
    ) {
        if isRunning, let book = currentBook, let page = currentPageSnapshot {
            startOnQueue(with: book, page: page, completion: completion)
            return
        }
        guard
            let saved = storedSnapshots().max(by: { $0.value.updatedAt < $1.value.updatedAt }),
            let book = BookRepository.shared.getById(saved.key)
        else {
            UserDefaults.standard.set(false, forKey: StorageKey.autoResumeEnabled)
            DispatchQueue.main.async { completion(.failure(StartError.noSavedSession)) }
            return
        }
        startOnQueue(with: book, page: saved.value.page, completion: completion)
    }

    /// Stops the server only if it is running (for app backgrounding).
    public func stopIfNeeded() {
        stop()
    }

    private func completeStart(with result: Result<Session, Error>) {
        guard let completion = startCompletion else { return }
        startCompletion = nil
        DispatchQueue.main.async { completion(result) }
    }

    private func setConnectionState(_ state: WebSyncConnectionState) {
        stateLock.lock()
        let changed = _connectionState != state
        _connectionState = state
        stateLock.unlock()
        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSyncConnectionStateChanged,
                object: state
            )
        }
    }

    private func setActiveBookID(_ bookID: String?) {
        stateLock.lock()
        let changed = _activeBookID != bookID
        _activeBookID = bookID
        stateLock.unlock()
        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSyncConnectionStateChanged,
                object: self.connectionState
            )
        }
    }

    private func readingURL(hostName: String, token: String) -> URL? {
        guard serverPort > 0 else { return nil }
        return URL(string: "https://\(hostName):\(serverPort)/?t=\(token)")
    }

    func stableToken(for bookId: String) -> String {
        var tokens = storedTokens()
        if let token = tokens[bookId] { return token }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        tokens[bookId] = token
        if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: StorageKey.bookTokens)
        }
        return token
    }

    private func storedTokens() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.bookTokens),
              let tokens = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return tokens
    }

    private func storeSnapshot(_ page: PageSnapshot, for bookId: String) {
        var snapshots = storedSnapshots()
        snapshots[bookId] = StoredSnapshot(page: page, updatedAt: Date())
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: StorageKey.snapshots)
        }
    }

    private func storedSnapshots() -> [String: StoredSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.snapshots),
              let snapshots = try? JSONDecoder().decode([String: StoredSnapshot].self, from: data) else {
            return [:]
        }
        return snapshots
    }

    @discardableResult
    private func activateBook(for token: String) -> String? {
        guard let bookId = storedTokens().first(where: { $0.value == token })?.key,
              let book = BookRepository.shared.getById(bookId) else { return nil }
        currentBook = book
        setActiveBookID(bookId)
        if let page = storedSnapshots()[bookId]?.page {
            currentPageSnapshot = page
            currentPageIndex = page.pageIndex
        } else {
            currentPageSnapshot = nil
            currentPageIndex = book.readingProgress.currentPageOffset
        }
        return bookId
    }

    private func progressPercent(bookId: String, page: PageSnapshot) -> Double {
        let chapterCount = max(BookRepository.shared.getChapters(for: bookId).count, 1)
        let chapterFraction = Double(page.pageIndex + 1) / Double(max(page.totalPages, 1))
        return min(100, max(0, (Double(page.chapterIndex) + chapterFraction) / Double(chapterCount) * 100))
    }

    private func makeTLSParameters(identity: SecIdentity) throws -> NWParameters {
        guard let localIdentity = sec_identity_create(identity) else {
            throw StartError.certificate("无法读取本机 HTTPS 身份")
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, localIdentity)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }

    // MARK: - SSE Notifications

    /// Notify connected SSE clients of a page change.
    public func notifyPageChanged(
        pageIndex: Int,
        chapterTitle: String,
        progressPercent: Double,
        bookId: String? = nil
    ) {
        let escapedTitle = chapterTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let eventData = """
        event: pagechange
        data: {"pageIndex":\(pageIndex),"chapterTitle":"\(escapedTitle)","progressPercent":\(progressPercent)}

        """
        broadcastSSE(eventData, bookId: bookId ?? currentBook?.id)
    }

    /// Notify connected SSE clients of a chapter change.
    public func notifyChapterChanged(chapterIndex: Int, chapterTitle: String) {
        let escapedTitle = chapterTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let eventData = """
        event: chapterchange
        data: {"chapterIndex":\(chapterIndex),"chapterTitle":"\(escapedTitle)"}

        """
        broadcastSSE(eventData, bookId: currentBook?.id)
    }

    /// Notify connected SSE clients of settings changes.
    public func notifySettingsChanged(_ settings: ReadingSettings) {
        guard let data = try? JSONSerialization.data(withJSONObject: settingsResponse(settings)),
              let json = String(data: data, encoding: .utf8) else { return }
        let eventData = """
        event: settingschange
        data: \(json)

        """
        // Reading appearance is global, so every connected browser must receive it.
        broadcastSSE(eventData)
    }

    // MARK: - Private: Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        readHTTPRequest(on: connection)
    }

    private func readHTTPRequest(on connection: NWConnection) {
        let maxSize = 8192
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxSize) { [weak self] data, _, _, error in
            if let error = error {
                print("[WebSyncServer] Read error: \(error)")
                connection.cancel()
                return
            }

            guard let self = self, let data = data,
                  let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let (method, path, queryParams, _) = self.parseHTTPRequest(requestString)

            let token = queryParams["t"] ?? ""
            guard !token.isEmpty, let requestBookId = self.activateBook(for: token) else {
                self.sendErrorResponse(statusCode: 403, message: "Forbidden", to: connection)
                return
            }

            switch (method, path) {
            case ("GET", "/"):
                self.serveWebReader(to: connection)

            case ("GET", "/sw.js"):
                self.serveServiceWorker(token: token, to: connection)

            case ("GET", "/api/book/info"):
                self.serveBookInfo(to: connection)

            case ("GET", "/api/page/current"):
                self.serveCurrentPage(to: connection)

            case ("GET", "/api/chapters"):
                self.serveChapters(to: connection)

            case ("GET", "/api/settings"):
                self.serveSettings(to: connection)

            case ("GET", "/api/stream"):
                self.handleSSEConnection(connection, bookId: requestBookId)

            case ("GET", "/api/progress"):
                self.serveProgress(to: connection)

            case ("GET", "/api/stats"):
                self.serveStats(to: connection)

            case ("GET", let p) where p.hasPrefix("/api/page/"):
                if let pageIndex = self.extractPageIndex(from: p) {
                    self.servePage(at: pageIndex, to: connection)
                } else {
                    self.sendErrorResponse(statusCode: 400, message: "Invalid page index", to: connection)
                }

            case ("POST", "/api/page/turn"):
                self.handleRemoteTurn(
                    connection: connection,
                    direction: queryParams["direction"] ?? "",
                    bookId: requestBookId
                )

            case ("POST", "/api/settings"):
                let body = queryParams["body"] ?? ""
                self.handleSettingsUpdate(connection: connection, body: body)

            case ("GET", "/api/streamold"):
                self.handleSSEConnection(connection, bookId: requestBookId)

            default:
                self.sendErrorResponse(statusCode: 404, message: "Not Found", to: connection)
            }
        }
    }

    // MARK: - HTTP Parsing

    private func parseHTTPRequest(_ raw: String) -> (method: String, path: String, query: [String: String], headers: [String: String]) {
        var method = "GET"
        var path = "/"
        var query: [String: String] = [:]
        var headers: [String: String] = [:]

        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return (method, path, query, headers)
        }

        let parts = requestLine.components(separatedBy: " ")
        if parts.count >= 2 {
            method = parts[0].uppercased()
            let fullPath = parts[1]
            if let queryStart = fullPath.range(of: "?") {
                path = String(fullPath[..<queryStart.lowerBound])
                let queryString = String(fullPath[queryStart.upperBound...])
                query = parseQueryString(queryString)
            } else {
                path = fullPath
            }
        }

        // Parse headers (skip request line)
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let headerParts = line.components(separatedBy: ": ")
            if headerParts.count >= 2 {
                let key = headerParts[0].lowercased()
                let value = headerParts.dropFirst().joined(separator: ": ")
                headers[key] = value
            }
        }

        return (method, path, query, headers)
    }

    private func parseQueryString(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return params
    }

    // MARK: - Route Handlers

    private func serveWebReader(to connection: NWConnection) {
        let html = webReaderHTML()
        sendHTTPResponse(statusCode: 200, contentType: "text/html; charset=utf-8", body: html, to: connection)
    }

    private func serveServiceWorker(token: String, to connection: NWConnection) {
        sendHTTPResponse(
            statusCode: 200,
            contentType: "application/javascript; charset=utf-8",
            body: webReaderServiceWorker(token: token),
            to: connection
        )
    }

    private func serveBookInfo(to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }

        let info: [String: Any] = [
            "id": book.id,
            "title": book.title,
            "author": book.author,
            "coverImagePath": book.resolvedCoverPath() ?? NSNull(),
            "fileFormat": book.fileFormat.rawValue,
            "readingProgress": [
                "currentChapterIndex": book.readingProgress.currentChapterIndex,
                "currentPageOffset": book.readingProgress.currentPageOffset,
                "totalPages": book.readingProgress.totalPages,
                "progressPercent": book.readingProgress.progressPercent,
                "lastReadTimestamp": book.readingProgress.lastReadTimestamp.timeIntervalSince1970
            ],
            "fileSize": book.fileSize
        ]
        sendJSONResponse(info, to: connection)
    }

    private func serveCurrentPage(to connection: NWConnection) {
        guard let book = currentBook, let page = currentPageSnapshot else {
            sendJSONResponse(["error": "No current page"], to: connection)
            return
        }
        sendJSONResponse([
            "bookId": book.id,
            "bookTitle": book.title,
            "pageIndex": page.pageIndex,
            "content": page.content,
            "chapterTitle": page.chapterTitle,
            "chapterIndex": page.chapterIndex,
            "totalPages": page.totalPages
        ], to: connection)
    }

    private func serveChapters(to connection: NWConnection) {
        // Return a simple chapter list. In a full implementation, this would
        // extract chapters from the book's spine/NCX.
        guard let book = currentBook else {
            sendJSONResponse(["chapters": []], to: connection)
            return
        }

        let response: [String: Any] = [
            "bookId": book.id,
            "chapters": [] // Populated by the full reader implementation
        ]
        sendJSONResponse(response, to: connection)
    }

    private func serveSettings(to connection: NWConnection) {
        let settings = ReadingSettingsRepository.shared.load()
        sendJSONResponse(settingsResponse(settings), to: connection)
    }

    private func settingsResponse(_ settings: ReadingSettings) -> [String: Any] {
        let theme = settings.readingTheme
        return [
            "fontSize": settings.fontSize,
            "theme": theme.rawValue,
            "lineSpacing": settings.lineSpacing,
            "fontFamily": settings.fontFamily,
            "backgroundColor": theme.backgroundColor,
            "textColor": theme.textColor,
            "accentColor": theme.accentColor,
            "panelColor": theme.panelColor,
            "controlSurfaceColor": theme.controlSurfaceColor
        ]
    }

    // MARK: - SSE Handling

    private func handleSSEConnection(_ connection: NWConnection, bookId: String) {
        let connectionId = UUID()

        sseLock.lock()
        sseConnections[connectionId] = SSEClient(connection: connection, bookId: bookId)
        sseLock.unlock()
        setConnectionState(.connected)

        // Send SSE headers
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: headers.data(using: .utf8)!, completion: .contentProcessed { _ in })

        // Send an initial connected event
        let connectedEvent = "event: connected\ndata: {\"status\":\"ok\"}\n\n"
        connection.send(content: connectedEvent.data(using: .utf8)!, completion: .contentProcessed { _ in })

        // A pending receive completes when the browser closes the EventSource.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                self?.removeSSEConnection(connectionId)
            }
        }

        // Keep-alive also detects half-open Wi-Fi/browser connections promptly.
        sendKeepAlivePings(to: connection, connectionId: connectionId)
    }

    private func sendKeepAlivePings(to connection: NWConnection, connectionId: UUID) {
        serverQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }

            self.sseLock.lock()
            let stillActive = self.sseConnections[connectionId] != nil
            self.sseLock.unlock()

            guard stillActive else { return }

            let ping = ":keepalive\n\n"
            connection.send(content: ping.data(using: .utf8)!, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.removeSSEConnection(connectionId)
                } else {
                    self?.sendKeepAlivePings(to: connection, connectionId: connectionId)
                }
            })
        }
    }

    private func broadcastSSE(_ eventData: String, bookId: String? = nil) {
        sseLock.lock()
        let clients = Array(sseConnections.values)
        sseLock.unlock()

        guard let data = eventData.data(using: .utf8) else { return }

        for client in clients where bookId == nil || client.bookId == bookId {
            client.connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func removeSSEConnection(_ id: UUID) {
        sseLock.lock()
        let connection = sseConnections.removeValue(forKey: id)?.connection
        let hasClients = !sseConnections.isEmpty
        sseLock.unlock()
        connection?.cancel()
        if isRunning && !hasClients {
            setConnectionState(.connecting)
        }
    }

    // MARK: - HTTP Response Helpers

    private func sendHTTPResponse(statusCode: Int, contentType: String, body: String, to connection: NWConnection) {
        let response = """
        HTTP/1.1 \(statusCode) \(statusMessage(for: statusCode))\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8)!, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSONResponse(_ json: [String: Any], to connection: NWConnection) {
        guard JSONSerialization.isValidJSONObject(json) else {
            print("[WebSyncServer] Invalid JSON response types: \(json.keys.sorted())")
            sendErrorResponse(statusCode: 500, message: "Internal Server Error", to: connection)
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            guard let body = String(data: data, encoding: .utf8) else {
                sendErrorResponse(statusCode: 500, message: "Internal Server Error", to: connection)
                return
            }
            sendHTTPResponse(
                statusCode: 200,
                contentType: "application/json; charset=utf-8",
                body: body,
                to: connection
            )
        } catch {
            print("[WebSyncServer] JSON serialization failed: \(error)")
            sendErrorResponse(statusCode: 500, message: "Internal Server Error", to: connection)
        }
    }

    private func sendErrorResponse(statusCode: Int, message: String, to connection: NWConnection) {
        let body = "{\"error\":\"\(message)\"}"
        sendHTTPResponse(statusCode: statusCode, contentType: "application/json; charset=utf-8", body: body, to: connection)
    }

    private func statusMessage(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        pageObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LVReadPageChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo else { return }
            let pageIndex = (userInfo["pageIndex"] as? Int) ?? 0
            let chapterTitle = (userInfo["chapterTitle"] as? String) ?? ""
            let progressPercent = (userInfo["progressPercent"] as? Double) ?? 0
            self?.notifyPageChanged(pageIndex: pageIndex, chapterTitle: chapterTitle, progressPercent: progressPercent)
        }

        chapterObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LVReadChapterChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo else { return }
            let chapterIndex = (userInfo["chapterIndex"] as? Int) ?? 0
            let chapterTitle = (userInfo["chapterTitle"] as? String) ?? ""
            self?.notifyChapterChanged(chapterIndex: chapterIndex, chapterTitle: chapterTitle)
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LVReadSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let settings = ReadingSettingsRepository.shared.load()
            self?.notifySettingsChanged(settings)
        }
    }

    private func removeObservers() {
        if let obs = pageObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = chapterObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = settingsObserver { NotificationCenter.default.removeObserver(obs) }
        pageObserver = nil
        chapterObserver = nil
        settingsObserver = nil
    }

    // MARK: - Additional Route Handlers

    private func servePage(at pageIndex: Int, to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }
        let minPage = max(0, currentPageIndex - 3)
        let maxPage = currentPageIndex + 3
        guard pageIndex >= minPage && pageIndex <= maxPage else {
            sendJSONResponse(["error": "out_of_range", "currentPage": currentPageIndex, "maxRange": [minPage, maxPage]], to: connection)
            return
        }
        if let pageContent = PageCacheManager.shared.getPage(bookId: book.id, pageIndex: pageIndex) {
            let response: [String: Any] = ["bookId": book.id, "bookTitle": book.title, "pageIndex": pageIndex, "content": pageContent.content, "chapterTitle": pageContent.chapterTitle, "chapterIndex": pageContent.chapterIndex, "totalPages": chapterPagesCount()]
            sendJSONResponse(response, to: connection)
        } else {
            sendJSONResponse(["error": "Page not in cache", "pageIndex": pageIndex], to: connection)
        }
    }

    private func handleRemoteTurn(connection: NWConnection, direction: String, bookId: String) {
        guard currentBook?.id == bookId, let page = currentPageSnapshot else {
            sendJSONResponse(["success": false, "error": "No active book"], to: connection)
            return
        }
        guard direction == "next" || direction == "prev" else {
            sendJSONResponse(["success": false, "error": "invalid_direction"], to: connection)
            return
        }

        let forward = direction == "next"
        let cachedPage = cachedSnapshot(from: page, forward: forward, bookId: bookId)
        if let cachedPage {
            currentPageSnapshot = cachedPage
            currentPageIndex = cachedPage.pageIndex
            storeSnapshot(cachedPage, for: bookId)
            let percent = progressPercent(bookId: bookId, page: cachedPage)
            BookRepository.shared.updateProgress(
                bookId: bookId,
                progress: ReadingProgress(
                    currentChapterIndex: cachedPage.chapterIndex,
                    currentPageOffset: cachedPage.pageIndex,
                    totalPages: cachedPage.totalPages,
                    progressPercent: percent,
                    lastReadTimestamp: Date()
                )
            )
            notifyPageChanged(
                pageIndex: cachedPage.pageIndex,
                chapterTitle: cachedPage.chapterTitle,
                progressPercent: percent,
                bookId: bookId
            )
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSyncPageTurnRequested,
                object: nil,
                userInfo: ["forward": forward, "bookId": bookId]
            )
        }
        sendJSONResponse(
            ["success": true, "direction": direction, "updated": cachedPage != nil],
            to: connection
        )
    }

    private func cachedSnapshot(
        from page: PageSnapshot,
        forward: Bool,
        bookId: String
    ) -> PageSnapshot? {
        let cache = PageCacheManager.shared
        var chapterIndex = page.chapterIndex
        var pageIndex = page.pageIndex + (forward ? 1 : -1)

        if forward,
           cache.getPage(bookId: bookId, chapterIndex: chapterIndex, pageIndex: pageIndex) == nil {
            chapterIndex += 1
            pageIndex = 0
        } else if !forward, pageIndex < 0 {
            chapterIndex -= 1
            guard chapterIndex >= 0,
                  let last = cache.getCachedPageIndices(bookId: bookId, chapterIndex: chapterIndex).last else {
                return nil
            }
            pageIndex = last
        }

        guard let cached = cache.getPage(
            bookId: bookId,
            chapterIndex: chapterIndex,
            pageIndex: pageIndex
        ) else { return nil }
        let totalPages = max(
            cache.getCachedPageIndices(bookId: bookId, chapterIndex: chapterIndex).count,
            cached.pageIndex + 1
        )
        return PageSnapshot(
            pageIndex: cached.pageIndex,
            content: cached.content,
            chapterTitle: cached.chapterTitle,
            chapterIndex: cached.chapterIndex,
            totalPages: totalPages
        )
    }

    private func serveProgress(to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }
        let total = chapterPagesCount()
        let percent = total > 0 ? (Double(currentPageIndex + 1) / Double(total)) * 100 : 0
        sendJSONResponse(["bookId": book.id, "pageIndex": currentPageIndex, "totalPages": total, "progressPercent": percent, "chapterTitle": currentChapterTitle(), "chapterIndex": currentChapterIndex()], to: connection)
    }

   private func handleSettingsUpdate(connection: NWConnection, body: String = "") {
       var settings = ReadingSettingsRepository.shared.load()
        if !body.isEmpty,
           let bodyData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let size = json["fontSize"] as? Int {
            settings.fontSize = size
        }
        ReadingSettingsRepository.shared.save(settings)
        notifySettingsChanged(settings)
        sendJSONResponse(["success": true], to: connection)
    }

    private func serveStats(to connection: NWConnection) {
        // Reading stats - return zeros for now
        sendJSONResponse(["totalBooksRead": 0, "totalReadingTimeSeconds": 0, "totalPagesRead": 0, "lastUpdated": Date().timeIntervalSince1970], to: connection)
    }

    private func chapterPagesCount() -> Int {
        guard let book = currentBook else { return 0 }
        return PageCacheManager.shared.getCachedPageCount(bookId: book.id)
    }

    private func currentChapterTitle() -> String {
        guard let book = currentBook else { return "" }
        let chapters = BookRepository.shared.getChapters(for: book.id)
        let idx = currentChapterIndex()
        if idx >= 0 && idx < chapters.count { return chapters[idx].title }
        return ""
    }

    private func currentChapterIndex() -> Int {
        guard let book = currentBook else { return 0 }
        let chapters = BookRepository.shared.getChapters(for: book.id)
        guard !chapters.isEmpty else { return 0 }
        let total = chapterPagesCount()
        guard total > 0 else { return 0 }
        return min(currentPageIndex * chapters.count / total, chapters.count - 1)
    }

    private func currentProgressPercent() -> Double {
        let total = chapterPagesCount()
        guard total > 0 else { return 0 }
        return (Double(currentPageIndex + 1) / Double(total)) * 100
    }

    // MARK: - Web Reader HTML (inline SPA)

    private func webReaderServiceWorker(token: String) -> String {
        let escapedToken = token.replacingOccurrences(of: "'", with: "")
        return """
        const cacheName='lvread-reader-v1';
        const readerURL='/?t=\(escapedToken)';
        self.addEventListener('install',event=>event.waitUntil(
          caches.open(cacheName).then(cache=>cache.add(readerURL)).then(()=>self.skipWaiting())
        ));
        self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
        self.addEventListener('fetch',event=>{
          if(event.request.mode!=='navigate')return;
          event.respondWith(fetch(event.request).then(response=>{
            const copy=response.clone();
            caches.open(cacheName).then(cache=>cache.put(event.request,copy));
            return response;
          }).catch(()=>caches.match(event.request).then(cached=>cached||caches.match(readerURL))));
        });
        """
    }

    func webReaderHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>LVRead - 电脑端同步阅读</title>
        <style>
        :root{--reader-bg:#F5F2EC;--reader-text:#24211D;--reader-accent:#236D67;--reader-panel:#F3F4F2;--reader-control:#FFFDF8;--reader-font-size:26px;--reader-line-height:1.5;--reader-font-family:"Songti SC","STSong",serif;}
        *{margin:0;padding:0;box-sizing:border-box;}
        html,body{min-height:100%;}
        body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--reader-panel);color:var(--reader-text);transition:background-color .2s,color .2s;}
        .topbar{height:64px;background:var(--reader-control);padding:0 32px;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:10;border-bottom:1px solid color-mix(in srgb,var(--reader-text) 12%,transparent);}
        .topbar-left,.brand,.topbar-right,.chapter-meta,.status{display:flex;align-items:center;}
        .topbar-left{gap:16px;min-width:0;}
        .brand{gap:8px;color:var(--reader-accent);font-size:20px;font-weight:700;letter-spacing:.5px;white-space:nowrap;}
        .brand-mark{position:relative;width:24px;height:24px;}
        .brand-mark:before,.brand-mark:after{content:"";position:absolute;top:1px;width:10px;height:19px;background:var(--reader-accent);}
        .brand-mark:before{left:1px;border-radius:2px 6px 2px 2px;transform:skewY(7deg);}
        .brand-mark:after{right:1px;border-radius:6px 2px 2px 2px;transform:skewY(-7deg);}
        .separator{width:1px;height:24px;background:color-mix(in srgb,var(--reader-text) 18%,transparent);}
        .book-title{max-width:46vw;font-size:15px;font-weight:500;color:var(--reader-text);opacity:.78;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
        .topbar-right{justify-content:flex-end;gap:16px;min-width:0;}
        .chapter-meta{font-size:13px;color:var(--reader-text);opacity:.78;white-space:nowrap;}
        .chapter-meta #pageInfo{margin-left:8px;padding-left:8px;border-left:1px solid color-mix(in srgb,var(--reader-text) 18%,transparent);}
        .status{font-size:12px;color:var(--reader-text);opacity:.72;gap:8px;padding-left:16px;border-left:1px solid color-mix(in srgb,var(--reader-text) 18%,transparent);}
        .dot{width:8px;height:8px;border-radius:50%;background:var(--reader-accent);box-shadow:0 0 0 3px color-mix(in srgb,var(--reader-accent) 12%,transparent);}
        .container{width:min(1120px,calc(100% - 48px));margin:0 auto;padding:40px 0 32px;}
        .content{height:clamp(496px,calc(100vh - 240px),720px);background:var(--reader-bg);color:var(--reader-text);border:1px solid color-mix(in srgb,var(--reader-text) 12%,transparent);border-radius:12px;padding:48px 64px;overflow:hidden;box-shadow:0 8px 40px color-mix(in srgb,var(--reader-text) 10%,transparent);transition:background-color .2s,color .2s,border-color .2s;}
        .content-text{font-family:var(--reader-font-family);font-size:var(--reader-font-size);line-height:var(--reader-line-height);white-space:pre-wrap;overflow-wrap:anywhere;text-align:justify;}
        .controls{display:flex;justify-content:center;gap:24px;margin-top:24px;}
        .controls button{min-width:152px;min-height:48px;background:var(--reader-control);color:var(--reader-accent);border:1px solid color-mix(in srgb,var(--reader-text) 18%,transparent);padding:8px 24px;border-radius:12px;font-size:14px;cursor:pointer;font-weight:600;transition:background-color .15s,border-color .15s,transform .15s;}
        .controls button:hover{background:color-mix(in srgb,var(--reader-accent) 10%,var(--reader-control));border-color:var(--reader-accent);}
        .controls button:active{transform:scale(.98);}
        .controls button:disabled{opacity:.45;cursor:not-allowed;}
        .shortcuts{margin-top:16px;text-align:center;font-size:12px;color:var(--reader-text);opacity:.58;line-height:1.8;}
        .shortcuts kbd{display:inline-flex;align-items:center;justify-content:center;min-width:32px;height:32px;background:var(--reader-control);color:var(--reader-accent);padding:0 8px;border-radius:8px;font-family:monospace;font-size:12px;border:1px solid color-mix(in srgb,var(--reader-text) 18%,transparent);}
        @media(max-width:760px){.topbar{height:auto;min-height:64px;padding:8px 16px;gap:8px;}.separator,.status{display:none;}.book-title{max-width:34vw;font-size:12px;}.topbar-right{gap:8px;}.container{width:calc(100% - 24px);padding-top:16px;}.content{height:calc(100vh - 224px);min-height:416px;padding:32px 24px;}.controls button{min-width:120px;}}
        </style>
        </head>
        <body>
        <div class="topbar">
        <div class="topbar-left">
        <div class="brand"><span class="brand-mark" aria-hidden="true"></span><span>LVRead</span></div>
        <span class="separator" aria-hidden="true"></span>
        <div class="book-title" id="bookTitle">正在读取书籍…</div>
        </div>
        <div class="topbar-right">
        <div class="chapter-meta"><span id="chapterTitle"></span><span id="pageInfo"></span></div>
        <div class="status"><span class="dot" id="statusDot"></span><span id="statusText">已连接</span></div>
        </div>
        </div>
        <div class="container">
        <article class="content" id="readingPage">
        <div class="content-text" id="content">正在加载…</div>
        </article>
        <div class="controls">
        <button id="prevBtn" onclick="prevPage()">&#9664; 上一页</button>
        <button id="nextBtn" onclick="nextPage()">下一页 &#9654;</button>
        </div>
        <div class="shortcuts">
        <kbd>&larr;</kbd> <kbd>&rarr;</kbd> 或 <kbd>J</kbd> <kbd>K</kbd> 翻页
        </div>
        </div>
        <script>
        var currentPage=0,totalPages=1,bookTitle='';
        var contentEl=document.getElementById('content');
        var bookTitleEl=document.getElementById('bookTitle');
        var pageInfoEl=document.getElementById('pageInfo');
        var chapterTitleEl=document.getElementById('chapterTitle');
        var statusDot=document.getElementById('statusDot');
        var statusText=document.getElementById('statusText');
        function applyPage(d){if(d.error){throw new Error(d.error);}var title=d.chapterTitle||'';contentEl.textContent=d.content||'当前页面暂无可同步文字';bookTitle=d.bookTitle||bookTitle;bookTitleEl.textContent=bookTitle||'LVRead';totalPages=d.totalPages||1;currentPage=d.pageIndex||0;chapterTitleEl.textContent=title;pageInfoEl.textContent=(currentPage+1)+' / '+totalPages;}
        function offlineMessage(){return '无法连接到 LVRead。\\n\\n情况一：手机端未打开同步开关。请打开 LVRead，在书架或阅读页点击电脑图标，再点击“打开同步”。\\n\\n情况二：同步已打开，但 App 进入了后台。iOS 会暂停局域网服务，请将 LVRead 切回前台，本页面会自动重新连接。';}
        function loadPage(){fetch('/api/page/current?t='+token()).then(r=>r.json()).then(applyPage).catch(e=>{contentEl.textContent=offlineMessage();console.error(e);});}
        function loadBookInfo(){fetch('/api/book/info?t='+token()).then(r=>r.json()).then(d=>{if(d.title){bookTitle=d.title;bookTitleEl.textContent=d.title;}}).catch(e=>{});}
        function token(){return new URLSearchParams(window.location.search).get('t')||'';}
        function turnPage(direction){fetch('/api/page/turn?t='+encodeURIComponent(token())+'&direction='+direction,{method:'POST'}).then(r=>r.json()).then(d=>{if(!d.success){throw new Error(d.error||'翻页失败');}if(d.updated){loadPage();}else{setTimeout(loadPage,700);}}).catch(e=>{contentEl.textContent='翻页失败：'+e.message;});}
        function prevPage(){turnPage('prev');}
        function nextPage(){turnPage('next');}
        function readerFontFamily(name){if(!name||name.indexOf('系统')>=0){return '-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif';}if(name.indexOf('仿宋')>=0){return '"FangSong","STFangsong",serif';}if(name.indexOf('楷体')>=0){return '"Kaiti SC","STKaiti","KaiTi",serif';}if(name.indexOf('宋体')>=0){return '"Songti SC","STSong","SimSun",serif';}return name+',serif';}
        function applySettings(d){var root=document.documentElement.style;var fontSize=Math.max(18,Math.min(30,(Number(d.fontSize)||23)*1.12));var lineHeight=Math.max(1.45,Math.min(2.2,(Number(d.lineSpacing)||1.3)+.2));root.setProperty('--reader-bg',d.backgroundColor||'#F5F2EC');root.setProperty('--reader-text',d.textColor||'#24211D');root.setProperty('--reader-accent',d.accentColor||'#236D67');root.setProperty('--reader-panel',d.panelColor||'#F3F4F2');root.setProperty('--reader-control',d.controlSurfaceColor||'#FFFDF8');root.setProperty('--reader-font-size',fontSize+'px');root.setProperty('--reader-line-height',lineHeight);root.setProperty('--reader-font-family',readerFontFamily(d.fontFamily));}
        function loadSettings(){fetch('/api/settings?t='+token()+'&v='+Date.now(),{cache:'no-store'}).then(r=>r.json()).then(applySettings).catch(e=>console.error(e));}
        function setStatus(ok){statusDot.style.background=ok?'var(--reader-accent)':'#C94A45';statusText.textContent=ok?'已连接':'连接已断开';}
        document.addEventListener('keydown',function(e){if(e.key==='ArrowRight'||e.key==='ArrowDown'||e.key==='j'){e.preventDefault();nextPage();}else if(e.key==='ArrowLeft'||e.key==='ArrowUp'||e.key==='k'){e.preventDefault();prevPage();}});
        var es=null,reconnectTimer=null;
        function connectSSE(){if(es){es.close();}es=new EventSource('/api/stream?t='+token());es.addEventListener('connected',function(){setStatus(true);});es.addEventListener('pagechange',loadPage);es.addEventListener('chapterchange',function(e){var d=JSON.parse(e.data);chapterTitleEl.textContent=d.chapterTitle;});es.addEventListener('settingschange',function(e){applySettings(JSON.parse(e.data));});es.onerror=function(){setStatus(false);es.close();clearTimeout(reconnectTimer);reconnectTimer=setTimeout(connectSSE,3000);};}
        if('serviceWorker' in navigator){navigator.serviceWorker.register('/sw.js?t='+encodeURIComponent(token())).catch(console.error);}
        loadPage();
        loadBookInfo();
        loadSettings();
        connectSSE();
        setInterval(function(){loadPage();loadSettings();},2000);
        </script>
        </body>
        </html>
        """
    }

    private func extractPageIndex(from path: String) -> Int? {
        // Extract from "/api/page/42"
        let pattern = "/api/page/(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
           let range = Range(match.range(at: 1), in: path) {
            return Int(path[range])
        }
        return nil
    }
}
