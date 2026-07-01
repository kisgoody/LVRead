import Foundation

struct Highlight: Codable, Identifiable, Equatable {
    let id: String
    let bookId: String
    let chapterIndex: Int
    let pageOffset: Int
    let startCharOffset: Int
    let endCharOffset: Int
    let text: String
    let color: String
    let note: String?
    let createdAt: Date

    init(id: String = UUID().uuidString,
         bookId: String,
         chapterIndex: Int,
         pageOffset: Int,
         startCharOffset: Int,
         endCharOffset: Int,
         text: String,
         color: String = "#FFD700",
         note: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.pageOffset = pageOffset
        self.startCharOffset = startCharOffset
        self.endCharOffset = endCharOffset
        self.text = text
        self.color = color
        self.note = note
        self.createdAt = createdAt
    }
}
