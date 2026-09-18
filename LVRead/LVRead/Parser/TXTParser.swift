import Foundation

final class TXTParser: FileParserProtocol {

    private let keepsFrontAndBackMatter: Bool

    init(keepsFrontAndBackMatter: Bool = false) {
        self.keepsFrontAndBackMatter = keepsFrontAndBackMatter
    }

    private struct ChapterCandidate {
        let title: String
        let startOffset: Int
        let endOffset: Int
        let body: String

        var meaningfulBodyLength: Int {
            body.unicodeScalars.reduce(into: 0) { count, scalar in
                if CharacterSet.alphanumerics.contains(scalar) { count += 1 }
            }
        }
    }

    // MARK: - Chapter Detection Patterns

    private let chapterPatterns: [NSRegularExpression] = {
        let raw: [String] = [
            #"^[　\s]*第[0-9零一二三四五六七八九十百千]+[章节回部卷集篇].*"#,
            #"^[　\s]*[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\s+\d+.*"#,
            #"^[　\s]*[Pp][Aa][Rr][Tt]\s+\d+.*"#,
            #"^[　\s]*卷[0-9零一二三四五六七八九十百千]+.*"#,
            #"^[　\s]*(序言|前言|楔子|引言|尾声|后记|番外|附录|尾声|终章|题记|引子).*"#,
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

        let lo = String.Index(utf16Offset: start, in: fullText)
        let hi = String.Index(utf16Offset: end, in: fullText)
        let content = String(fullText[lo..<hi])
        print("[TXT] Content sliced: \(content.count) chars")

        return Self.standardizedBody(content)
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
        let utf16 = fullText.utf16

        var rawCandidates: [(title: String, offset: Int)] = []
        var cumulativeOffset = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineLen = line.utf16.count
            let isCandidate = chapterPatterns.contains { regex in
                regex.firstMatch(in: trimmed, range: NSRange(0..<trimmed.utf16.count)) != nil
            }
            if isCandidate {
                rawCandidates.append((title: trimmed, offset: cumulativeOffset))
            }
            cumulativeOffset += lineLen + 1
        }

        guard !rawCandidates.isEmpty else {
            return [Chapter(
                bookId: "",
                title: "正文",
                level: 1,
                orderIndex: 0,
                startOffset: 0,
                endOffset: Int64(utf16.count),
                pageCount: 0
            )]
        }

        let source = fullText as NSString
        let candidates = rawCandidates.enumerated().map { index, value in
            let end = index + 1 < rawCandidates.count
                ? rawCandidates[index + 1].offset
                : source.length
            let block = source.substring(
                with: NSRange(location: value.offset, length: max(0, end - value.offset))
            )
            let body = block.components(separatedBy: .newlines).dropFirst().joined(separator: "\n")
            return ChapterCandidate(
                title: value.title,
                startOffset: value.offset,
                endOffset: end,
                body: body
            )
        }

        let filtered = removingDirectoryAndDuplicateCandidates(candidates)
        guard !filtered.isEmpty else {
            return [Chapter(
                bookId: "",
                title: "正文",
                level: 1,
                orderIndex: 0,
                startOffset: 0,
                endOffset: Int64(utf16.count),
                pageCount: 0
            )]
        }

        return filtered.enumerated().map { index, candidate in
            Chapter(
                bookId: "",
                title: candidate.title,
                level: 1,
                orderIndex: index,
                startOffset: Int64(candidate.startOffset),
                endOffset: Int64(candidate.endOffset),
                pageCount: 0
            )
        }
    }

    /// Detects chapter tables created by older TXT rules so an already imported
    /// book can rebuild its chapter index without changing the source file.
    static func requiresChapterRebuild(_ chapters: [Chapter]) -> Bool {
        let groups = Dictionary(grouping: chapters, by: { canonicalTitle($0.title) })
        return groups.values.contains { values in
            guard values.count > 1 else { return false }
            let lengths = values.map { max(0, $0.endOffset - $0.startOffset) }
            return lengths.contains(where: { $0 < 200 })
                && lengths.contains(where: { $0 >= 200 })
        }
    }

    static func canonicalTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[\[［]\d+[\]］]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func removingDirectoryAndDuplicateCandidates(
        _ candidates: [ChapterCandidate]
    ) -> [ChapterCandidate] {
        let grouped = Dictionary(grouping: candidates.indices) {
            Self.canonicalTitle(candidates[$0].title)
        }
        var kept = Set<Int>()

        for indices in grouped.values {
            let meaningful = indices.filter { isMeaningfulNovelBody(candidates[$0]) }
            guard !meaningful.isEmpty else { continue }

            var accepted: [Int] = []
            for index in meaningful {
                let duplicate = accepted.contains {
                    Self.bodiesAreEquivalent(candidates[$0].body, candidates[index].body)
                }
                if !duplicate { accepted.append(index) }
            }
            kept.formUnion(accepted)
        }

        return candidates.indices.compactMap { kept.contains($0) ? candidates[$0] : nil }
    }

