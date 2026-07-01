import Foundation

struct TransferTask: Codable, Identifiable, Equatable {
    let id: String
    let targetDeviceId: String
    let direction: TransferDirection
    var bookIds: [String]
    var status: TransferStatus
    var progress: Double
    var transferredBytes: Int64
    var totalBytes: Int64
    let createdAt: Date
    var completedAt: Date?

    init(id: String = UUID().uuidString,
         targetDeviceId: String,
         direction: TransferDirection,
         bookIds: [String],
         status: TransferStatus = .pending,
         progress: Double = 0,
         transferredBytes: Int64 = 0,
         totalBytes: Int64 = 0,
         createdAt: Date = Date(),
         completedAt: Date? = nil) {
        self.id = id
        self.targetDeviceId = targetDeviceId
        self.direction = direction
        self.bookIds = bookIds
        self.status = status
        self.progress = progress
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

enum TransferDirection: String, Codable {
    case send = "SEND"
    case receive = "RECEIVE"
}

enum TransferStatus: String, Codable {
    case pending = "PENDING"
    case connecting = "CONNECTING"
    case transferring = "TRANSFERRING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    var displayName: String {
        switch self {
        case .pending: return "等待中"
        case .connecting: return "连接中"
        case .transferring: return "传输中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
