import Foundation

struct Book: Codable, Identifiable, Equatable {
    let id: String  // UUID v4
    var title: String
    var author: String
    var coverImagePath: String?
    var filePath: String
    let fileHash: String
    let fileSize: Int64
    let fileFormat: FileFormat
    let source: BookSource
    var encoding: String?
    var category: String?
    var readingProgress: ReadingProgress
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var customOrder: Int

    init(id: String = UUID().uuidString,
         title: String,
         author: String = "未知作者",
         coverImagePath: String? = nil,
         filePath: String,
         fileHash: String,
         fileSize: Int64,
         fileFormat: FileFormat,
         source: BookSource,
         encoding: String? = nil,
         category: String? = nil,
         readingProgress: ReadingProgress = ReadingProgress(),
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         isFavorite: Bool = false,
         customOrder: Int = 0) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespaces)
        self.author = author.isEmpty ? "未知作者" : author
        self.coverImagePath = coverImagePath
        self.filePath = filePath
        self.fileHash = fileHash
        self.fileSize = fileSize
        self.fileFormat = fileFormat
        self.source = source
        self.encoding = encoding
        self.category = category
        self.readingProgress = readingProgress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.customOrder = customOrder
    }

    var progressPercentDisplay: String {
        String(format: "%.1f%%", readingProgress.progressPercent)
    }

   var fileSizeDisplay: String {
       ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
   }

    /// Resolves the stored file path to an absolute path.
    /// Handles both legacy absolute paths and new relative paths (relative to Documents).
    func resolvedFilePath() -> String {
        if filePath.hasPrefix("/") {
            return filePath
        }
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return (docs as NSString).appendingPathComponent(filePath)
    }

    /// Resolves the stored cover image path to an absolute path.
    func resolvedCoverPath() -> String? {
        guard let cover = coverImagePath else { return nil }
        if cover.hasPrefix("/") {
            return cover
        }
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return (docs as NSString).appendingPathComponent(cover)
    }
}
