import Foundation
import Network

// MARK: - TCP Transfer Server Delegate

protocol TCPTransferServerDelegate: AnyObject {
    /// Received a transfer request from a remote device.
    func tcpTransferServer(_ server: TCPTransferServer,
                           didReceiveTransferRequest json: [String: Any],
                           from connection: NWConnection)

    /// Received a file chunk from a remote device.
    func tcpTransferServer(_ server: TCPTransferServer,
                           didReceiveChunk taskId: String,
                           bookId: String,
                           chunkIndex: Int,
                           totalChunks: Int,
                           data: Data,
                           offset: Int64)

    /// Received a transfer-complete signal.
    func tcpTransferServer(_ server: TCPTransferServer,
                           didReceiveComplete taskId: String)

    /// Received a transfer-cancel signal.
    func tcpTransferServer(_ server: TCPTransferServer,
                           didReceiveCancel taskId: String)
}

// MARK: - TCP Transfer Server

/// Listens for incoming TCP connections on port 29877 to handle file transfers.
/// Receives messages with a 4-byte big-endian length header followed by a JSON body.
final class TCPTransferServer {

    public weak var delegate: TCPTransferServerDelegate?

    private let port: UInt16 = 29877
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private let connectionLock = NSLock()
    private let queue = DispatchQueue(label: "com.lvread.tcpTransferServer", qos: .userInitiated)

    // MARK: - Message Types

    private enum MessageType: String {
        case transferRequest   = "TRANSFER_REQUEST"
        case fileChunk         = "FILE_CHUNK"
        case transferComplete  = "TRANSFER_COMPLETE"
        case transferCancel    = "TRANSFER_CANCEL"
    }

    // MARK: - Public API

    public func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .wifi

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw NSError(domain: "TCPTransferServer", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
            }

            listener = try NWListener(using: params, on: nwPort)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print(" Listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    print(" Listener failed: \(error)")
                    self?.stop()
                case .cancelled:
                    print(" Listener cancelled")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.start(queue: queue)

        } catch {
            print(" Failed to start: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil

        connectionLock.lock()
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        connectionLock.unlock()
    }

    /// Sends a JSON response back to a specific connection with a 4-byte length prefix.
    public func sendResponse(_ json: [String: Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        sendData(data, to: connection)
    }

    // MARK: - Private: Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connectionLock.lock()
        activeConnections.append(connection)
        connectionLock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print(" Connection ready: \(connection.endpoint)")
                self?.startReading(on: connection)
            case .failed(let error):
                print(" Connection failed: \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func startReading(on connection: NWConnection) {
        // Read the 4-byte length header
        let headerSize = 4
        connection.receive(minimumIncompleteLength: headerSize, maximumLength: headerSize) { [weak self] data, _, _, error in
            if let error = error {
                print(" Read error: \(error)")
                self?.removeConnection(connection)
                return
            }

            guard let data = data, data.count == headerSize else {
                self?.removeConnection(connection)
                return
            }

            let payloadLength = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self?.readPayload(length: Int(payloadLength), on: connection)
        }
    }

    private func readPayload(length: Int, on connection: NWConnection) {
        guard length > 0, length < 100 * 1024 * 1024 else {
            removeConnection(connection)
            return
        }

        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            if let error = error {
                print(" Payload read error: \(error)")
                self?.removeConnection(connection)
                return
            }

            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self?.processMessage(json, from: connection)
            }

            // Continue reading next message
            self?.startReading(on: connection)
        }
    }

    private func processMessage(_ json: [String: Any], from connection: NWConnection) {
        guard let typeString = json["type"] as? String,
              let messageType = MessageType(rawValue: typeString) else {
            return
        }

        switch messageType {
        case .transferRequest:
            delegate?.tcpTransferServer(self, didReceiveTransferRequest: json, from: connection)

        case .fileChunk:
            let taskId = (json["taskId"] as? String) ?? ""
            let bookId = (json["bookId"] as? String) ?? ""
            let chunkIndex = (json["chunkIndex"] as? Int) ?? 0
            let totalChunks = (json["totalChunks"] as? Int) ?? 0
            let offset = (json["offset"] as? Int64) ?? 0

            var chunkData = Data()
            if let base64 = json["data"] as? String {
                chunkData = Data(base64Encoded: base64) ?? Data()
            }

            delegate?.tcpTransferServer(self,
                                        didReceiveChunk: taskId,
                                        bookId: bookId,
                                        chunkIndex: chunkIndex,
                                        totalChunks: totalChunks,
                                        data: chunkData,
                                        offset: offset)

        case .transferComplete:
            let taskId = (json["taskId"] as? String) ?? ""
            delegate?.tcpTransferServer(self, didReceiveComplete: taskId)

        case .transferCancel:
            let taskId = (json["taskId"] as? String) ?? ""
            delegate?.tcpTransferServer(self, didReceiveCancel: taskId)
        }
    }

    // MARK: - Private: Data Sending

    private func sendData(_ data: Data, to connection: NWConnection) {
        var lengthPrefix = UInt32(data.count).bigEndian
        let header = Data(bytes: &lengthPrefix, count: 4)
        var combined = header
        combined.append(data)

        connection.send(content: combined, completion: .contentProcessed { error in
            if let error = error {
                print(" Send error: \(error)")
            }
        })
    }

    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        connectionLock.lock()
        activeConnections.removeAll { $0 === connection }
        connectionLock.unlock()
    }
}
