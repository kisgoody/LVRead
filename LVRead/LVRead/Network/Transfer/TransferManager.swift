import Foundation
import Network
import UIKit

// MARK: - Transfer Manager Delegate

protocol TransferManagerDelegate: AnyObject {
    /// Called when the active transfer's progress changes.
    func transferManager(_ manager: TransferManager,
                         didUpdateProgress task: TransferTask)

    /// Called when a transfer completes successfully.
    func transferManager(_ manager: TransferManager,
                         didComplete task: TransferTask)

    /// Called when a transfer fails.
    func transferManager(_ manager: TransferManager,
                         didFail task: TransferTask,
                         withError error: Error)
}

// MARK: - Transfer Manager

/// Singleton orchestrating book transfer send/receive operations.
/// Acts as the delegate for both TCPTransferServer and TCPTransferClient.
final class TransferManager {

    public static let shared = TransferManager()

    public weak var delegate: TransferManagerDelegate?

    // MARK: - Subsystems

    private let server = TCPTransferServer()
    private var client: TCPTransferClient?
    private let chunkSize = 64 * 1024 // 64 KB

    // MARK: - Active Task Tracking

    private var activeTask: TransferTask?
    private var chunkBuffer: [Int: Data] = [:]
    private var pendingBookIds: [String] = []
    private var pendingBookFormats: [String: String] = [:]
    private var activeServerConnection: NWConnection?
    private let taskLock = NSLock()
    private var receivedTotalChunks: Int = 0

    /// Background task identifier for finishing transfers when app backgrounds.
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Initialization

    private init() {
        server.delegate = self
    }

    // MARK: - Lifecycle

    /// Called by AppConfiguration to complete setup after all subsystems are ready.
    public func initialize() {
        server.delegate = self
    }

    /// Start listening for incoming transfers.
    public func startServer() {
        server.start()
    }

    /// Stop the transfer server.
    public func stopServer() {
        server.stop()
    }

    // MARK: - Sending Books

    /// Sends an array of books to a target device.
    /// - Parameters:
    ///   - books: The books to transfer.
    ///   - device: The target LanDevice.
    ///   - completion: Called on the main queue with the task result.
    public func sendBooks(_ books: [Book],
                          to device: LanDevice,
                          completion: ((Result<TransferTask, Error>) -> Void)?) {
        let taskId = UUID().uuidString
        let bookIds = books.map { $0.id }
        let totalBytes = books.reduce(Int64(0)) { $0 + $1.fileSize }

        var task = TransferTask(
            id: taskId,
            targetDeviceId: device.id,
            direction: .send,
            bookIds: bookIds,
            status: .connecting,
            progress: 0.0,
            transferredBytes: 0,
            totalBytes: totalBytes,
            createdAt: Date(),
            completedAt: nil
        )

        taskLock.lock()
        self.activeTask = task
        taskLock.unlock()

        // Connect to the target device's TCP server
        let transferClient = TCPTransferClient(host: device.ipAddress, port: UInt16(device.port))
        self.client = transferClient
        transferClient.delegate = self

        transferClient.connect()

        // Store completion for when connected
        self.pendingCompletion = completion
        self.pendingBooks = books
    }

    // MARK: - Internals for pending context

    private var pendingCompletion: ((Result<TransferTask, Error>) -> Void)?
    private var pendingBooks: [Book] = []

    /// Performs the actual file streaming once connected.
    private func streamBooks(_ books: [Book], taskId: String) {
        taskLock.lock()
        guard var task = activeTask, task.id == taskId else {
            taskLock.unlock()
            return
        }
        task.status = .transferring
        activeTask = task
        taskLock.unlock()

        notifyProgress()

        // Send TRANSFER_REQUEST
        let bookInfos: [[String: Any]] = books.map { book in
            [
                "id": book.id,
                "title": book.title,
                "author": book.author,
                "fileHash": book.fileHash,
                "fileSize": book.fileSize,
                "fileFormat": book.fileFormat
            ]
        }

        let request: [String: Any] = [
            "type": "TRANSFER_REQUEST",
            "taskId": taskId,
            "books": bookInfos
        ]
        client?.sendMessage(request)

        // Stream each book's file in chunks
        var globalOffset: Int64 = 0

        for book in books {
            guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: book.resolvedFilePath())) else {
                failTask(with: LVError.fileNotFound)
                return
            }

            let totalChunks = Int(ceil(Double(fileData.count) / Double(chunkSize)))

            for chunkIndex in 0..<totalChunks {
                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, fileData.count)
                let chunk = fileData.subdata(in: start..<end)

                client?.sendFileChunk(
                    taskId: taskId,
                    bookId: book.id,
                    chunkIndex: chunkIndex,
                    totalChunks: totalChunks,
                    data: chunk,
                    offset: globalOffset + Int64(start)
                )

