import Foundation

struct ReadingProgress: Codable, Equatable, Hashable {
    var currentChapterIndex: Int
    var currentPageOffset: Int
    var totalPages: Int
    var progressPercent: Double
    var lastReadTimestamp: Date

    init(currentChapterIndex: Int = 0,
         currentPageOffset: Int = 0,
         totalPages: Int = 0,
         progressPercent: Double = 0.0,
         lastReadTimestamp: Date = Date()) {
        self.currentChapterIndex = currentChapterIndex
        self.currentPageOffset = currentPageOffset
        self.totalPages = totalPages
        self.progressPercent = progressPercent
        self.lastReadTimestamp = lastReadTimestamp
    }
}

enum ReadingProgressFilter: String, CaseIterable {
    case all = "全部"
    case unread = "未读"
    case reading = "在读"
    case finished = "已读完"

    func matches(_ progress: ReadingProgress) -> Bool {
        switch self {
        case .all: return true
        case .unread: return progress.progressPercent == 0
        case .reading: return progress.progressPercent > 0 && progress.progressPercent < 100
        case .finished: return progress.progressPercent >= 100
        }
    }
}
