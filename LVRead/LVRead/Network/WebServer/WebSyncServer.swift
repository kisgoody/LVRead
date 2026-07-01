import Foundation
import Network
import UIKit

// MARK: - Web Sync Server

/// A minimal embedded HTTP server that provides a web reader interface
/// for syncing reading progress, pages, chapters, and settings.
final class WebSyncServer {

    public static let shared = WebSyncServer()

    private var listener: NWListener?
    private var authToken: String = ""
    private var serverPort: UInt16 = 8989
    private var isRunning = false

    /// The URL that a web browser should connect to.
    public private(set) var serverURL: String = ""

    /// The current book being synced.
    private var currentBook: Book?
    private var currentPageIndex: Int = 0

    /// SSE client connections keyed by a connection identifier.
    private var sseConnections: [UUID: NWConnection] = [:]
    private let sseLock = NSLock()

    private let serverQueue = DispatchQueue(label: "com.lvread.webSyncServer", qos: .utility)

    /// Notification observers.
    private var pageObserver: NSObjectProtocol?
    private var chapterObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    // MARK: - Public API

    /// Starts the HTTP server: generates an auth token, picks an available port,
    /// begins accepting connections.
    public func start(with book: Book, pageIndex: Int) -> URL? {
        guard !isRunning else { return nil }
        isRunning = true
        currentBook = book
        currentPageIndex = pageIndex

        authToken = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        serverPort = findAvailablePort(startingAt: 8989)

        guard let ip = UDPDiscoveryService.shared.getLocalIP() else {
            print("[WebSyncServer] Cannot determine local IP")
            isRunning = false
            return nil
        }

        serverURL = "http://\(ip):\(serverPort)/?t=\(authToken)"

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .wifi

            guard let portEndpoint = NWEndpoint.Port(rawValue: serverPort) else {
                throw NSError(domain: "WebSyncServer", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
            }

            listener = try NWListener(using: params, on: portEndpoint)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("[WebSyncServer] Ready on port \(self?.serverPort ?? 0)")
                case .failed(let error):
                    print("[WebSyncServer] Listener failed: \(error)")
                    self?.stop()
                case .cancelled:
                    print("[WebSyncServer] Listener cancelled")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: serverQueue)
            print("[WebSyncServer] Started at \(serverURL)")
        } catch {
            print("[WebSyncServer] Failed to start: \(error)")
            isRunning = false
            return nil
        }

