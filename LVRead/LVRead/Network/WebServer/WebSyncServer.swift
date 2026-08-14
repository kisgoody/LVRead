import Foundation
import CryptoKit
import Network
import Security
import UIKit

extension Notification.Name {
    static let webSyncPageTurnRequested = Notification.Name("webSyncPageTurnRequested")
    static let webSyncConnectionStateChanged = Notification.Name("webSyncConnectionStateChanged")
}

enum WebSocketFrameCodec {
    enum Opcode: UInt8 {
        case text = 0x1
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    struct Frame {
        let opcode: Opcode
        let payload: Data
    }

    struct DecodeResult {
        let frames: [Frame]
        let remaining: Data
    }

    enum CodecError: Error {
        case unsupportedFrame
        case invalidLength
    }

    static func encode(_ payload: Data, opcode: Opcode) -> Data {
        var result = Data([0x80 | opcode.rawValue])
        switch payload.count {
        case 0...125:
            result.append(UInt8(payload.count))
        case 126...65_535:
            result.append(126)
            var length = UInt16(payload.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        default:
            result.append(127)
            var length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        }
        result.append(payload)
        return result
    }

    static func decodeFrames(from data: Data) throws -> DecodeResult {
        var frames: [Frame] = []
        var offset = 0
        while data.count - offset >= 2 {
            let first = data[offset]
            let second = data[offset + 1]
            guard first & 0x80 != 0,
                  let opcode = Opcode(rawValue: first & 0x0F) else {
                throw CodecError.unsupportedFrame
            }
            let masked = second & 0x80 != 0
            var length = Int(second & 0x7F)
            var headerLength = 2
            if length == 126 {
                guard data.count - offset >= 4 else { break }
                length = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
                headerLength = 4
            } else if length == 127 {
                guard data.count - offset >= 10 else { break }
                let value = data[(offset + 2)..<(offset + 10)].reduce(UInt64(0)) {
                    ($0 << 8) | UInt64($1)
                }
                guard value <= UInt64(Int.max) else { throw CodecError.invalidLength }
                length = Int(value)
                headerLength = 10
            }
            let maskLength = masked ? 4 : 0
            guard data.count - offset >= headerLength + maskLength + length else { break }
            let maskStart = offset + headerLength
            let payloadStart = maskStart + maskLength
            var payload = Data(data[payloadStart..<(payloadStart + length)])
            if masked {
                let key = Array(data[maskStart..<(maskStart + 4)])
                for index in payload.indices {
                    payload[index] ^= key[index % 4]
                }
            }
            frames.append(Frame(opcode: opcode, payload: payload))
            offset = payloadStart + length
        }
        return DecodeResult(frames: frames, remaining: Data(data[offset...]))
    }
}

enum WebSyncConnectionState: String, Equatable {
    case disconnected
    case connecting
    case connected

    var title: String {
        switch self {
        case .disconnected: return L("同步已关闭")
        case .connecting: return L("等待连接")
        case .connected: return L("连接成功")
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

    struct PageLayoutSnapshot: Codable, Equatable {
        let width: Double
        let height: Double
        let safeAreaTop: Double
        let safeAreaLeft: Double
        let safeAreaBottom: Double
        let safeAreaRight: Double
        let usesContinuousInsets: Bool

        init(size: CGSize, safeAreaInsets: UIEdgeInsets, usesContinuousInsets: Bool) {
            width = size.width
            height = size.height
            safeAreaTop = safeAreaInsets.top
            safeAreaLeft = safeAreaInsets.left
            safeAreaBottom = safeAreaInsets.bottom
            safeAreaRight = safeAreaInsets.right
            self.usesContinuousInsets = usesContinuousInsets
        }

        var size: CGSize { CGSize(width: width, height: height) }
        var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(
                top: safeAreaTop,
                left: safeAreaLeft,
                bottom: safeAreaBottom,
                right: safeAreaRight
            )
        }
    }

    struct PageSnapshot: Codable, Equatable {
        let pageIndex: Int
        let content: String
        let chapterTitle: String
        let chapterIndex: Int
        let totalPages: Int
        let layout: PageLayoutSnapshot?

        init(
            pageIndex: Int,
            content: String,
            chapterTitle: String,
            chapterIndex: Int,
            totalPages: Int,
            layout: PageLayoutSnapshot? = nil
        ) {
            self.pageIndex = pageIndex
            self.content = content
            self.chapterTitle = chapterTitle
            self.chapterIndex = chapterIndex
            self.totalPages = totalPages
            self.layout = layout
        }
    }

    private struct StoredSnapshot: Codable {
        let page: PageSnapshot
        let updatedAt: Date
    }

    private struct WebSocketClient {
        let connection: NWConnection
        let bookId: String
    }

    struct OfflineBookArchive: Codable {
        struct OfflinePage: Codable {
            let chapterIndex: Int
            let pageIndex: Int
            let chapterTitle: String
            let content: String
        }

        let version: Int
        let bookId: String
        let title: String
        let author: String
        let pages: [OfflinePage]
        var progress: ReadingProgress
        let settings: ReadingSettings
        let generatedAt: Date
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
        static let foregroundReconnectEnabled = "web_sync_foreground_reconnect_enabled_v2"
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
    private var currentArchive: OfflineBookArchive?
    private var archiveBuildProgress = 0.0
    private var archiveBuildError: String?
    private var archiveBuildID: UUID?

    /// WebSocket connections keyed by a connection identifier.
    private var webSocketConnections: [UUID: WebSocketClient] = [:]
    private let webSocketLock = NSLock()

    private let serverQueue = DispatchQueue(label: "com.lvread.webSyncServer", qos: .utility)
    private let archiveQueue = DispatchQueue(label: "com.lvread.webSyncArchive", qos: .utility)

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
            ),
            layout: nil
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
        UserDefaults.standard.set(true, forKey: StorageKey.foregroundReconnectEnabled)
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
        if currentBook?.id != book.id {
            resetArchiveBuild()
        }
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
        UserDefaults.standard.set(false, forKey: StorageKey.foregroundReconnectEnabled)
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

        webSocketLock.lock()
        let activeConnections = webSocketConnections.values.map(\.connection)
        webSocketConnections.removeAll()
        webSocketLock.unlock()
        activeConnections.forEach { $0.cancel() }

        removeObservers()
        hostPublisher.stop()
        completeStart(with: .failure(startError))
        serverURL = ""
        serverPort = 0
        currentBook = nil
        setActiveBookID(nil)
        currentPageSnapshot = nil
        currentArchive = nil
        archiveBuildID = nil
        archiveBuildProgress = 0
        archiveBuildError = nil
    }

