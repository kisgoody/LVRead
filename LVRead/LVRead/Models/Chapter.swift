import Foundation

struct Chapter: Codable, Identifiable, Equatable {
    let id: String
    let bookId: String
    var title: String
    var level: Int
    var orderIndex: Int
    var startOffset: Int64
    var endOffset: Int64
    var pageCount: Int
    var internalHref: String?

    init(id: String = UUID().uuidString,
         bookId: String,
         title: String,
         level: Int = 1,
         orderIndex: Int,
         startOffset: Int64 = 0,
         endOffset: Int64 = 0,
         pageCount: Int = 0,
         internalHref: String? = nil) {
        self.id = id
        self.bookId = bookId
        self.title = title
        self.level = max(1, min(3, level))
        self.orderIndex = orderIndex
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.pageCount = pageCount
        self.internalHref = internalHref
    }
}