    private func isMeaningfulNovelBody(_ candidate: ChapterCandidate) -> Bool {
        guard candidate.meaningfulBodyLength >= 20 else { return false }
        let title = Self.canonicalTitle(candidate.title)
        let excludedTitles = ["目录", "前言", "序言", "后记", "版权声明", "读者评论"]
        if !keepsFrontAndBackMatter,
           excludedTitles.contains(where: { title.hasPrefix($0) }) {
            return false
        }

        let compact = candidate.body
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
        let noise = ["下载地址", "最新网址", "手机用户请访问", "本章未完", "请收藏本站"]
        return !(compact.count < 500 && noise.contains(where: compact.contains))
    }

    private static func bodiesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = fingerprintText(lhs)
        let right = fingerprintText(rhs)
        guard !left.isEmpty, !right.isEmpty else { return left == right }
        if left == right { return true }
        let shorter = min(left.count, right.count)
        let longer = max(left.count, right.count)
        guard Double(shorter) / Double(longer) >= 0.9 else { return false }
        return left.prefix(min(256, shorter)) == right.prefix(min(256, shorter))
    }

    private static func fingerprintText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[\[［]\d+[\]］]"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    /// Publication layout: one paragraph per line, no blank lines between body
    /// paragraphs, and a two-em indentation for Chinese prose.
    private static func standardizedBody(_ content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current = ""

        func finishParagraph() {
            let value = current.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { paragraphs.append(value) }
            current = ""
        }

        for rawLine in lines {
            var line = rawLine
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(
                of: #"^#{1,6}\s*"#,
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: #" {2,}"#,
                with: " ",
                options: .regularExpression
            )
            if line.isEmpty {
                finishParagraph()
                continue
            }
            if line.range(of: #"^[-=_*]{3,}$"#, options: .regularExpression) != nil {
                finishParagraph()
                continue
            }
            if line.range(of: #"^[\[［][^\]］]+[\]］]$"#, options: .regularExpression) != nil {
                finishParagraph()
                continue
            }
            if current.isEmpty {
                current = line
            } else if shouldStartNewParagraph(after: current, next: line) {
                finishParagraph()
                current = line
            } else {
                current += joiner(between: current, and: line) + line
            }
        }
        finishParagraph()
        guard let title = paragraphs.first else { return "" }
        let body = paragraphs.dropFirst().map { paragraph in
            let normalized = normalizeMixedText(paragraph)
            let indentation = containsCJK(normalized) ? "　　" : "    "
            return indentation + normalized
        }
        guard !body.isEmpty else { return title }
        return title + "\n\n" + body.joined(separator: "\n")
    }

    private static func shouldStartNewParagraph(after current: String, next: String) -> Bool {
        let paragraphEnd = CharacterSet(charactersIn: "。！？!?…；;：:”’」』）)")
        if let last = current.unicodeScalars.last, paragraphEnd.contains(last) { return true }
        return next.hasPrefix("“") || next.hasPrefix("「") || next.hasPrefix("『")
    }

    private static func joiner(between lhs: String, and rhs: String) -> String {
        guard let left = lhs.unicodeScalars.last,
              let right = rhs.unicodeScalars.first else { return "" }
        return CharacterSet.alphanumerics.contains(left)
            && left.isASCII
            && CharacterSet.alphanumerics.contains(right)
            && right.isASCII ? " " : ""
    }

    private static func normalizeMixedText(_ value: String) -> String {
        var result = value
        let replacements = [
            (#"(?<=[\p{Han}]),"#, "，"),
            (#"(?<=[\p{Han}])\."#, "。"),
            (#"(?<=[\p{Han}])!"#, "！"),
            (#"(?<=[\p{Han}])\?"#, "？"),
            (#"\((?=[\p{Han}])"#, "（"),
            (#"(?<=[\p{Han}])\)"#, "）"),
            (#"(?<=[A-Za-z0-9])，"#, ","),
            (#"(?<=[A-Za-z0-9])。"#, "."),
            (#"(?<=[A-Za-z0-9])！"#, "!"),
            (#"(?<=[A-Za-z0-9])？"#, "?"),
            (#"（(?=[A-Za-z0-9])"#, "("),
            (#"(?<=[A-Za-z0-9])）"#, ")")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(
            of: #"([\p{Han}])([A-Za-z0-9])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"([A-Za-z0-9])([\p{Han}])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"([A-Za-z])([0-9])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\s+([，。！？；：,.!?;:）)])"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"([（(])\s+"#,
            with: "$1",
            options: .regularExpression
        )
        return normalizeQuotes(in: result, usesCJKStyle: containsCJK(result))
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private static func normalizeQuotes(in value: String, usesCJKStyle: Bool) -> String {
        guard usesCJKStyle else {
            return value
                .replacingOccurrences(of: "“", with: "\"")
                .replacingOccurrences(of: "”", with: "\"")
                .replacingOccurrences(of: "‘", with: "'")
                .replacingOccurrences(of: "’", with: "'")
        }
        var doubleOpen = true
        var singleOpen = true
        var result = ""
        for character in value {
            switch character {
            case "\"":
                result.append(doubleOpen ? "“" : "”")
                doubleOpen.toggle()
            case "'":
                result.append(singleOpen ? "‘" : "’")
                singleOpen.toggle()
            default:
                result.append(character)
            }
        }
        return result
    }
}
