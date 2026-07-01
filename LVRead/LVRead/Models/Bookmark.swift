import Foundation

struct Bookmark: Codable, Identifiable, Equatable {
    let id: String
    let bookId: String
    let chapterIndex: Int
    let pageOffset: Int
    let chapterTitle: String
    let snippet: String
    let createdAt: Date

    init(id: String = UUID().uuidString,
         bookId: String,
         chapterIndex: Int,
         pageOffset: Int,
         chapterTitle: String = "",
         snippet: String = "",
         createdAt: Date = Date()) {
        self.id = id
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.pageOffset = pageOffset
        self.chapterTitle = chapterTitle
        self.snippet = snippet
        self.createdAt = createdAt
    }
}