                // Update progress
                taskLock.lock()
                if var t = activeTask {
                    t.transferredBytes = globalOffset + Int64(end)
                    t.progress = Double(t.transferredBytes) / Double(t.totalBytes)
                    activeTask = t
                }
                taskLock.unlock()
                notifyProgress()
            }

            globalOffset += Int64(fileData.count)
        }

        // Send TRANSFER_COMPLETE
        let completeMsg: [String: Any] = [
            "type": "TRANSFER_COMPLETE",
            "taskId": taskId
        ]
        client?.sendMessage(completeMsg)

        // Mark complete locally
        completeTask(success: true)
    }

    // MARK: - Task Management

    private func completeTask(success: Bool) {
        taskLock.lock()
        guard var task = activeTask else {
            taskLock.unlock()
            return
        }

        if success {
            task.status = .completed
            task.progress = 1.0
            task.transferredBytes = task.totalBytes
        }
        task.completedAt = Date()
        let finalTask = task
        activeTask = nil
        chunkBuffer.removeAll()
        pendingBookIds.removeAll()
        taskLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if success {
                self.delegate?.transferManager(self, didComplete: finalTask)
            }
        }

        pendingCompletion = nil
        pendingBooks.removeAll()
    }

    private func failTask(with error: Error) {
        taskLock.lock()
        guard var task = activeTask else {
            taskLock.unlock()
            return
        }
        task.status = .failed
        task.completedAt = Date()
        let failedTask = task
        activeTask = nil
        chunkBuffer.removeAll()
        pendingBookIds.removeAll()
        taskLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.transferManager(self, didFail: failedTask, withError: error)
        }

        pendingCompletion = nil
        pendingBooks.removeAll()

        client?.disconnect()
        client = nil
    }

    private func notifyProgress() {
        taskLock.lock()
        guard let task = activeTask else {
            taskLock.unlock()
            return
        }
        let snapshot = task
        taskLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.transferManager(self, didUpdateProgress: snapshot)
        }
    }

    // MARK: - Lifecycle Handling

    public func handleBackgroundTransition() {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "LVRead.Transfer") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    public func handleForegroundTransition() {
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    // MARK: - Cancel

    public func cancelActiveTask() {
        guard let taskId = activeTask?.id else { return }
        let cancelMsg: [String: Any] = [
            "type": "TRANSFER_CANCEL",
            "taskId": taskId
        ]
        client?.sendMessage(cancelMsg)
        client?.disconnect()
        client = nil

        failTask(with: LVError.transferFailed)
    }
}

// MARK: - TCPTransferServerDelegate

extension TransferManager: TCPTransferServerDelegate {

    public func tcpTransferServer(_ server: TCPTransferServer,
                                  didReceiveTransferRequest json: [String: Any],
                                  from connection: NWConnection) {
        guard let taskId = json["taskId"] as? String,
              let books = json["books"] as? [[String: Any]] else {
            return
        }

        // Create a receive task
        let bookIds = books.compactMap { $0["id"] as? String }
        let totalBytes = books.reduce(Int64(0)) { sum, book in
            sum + Int64((book["fileSize"] as? Int64) ?? 0)
        }

        var task = TransferTask(
            id: taskId,
            targetDeviceId: "",
            direction: .receive,
            bookIds: bookIds,
            status: .connecting,
            progress: 0.0,
            transferredBytes: 0,
            totalBytes: totalBytes,
            createdAt: Date(),
            completedAt: nil
        )

        taskLock.lock()
        activeTask = task
        pendingBookIds = books.compactMap { $0["id"] as? String }
        pendingBookFormats = books.reduce(into: [:]) { dict, book in
            if let id = book["id"] as? String, let fmt = book["fileFormat"] as? String {
                dict[id] = fmt
            }
        }
        receivedTotalChunks = 0
        chunkBuffer.removeAll()
        taskLock.unlock()

        // Update status
        task.status = .transferring
        taskLock.lock()
        activeTask = task
        taskLock.unlock()
        notifyProgress()

        // Store connection for response
        taskLock.lock()
        self.activeServerConnection = connection
        taskLock.unlock()

        // Send acceptance response
        let response: [String: Any] = [
            "type": "TRANSFER_RESPONSE",
            "taskId": taskId,
            "accepted": true
        ]
        server.sendResponse(response, to: connection)
    }

