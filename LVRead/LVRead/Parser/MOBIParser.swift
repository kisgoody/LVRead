import Foundation

// MARK: - MOBI/AZW3 Parser

/// Provides basic support for MOBI and AZW3 (KF8) files by parsing the PalmDOC
/// header and MOBI header to extract metadata and text records. Full rendering
/// fidelity (embedded fonts, complex KF8 layout) is not supported — users are
/// encouraged to convert to EPUB via Calibre for the best experience.
final class MOBIParser: FileParserProtocol {

    // MARK: - Constants

    private static let palmDBHeaderSize = 78
    private static let mobiHeaderMinSize = 232

    /// MOBI header encoding field values.
    private static let mobiEncodingCP1252  = UInt32(1252)  // Windows-1252 → UTF-8
    private static let mobiEncodingUTF8    = UInt32(65001) // UTF-8

    /// PalmDOC record attributes for determining text vs. metadata records.
    private static let recordAttrCompressed = UInt8(0x02)

    // MARK: - FileParserProtocol

    func parseMetadata(filePath: String) throws -> BookMetadata {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath), options: .alwaysMapped)
        let bytes = [UInt8](data)

        guard bytes.count >= Self.palmDBHeaderSize else {
            throw MOBIParserError.fileTooSmall
        }

        // Parse PalmDB header.
        let numRecords = readUInt16(bytes, offset: 76)
        guard numRecords > 1 else {
            throw MOBIParserError.noRecords
        }

        // Read record 0 (MOBI header).
        let record0Offset = Int(readUInt32(bytes, offset: 78))
        guard record0Offset > 0, record0Offset + Self.mobiHeaderMinSize <= bytes.count else {
            throw MOBIParserError.invalidMOBIHeader
        }

        // Detect encoding from the MOBI header.
        let encodingField = readUInt32(bytes, offset: record0Offset + 28)
        let encoding = self.encodingName(from: encodingField)

        // Extract title.
        let fullNameOffset = Int(readUInt32(bytes, offset: record0Offset + 84))
        let fullNameLength = Int(readUInt32(bytes, offset: record0Offset + 88))
        let title = readString(bytes, offset: fullNameOffset, length: fullNameLength, encoding: encoding)

        // EXTH header for author.
        let author = extractEXTHAuthor(bytes: bytes, record0Offset: record0Offset, encoding: encoding)

        // Build chapters from text records.
        let chapters = buildChapters(bytes: bytes, numRecords: Int(numRecords), record0Offset: record0Offset, encoding: encoding)

        // Estimate total characters.
        var totalChars: Int64 = 0
        for chapter in chapters {
            totalChars += chapter.endOffset - chapter.startOffset
        }

        return BookMetadata(
            title: title ?? fileURLToTitle(filePath),
            author: author ?? "未知作者",
            coverImageData: nil,
            chapters: chapters,
            encoding: encoding,
            totalCharCount: totalChars
        )
    }

    func parseChapterContent(filePath: String, chapter: Chapter, encoding: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath), options: .alwaysMapped)
        let bytes = [UInt8](data)

        let note = """
        [注意] MOBI格式支持有限。建议使用Calibre将文件转换为EPUB格式以获得更好的阅读体验。

        ===

        """

        guard bytes.count >= Self.palmDBHeaderSize else {
            return note
        }

        let numRecords = readUInt16(bytes, offset: 76)
        guard numRecords > 1 else {
            return note
        }

        let record0Offset = Int(readUInt32(bytes, offset: 78))
        guard record0Offset > 0 else {
            return note
        }

        let textStartRecord = Int(readUInt16(bytes, offset: record0Offset + 8) + 1)

        let useCompression = (readUInt16(bytes, offset: record0Offset) & 0x0002) != 0
        let compressionType = readUInt16(bytes, offset: record0Offset)

        let recordIndex = textStartRecord + chapter.orderIndex
        guard recordIndex < numRecords else {
            return note + "(章节超出范围)"
        }

        let recordOffsets = parseRecordOffsets(bytes: bytes, numRecords: Int(numRecords))
        let start = recordOffsets[recordIndex]
        let end = (recordIndex + 1 < recordOffsets.count) ? recordOffsets[recordIndex + 1] : bytes.count

        var recordBytes = Array(bytes[start..<end])

        if useCompression && compressionType == 2 {
            recordBytes = decompressPalmDOC(recordBytes)
        }

        if let text = decodeString(recordBytes, encoding: encoding) {
            return note + text
        }

        return note
    }

    func getBookStats(filePath: String) throws -> BookStats {
        let fileSize = try fileSizeBytes(at: filePath)
        let metadata = try parseMetadata(filePath: filePath)
        return BookStats(
            totalChapters: metadata.chapters.count,
            totalChars: metadata.totalCharCount,
            fileSizeBytes: fileSize
        )
    }

    // MARK: - PalmDOC Record Parsing

    private func parseRecordOffsets(bytes: [UInt8], numRecords: Int) -> [Int] {
        var offsets: [Int] = []
        for i in 0..<numRecords {
            let off = Int(readUInt32(bytes, offset: 78 + i * 8))
            offsets.append(off)
        }
        return offsets
    }

    // MARK: - Chapter Construction

    private func buildChapters(
        bytes: [UInt8],
        numRecords: Int,
        record0Offset: Int,
        encoding: String
    ) -> [Chapter] {
        let textStartRecord = Int(readUInt16(bytes, offset: record0Offset + 8) + 1)
        let textRecordCount = numRecords - textStartRecord
        guard textRecordCount > 0 else { return [] }

        var chapters: [Chapter] = []
        let recordOffsets = parseRecordOffsets(bytes: bytes, numRecords: numRecords)

        for i in 0..<textRecordCount {
            let idx = textStartRecord + i
            let startOffset = Int64(recordOffsets[idx])
            let endOffset = (idx + 1 < recordOffsets.count)
                ? Int64(recordOffsets[idx + 1])
                : Int64(bytes.count)

            let title: String
            if textRecordCount <= 1 {
                title = "正文"
            } else {
                title = "第 \(i + 1) 部分"
            }

            let chapter = Chapter(
                bookId: "",
                title: title,
                level: 1,
                orderIndex: i,
                startOffset: startOffset,
                endOffset: endOffset,
                pageCount: 0,
                internalHref: nil
            )
            chapters.append(chapter)
        }

        return chapters
    }

    // MARK: - EXTH Header Parsing

    /// EXTH (Extended Header) stores optional metadata such as author, publisher,
    /// description, etc. It immediately follows the MOBI header.
    private func extractEXTHAuthor(bytes: [UInt8], record0Offset: Int, encoding: String) -> String? {
        let mobiHeaderLength = Int(readUInt32(bytes, offset: record0Offset + 20))

        // Check for EXTH identifier "EXTH" at the end of the MOBI header.
        let exthOffset = record0Offset + mobiHeaderLength
        guard exthOffset + 12 <= bytes.count else { return nil }

        // Verify "EXTH" magic bytes.
        let magic = String(bytes: bytes[exthOffset..<exthOffset+4], encoding: .ascii)
        guard magic == "EXTH" else { return nil }

        let recordCount = Int(readUInt32(bytes, offset: exthOffset + 8))

        var pos = exthOffset + 12
        for _ in 0..<recordCount {
            guard pos + 8 <= bytes.count else { break }

            let recordType = readUInt32(bytes, offset: pos)
            let recordLen  = Int(readUInt32(bytes, offset: pos + 4))

            guard pos + 8 + recordLen <= bytes.count else { break }

            if recordType == 100 { // Author
                let authorData = Array(bytes[(pos + 8)..<(pos + 8 + recordLen)])
                if let author = decodeString(authorData, encoding: encoding) {
                    return author.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Also check for publisher (type 101) and description (type 103) for
            // future use, though we only need author right now.

            pos += 8 + recordLen
        }

        return nil
    }

    // MARK: - PalmDOC Decompression

    /// Implements PalmDOC LZ77-style decompression.
    private func decompressPalmDOC(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var i = 0

        while i < input.count {
            let c = input[i]
            i += 1

            if c == 0 {
                // Literal byte 0x00.
                output.append(0)
            } else if c <= 0x08 {
                // Copy c literal bytes.
                for _ in 0..<c {
                    guard i < input.count else { break }
                    output.append(input[i])
                    i += 1
                }
            } else if c <= 0x7F {
                // Single literal byte.
                output.append(c)
            } else if c <= 0xBF {
                // Length-distance pair (2 bytes): copy from earlier in output.
                guard i < input.count else { break }
                let c2 = input[i]
                i += 1
                let distance = (Int(c & 0x1F) << 8) | Int(c2)
                let length = (Int(c & 0x60) >> 5) + 3
                copyFromOutput(&output, distance: distance, length: length)
            } else {
                // Length-distance pair (3 bytes).
                guard i + 1 < input.count else { break }
                let c2 = input[i]
                let c3 = input[i + 1]
                i += 2
                let distance = (Int(c3) << 8) | Int(c2)
                let length = Int(c & 0x3F) + 4
                copyFromOutput(&output, distance: distance, length: length)
            }
        }

        return output
    }

    private func copyFromOutput(_ output: inout [UInt8], distance: Int, length: Int) {
        let start = output.count - distance
        for j in 0..<length {
            let srcIdx = start + j
            if srcIdx >= 0 && srcIdx < output.count {
                output.append(output[srcIdx])
            } else {
                output.append(0x20) // space as fallback
            }
        }
    }

    // MARK: - Helpers

    private func encodingName(from field: UInt32) -> String {
        switch field {
        case Self.mobiEncodingUTF8:
            return "UTF-8"
        case Self.mobiEncodingCP1252:
            return "UTF-8" // Map CP1252 → UTF-8 as closest approximation
        default:
            return "UTF-8"
        }
    }

    private func decodeString(_ bytes: [UInt8], encoding: String) -> String? {
        let data = Data(bytes)
        if encoding == "UTF-8" {
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        }
        if let nsEnc = nsStringEncoding(from: encoding) {
            return String(data: data, encoding: nsEnc)
        }
        return String(data: data, encoding: .utf8)
    }

    private func nsStringEncoding(from name: String) -> String.Encoding? {
        switch name.uppercased() {
        case "UTF-8": return .utf8
        case "UTF-16BE": return .utf16BigEndian
        case "UTF-16LE": return .utf16LittleEndian
        case "WINDOWS-1252": return .windowsCP1252
        default: return nil
        }
    }

    private func fileURLToTitle(_ path: String) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return name.isEmpty ? "未命名" : name
    }

    private func fileSizeBytes(at path: String) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.size] as? Int64) ?? 0
    }

    // MARK: - Binary Reader Helpers

    private func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return (UInt32(bytes[offset]) << 24)
             | (UInt32(bytes[offset + 1]) << 16)
             | (UInt32(bytes[offset + 2]) << 8)
             | UInt32(bytes[offset + 3])
    }

    private func readString(_ bytes: [UInt8], offset: Int, length: Int, encoding: String) -> String? {
        guard offset >= 0, offset + length <= bytes.count, length > 0 else { return nil }
        let slice = Array(bytes[offset..<(offset + length)])
        return decodeString(slice, encoding: encoding)
    }
}

// MARK: - MOBI Parser Errors

enum MOBIParserError: LocalizedError {
    case fileTooSmall
    case noRecords
    case invalidMOBIHeader

    var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "MOBI文件过小，无法解析"
        case .noRecords:
            return "MOBI文件中没有记录"
        case .invalidMOBIHeader:
            return "MOBI文件头无效"
        }
    }
}