        setupObservers()
        return URL(string: serverURL)
    }

    /// Stops the server and closes all connections.
    public func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil

        sseLock.lock()
        for (_, conn) in sseConnections {
            conn.cancel()
        }
        sseConnections.removeAll()
        sseLock.unlock()

        removeObservers()
    }

    /// Stops the server only if it is running (for app backgrounding).
    public func stopIfNeeded() {
        if isRunning {
            stop()
        }
    }

    // MARK: - SSE Notifications

    /// Notify connected SSE clients of a page change.
    public func notifyPageChanged(pageIndex: Int, chapterTitle: String, progressPercent: Double) {
        let escapedTitle = chapterTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let eventData = """
        event: pagechange
        data: {"pageIndex":\(pageIndex),"chapterTitle":"\(escapedTitle)","progressPercent":\(progressPercent)}

        """
        broadcastSSE(eventData)
    }

    /// Notify connected SSE clients of a chapter change.
    public func notifyChapterChanged(chapterIndex: Int, chapterTitle: String) {
        let escapedTitle = chapterTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let eventData = """
        event: chapterchange
        data: {"chapterIndex":\(chapterIndex),"chapterTitle":"\(escapedTitle)"}

        """
        broadcastSSE(eventData)
    }

    /// Notify connected SSE clients of settings changes.
    public func notifySettingsChanged(_ settings: ReadingSettings) {
        let fontSize = settings.fontSize
        let theme = settings.readingTheme.rawValue
        let eventData = """
        event: settingschange
        data: {"fontSize":\(fontSize),"theme":"\(theme)"}

        """
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

            let (method, path, queryParams, headers) = self.parseHTTPRequest(requestString)

            // Verify auth token for all API endpoints (except root when in dev mode)
            // All endpoints now require authentication for security
            let requiresAuth = !path.isEmpty && !path.hasPrefix("/api/stream")
            if requiresAuth {
                let token = queryParams["t"] ?? ""
                if token.isEmpty || token != self.authToken {
                    self.sendErrorResponse(statusCode: 403, message: "Forbidden", to: connection)
                    return
                }
            }

            switch (method, path) {
            case ("GET", "/"):
                self.serveWebReader(to: connection)

            case ("GET", "/api/book/info"):
                self.serveBookInfo(to: connection)

            case ("GET", "/api/page/current"):
                self.serveCurrentPage(to: connection)

            case ("GET", "/api/chapters"):
                self.serveChapters(to: connection)

            case ("GET", "/api/settings"):
                self.serveSettings(to: connection)

            case ("GET", "/api/stream"):
                self.handleSSEConnection(connection, token: queryParams["t"] ?? "")

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
                let body = queryParams["body"] ?? ""
                self.handleRemoteTurn(connection: connection, body: body)

            case ("POST", "/api/settings"):
                let body = queryParams["body"] ?? ""
                self.handleSettingsUpdate(connection: connection, body: body)

            case ("GET", "/api/streamold"):
                self.handleSSEConnection(connection, token: queryParams["t"] ?? "")

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

    private func serveBookInfo(to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }

        let info: [String: Any] = [
            "id": book.id,
            "title": book.title,
            "author": book.author,
            "coverImagePath": book.resolvedCoverPath() as Any,
            "fileFormat": book.fileFormat,
            "readingProgress": book.readingProgress,
            "fileSize": book.fileSize
        ]
        sendJSONResponse(info, to: connection)
    }

    private func serveCurrentPage(to connection: NWConnection) {
        guard let book = currentBook else {
            sendJSONResponse(["error": "No current book"], to: connection)
            return
        }

        let pageIndex = currentPageIndex
        if let pageContent = PageCacheManager.shared.getPage(bookId: book.id, pageIndex: pageIndex) {
            let response: [String: Any] = [
                "bookId": book.id,
                "bookTitle": book.title,
                "pageIndex": pageIndex,
                "content": pageContent,
                "totalPages": 0 // Will be populated by the reader
            ]
            sendJSONResponse(response, to: connection)
        } else {
            sendJSONResponse(["error": "Page not found in cache", "pageIndex": pageIndex], to: connection)
        }
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
        let response: [String: Any] = [
            "fontSize": settings.fontSize,
            "theme": settings.readingTheme.rawValue,
            "lineSpacing": settings.lineSpacing,
            "fontFamily": settings.fontFamily
        ]
        sendJSONResponse(response, to: connection)
    }

    // MARK: - SSE Handling

    private func handleSSEConnection(_ connection: NWConnection, token: String) {
        // Verify SSE auth
        if token != authToken {
            sendErrorResponse(statusCode: 403, message: "Forbidden", to: connection)
            return
        }

        let connectionId = UUID()

        sseLock.lock()
        sseConnections[connectionId] = connection
        sseLock.unlock()

        // Send SSE headers
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: headers.data(using: .utf8)!, completion: .contentProcessed { _ in })

        // Send an initial connected event
        let connectedEvent = "event: connected\ndata: {\"status\":\"ok\"}\n\n"
        connection.send(content: connectedEvent.data(using: .utf8)!, completion: .contentProcessed { _ in })

        // Start keep-alive pings every 30 seconds
        sendKeepAlivePings(to: connection, connectionId: connectionId)
    }

    private func sendKeepAlivePings(to connection: NWConnection, connectionId: UUID) {
        serverQueue.asyncAfter(deadline: .now() + 30) { [weak self] in
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

    private func broadcastSSE(_ eventData: String) {
        sseLock.lock()
        let connections = Array(sseConnections.values)
        sseLock.unlock()

        guard let data = eventData.data(using: .utf8) else { return }

        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func removeSSEConnection(_ id: UUID) {
        sseLock.lock()
        sseConnections[id]?.cancel()
        sseConnections.removeValue(forKey: id)
        sseLock.unlock()
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
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let body = String(data: data, encoding: .utf8) else {
            sendErrorResponse(statusCode: 500, message: "Internal Server Error", to: connection)
            return
        }
        sendHTTPResponse(statusCode: 200, contentType: "application/json; charset=utf-8", body: body, to: connection)
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

    // MARK: - Port Discovery

    private func findAvailablePort(startingAt port: UInt16) -> UInt16 {
        var currentPort = port
        while currentPort < port + 100 {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let testPort = NWEndpoint.Port(rawValue: currentPort) else {
                currentPort += 1
                continue
            }
            if let testListener = try? NWListener(using: params, on: testPort) {
                testListener.cancel()
                return currentPort
            }
            currentPort += 1
        }
        return port // fallback
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

    private func handleRemoteTurn(connection: NWConnection, body: String = "") {
        guard let book = currentBook else {
            sendJSONResponse(["success": false, "error": "No active book"], to: connection)
            return
        }
        let parsedDirection: String
        if !body.isEmpty,
           let bodyData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let dir = json["direction"] as? String {
            parsedDirection = dir
        } else {
            parsedDirection = "next"
        }
        let total = chapterPagesCount()
        switch parsedDirection {
        case "next":
            if currentPageIndex < total - 1 {
                currentPageIndex += 1
                notifyPageChanged(pageIndex: currentPageIndex, chapterTitle: currentChapterTitle(), progressPercent: currentProgressPercent())
                sendJSONResponse(["success": true, "newPageIndex": currentPageIndex, "direction": "next"], to: connection)
            } else {
                sendJSONResponse(["success": false, "error": "already_at_end"], to: connection)
            }
        case "prev":
            if currentPageIndex > 0 {
                currentPageIndex -= 1
                notifyPageChanged(pageIndex: currentPageIndex, chapterTitle: currentChapterTitle(), progressPercent: currentProgressPercent())
                sendJSONResponse(["success": true, "newPageIndex": currentPageIndex, "direction": "prev"], to: connection)
            } else {
                sendJSONResponse(["success": false, "error": "already_at_beginning"], to: connection)
            }
        default:
            sendJSONResponse(["success": false, "error": "invalid_direction"], to: connection)
        }
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

    private func webReaderHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>LV Read - Web Reader</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box;}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#1a1a2e;color:#e0e0e0;min-height:100vh;}
        .topbar{background:linear-gradient(135deg,#FF5E3A,#ff7b5f);padding:12px 24px;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:10;box-shadow:0 2px 12px rgba(255,94,58,0.3);}
        .topbar h1{font-size:18px;font-weight:600;color:#fff;letter-spacing:0.5px;}
        .topbar .status{font-size:12px;color:rgba(255,255,255,0.85);display:flex;align-items:center;gap:6px;}
        .topbar .dot{width:8px;height:8px;border-radius:50%;background:#4cff4c;display:inline-block;}
        .container{max-width:800px;margin:0 auto;padding:32px 24px;}
        .content{background:#242444;border-radius:12px;padding:32px;line-height:1.8;font-size:17px;min-height:60vh;box-shadow:0 4px 20px rgba(0,0,0,0.3);white-space:pre-wrap;word-wrap:break-word;}
        .content h1,.content h2,.content h3{color:#FF5E3A;margin:16px 0 8px;}
        .content p{margin:8px 0;}
        .controls{display:flex;justify-content:center;gap:16px;margin-top:24px;}
        .controls button{background:#FF5E3A;color:#fff;border:none;padding:10px 24px;border-radius:8px;font-size:15px;cursor:pointer;transition:background 0.2s;font-weight:500;}
        .controls button:hover{background:#ff7b5f;}
        .controls button:disabled{background:#555;cursor:not-allowed;}
        .info-bar{text-align:center;margin-top:16px;font-size:13px;color:#888;}
        .shortcuts{margin-top:20px;text-align:center;font-size:12px;color:#666;line-height:1.8;}
        .shortcuts kbd{background:#333;color:#FF5E3A;padding:2px 8px;border-radius:4px;font-family:monospace;font-size:12px;border:1px solid #444;}
        .chapter-title{font-size:14px;color:#aaa;margin-bottom:4px;}
        @media(max-width:600px){.container{padding:16px 12px;}.content{padding:20px;font-size:15px;}}
        </style>
        </head>
        <body>
        <div class="topbar">
        <h1>LV Read</h1>
        <div class="status"><span class="dot" id="statusDot"></span><span id="statusText">connected</span></div>
        </div>
        <div class="container">
        <div class="chapter-title" id="chapterTitle"></div>
        <div class="content" id="content">Loading...</div>
        <div class="controls">
        <button id="prevBtn" onclick="prevPage()">&#9664; Prev</button>
        <button id="nextBtn" onclick="nextPage()">Next &#9654;</button>
        </div>
        <div class="info-bar" id="pageInfo"></div>
        <div class="shortcuts">
        <kbd>&larr;</kbd> <kbd>&rarr;</kbd> or <kbd>J</kbd> <kbd>K</kbd> &mdash; Navigate pages<br>
        <kbd>F</kbd> Toggle fullscreen &middot; <kbd>S</kbd> Settings
        </div>
        </div>
        <script>
        var currentPage=0,totalPages=1,bookTitle='';
        var contentEl=document.getElementById('content');
        var pageInfoEl=document.getElementById('pageInfo');
        var chapterTitleEl=document.getElementById('chapterTitle');
        var statusDot=document.getElementById('statusDot');
        var statusText=document.getElementById('statusText');
        function loadPage(){fetch('/api/page/current?t='+token()).then(r=>r.json()).then(d=>{if(d.content){contentEl.textContent=d.content;bookTitle=d.bookTitle||'';totalPages=d.totalPages||1;currentPage=d.pageIndex||0;chapterTitleEl.textContent=bookTitle;pageInfoEl.textContent='Page '+(currentPage+1)+' of '+totalPages;}}).catch(e=>console.error(e));}
        function loadBookInfo(){fetch('/api/book/info?t='+token()).then(r=>r.json()).then(d=>{if(d.title){chapterTitleEl.textContent=d.title+' by '+d.author;}}).catch(e=>{});}
        function token(){return new URLSearchParams(window.location.search).get('t')||'';}
        function prevPage(){if(currentPage>0){currentPage--;contentEl.textContent='Loading...';fetch('/api/page/current?t='+token()).then(r=>r.json()).then(d=>{contentEl.textContent=d.content;pageInfoEl.textContent='Page '+(currentPage+1)+' of '+totalPages;});}}
        function nextPage(){if(currentPage<totalPages-1){currentPage++;contentEl.textContent='Loading...';fetch('/api/page/current?t='+token()).then(r=>r.json()).then(d=>{contentEl.textContent=d.content;pageInfoEl.textContent='Page '+(currentPage+1)+' of '+totalPages;});}}
        function setStatus(ok){statusDot.style.background=ok?'#4cff4c':'#ff4c4c';statusText.textContent=ok?'connected':'disconnected';}
        document.addEventListener('keydown',function(e){if(e.key==='ArrowRight'||e.key==='ArrowDown'||e.key==='j'){e.preventDefault();nextPage();}else if(e.key==='ArrowLeft'||e.key==='ArrowUp'||e.key==='k'){e.preventDefault();prevPage();}});
        var es=new EventSource('/api/stream?t='+token());
        es.addEventListener('connected',function(e){setStatus(true);});
        es.addEventListener('pagechange',function(e){var d=JSON.parse(e.data);currentPage=d.pageIndex;totalPages=d.totalPages;pageInfoEl.textContent='Page '+(currentPage+1)+' of '+totalPages;loadPage();});
        es.addEventListener('chapterchange',function(e){var d=JSON.parse(e.data);chapterTitleEl.textContent=d.chapterTitle;});
        es.addEventListener('settingschange',function(e){var d=JSON.parse(e.data);document.body.style.fontSize=d.fontSize+'px';});
        es.onerror=function(){setStatus(false);setTimeout(function(){es=new EventSource('/api/stream?t='+token());setupSSE(es);},3000);};
        function setupSSE(s){s.addEventListener('connected',function(e){setStatus(true);});s.addEventListener('pagechange',function(e){var d=JSON.parse(e.data);currentPage=d.pageIndex;totalPages=d.totalPages;pageInfoEl.textContent='Page '+(currentPage+1)+' of '+totalPages;loadPage();});s.addEventListener('chapterchange',function(e){var d=JSON.parse(e.data);chapterTitleEl.textContent=d.chapterTitle;});s.addEventListener('settingschange',function(e){var d=JSON.parse(e.data);document.body.style.fontSize=d.fontSize+'px';});s.onerror=function(){setStatus(false);setTimeout(function(){es=new EventSource('/api/stream?t='+token());setupSSE(es);},3000);};}
        loadPage();
        loadBookInfo();
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