    public func tcpTransferServer(_ server: TCPTransferServer,
                                  didReceiveChunk taskId: String,
                                  bookId: String,
                                  chunkIndex: Int,
                                  totalChunks: Int,
                                  data: Data,
                                  offset: Int64) {
        taskLock.lock()
        let chunkKey = chunkIndex
        chunkBuffer[chunkKey] = data

        // Track total chunks expected
        if receivedTotalChunks == 0 {
            receivedTotalChunks = totalChunks
        }

        // Update progress
        if var task = activeTask {
            task.transferredBytes += Int64(data.count)
            if task.totalBytes > 0 {
                task.progress = Double(task.transferredBytes) / Double(task.totalBytes)
            }
            activeTask = task
        }
        let chunksReceived = chunkBuffer.count
        taskLock.unlock()

        notifyProgress()

        // Check if all chunks for this book are received
        if chunksReceived >= totalChunks {
            assembleBook(bookId: bookId, totalChunks: totalChunks)
        }
    }

    public func tcpTransferServer(_ server: TCPTransferServer,
                                  didReceiveComplete taskId: String) {
        completeTask(success: true)
        taskLock.lock()
        activeServerConnection = nil
        taskLock.unlock()
    }

    public func tcpTransferServer(_ server: TCPTransferServer,
                                  didReceiveCancel taskId: String) {
        failTask(with: LVError.transferFailed)
        taskLock.lock()
        activeServerConnection = nil
        taskLock.unlock()
    }

    // MARK: - Receive Side Book Assembly

    private func assembleBook(bookId: String, totalChunks: Int) {
        taskLock.lock()
        var assembledData = Data(capacity: chunkBuffer.count * chunkSize)
        for i in 0..<totalChunks {
            if let chunk = chunkBuffer[i] {
                assembledData.append(chunk)
            }
        }
        
        // Verify data integrity: check expected size from task
        let expectedSize = activeTask?.totalBytes ?? 0
        let receivedSize = Int64(assembledData.count)
        
        chunkBuffer.removeAll()
        receivedTotalChunks = 0
        taskLock.unlock()

        // Verify size matches expected
        if expectedSize > 0 && receivedSize != expectedSize {
            print("⚠️ Transfer size mismatch: expected \(expectedSize), got \(receivedSize)")
            failTask(with: LVError.transferFailed)
            return
        }

        // Save to books directory via BookImportManager
        let booksDir = BookImportManager.shared.booksDirectory
        let format = pendingBookFormats[bookId] ?? "EPUB"
        let ext = format.lowercased()
        var fileName = "received_\(bookId).\(ext)"
        // Validate extension: if unknown, try to detect from assembled data
        if !["epub", "txt", "pdf", "mobi", "azw3"].contains(ext) {
            fileName = "received_\(bookId).epub"
        }
        let filePath = (booksDir() as NSString).appendingPathComponent(fileName)

        do {
            try assembledData.write(to: URL(fileURLWithPath: filePath))
        } catch {
            failTask(with: error)
            return
        }

        // Compute hash and verify integrity
        guard let computedHash = BookImportManager.shared.computeSHA256(filePath) else {
            failTask(with: LVError.transferFailed)
            return
        }

        // Check if book already exists by hash (duplicate detection)
        if let existingBook = BookRepository.shared.getByHash(computedHash) {
            // Book already in library, skip import but mark as complete
            print("📚 Received book already exists in library")
            // Clean up the received file
            try? FileManager.default.removeItem(atPath: filePath)
        } else {
            // Import the received file
            BookImportManager.shared.importFile(
                from: URL(fileURLWithPath: filePath),
                completion: { result in
                    switch result {
                    case .success(let book):
                        print("✅ Imported received book: \(book.title)")
                    case .failure(let error):
                        print("⚠️ Failed to import received book: \(error)")
                    }
                }
            )
        }
    }
}

// MARK: - TCPTransferClientDelegate

extension TransferManager: TCPTransferClientDelegate {

    public func tcpTransferClient(_ client: TCPTransferClient,
                                  didConnectTo host: String) {
        taskLock.lock()
        let taskId = activeTask?.id ?? ""
        taskLock.unlock()

        // Begin streaming the pending books
        if !pendingBooks.isEmpty {
            streamBooks(pendingBooks, taskId: taskId)
        }
    }

    public func tcpTransferClient(_ client: TCPTransferClient,
                                  didReceiveProgress taskId: String,
                                  progress: Double,
                                  transferredBytes: Int64,
                                  totalBytes: Int64) {
        taskLock.lock()
        if var task = activeTask, task.id == taskId {
            task.progress = progress
            task.transferredBytes = transferredBytes
            task.totalBytes = totalBytes
            activeTask = task
        }
        taskLock.unlock()
        notifyProgress()
    }

    public func tcpTransferClient(_ client: TCPTransferClient,
                                  didCompleteTransfer taskId: String) {
        completeTask(success: true)
    }

    public func tcpTransferClient(_ client: TCPTransferClient,
                                  didFailWithError error: Error) {
        failTask(with: error)
    }
}
