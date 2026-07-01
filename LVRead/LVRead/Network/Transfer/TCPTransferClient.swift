import Foundation
import Network

// MARK: - TCP Transfer Client Delegate

protocol TCPTransferClientDelegate: AnyObject {
    /// Client successfully connected to the remote host.
    func tcpTransferClient(_ client: TCPTransferClient, didConnectTo host: String)

    /// Received progress update from the remote peer.
    func tcpTransferClient(_ client: TCPTransferClient,
                           didReceiveProgress taskId: String,
                           progress: Double,
                           transferredBytes: Int64,
                           totalBytes: Int64)

    /// Transfer completed successfully.
    func tcpTransferClient(_ client: TCPTransferClient,
                           didCompleteTransfer taskId: String)

    /// An error occurred during the connection or transfer.
    func tcpTransferClient(_ client: TCPTransferClient,
                           didFailWithError error: Error)
}

// MARK: - TCP Transfer Client

/// Connects to a remote TCPTransferServer to send messages and file chunks.
final class TCPTransferClient {

    public weak var delegate: TCPTransferClientDelegate?

    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.lvread.tcpTransferClient", qos: .userInitiated)

    /// Creates a new TCP transfer client targeting the given host and port.
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    // MARK: - Public API

    /// Connects to the remote server.
    public func connect() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            delegate?.tcpTransferClient(self, didFailWithError:
                NSError(domain: "TCPTransferClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid port"]))
            return
        }

        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi

        connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.delegate?.tcpTransferClient(self, didConnectTo: self.host)
                }
            case .failed(let error):
                DispatchQueue.main.async {
                    self.delegate?.tcpTransferClient(self, didFailWithError: error)
                }
            case .cancelled:
                break
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    /// Sends a JSON message with a 4-byte big-endian length prefix.
    public func sendMessage(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        sendData(data)
    }

    /// Sends a file chunk as a base64-encoded JSON message.
    public func sendFileChunk(taskId: String,
                              bookId: String,
                              chunkIndex: Int,
                              totalChunks: Int,
                              data chunkData: Data,
                              offset: Int64) {
        let message: [String: Any] = [
            "type": "FILE_CHUNK",
            "taskId": taskId,
            "bookId": bookId,
            "chunkIndex": chunkIndex,
            "totalChunks": totalChunks,
            "data": chunkData.base64EncodedString(),
            "offset": offset
        ]
        sendMessage(message)
    }

    /// Disconnects from the remote server.
    public func disconnect() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Private

    private func sendData(_ data: Data) {
        var lengthPrefix = UInt32(data.count).bigEndian
        let header = Data(bytes: &lengthPrefix, count: 4)
        var combined = header
        combined.append(data)

        connection?.send(content: combined, completion: .contentProcessed { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.delegate?.tcpTransferClient(self, didFailWithError: error)
                }
            }
        })
    }
}
