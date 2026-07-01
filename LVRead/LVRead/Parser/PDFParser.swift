import Foundation
import PDFKit

// MARK: - PDF Parser

/// Parses PDF documents using PDFKit. Chapters are created by grouping pages
/// into manageable segments (typically 20 pages per group for large documents,
/// or one chapter per logical section where detection is feasible).
final class PDFParser: FileParserProtocol {

    /// Number of pages to bundle into a single chapter for large PDFs.
    private let pagesPerChapter = 20

    // MARK: - FileParserProtocol

    func parseMetadata(filePath: String) throws -> BookMetadata {
        guard let pdfDocument = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
            throw PDFParserError.failedToOpenPDF
        }

        let pageCount = pdfDocument.pageCount

        // Extract title and author from PDF metadata attributes.
        let (title, author) = extractMetadata(from: pdfDocument, fallbackPath: filePath)

        // Build chapters by grouping pages.
        let chapters = buildChapters(pageCount: pageCount)

        // Attempt to extract cover image from the first page.
        let coverData = renderCoverImage(from: pdfDocument)

        // Estimate total character count by sampling pages.
        let totalChars = estimateTotalChars(from: pdfDocument, pageCount: pageCount)

        return BookMetadata(
            title: title,
            author: author,
            coverImageData: coverData,
            chapters: chapters,
            encoding: "UTF-8",
            totalCharCount: totalChars
        )
    }

    func parseChapterContent(filePath: String, chapter: Chapter, encoding: String) throws -> String {
        guard let pdfDocument = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
            throw PDFParserError.failedToOpenPDF
        }

        // Chapters are 1-indexed via orderIndex; pages are 0-indexed in PDFKit.
        let startPage = chapter.orderIndex * pagesPerChapter
        let endPage   = min(startPage + pagesPerChapter - 1, pdfDocument.pageCount - 1)

        guard startPage < pdfDocument.pageCount else {
            throw PDFParserError.invalidPageRange
        }

        var lines: [String] = []
        let headerPrefix = "===== \(chapter.title) ====="
        lines.append(headerPrefix)

        for i in startPage...endPage {
            guard let page = pdfDocument.page(at: i) else { continue }

            // Page number marker.
            lines.append("[第 \(i + 1) 页 / 共 \(pdfDocument.pageCount) 页]")
            lines.append("")

            if let pageContent = page.string {
                let trimmed = pageContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func getBookStats(filePath: String) throws -> BookStats {
        let fileSize = try fileSizeBytes(at: filePath)
        guard let pdfDocument = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
            throw PDFParserError.failedToOpenPDF
        }
        let totalChars = estimateTotalChars(from: pdfDocument, pageCount: pdfDocument.pageCount)
        let chapterCount = max(1, (pdfDocument.pageCount + pagesPerChapter - 1) / pagesPerChapter)

        return BookStats(
            totalChapters: chapterCount,
            totalChars: totalChars,
            fileSizeBytes: fileSize
        )
    }

    // MARK: - Rendering

    /// Render a specific page range as a UIImage (useful for web-sync previews).
    func renderPageAsImage(
        filePath: String,
        pageIndex: Int,
        size: CGSize = CGSize(width: 400, height: 560)
    ) -> UIImage? {
        guard let pdfDocument = PDFDocument(url: URL(fileURLWithPath: filePath)),
              let page = pdfDocument.page(at: pageIndex) else {
            return nil
        }
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(size.width / pageRect.width, size.height / pageRect.height)
        let scaledRect = CGRect(
            x: 0, y: 0,
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: scaledRect.size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(scaledRect)
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: scaledRect.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
    }

    // MARK: - Metadata Extraction

    /// Reads standard PDF metadata keys and falls back to the file name for
    /// the title when metadata is absent.
    private func extractMetadata(
        from document: PDFDocument,
        fallbackPath: String
    ) -> (title: String, author: String) {
        var title: String?
        var author: String?

        if let attrs = document.documentAttributes {
            if let pdfTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String,
               !pdfTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                title = pdfTitle.trimmingCharacters(in: .whitespaces)
            }
            if let pdfAuthor = attrs[PDFDocumentAttribute.authorAttribute] as? String,
               !pdfAuthor.trimmingCharacters(in: .whitespaces).isEmpty {
                author = pdfAuthor.trimmingCharacters(in: .whitespaces)
            }
        }

        // Try reading with PDFKit's built-in metadata (may return different keys).
        if title == nil {
            title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        }

        // Fall back to file name.
        if title == nil || title!.isEmpty || title == "Untitled" {
            let fileName = ((fallbackPath as NSString).lastPathComponent as NSString).deletingPathExtension
            title = fileName.isEmpty ? "未命名PDF" : fileName
        }

        if author == nil {
            author = "未知作者"
        }

        return (title: title!, author: author!)
    }

    // MARK: - Chapter Construction

    private func buildChapters(pageCount: Int) -> [Chapter] {
        guard pageCount > 0 else {
            return [Chapter(
                bookId: "",
                title: "空白文档",
                level: 1,
                orderIndex: 0,
                startOffset: 0,
                endOffset: 0,
                pageCount: 0
            )]
        }

        let groupCount = max(1, (pageCount + pagesPerChapter - 1) / pagesPerChapter)
        var chapters: [Chapter] = []

        for i in 0..<groupCount {
            let startPage = i * pagesPerChapter + 1
            let endPage   = min((i + 1) * pagesPerChapter, pageCount)

            let title: String
            if groupCount == 1 {
                title = "正文 (共 \(pageCount) 页)"
            } else {
                title = "第 \(i + 1) 部分 (\(startPage)-\(endPage) 页)"
            }

            let chapter = Chapter(
                bookId: "",
                title: title,
                level: 1,
                orderIndex: i,
                startOffset: 0,
                endOffset: 0,
                pageCount: endPage - startPage + 1,
                internalHref: nil
            )
            chapters.append(chapter)
        }

        return chapters
    }

    // MARK: - Cover Image

    private func renderCoverImage(from document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0) else { return nil }

        let pageRect = page.bounds(for: .mediaBox)
        let thumbSize = CGSize(width: 300, height: 420)
        let scale = min(thumbSize.width / pageRect.width, thumbSize.height / pageRect.height)
        let scaledRect = CGRect(
            x: 0, y: 0,
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: scaledRect.size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(scaledRect)
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: scaledRect.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }

        return image.pngData()
    }

    // MARK: - Text Estimation

    private func estimateTotalChars(from document: PDFDocument, pageCount: Int) -> Int64 {
        guard pageCount > 0 else { return 0 }

        // Sample up to 10 pages to estimate total character count.
        let sampleSize = min(10, pageCount)
        var sampleChars = 0
        let step = max(1, pageCount / sampleSize)

        var sampled = 0
        for i in stride(from: 0, to: pageCount, by: step) {
            guard sampled < sampleSize else { break }
            if let page = document.page(at: i), let text = page.string {
                sampleChars += text.count
            }
            sampled += 1
        }

        guard sampled > 0 else { return 0 }

        let avgPerPage = Double(sampleChars) / Double(sampled)
        return Int64(avgPerPage * Double(pageCount))
    }

    // MARK: - Helpers

    private func fileSizeBytes(at path: String) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.size] as? Int64) ?? 0
    }
}

// MARK: - PDF Parser Errors

enum PDFParserError: LocalizedError {
    case failedToOpenPDF
    case invalidPageRange

    var errorDescription: String? {
        switch self {
        case .failedToOpenPDF:
            return "无法打开PDF文件"
        case .invalidPageRange:
            return "PDF页面范围超出"
        }
    }
}
