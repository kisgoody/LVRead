import Foundation

final class TXTParser: FileParserProtocol {

    // MARK: - Chapter Detection Patterns

    private let chapterPatterns: [NSRegularExpression] = {
        let raw: [String] = [
            #"^[　\s]*第[0-9零一二三四五六七八九十百千]+[章节回部卷集篇].*"#,
            #"^[　\s]*[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\s+\d+.*"#,
            #"^[　\s]*[Pp][Aa][Rr][Tt]\s+\d+.*"#,
            #"^[　\s]*(序言|前言|楔子|引言|尾声|后记|番外|附录|尾声|终章|题记|引子).*"#,
            #"^[　\s]*[一二三四五六七八九十]+、.*"#,
            #"^[　\s]*\d+[\.\)、]\s+\S.*"#,
            #"^[　\s]*[IVX]+[\.\)、]\s+\S.*"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    // MARK: - FileParserProtocol

    func parseMetadata(filePath: String) throws -> BookMetadata {
        let encoding = EncodingDetector.detectEncoding(filePath: filePath)
        guard let fullText = readFullText(filePath: filePath, encoding: encoding) else {
            throw LVError.parseFailed
        }

        let lines = fullText.components(separatedBy: .newlines)

        // Title / author detection from first 1000 chars
        let sampleLines = lines.prefix(50).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var title = sampleLines.first ?? ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        title = title.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces)
        if title.count > 60 { title = String(title.prefix(60)) }

        var author = "未知作者"
        for line in sampleLines {
            if line.hasPrefix("作者") || line.hasPrefix("著者") || line.hasPrefix("Author") || line.hasPrefix("author") {
                let parts = line.components(separatedBy: CharacterSet(charactersIn: "：:"))
                if parts.count >= 2, !parts[1].trimmingCharacters(in: .whitespaces).isEmpty {
                    author = parts[1].trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        if author == "未知作者", sampleLines.count >= 2 {
            let candidate = sampleLines[1]
            if candidate.count <= 20 { author = candidate }
        }

        let chapters = detectChapters(from: lines, fullText: fullText, encoding: encoding)
        let totalCharCount = Int64(fullText.count)

        return BookMetadata(
            title: title,
            author: author,
            coverImageData: nil,
            chapters: chapters,
            encoding: encoding,
            totalCharCount: totalCharCount
        )
    }

    /// Read the full text and slice by the UTF-16 offsets computed during metadata parse.
    /// This is the only reliable way to extract chapter boundaries for multi-byte encodings.
    func parseChapterContent(filePath: String, chapter: Chapter, encoding: String) throws -> String {
        print("[TXT] parseChapterContent: encoding=\(encoding), chapter=\(chapter.title), offsets=\(chapter.startOffset)..\(chapter.endOffset)")
        guard let fullText = readFullText(filePath: filePath, encoding: encoding) else {
            print("[TXT] readFullText returned nil → throw parseFailed")
            throw LVError.parseFailed
        }
        print("[TXT] Full text loaded: \(fullText.count) chars, utf16=\(fullText.utf16.count)")

        let start = Int(chapter.startOffset)
        let end   = Int(chapter.endOffset)

        guard start >= 0, end <= fullText.utf16.count, start < end else {
            print("[TXT] Offset guard failed: start=\(start) end=\(end) utf16count=\(fullText.utf16.count)")
            throw LVError.parseFailed
        }
        print("[TXT] Offset guard passed, slicing utf16[\(start)..<\(end)]")

        let utf16 = fullText.utf16
        let lo = String.Index(utf16Offset: start, in: fullText)
        let hi = String.Index(utf16Offset: end, in: fullText)
        let content = String(fullText[lo..<hi])
        print("[TXT] Content sliced: \(content.count) chars")

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getBookStats(filePath: String) throws -> BookStats {
        let encoding = EncodingDetector.detectEncoding(filePath: filePath)
        guard let fullText = readFullText(filePath: filePath, encoding: encoding) else {
            throw LVError.parseFailed
        }
        let lines = fullText.components(separatedBy: .newlines)
        let chapters = detectChapters(from: lines, fullText: fullText, encoding: encoding)
        let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
        return BookStats(
            totalChapters: chapters.count,
            totalChars: Int64(fullText.count),
            fileSizeBytes: (attrs[.size] as? Int64) ?? 0
        )
    }

    // MARK: - Private helpers

    private func readFullText(filePath: String, encoding: String) -> String? {
        EncodingDetector.readWithEncoding(filePath: filePath, encoding: encoding)
    }

    // MARK: - Private: Chapter Detection

    private func detectChapters(from lines: [String], fullText: String, encoding: String) -> [Chapter] {
        var chapters: [Chapter] = []
        let utf16 = fullText.utf16

        var candidates: [(lineIndex: Int, line: String, offset: Int)] = []
        var cumulativeOffset = 0
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineLen = line.utf16.count
            let isCandidate = chapterPatterns.contains { regex in
                regex.firstMatch(in: trimmed, range: NSRange(0..<trimmed.utf16.count)) != nil
            }
            if isCandidate {
                candidates.append((lineIndex: idx, line: trimmed, offset: cumulativeOffset))
            }
            cumulativeOffset += lineLen + 1
        }

        if candidates.isEmpty {
            chapters.append(Chapter(bookId: "", title: "正文", level: 1, orderIndex: 0, startOffset: 0, endOffset: Int64(utf16.count), pageCount: 0))
            return chapters
        }

        // Deduplicate contiguous candidates
        var filtered: [(lineIndex: Int, line: String, offset: Int)] = []
        for cand in candidates {
            if let last = filtered.last, cand.lineIndex - last.lineIndex <= 1 { continue }
            filtered.append(cand)
        }

        // Preamble
        if let first = filtered.first, first.offset > 0 {
            chapters.append(Chapter(bookId: "", title: "前言", level: 1, orderIndex: 0, startOffset: 0, endOffset: Int64(first.offset), pageCount: 0))
        }

        for (i, cand) in filtered.enumerated() {
            let end = (i + 1 < filtered.count) ? filtered[i + 1].offset : utf16.count
            chapters.append(Chapter(
                bookId: "", title: cand.line, level: 1, orderIndex: chapters.count,
                startOffset: Int64(cand.offset), endOffset: Int64(end), pageCount: 0
            ))
        }
        return chapters
    }
}
