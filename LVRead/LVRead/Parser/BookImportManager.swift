import Foundation
import UIKit
import CommonCrypto

// MARK: - Book Import Manager

/// Singleton that manages the full book-import pipeline: copy, hash, detect
/// encoding, parse metadata, extract cover, persist to database, and report
/// progress through a 10-step callback.
final class BookImportManager {

    // MARK: - Singleton

    static let shared = BookImportManager()

    private let importQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.lvread.bookimport"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Public API

    /// Quick async import (no progress reporting).
    func importFile(
        from url: URL,
        completion: @escaping (Result<Book, LVError>) -> Void
    ) {
        importFileWithProgress(from: url, progressHandler: nil, completion: completion)
    }

    /// Import a file with 10-step progress reporting.
    ///
    /// Progress steps:
    ///   0%   — Computing file hash
    ///  10%   — Detecting encoding
    ///  20%   — Parsing metadata (begin)
    ///  30%   — Parsing metadata (complete)
    ///  40%   — Copying file to books directory
    ///  50%   — Extracting / saving cover image
    ///  60%   — Prepating book model
    ///  70%   — Saving book record to database
    ///  80%   — Saving chapters to database
    ///  90%   — Caching and finalizing
    /// 100%   — Import complete
    func importFileWithProgress(
        from url: URL,
        progressHandler: ((Float, String) -> Void)?,
        completion: @escaping (Result<Book, LVError>) -> Void
    ) {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self] in
            guard let self = self else { return }
            self.performImport(
                from: url,
                operation: operation,
                progressHandler: progressHandler,
                completion: completion
            )
        }
        importQueue.addOperation(operation)
    }

    // MARK: - Format Detection

    /// Map a URL to its `FileFormat` by inspecting the path extension.
    func detectFormat(_ url: URL) -> FileFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "epub":
            return .epub
        case "txt", "text":
            return .txt
        case "pdf":
            return .pdf
        case "mobi":
            return .mobi
        case "azw3", "azw":
            return .azw3
        default:
            // Fallback: inspect file data for known signatures.
            if let hint = detectFormatBySignature(url) {
                return hint
            }
            return .txt
        }
    }

    /// Return the appropriate parser implementation for a given format.
    func parserFor(format: FileFormat) -> FileParserProtocol {
        switch format {
        case .epub:
            return EPUBParser()
        case .txt:
            return TXTParser()
        case .pdf:
            return PDFParser()
        case .mobi, .azw3:
            return MOBIParser()
        }
    }

    // MARK: - Storage Paths

    /// The application's dedicated books storage directory.
    func booksDirectory() -> String {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let dir = (documents as NSString).appendingPathComponent("LVReadBooks")
        ensureDirectoryExists(dir)
        return dir
    }

    /// The application's dedicated cover-image storage directory.
    func coversDirectory() -> String {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let dir = (documents as NSString).appendingPathComponent("LVReadCovers")
        ensureDirectoryExists(dir)
        return dir
    }

    // MARK: - SHA-256 Computatation

    /// Compute the SHA-256 hash of a file using CommonCrypto, reading in 8 KB chunks.
    func computeSHA256(_ filePath: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { try? handle.close() }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        let chunkSize = 8192
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: chunkSize)
            guard !data.isEmpty else { return false }
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                _ = CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(bytes.count))
            }
            return true
        }) {}

        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            _ = CC_SHA256_Final(bytes.bindMemory(to: UInt8.self).baseAddress, &context)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private: Import Pipeline

    private func performImport(
        from url: URL,
        operation: BlockOperation,
        progressHandler: ((Float, String) -> Void)?,
        completion: @escaping (Result<Book, LVError>) -> Void
    ) {
        // Ensure we have a local file path. If the URL uses a security-scoped
        // resource (e.g. from the document picker), start accessing it.
        let needsScopedAccess = !url.isFileURL || url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let filePath = url.path
        let format = detectFormat(url)

        // Step 0: Report format.
        reportProgress(progressHandler, percent: 0.0, message: "检测文件格式: \(format.displayName)", operation: operation)

        // Step 0 → 10%: Compute hash.
        guard let fileHash = computeSHA256(filePath) else {
            dispatchCompletion(completion, result: .failure(.parseFailed))
            return
        }

        // Duplicate check.
        if let existing = BookRepository.shared.getByHash(fileHash) {
            reportProgress(progressHandler, percent: 1.0, message: "该书已存在", operation: operation)
            dispatchCompletion(completion, result: .success(existing))
            return
        }

        reportProgress(progressHandler, percent: 0.10, message: "SHA-256计算完成", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 10% → 20%: Detect encoding (formats like EPUB and PDF use UTF-8 natively).
        let encoding: String
        if format == .epub || format == .pdf {
            encoding = "UTF-8"
        } else {
            encoding = EncodingDetector.detectEncoding(filePath: filePath)
            reportProgress(progressHandler, percent: 0.15, message: "检测编码: \(encoding)", operation: operation)
        }
        guard !operation.isCancelled else { return }

        // Step 20% → 40%: Parse metadata.
        let parser = parserFor(format: format)
        reportProgress(progressHandler, percent: 0.20, message: "开始解析...", operation: operation)
        guard !operation.isCancelled else { return }

        let metadata: BookMetadata
        do {
            metadata = try parser.parseMetadata(filePath: filePath)
        } catch {
            reportProgress(progressHandler, percent: 0.0, message: "解析失败: \(error.localizedDescription)", operation: operation)
            dispatchCompletion(completion, result: .failure(.parseFailed))
            return
        }

        reportProgress(progressHandler, percent: 0.35, message: "解析完成: 发现 \(metadata.chapters.count) 个章节", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 40% → 50%: Copy file to books directory.
        let booksDir = booksDirectory()
        let destFileName = "\(fileHash).\(url.pathExtension)"
        let destPath = (booksDir as NSString).appendingPathComponent(destFileName)

        // Only copy if we haven't already.
        if !fileManager.fileExists(atPath: destPath) {
            do {
                try fileManager.copyItem(atPath: filePath, toPath: destPath)
            } catch {
                dispatchCompletion(completion, result: .failure(.storageFull))
                return
            }
        }
        reportProgress(progressHandler, percent: 0.50, message: "文件已拷贝", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 50% → 60%: Save cover image.
        let coverImagePath: String?
        if let coverData = metadata.coverImageData {
            coverImagePath = saveCoverImage(coverData, bookHash: fileHash)
            if let coverPath = coverImagePath,
               let coverImage = UIImage(data: coverData) {
                ImageCacheManager.shared.cacheImage(coverImage, forKey: fileHash)
            }
        } else if format == .pdf {
            // Try generating a cover from the first page.
            if let pdfParser = parser as? PDFParser,
               let pdfCover = pdfParser.renderPageAsImage(filePath: destPath, pageIndex: 0) {
                if let pngData = pdfCover.pngData() {
                    coverImagePath = saveCoverImage(pngData, bookHash: fileHash)
                    ImageCacheManager.shared.cacheImage(pdfCover, forKey: fileHash)
                } else {
                    coverImagePath = nil
                }
            } else {
                coverImagePath = nil
            }
        } else {
            coverImagePath = nil
        }
        reportProgress(progressHandler, percent: 0.60, message: "封面已处理", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 60% → 70%: Build book model.
        let fileSize: Int64
        if let attrs = try? fileManager.attributesOfItem(atPath: destPath),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        let bookId = UUID().uuidString
        let relativeBookPath = "LVReadBooks/\(destFileName)"
        let relativeCoverPath: String?
        if let coverAbsPath = coverImagePath {
            let coverFileName = (coverAbsPath as NSString).lastPathComponent
            relativeCoverPath = "LVReadCovers/\(coverFileName)"
        } else {
            relativeCoverPath = nil
        }
        let book = Book(
            id: bookId,
            title: metadata.title,
            author: metadata.author,
            coverImagePath: relativeCoverPath,
            filePath: relativeBookPath,
            fileHash: fileHash,
            fileSize: fileSize,
            fileFormat: format,
            source: .shareImport,
            encoding: metadata.encoding ?? encoding,
            category: nil,
            readingProgress: ReadingProgress(),
            createdAt: Date(),
            updatedAt: Date()
        )
        print("[IMPORT] Book created: title=\(book.title), format=\(format), encoding=\(book.encoding ?? "nil"), chapters=\(metadata.chapters.count)")
        reportProgress(progressHandler, percent: 0.70, message: "模型已创建", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 70% → 80%: Save book to database.
        let insertResult = BookRepository.shared.insert(book)
        guard case .success(let savedBook) = insertResult else {
            // Clean up copied file on failure.
            try? fileManager.removeItem(atPath: destPath)
            dispatchCompletion(completion, result: .failure(.databaseError))
            return
        }
        reportProgress(progressHandler, percent: 0.80, message: "书籍已入库", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 80% → 90%: Save chapters.
        let chapters = metadata.chapters.map { chapter in
            Chapter(
                id: chapter.id,
                bookId: bookId,
                title: chapter.title,
                level: chapter.level,
                orderIndex: chapter.orderIndex,
                startOffset: chapter.startOffset,
                endOffset: chapter.endOffset,
                pageCount: chapter.pageCount,
                internalHref: chapter.internalHref
            )
        }
        BookRepository.shared.insertChapters(chapters)
        reportProgress(progressHandler, percent: 0.90, message: "章节已保存", operation: operation)
        guard !operation.isCancelled else { return }

        // Step 90% → 100%: Finalize.
        reportProgress(progressHandler, percent: 1.0, message: "导入完成", operation: operation)

        dispatchCompletion(completion, result: .success(savedBook))
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists(_ path: String) {
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func saveCoverImage(_ data: Data, bookHash: String) -> String? {
        let coversDir = coversDirectory()
        let fileName = "\(bookHash).png"
        let filePath = (coversDir as NSString).appendingPathComponent(fileName)

        do {
            try data.write(to: URL(fileURLWithPath: filePath))
            return filePath
        } catch {
            return nil
        }
    }

    private func reportProgress(
        _ handler: ((Float, String) -> Void)?,
        percent: Float,
        message: String,
        operation: BlockOperation
    ) {
        guard !operation.isCancelled else { return }
        handler?(percent, message)
    }

    private func dispatchCompletion(
        _ completion: @escaping (Result<Book, LVError>) -> Void,
        result: Result<Book, LVError>
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    /// Detect file format by inspecting magic bytes in the file header.
    private func detectFormatBySignature(_ url: URL) -> FileFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let header = handle.readData(ofLength: 64)
        let bytes = [UInt8](header)

        // EPUB: PK\x03\x04 (ZIP) + check for mimetype
        if bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B {
            return .epub
        }
        // PDF: %PDF
        if bytes.count >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return .pdf
        }
        // MOBI/AZW: PalmDB header (0x424F4F4B4D4F4249 = "BOOKMOBI")
        if bytes.count >= 68 {
            let mobiMagic = String(bytes: bytes[60..<68], encoding: .ascii)
            if mobiMagic == "BOOKMOBI" {
                // Further discriminate: check for AZW3/KF8 marker
                // "AZW3" appears near offset 68+ in newer files
                if bytes.count >= 72 {
                    let kindleMagic = String(bytes: bytes[68..<72], encoding: .ascii)
                    if kindleMagic == "AZW3" {
                        return .azw3
                    }
                }
                return .mobi
            }
        }
        return nil
    }
}
