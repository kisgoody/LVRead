import Foundation

// MARK: - File Parser Protocol

protocol FileParserProtocol {
    /// Parse the file at the given path and return metadata including chapters.
    func parseMetadata(filePath: String) throws -> BookMetadata

    /// Parse the content of a specific chapter from a file.
    func parseChapterContent(filePath: String, chapter: Chapter, encoding: String) throws -> String

    /// Return summary statistics for the book at the given path.
    func getBookStats(filePath: String) throws -> BookStats
}

// MARK: - Book Metadata

struct BookMetadata {
    let title: String
    let author: String
    let coverImageData: Data?
    let chapters: [Chapter]
    let encoding: String?
    let totalCharCount: Int64
}

// MARK: - Book Stats

struct BookStats {
    let totalChapters: Int
    let totalChars: Int64
    let fileSizeBytes: Int64
}