    func updateCurrentPage(bookId: String, page: PageSnapshot) {
        serverQueue.async { [weak self] in
            guard let self else { return }
            self.storeSnapshot(page, for: bookId)
            guard self.isRunning else { return }
            if self.currentBook?.id != bookId {
                self.resetArchiveBuild()
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

    /// Rebuilds the listener after iOS has suspended the app, but only when the
    /// user previously enabled web sync. This is intentionally not called on launch.
    func reconnectAfterForegroundIfNeeded() {
        guard UserDefaults.standard.bool(
            forKey: StorageKey.foregroundReconnectEnabled
        ) else { return }

        serverQueue.async { [weak self] in
            guard let self else { return }
            guard
                let saved = self.storedSnapshots().max(
                    by: { $0.value.updatedAt < $1.value.updatedAt }
                ),
                let book = BookRepository.shared.getById(saved.key)
            else {
                UserDefaults.standard.set(
                    false,
                    forKey: StorageKey.foregroundReconnectEnabled
                )
                return
            }

            // A suspended app does not mean the listener has failed. Keep the
            // existing listener and WebSocket sessions alive whenever possible;
            // the browser owns reconnection after a passive network interruption.
            guard !self.isRunning else { return }
            self.startOnQueue(with: book, page: saved.value.page) { result in
                if case .failure(let error) = result {
                    print("[WebSyncServer] Foreground reconnect failed: \(error)")
                }
            }
        }
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

    // MARK: - WebSocket Notifications

    /// Notify connected WebSocket clients of a page change.
    public func notifyPageChanged(
        pageIndex: Int,
        chapterTitle: String,
        progressPercent: Double,
        bookId: String? = nil
    ) {
        let targetBookId = bookId ?? currentBook?.id
        broadcastWebSocket([
            "type": "pagechange",
            "bookId": targetBookId ?? "",
            "pageIndex": pageIndex,
            "chapterIndex": currentPageSnapshot?.chapterIndex ?? 0,
            "chapterTitle": chapterTitle,
            "progressPercent": progressPercent,
            "updatedAt": Date().timeIntervalSince1970
        ], bookId: targetBookId)
    }

    /// Notify connected WebSocket clients of a chapter change.
    public func notifyChapterChanged(chapterIndex: Int, chapterTitle: String) {
        broadcastWebSocket([
            "type": "chapterchange",
            "chapterIndex": chapterIndex,
            "chapterTitle": chapterTitle
        ], bookId: currentBook?.id)
    }

    /// Notify connected WebSocket clients of settings changes.
    public func notifySettingsChanged(_ settings: ReadingSettings) {
        resetArchiveBuild()
        var message = settingsResponse(settings)
        message["type"] = "settingschange"
        broadcastWebSocket(message)
        broadcastWebSocket(["type": "archivechanged"])
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

            let (method, path, queryParams, headers) = self.parseHTTPRequest(requestString)

            let token = queryParams["t"] ?? ""
            guard !token.isEmpty, let requestBookId = self.activateBook(for: token) else {
                self.sendErrorResponse(statusCode: 403, message: "Forbidden", to: connection)
                return
            }

            if method == "GET", path == "/ws",
               headers["upgrade"]?.lowercased() == "websocket" {
                self.handleWebSocketUpgrade(
                    connection,
                    bookId: requestBookId,
                    headers: headers
                )
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

            case ("GET", "/api/book/archive"):
                self.serveBookArchive(to: connection)

            case ("GET", "/api/book/archive/status"):
                self.serveBookArchiveStatus(to: connection)

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

    private func serveBookArchive(to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }
        guard var archive = currentArchive, archive.bookId == book.id else {
            beginArchiveBuildIfNeeded(for: book)
            sendHTTPResponse(
                statusCode: 202,
                contentType: "application/json; charset=utf-8",
                body: "{\"status\":\"building\",\"progress\":\(archiveBuildProgress)}",
                to: connection
            )
            return
        }
        do {
            archive.progress = BookRepository.shared.getById(book.id)?.readingProgress
                ?? book.readingProgress
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(archive)
            guard let body = String(data: data, encoding: .utf8) else {
                throw StartError.listener("无法编码离线书籍")
            }
            sendHTTPResponse(
                statusCode: 200,
                contentType: "application/json; charset=utf-8",
                body: body,
                to: connection
            )
        } catch {
            print("[WebSyncServer] Failed to build offline archive: \(error)")
            sendErrorResponse(statusCode: 500, message: "archive_failed", to: connection)
        }
    }

    private func serveBookArchiveStatus(to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }
        beginArchiveBuildIfNeeded(for: book)
        sendJSONResponse([
            "bookId": book.id,
            "ready": currentArchive?.bookId == book.id,
            "progress": archiveBuildProgress,
            "error": archiveBuildError ?? NSNull()
        ], to: connection)
    }

    private func resetArchiveBuild() {
        currentArchive = nil
        archiveBuildID = nil
        archiveBuildProgress = 0
        archiveBuildError = nil
    }

    private func beginArchiveBuildIfNeeded(for book: Book) {
        guard currentArchive?.bookId != book.id, archiveBuildID == nil else { return }
        let buildID = UUID()
        archiveBuildID = buildID
        archiveBuildProgress = 0
        archiveBuildError = nil
        var chapters = BookRepository.shared.getChapters(for: book.id)
        if chapters.isEmpty {
            chapters = [Chapter(bookId: book.id, title: L("正文"), orderIndex: 0)]
        }
        let layout = currentPageSnapshot?.layout ?? PageLayoutSnapshot(
            size: CGSize(width: 390, height: 844),
            safeAreaInsets: .zero,
            usesContinuousInsets: false
        )
        let settings = ReadingSettingsRepository.shared.load()
        archiveQueue.async { [weak self] in
            guard let self else { return }
            do {
                let archive = try self.makeBookArchive(
                    for: book,
                    chapters: chapters,
                    layout: layout,
                    settings: settings,
                    progress: { completed, total in
                        self.serverQueue.async {
                            guard self.archiveBuildID == buildID else { return }
                            self.archiveBuildProgress = Double(completed) / Double(max(total, 1))
                            self.broadcastWebSocket([
                                "type": "archiveprogress",
                                "progress": self.archiveBuildProgress
                            ], bookId: book.id)
                        }
                    }
                )
                self.serverQueue.async {
                    guard self.archiveBuildID == buildID else { return }
                    self.currentArchive = archive
                    self.archiveBuildProgress = 1
                    self.archiveBuildID = nil
                    self.broadcastWebSocket([
                        "type": "archiveready",
                        "progress": 1
                    ], bookId: book.id)
                }
            } catch {
                self.serverQueue.async {
                    guard self.archiveBuildID == buildID else { return }
                    self.archiveBuildError = error.localizedDescription
                    self.archiveBuildID = nil
                    self.broadcastWebSocket([
                        "type": "archiveerror",
                        "message": error.localizedDescription
                    ], bookId: book.id)
                }
            }
        }
    }

    private func makeBookArchive(
        for book: Book,
        chapters: [Chapter],
        layout: PageLayoutSnapshot,
        settings: ReadingSettings,
        progress: @escaping (Int, Int) -> Void
    ) throws -> OfflineBookArchive {
        let paginator = NativeDocumentChapterPaginator(
            book: book,
            chapters: chapters,
            size: layout.size,
            safeAreaInsets: layout.usesContinuousInsets ? .zero : layout.safeAreaInsets,
            textInsets: layout.usesContinuousInsets
                ? NativeDocumentTypography.continuousInsets(size: layout.size, settings: settings)
                : nil,
            settings: settings
        )
        var pages: [OfflineBookArchive.OfflinePage] = []
        for chapterIndex in chapters.indices {
            let chapterPages = try paginator.pages(at: chapterIndex)
            pages.append(contentsOf: chapterPages.map {
                OfflineBookArchive.OfflinePage(
                    chapterIndex: $0.chapterIndex,
                    pageIndex: $0.pageIndex,
                    chapterTitle: $0.chapterTitle,
                    content: $0.text
                )
            })
            progress(chapterIndex + 1, chapters.count)
        }
        guard !pages.isEmpty else { throw StartError.listener("书籍没有可同步内容") }
        return OfflineBookArchive(
            version: 1,
            bookId: book.id,
            title: book.title,
            author: book.author,
            pages: pages,
            progress: book.readingProgress,
            settings: settings,
            generatedAt: Date()
        )
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

    // MARK: - WebSocket Handling

    private func handleWebSocketUpgrade(
        _ connection: NWConnection,
        bookId: String,
        headers: [String: String]
    ) {
        guard let key = headers["sec-websocket-key"], !key.isEmpty else {
            sendErrorResponse(statusCode: 400, message: "Missing WebSocket key", to: connection)
            return
        }
        let accept = Self.webSocketAccept(for: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r
        """
        let connectionId = UUID()
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            self.webSocketLock.lock()
            self.webSocketConnections[connectionId] = WebSocketClient(
                connection: connection,
                bookId: bookId
            )
            self.webSocketLock.unlock()
            self.setConnectionState(.connected)
            self.sendWebSocket([
                "type": "connected",
                "bookId": bookId,
                "serverTime": Date().timeIntervalSince1970
            ], to: connection)
            self.receiveWebSocket(on: connection, connectionId: connectionId, buffer: Data())
        })
    }

    static func webSocketAccept(for key: String) -> String {
        let source = Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
        return Data(Insecure.SHA1.hash(data: source)).base64EncodedString()
    }

    private func receiveWebSocket(
        on connection: NWConnection,
        connectionId: UUID,
        buffer: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if complete || error != nil {
                self.removeWebSocketConnection(connectionId)
                return
            }
            var pending = buffer
            if let data { pending.append(data) }
            do {
                let decoded = try WebSocketFrameCodec.decodeFrames(from: pending)
                for frame in decoded.frames {
                    switch frame.opcode {
                    case .text:
                        self.handleWebSocketMessage(frame.payload, connection: connection)
                    case .ping:
                        connection.send(
                            content: WebSocketFrameCodec.encode(frame.payload, opcode: .pong),
                            completion: .contentProcessed { _ in }
                        )
                    case .close:
                        self.removeWebSocketConnection(connectionId)
                        return
                    default:
                        break
                    }
                }
                self.receiveWebSocket(
                    on: connection,
                    connectionId: connectionId,
                    buffer: decoded.remaining
                )
            } catch {
                self.removeWebSocketConnection(connectionId)
            }
        }
    }

    private func handleWebSocketMessage(_ data: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "progress":
            applyRemoteProgress(json, connection: connection)
        case "ping":
            sendWebSocket(["type": "pong"], to: connection)
        default:
            break
        }
    }

    private func applyRemoteProgress(_ json: [String: Any], connection: NWConnection) {
        guard let book = currentBook,
              let chapterIndex = json["chapterIndex"] as? Int,
              let pageIndex = json["pageIndex"] as? Int,
              let updatedAt = json["updatedAt"] as? TimeInterval else { return }
        let remoteDate = Date(timeIntervalSince1970: updatedAt)
        let storedBook = BookRepository.shared.getById(book.id) ?? book
        let isLiveTurn = json["live"] as? Bool == true
        guard isLiveTurn || remoteDate > storedBook.readingProgress.lastReadTimestamp else {
            sendWebSocket(currentProgressMessage(for: storedBook), to: connection)
            return
        }
        let archivePage = currentArchive?.pages.first(where: {
            $0.chapterIndex == chapterIndex && $0.pageIndex == pageIndex
        })
        let cachedPage = PageCacheManager.shared.getPage(
            bookId: book.id,
            chapterIndex: chapterIndex,
            pageIndex: pageIndex
        )
        guard archivePage != nil || cachedPage != nil else {
            beginArchiveBuildIfNeeded(for: storedBook)
            sendWebSocket(["type": "archivepending"], to: connection)
            return
        }
        let chapterPageCount = currentArchive?.pages.filter {
            $0.chapterIndex == chapterIndex
        }.count ?? max((cachedPage?.pageIndex ?? 0) + 1, 1)
        let snapshot = PageSnapshot(
            pageIndex: archivePage?.pageIndex ?? cachedPage?.pageIndex ?? pageIndex,
            content: archivePage?.content ?? cachedPage?.content ?? "",
            chapterTitle: archivePage?.chapterTitle ?? cachedPage?.chapterTitle ?? "",
            chapterIndex: archivePage?.chapterIndex ?? cachedPage?.chapterIndex ?? chapterIndex,
            totalPages: max(chapterPageCount, 1),
            layout: currentPageSnapshot?.layout
        )
        currentPageSnapshot = snapshot
        currentPageIndex = pageIndex
        storeSnapshot(snapshot, for: book.id)
        let percent = progressPercent(bookId: book.id, page: snapshot)
        BookRepository.shared.updateProgress(
            bookId: book.id,
            progress: ReadingProgress(
                currentChapterIndex: chapterIndex,
                currentPageOffset: pageIndex,
                totalPages: snapshot.totalPages,
                progressPercent: percent,
                lastReadTimestamp: remoteDate
            )
        )
        notifyPageChanged(
            pageIndex: pageIndex,
            chapterTitle: snapshot.chapterTitle,
            progressPercent: percent,
            bookId: book.id
        )
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSyncPageTurnRequested,
                object: nil,
                userInfo: [
                    "forward": chapterIndex > storedBook.readingProgress.currentChapterIndex
                        || (chapterIndex == storedBook.readingProgress.currentChapterIndex
                            && pageIndex > storedBook.readingProgress.currentPageOffset),
                    "bookId": book.id,
                    "chapterIndex": chapterIndex,
                    "pageIndex": pageIndex
                ]
            )
        }
    }

    private func currentProgressMessage(for book: Book) -> [String: Any] {
        [
            "type": "progress",
            "bookId": book.id,
            "chapterIndex": book.readingProgress.currentChapterIndex,
            "pageIndex": book.readingProgress.currentPageOffset,
            "updatedAt": book.readingProgress.lastReadTimestamp.timeIntervalSince1970
        ]
    }

    private func sendWebSocket(_ json: [String: Any], to connection: NWConnection) {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        connection.send(
            content: WebSocketFrameCodec.encode(data, opcode: .text),
            completion: .contentProcessed { _ in }
        )
    }

    private func broadcastWebSocket(_ json: [String: Any], bookId: String? = nil) {
        webSocketLock.lock()
        let clients = Array(webSocketConnections.values)
        webSocketLock.unlock()
        clients.filter { bookId == nil || $0.bookId == bookId }.forEach {
            sendWebSocket(json, to: $0.connection)
        }
    }

    private func removeWebSocketConnection(_ id: UUID) {
        webSocketLock.lock()
        let connection = webSocketConnections.removeValue(forKey: id)?.connection
        let hasClients = !webSocketConnections.isEmpty
        webSocketLock.unlock()
        connection?.cancel()
        if isRunning && !hasClients { setConnectionState(.connecting) }
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
        case 202: return "Accepted"
        case 400: return "Bad Request"
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
        let target: PageSnapshot
        do {
            target = try resolvedTurnSnapshot(from: page, forward: forward, bookId: bookId)
        } catch let error as RemoteTurnError {
            sendJSONResponse(["success": false, "error": error.rawValue], to: connection)
            return
        } catch {
            print("[WebSyncServer] Failed to resolve remote page turn: \(error)")
            sendJSONResponse(["success": false, "error": RemoteTurnError.pageLoadFailed.rawValue], to: connection)
            return
        }

        currentPageSnapshot = target
        currentPageIndex = target.pageIndex
        storeSnapshot(target, for: bookId)
        let percent = progressPercent(bookId: bookId, page: target)
        BookRepository.shared.updateProgress(
            bookId: bookId,
            progress: ReadingProgress(
                currentChapterIndex: target.chapterIndex,
                currentPageOffset: target.pageIndex,
                totalPages: target.totalPages,
                progressPercent: percent,
                lastReadTimestamp: Date()
            )
        )
        notifyPageChanged(
            pageIndex: target.pageIndex,
            chapterTitle: target.chapterTitle,
            progressPercent: percent,
            bookId: bookId
        )

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSyncPageTurnRequested,
                object: nil,
                userInfo: [
                    "forward": forward,
                    "bookId": bookId,
                    "chapterIndex": target.chapterIndex,
                    "pageIndex": target.pageIndex
                ]
            )
        }
        sendJSONResponse(
            ["success": true, "direction": direction, "updated": true],
            to: connection
        )
    }

    private func resolvedTurnSnapshot(
        from page: PageSnapshot,
        forward: Bool,
        bookId: String
    ) throws -> PageSnapshot {
        guard let book = currentBook, book.id == bookId else {
            throw RemoteTurnError.pageLoadFailed
        }
        let cache = PageCacheManager.shared
        let sameChapterPageIndex = page.pageIndex + (forward ? 1 : -1)
        if sameChapterPageIndex >= 0,
           sameChapterPageIndex < page.totalPages,
           let cached = cache.getPage(
               bookId: bookId,
               chapterIndex: page.chapterIndex,
               pageIndex: sameChapterPageIndex
           ) {
            return snapshot(from: cached, totalPages: page.totalPages, layout: page.layout)
        }

        guard book.fileFormat != .pdf else {
            throw RemoteTurnError.pageLoadFailed
        }
        var chapters = BookRepository.shared.getChapters(for: bookId)
        if chapters.isEmpty {
            chapters = [Chapter(bookId: bookId, title: "正文", orderIndex: 0)]
        }
        guard chapters.indices.contains(page.chapterIndex) else {
            throw RemoteTurnError.pageLoadFailed
        }
        let layout = page.layout ?? PageLayoutSnapshot(
            size: UIScreen.main.bounds.size,
            safeAreaInsets: .zero,
            usesContinuousInsets: false
        )
        let settings = ReadingSettingsRepository.shared.load()
        let paginator = NativeDocumentChapterPaginator(
            book: book,
            chapters: chapters,
            size: layout.size,
            safeAreaInsets: layout.usesContinuousInsets ? .zero : layout.safeAreaInsets,
            textInsets: layout.usesContinuousInsets
                ? NativeDocumentTypography.continuousInsets(size: layout.size, settings: settings)
                : nil,
            settings: settings
        )

        func materializedPages(at chapterIndex: Int) throws -> [NativeDocumentPage] {
            let pages = try paginator.pages(at: chapterIndex)
            let cachedPages = pages.map {
                PageData(
                    pageIndex: $0.pageIndex,
                    startCharOffset: $0.startOffset,
                    endCharOffset: $0.endOffset,
                    content: $0.text,
                    chapterTitle: $0.chapterTitle,
                    chapterIndex: $0.chapterIndex
                )
            }
            cache.cachePages(cachedPages, bookId: bookId, centerPage: page.pageIndex)
            return pages
        }

        let currentPages = try materializedPages(at: page.chapterIndex)
        if currentPages.indices.contains(sameChapterPageIndex) {
            return snapshot(
                from: currentPages[sameChapterPageIndex],
                totalPages: currentPages.count,
                layout: layout
            )
        }

        var chapterIndex = page.chapterIndex + (forward ? 1 : -1)
        while chapters.indices.contains(chapterIndex) {
            let pages = try materializedPages(at: chapterIndex)
            if let target = forward ? pages.first : pages.last {
                return snapshot(from: target, totalPages: pages.count, layout: layout)
            }
            chapterIndex += forward ? 1 : -1
        }
        throw forward ? RemoteTurnError.endOfBook : RemoteTurnError.beginningOfBook
    }

    private func snapshot(
        from page: PageData,
        totalPages: Int,
        layout: PageLayoutSnapshot?
    ) -> PageSnapshot {
        return PageSnapshot(
            pageIndex: page.pageIndex,
            content: page.content,
            chapterTitle: page.chapterTitle,
            chapterIndex: page.chapterIndex,
            totalPages: max(totalPages, 1),
            layout: layout
        )
    }

    private func snapshot(
        from page: NativeDocumentPage,
        totalPages: Int,
        layout: PageLayoutSnapshot
    ) -> PageSnapshot {
        PageSnapshot(
            pageIndex: page.pageIndex,
            content: page.text,
            chapterTitle: page.chapterTitle,
            chapterIndex: page.chapterIndex,
            totalPages: max(totalPages, 1),
            layout: layout
        )
    }

    private enum RemoteTurnError: String, Error {
        case beginningOfBook = "beginning_of_book"
        case endOfBook = "end_of_book"
        case pageLoadFailed = "page_load_failed"
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
        const cacheName='lvread-reader-v4';
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
        html,body{height:100%;overflow:hidden;}
        body{height:100vh;height:100dvh;display:flex;flex-direction:column;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--reader-panel);color:var(--reader-text);transition:background-color .2s,color .2s;}
        .topbar{height:64px;flex:0 0 64px;background:var(--reader-control);padding:0 32px;display:flex;align-items:center;justify-content:space-between;z-index:10;border-bottom:1px solid color-mix(in srgb,var(--reader-text) 12%,transparent);}
        .topbar-left,.brand,.topbar-right,.chapter-meta,.status,.cache-status,.reading-mode-control{display:flex;align-items:center;}
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
        .cache-status{font-size:12px;color:var(--reader-text);opacity:.72;gap:6px;white-space:nowrap;}
        .cache-status.ready{color:var(--reader-accent);opacity:1;}
        .dot{width:8px;height:8px;border-radius:50%;background:var(--reader-accent);box-shadow:0 0 0 3px color-mix(in srgb,var(--reader-accent) 12%,transparent);}
        .reading-mode-control{height:44px;padding:4px;background:color-mix(in srgb,var(--reader-text) 7%,var(--reader-control));border:1px solid color-mix(in srgb,var(--reader-text) 12%,transparent);border-radius:12px;white-space:nowrap;}
        .mode-option{height:36px;min-width:80px;padding:0 16px;background:transparent;color:var(--reader-text);border:0;border-radius:8px;font-size:14px;font-weight:500;cursor:pointer;transition:background-color .15s,color .15s,transform .15s;}
        .mode-option:hover:not(.selected){background:color-mix(in srgb,var(--reader-accent) 10%,transparent);}
        .mode-option:active{transform:scale(.97);}
        .mode-option:focus-visible{outline:2px solid var(--reader-accent);outline-offset:1px;}
        .mode-option.selected{background:var(--reader-accent);color:var(--reader-control);box-shadow:0 2px 8px color-mix(in srgb,var(--reader-accent) 24%,transparent);}
        .mode-option:disabled{opacity:.45;cursor:not-allowed;}
        .container{width:min(1120px,calc(100% - 48px));flex:1;min-height:0;margin:0 auto;padding:24px 0 16px;display:flex;flex-direction:column;}
        .container.mobile-portrait{width:min(430px,calc(100% - 32px));}
        .container.mobile-portrait .paper{padding:32px;}
        .content{position:relative;flex:1;min-height:0;display:grid;grid-template-columns:1fr;background:var(--reader-bg);color:var(--reader-text);border:1px solid color-mix(in srgb,var(--reader-text) 12%,transparent);border-radius:12px;overflow:hidden;box-shadow:0 8px 40px color-mix(in srgb,var(--reader-text) 10%,transparent);perspective:1800px;transition:background-color .2s,color .2s,border-color .2s;}
        .paper{position:relative;min-width:0;padding:40px 48px;overflow:hidden;background:var(--reader-bg);}
        .paper.right{display:none;}
        .container.spread-mode .content{grid-template-columns:1fr 1fr;}
        .container.spread-mode .paper.left{border-right:1px solid color-mix(in srgb,var(--reader-text) 10%,transparent);box-shadow:inset -18px 0 24px -28px rgba(0,0,0,.55);}
        .container.spread-mode .paper.right{display:block;box-shadow:inset 18px 0 24px -28px rgba(0,0,0,.55);}
        .content-text{font-family:var(--reader-font-family);font-size:var(--reader-font-size);line-height:var(--reader-line-height);white-space:pre-wrap;overflow-wrap:anywhere;text-align:justify;}
        .turn-sheet{position:absolute;top:0;bottom:0;width:50%;z-index:5;transform-style:preserve-3d;pointer-events:none;will-change:transform;}
        .turn-sheet.next{left:50%;transform-origin:left center;animation:turnNext .86s cubic-bezier(.25,.65,.22,1) forwards;}
        .turn-sheet.prev{left:0;transform-origin:right center;transform:rotateY(-180deg);animation:turnPrev .86s cubic-bezier(.25,.65,.22,1) forwards;}
        .turn-face{position:absolute;inset:0;padding:40px 48px;overflow:hidden;background:var(--reader-bg);backface-visibility:hidden;font-family:var(--reader-font-family);font-size:var(--reader-font-size);line-height:var(--reader-line-height);color:var(--reader-text);white-space:pre-wrap;overflow-wrap:anywhere;text-align:justify;box-shadow:0 0 18px rgba(0,0,0,.12);}
        .turn-face:after{content:"";position:absolute;inset:0;pointer-events:none;background:linear-gradient(90deg,rgba(0,0,0,.22),transparent 18%,transparent 72%,rgba(255,255,255,.18));opacity:0;animation:pageShade .86s ease-in-out;}
        .turn-face.back{transform:rotateY(180deg);filter:brightness(.94);}
        @keyframes turnNext{0%{transform:rotateY(0deg) skewY(0deg)}35%{transform:rotateY(-62deg) skewY(-1.2deg)}68%{transform:rotateY(-132deg) skewY(.8deg)}100%{transform:rotateY(-180deg) skewY(0deg)}}
        @keyframes turnPrev{0%{transform:rotateY(-180deg) skewY(0deg)}32%{transform:rotateY(-128deg) skewY(-.8deg)}68%{transform:rotateY(-48deg) skewY(1.2deg)}100%{transform:rotateY(0deg) skewY(0deg)}}
        @keyframes pageShade{0%,100%{opacity:0}45%,60%{opacity:1}}
        .controls{display:flex;justify-content:center;gap:24px;margin-top:16px;}
        .controls button{min-width:152px;min-height:48px;background:var(--reader-control);color:var(--reader-accent);border:1px solid color-mix(in srgb,var(--reader-text) 18%,transparent);padding:8px 24px;border-radius:12px;font-size:14px;cursor:pointer;font-weight:600;transition:background-color .15s,border-color .15s,transform .15s;}
        .controls button:hover{background:color-mix(in srgb,var(--reader-accent) 10%,var(--reader-control));border-color:var(--reader-accent);}
        .controls button:active{transform:scale(.98);}
        .controls button:disabled{opacity:.45;cursor:not-allowed;}
        .shortcuts{height:32px;margin-top:8px;text-align:center;font-size:12px;color:var(--reader-text);opacity:.58;line-height:32px;}
        .shortcuts kbd{display:inline-flex;align-items:center;justify-content:center;min-width:32px;height:32px;background:var(--reader-control);color:var(--reader-accent);padding:0 8px;border-radius:8px;font-family:monospace;font-size:12px;border:1px solid color-mix(in srgb,var(--reader-text) 18%,transparent);}
        @media(max-width:760px){.topbar{padding:0 16px;gap:8px;}.separator,.status,.chapter-meta{display:none;}.book-title{max-width:24vw;font-size:12px;}.topbar-right{gap:8px;}.mode-option{min-width:64px;padding:0 12px;}.container,.container.mobile-portrait{width:calc(100% - 24px);padding:16px 0 8px;}.paper,.turn-face{padding:24px;}.controls{margin-top:8px;}.controls button{min-width:120px;}.shortcuts{margin-top:0;}}
        @media(prefers-reduced-motion:reduce){.turn-sheet.next,.turn-sheet.prev{animation-duration:.01ms;}}
        @media(max-width:520px){.book-title,.separator{display:none;}}
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
        <div class="reading-mode-control" role="group" aria-label="网页阅读模式">
        <button class="mode-option selected" type="button" data-mode="default" aria-pressed="true">默认</button>
        <button class="mode-option" type="button" data-mode="mobile" aria-pressed="false">手机竖屏</button>
        <button class="mode-option" type="button" data-mode="spread" aria-pressed="false">双页</button>
        </div>
        <div class="chapter-meta"><span id="chapterTitle"></span><span id="pageInfo"></span></div>
        <div class="cache-status" id="cacheStatus">整书缓存 0%</div>
        <div class="status"><span class="dot" id="statusDot"></span><span id="statusText">已连接</span></div>
        </div>
        </div>
        <div class="container" id="readerContainer">
        <article class="content" id="readingPage" aria-live="polite">
        <section class="paper left"><div class="content-text" id="leftContent">正在加载…</div></section>
        <section class="paper right"><div class="content-text" id="rightContent"></div></section>
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
        var currentIndex=0,totalPages=0,bookTitle='',archive=null,ws=null,reconnectTimer=null,archivePollTimer=null,turning=false,readingMode='default';
        var leftContentEl=document.getElementById('leftContent');
        var rightContentEl=document.getElementById('rightContent');
        var bookTitleEl=document.getElementById('bookTitle');
        var pageInfoEl=document.getElementById('pageInfo');
        var chapterTitleEl=document.getElementById('chapterTitle');
        var statusDot=document.getElementById('statusDot');
        var statusText=document.getElementById('statusText');
        var cacheStatus=document.getElementById('cacheStatus');
        var readingModeButtons=document.querySelectorAll('.mode-option');
        var readerContainer=document.getElementById('readerContainer');
        var readingPage=document.getElementById('readingPage');
        var readingModeStorageKey='lvread_web_reading_mode';
        var readerBaseFontSize=26;
        function fitRenderedPages(){var visible=readingMode==='spread'?[leftContentEl,rightContentEl]:[leftContentEl];visible.forEach(function(el){el.style.fontSize='';});var size=readerBaseFontSize;function overflows(el){var paper=el.parentElement,style=getComputedStyle(paper),height=paper.clientHeight-parseFloat(style.paddingTop)-parseFloat(style.paddingBottom);return el.scrollHeight>height+1;}while(size>12&&visible.some(overflows)){size-=.5;visible.forEach(function(el){el.style.fontSize=size+'px';});}}
        function schedulePortraitResize(){requestAnimationFrame(function(){fitRenderedPages();});}
        function pagesPerView(){return readingMode==='spread'?2:1;}
        function applyWebReadingMode(mode){var nextMode=mode==='mobile'||mode==='spread'?mode:'default';var anchor=pageAt(0);readingMode=nextMode;readerContainer.classList.toggle('mobile-portrait',nextMode==='mobile');readerContainer.classList.toggle('spread-mode',nextMode==='spread');if(anchor&&archive){var found=archive.pages.indexOf(anchor);currentIndex=nextMode==='spread'?Math.floor(found/2)*2:found;}readingModeButtons.forEach(function(button){var selected=button.dataset.mode===nextMode;button.classList.toggle('selected',selected);button.setAttribute('aria-pressed',selected);});try{localStorage.setItem(readingModeStorageKey,nextMode);}catch(e){console.warn('无法保存网页阅读模式',e);}renderPages(false);}
        function loadWebReadingMode(){var mode='default';try{mode=localStorage.getItem(readingModeStorageKey)||mode;}catch(e){console.warn('无法读取网页阅读模式',e);}applyWebReadingMode(mode);}
        function openArchiveDB(){return new Promise(function(resolve,reject){var request=indexedDB.open('lvread-offline',1);request.onupgradeneeded=function(){if(!request.result.objectStoreNames.contains('books')){request.result.createObjectStore('books',{keyPath:'bookId'});}};request.onsuccess=function(){resolve(request.result);};request.onerror=function(){reject(request.error);};});}
        function saveArchive(){if(!archive||!archive._complete){return Promise.resolve();}return openArchiveDB().then(function(db){return new Promise(function(resolve,reject){var tx=db.transaction('books','readwrite');tx.objectStore('books').put(archive);tx.oncomplete=function(){try{localStorage.setItem('lvread_last_book_id',archive.bookId);}catch(e){}db.close();resolve();};tx.onerror=function(){reject(tx.error);};});});}
        function loadCachedArchive(){return openArchiveDB().then(function(db){return new Promise(function(resolve,reject){var id='';try{id=localStorage.getItem('lvread_last_book_id')||'';}catch(e){}var store=db.transaction('books','readonly').objectStore('books');var request=id?store.get(id):store.getAll();request.onsuccess=function(){var result=id?request.result:(request.result||[]).pop();db.close();if(result&&result._complete){archive=result;prepareArchive();renderPages(false);setCacheProgress(1,false,true);resolve(true);}else{resolve(false);}};request.onerror=function(){db.close();reject(request.error);};});}).catch(function(e){console.warn('无法读取离线书籍',e);return false;});}
        function prepareArchive(){archive.pages=Array.isArray(archive.pages)?archive.pages:[];totalPages=archive.pages.length;bookTitle=archive.title||bookTitle;bookTitleEl.textContent=bookTitle||'LVRead';var progress=archive.progress||{};var pageIndex=Number(progress.pageIndex!==undefined?progress.pageIndex:progress.currentPageOffset)||0;var chapterIndex=Number(progress.chapterIndex!==undefined?progress.chapterIndex:progress.currentChapterIndex)||0;var index=archive.pages.findIndex(function(page){return page.chapterIndex===chapterIndex&&page.pageIndex===pageIndex;});currentIndex=Math.max(index,0);if(readingMode==='spread'){currentIndex=Math.floor(currentIndex/2)*2;}if(archive.settings){applySettings(archive.settings);}}
        function pageAt(offset){return archive&&archive.pages?archive.pages[currentIndex+offset]:null;}
        function renderPages(animate,direction){if(!archive){return;}var oldLeft=leftContentEl.textContent,oldRight=rightContentEl.textContent;var left=pageAt(0),right=readingMode==='spread'?pageAt(1):null;var title=(left||right||{}).chapterTitle||'';leftContentEl.textContent=left?left.content:'';rightContentEl.textContent=right?right.content:'';fitRenderedPages();if(animate&&readingMode==='spread'){animateTurn(direction,oldLeft,oldRight,left,right);}chapterTitleEl.textContent=title;var first=totalPages?currentIndex+1:0;var last=Math.min(currentIndex+pagesPerView(),totalPages);pageInfoEl.textContent=totalPages?(first+(last>first?'–'+last:'')+' / '+totalPages):'0 / 0';document.getElementById('prevBtn').disabled=currentIndex<=0;document.getElementById('nextBtn').disabled=currentIndex+pagesPerView()>=totalPages;}
        function animateTurn(direction,oldLeft,oldRight,left,right){var sheet=document.createElement('div');var fontSize=getComputedStyle(direction==='next'?rightContentEl:leftContentEl).fontSize;sheet.className='turn-sheet '+direction;sheet.innerHTML='<div class="turn-face front"></div><div class="turn-face back"></div>';sheet.querySelector('.front').textContent=direction==='next'?oldRight:(left?left.content:'');sheet.querySelector('.back').textContent=direction==='next'?(left?left.content:''):oldLeft;sheet.querySelectorAll('.turn-face').forEach(function(face){face.style.fontSize=fontSize;});readingPage.appendChild(sheet);turning=true;sheet.addEventListener('animationend',function(){sheet.remove();turning=false;},{once:true});}
        function progressTime(progress){return Number(progress&&(progress.updatedAt||progress.lastReadTimestamp))||0;}
        function setCacheProgress(value,error,ready){var percent=Math.max(0,Math.min(100,Math.round(Number(value||0)*100)));cacheStatus.classList.toggle('ready',!!ready&&!error);cacheStatus.textContent=error?'整书缓存失败':ready?'✓ 已离线缓存':'整书缓存 '+percent+'%';}
        function fetchCurrentPage(){if(archive&&archive._complete){return Promise.resolve();}return fetch('/api/page/current?t='+token(),{cache:'no-store'}).then(function(r){return r.json();}).then(function(page){archive={bookId:page.bookId,title:page.bookTitle,pages:[{chapterIndex:page.chapterIndex,pageIndex:page.pageIndex,chapterTitle:page.chapterTitle,content:page.content}],progress:{chapterIndex:page.chapterIndex,pageIndex:page.pageIndex},_complete:false};currentIndex=0;totalPages=1;bookTitle=page.bookTitle||'';bookTitleEl.textContent=bookTitle||'LVRead';renderPages(false);});}
        function fetchArchive(){var localProgress=archive&&archive.progress;return fetch('/api/book/archive?t='+token(),{cache:'no-store'}).then(function(r){if(r.status===202){throw new Error('archive_building');}if(!r.ok){throw new Error('archive '+r.status);}return r.json();}).then(function(data){if(progressTime(localProgress)>progressTime(data.progress)){data.progress=localProgress;}data._complete=true;archive=data;prepareArchive();renderPages(false);return saveArchive().then(function(){setCacheProgress(1,false,true);sendProgress(false);});}).catch(function(error){if(error.message!=='archive_building'){setCacheProgress(0,true,false);}throw error;});}
        function pollArchiveStatus(){clearTimeout(archivePollTimer);fetch('/api/book/archive/status?t='+token(),{cache:'no-store'}).then(function(r){return r.json();}).then(function(status){setCacheProgress(status.progress,status.error);if(status.ready){return fetchArchive();}if(!status.error){archivePollTimer=setTimeout(pollArchiveStatus,500);}}).catch(function(){archivePollTimer=setTimeout(pollArchiveStatus,1500);});}
        function token(){return new URLSearchParams(window.location.search).get('t')||'';}
        function sendProgress(markNow){if(!archive||!archive.pages.length){return;}var page=pageAt(0);var previous=archive.progress||{};var live=markNow!==false;var message={type:'progress',bookId:archive.bookId,chapterIndex:page.chapterIndex,pageIndex:page.pageIndex,updatedAt:live?Date.now()/1000:progressTime(previous),live:live};archive.progress=message;saveArchive().catch(function(e){console.warn('无法保存阅读进度',e);});if(ws&&ws.readyState===WebSocket.OPEN){ws.send(JSON.stringify(message));}}
        function turnPage(direction){if(turning||!archive){return;}var next=currentIndex+(direction==='next'?pagesPerView():-pagesPerView());var max=Math.max(0,totalPages-1);if(next<0||next>max){statusText.textContent=next<0?'已到全书开头':'已到全书末尾';return;}currentIndex=next;renderPages(true,direction);sendProgress();}
        function prevPage(){turnPage('prev');}
        function nextPage(){turnPage('next');}
<<<<<<< HEAD
        function readerFontFamily(name){if(!name||name==='system-zh'||name==='system-en'||name.indexOf('系统')>=0){return '-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif';}if(name==='pingfang-sc'){return '"PingFang SC",-apple-system,BlinkMacSystemFont,sans-serif';}if(name==='pingfang-tc'){return '"PingFang TC","PingFang HK","PingFang SC",sans-serif';}if(name==='fangsong-sc'||name.indexOf('仿宋')>=0){return '"FangSong","STFangsong",serif';}if(name==='kaiti-sc'||name.indexOf('楷体')>=0){return '"Kaiti SC","STKaiti","KaiTi",serif';}if(name==='songti-sc'||name.indexOf('宋体')>=0){return '"Songti SC","STSong","SimSun",serif';}if(name==='heiti-sc'||name.indexOf('黑体')>=0){return '"Heiti SC","STHeiti",sans-serif';}if(name==='sf-pro'){return '-apple-system,BlinkMacSystemFont,sans-serif';}if(name==='new-york'){return '"New York",Georgia,serif';}if(name==='avenir-next'){return '"Avenir Next",Avenir,sans-serif';}if(name==='helvetica-neue'){return '"Helvetica Neue",Helvetica,Arial,sans-serif';}if(name.indexOf('custom:')===0){name=name.slice(7);}return name+',serif';}
        function applySettings(d){var root=document.documentElement.style;var fontSize=Math.max(16,Math.min(30,Number(d.fontSize)||24));var lineHeight=Math.max(1.2,Math.min(2.2,Number(d.lineSpacing)||1.2));readerBaseFontSize=fontSize;root.setProperty('--reader-bg',d.backgroundColor||'#FFFDF8');root.setProperty('--reader-text',d.textColor||'#24211D');root.setProperty('--reader-accent',d.accentColor||'#236D67');root.setProperty('--reader-panel',d.panelColor||'#F5F2EC');root.setProperty('--reader-control',d.controlSurfaceColor||'#FFFDF8');root.setProperty('--reader-font-size',fontSize+'px');root.setProperty('--reader-line-height',lineHeight);root.setProperty('--reader-font-family',readerFontFamily(d.fontFamily));schedulePortraitResize();}
=======
        function readerFontFamily(name){if(!name||name.indexOf('系统')>=0){return '-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif';}if(name.indexOf('仿宋')>=0){return '"FangSong","STFangsong",serif';}if(name.indexOf('楷体')>=0){return '"Kaiti SC","STKaiti","KaiTi",serif';}if(name.indexOf('宋体')>=0){return '"Songti SC","STSong","SimSun",serif';}return name+',serif';}
        function applySettings(d){var root=document.documentElement.style;var fontSize=Math.max(18,Math.min(30,(Number(d.fontSize)||23)*1.12));var lineHeight=Math.max(1.45,Math.min(2.2,(Number(d.lineSpacing)||1.3)+.2));readerBaseFontSize=fontSize;root.setProperty('--reader-bg',d.backgroundColor||'#F5F2EC');root.setProperty('--reader-text',d.textColor||'#24211D');root.setProperty('--reader-accent',d.accentColor||'#236D67');root.setProperty('--reader-panel',d.panelColor||'#F3F4F2');root.setProperty('--reader-control',d.controlSurfaceColor||'#FFFDF8');root.setProperty('--reader-font-size',fontSize+'px');root.setProperty('--reader-line-height',lineHeight);root.setProperty('--reader-font-family',readerFontFamily(d.fontFamily));schedulePortraitResize();}
>>>>>>> parent of be44238 (添加覆盖翻页、重构阅读统计)
        function loadSettings(){fetch('/api/settings?t='+token()+'&v='+Date.now(),{cache:'no-store'}).then(r=>r.json()).then(applySettings).catch(e=>console.error(e));}
        function setStatus(ok){statusDot.style.background=ok?'var(--reader-accent)':'#C94A45';statusText.textContent=ok?'已连接':'连接已断开';}
        readingModeButtons.forEach(function(button){button.addEventListener('click',function(){applyWebReadingMode(button.dataset.mode);});});
        window.addEventListener('resize',schedulePortraitResize);
        document.addEventListener('keydown',function(e){if(e.key==='ArrowRight'||e.key==='ArrowDown'||e.key==='j'){e.preventDefault();nextPage();}else if(e.key==='ArrowLeft'||e.key==='ArrowUp'||e.key==='k'){e.preventDefault();prevPage();}});
        function applyRemoteProgress(d,live,retried){if(!archive||d.bookId!==archive.bookId){return;}if(!live&&progressTime(archive.progress)>progressTime(d)){sendProgress(false);return;}var found=archive.pages.findIndex(function(page){return page.chapterIndex===Number(d.chapterIndex)&&page.pageIndex===Number(d.pageIndex);});if(found>=0){currentIndex=readingMode==='spread'?Math.floor(found/2)*2:found;renderPages(false);archive.progress=d;saveArchive().catch(console.warn);}else if(live&&!retried){fetchArchive().then(function(){applyRemoteProgress(d,true,true);}).catch(console.warn);}}
        function connectWebSocket(){clearTimeout(reconnectTimer);if(ws&&(ws.readyState===WebSocket.OPEN||ws.readyState===WebSocket.CONNECTING)){return;}var protocol=location.protocol==='https:'?'wss:':'ws:';ws=new WebSocket(protocol+'//'+location.host+'/ws?t='+encodeURIComponent(token()));ws.onopen=function(){setStatus(true);sendProgress(false);pollArchiveStatus();};ws.onmessage=function(event){try{var d=JSON.parse(event.data);if(d.type==='pagechange'){applyRemoteProgress(d,true);}else if(d.type==='progress'){applyRemoteProgress(d,false);}else if(d.type==='settingschange'){applySettings(d);if(archive){archive.settings=d;saveArchive();}}else if(d.type==='archivechanged'){pollArchiveStatus();}else if(d.type==='archiveprogress'){setCacheProgress(d.progress);}else if(d.type==='archiveready'){fetchArchive().catch(function(){pollArchiveStatus();});}else if(d.type==='archiveerror'){setCacheProgress(0,true);}}catch(e){console.warn('无法处理同步消息',e);}};ws.onclose=function(){setStatus(false);reconnectTimer=setTimeout(connectWebSocket,3000);};ws.onerror=function(){ws.close();};}
        if('serviceWorker' in navigator){navigator.serviceWorker.register('/sw.js?t='+encodeURIComponent(token())).catch(console.error);}
        loadWebReadingMode();
        loadCachedArchive().then(function(){return fetchCurrentPage();}).then(pollArchiveStatus).catch(function(e){if(!archive){leftContentEl.textContent='请先连接 LVRead 同步书籍';}setStatus(false);console.warn(e);});
        connectWebSocket();
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
