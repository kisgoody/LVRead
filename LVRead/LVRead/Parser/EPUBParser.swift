import Foundation
import zlib

final class EPUBParser: FileParserProtocol {

    func parseMetadata(filePath: String) throws -> BookMetadata {
        let unzipDir = try unzipEPUB(filePath: filePath)
        defer {
            do {
                try FileManager.default.removeItem(atPath: unzipDir)
            } catch {
                print("⚠️ EPUBParser: failed to clean up temp dir \(unzipDir): \(error)")
            }
        }

        let containerPath = (unzipDir as NSString).appendingPathComponent("META-INF/container.xml")
        guard let containerXML = try? String(contentsOfFile: containerPath, encoding: .utf8) else {
            throw LVError.parseFailed
        }

        // Extract OPF path
        guard let opfRelPath = firstMatch(in: containerXML, pattern: "full-path=\"([^\"]+)\"") else {
            throw LVError.parseFailed
        }
        let opfPath = (unzipDir as NSString).appendingPathComponent(opfRelPath)
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        guard let opfXML = try? String(contentsOfFile: opfPath, encoding: .utf8) else {
            throw LVError.parseFailed
        }

        // Parse metadata - strip namespaces
        var cleanXML = opfXML.replacingOccurrences(of: "<dc:", with: "<")
        cleanXML = cleanXML.replacingOccurrences(of: "</dc:", with: "</")

        let title = firstMatch(in: cleanXML, pattern: "<title[^>]*>(.*?)</title>") ?? "未知书名"
        let author = firstMatch(in: cleanXML, pattern: "<creator[^>]*>(.*?)</creator>") ?? "未知作者"

        // Extract manifest items
        var manifestMap: [String: String] = [:]
        let manifestPattern = try? NSRegularExpression(pattern: "id=\"([^\"]+)\"[^>]*href=\"([^\"]+)\"")
        if let regex = manifestPattern {
            regex.enumerateMatches(in: opfXML, range: NSRange(opfXML.startIndex..., in: opfXML)) { match, _, _ in
                guard let m = match,
                      let idR = Range(m.range(at: 1), in: opfXML),
                      let hrefR = Range(m.range(at: 2), in: opfXML) else { return }
                manifestMap[String(opfXML[idR])] = String(opfXML[hrefR])
            }
        }

        // Extract spine order (itemref idref="...")
        var spineOrder: [String] = []
        let spinePattern = try? NSRegularExpression(pattern: "idref=\"([^\"]+)\"")
        if let regex = spinePattern {
            // Only match within <spine>...</spine>
            if let spineRange = cleanXML.range(of: "<spine[^>]*>.*?</spine>", options: .regularExpression) {
                let spineXML = String(cleanXML[spineRange])
                regex.enumerateMatches(in: spineXML, range: NSRange(spineXML.startIndex..., in: spineXML)) { match, _, _ in
                    guard let m = match, let r = Range(m.range(at: 1), in: spineXML) else { return }
                    spineOrder.append(String(spineXML[r]))
                }
            }
        }

        // Extract cover image
        var coverData: Data? = nil
        if let coverHref = extractCoverHref(opfXML: opfXML, manifest: manifestMap, opfDir: opfDir) {
            let coverPath = (opfDir as NSString).appendingPathComponent(coverHref)
            coverData = try? Data(contentsOf: URL(fileURLWithPath: coverPath))
        }

        // Try to find NCX for chapter titles
        let ncxHref = manifestMap.values.first { $0.hasSuffix(".ncx") } ?? "toc.ncx"
        let ncxPath = (opfDir as NSString).appendingPathComponent(ncxHref)
        var ncxTitles: [String] = []
        if let ncxXML = try? String(contentsOfFile: ncxPath, encoding: .utf8) {
            let navPattern = try? NSRegularExpression(pattern: "<text>([^<]+)</text>")
            if let regex = navPattern {
                let matches = regex.matches(in: ncxXML, range: NSRange(ncxXML.startIndex..., in: ncxXML))
                ncxTitles = matches.compactMap { match -> String? in
                    guard let r = Range(match.range(at: 1), in: ncxXML) else { return nil }
                    return String(ncxXML[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Build chapter list
        var chapters: [Chapter] = []
        var totalChars: Int64 = 0

        for (idx, spineId) in spineOrder.enumerated() {
            let href = manifestMap[spineId] ?? ""
            let fullPath = (opfDir as NSString).appendingPathComponent(href)
            let title = idx < ncxTitles.count ? ncxTitles[idx] : "第\(idx + 1)章"

            // Count chars for this chapter
            if let htmlData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
               let html = String(data: htmlData, encoding: .utf8) {
                let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                totalChars += Int64(stripped.count)
            }

           chapters.append(Chapter(
               bookId: "",
               title: title,
               level: 1,
               orderIndex: idx,
               startOffset: 0,
               endOffset: 0,
               pageCount: 0,
                internalHref: href
           ))
        }

        // If no chapters parsed, create a single chapter
        if chapters.isEmpty {
            chapters = [Chapter(bookId: "", title: "正文", level: 1, orderIndex: 0)]
        }

        return BookMetadata(
            title: title,
            author: author,
            coverImageData: coverData,
            chapters: chapters,
            encoding: "UTF-8",
            totalCharCount: totalChars
        )
    }

    func parseChapterContent(filePath: String, chapter: Chapter, encoding: String = "UTF-8") throws -> String {
        // Extract EPUB and resolve the relative href (stored during import)
        guard let relativeHref = chapter.internalHref, !relativeHref.isEmpty else {
            throw LVError.parseFailed
        }
        
        let unzipDir = try unzipEPUB(filePath: filePath)
        defer {
            do {
                try FileManager.default.removeItem(atPath: unzipDir)
            } catch {
                print("⚠️ EPUBParser: failed to clean up temp dir \(unzipDir): \(error)")
            }
        }
        
        let containerPath = (unzipDir as NSString).appendingPathComponent("META-INF/container.xml")
        guard let containerXML = try? String(contentsOfFile: containerPath, encoding: .utf8),
              let opfRelPath = firstMatch(in: containerXML, pattern: "full-path=\"([^\"]+)\"") else {
            throw LVError.parseFailed
        }

        let opfDir = ((unzipDir as NSString).appendingPathComponent(opfRelPath) as NSString).deletingLastPathComponent
        let fullPath = (opfDir as NSString).appendingPathComponent(relativeHref)
        guard let htmlData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
            throw LVError.parseFailed
        }
        return extractTextFromHTML(htmlData)
    }

    func getBookStats(filePath: String) throws -> BookStats {
        let metadata = try parseMetadata(filePath: filePath)
        let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
        return BookStats(
            totalChapters: metadata.chapters.count,
            totalChars: metadata.totalCharCount,
            fileSizeBytes: (attrs[.size] as? Int64) ?? 0
        )
    }

    // MARK: - Private Helpers

    private func unzipEPUB(filePath: String) throws -> String {
        let tempDir = NSTemporaryDirectory()
        let uuid = UUID().uuidString
        let extractDir = (tempDir as NSString).appendingPathComponent("epub_\(uuid)")
        try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: .alwaysMapped) else {
            throw LVError.parseFailed
        }

        try extractZIP(data: data, to: extractDir)
        return extractDir
    }

    /// Minimal ZIP extractor using zlib for decompression (works on iOS device & simulator).
    private func extractZIP(data: Data, to directory: String) throws {
        // Find End of Central Directory record
        guard data.count > 22 else { throw LVError.parseFailed }
        var eocdOffset = data.count - 22
        while eocdOffset > 0 {
            let sig = data.subdata(in: eocdOffset..<eocdOffset+4)
            if sig[0] == 0x50 && sig[1] == 0x4B && sig[2] == 0x05 && sig[3] == 0x06 { break }
            eocdOffset -= 1
        }
        guard eocdOffset > 0 else { throw LVError.parseFailed }

        let cdSize = Int(data.subdata(in: eocdOffset+12..<eocdOffset+16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        let cdOffset = Int(data.subdata(in: eocdOffset+16..<eocdOffset+20).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })

        // Parse central directory
        var pos = cdOffset
        let cdEnd = cdOffset + cdSize
        while pos + 46 <= cdEnd {
            let sig = data.subdata(in: pos..<pos+4)
            guard sig[0] == 0x50 && sig[1] == 0x4B && sig[2] == 0x01 && sig[3] == 0x02 else { break }

            let compressionMethod = data.subdata(in: pos+10..<pos+12).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            let compressedSize = Int(data.subdata(in: pos+20..<pos+24).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
            let uncompressedSize = Int(data.subdata(in: pos+24..<pos+28).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
            let fileNameLen = Int(data.subdata(in: pos+28..<pos+30).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            let extraLen = Int(data.subdata(in: pos+30..<pos+32).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            let commentLen = Int(data.subdata(in: pos+32..<pos+34).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            let localHeaderOffset = Int(data.subdata(in: pos+42..<pos+46).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })

            let fileNameData = data.subdata(in: pos+46..<pos+46+fileNameLen)
            guard let fileName = String(data: fileNameData, encoding: .utf8) else { break }

            pos += 46 + fileNameLen + extraLen + commentLen

            // Skip directories
            if fileName.hasSuffix("/") { continue }

            let destPath = (directory as NSString).appendingPathComponent(fileName)
            let destDir = (destPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

            // Find local file header
            var lhPos = localHeaderOffset
            guard lhPos + 30 <= data.count else { continue }
            let lhSig = data.subdata(in: lhPos..<lhPos+4)
            guard lhSig[0] == 0x50 && lhSig[1] == 0x4B && lhSig[2] == 0x03 && lhSig[3] == 0x04 else { continue }

            let lhFileNameLen = Int(data.subdata(in: lhPos+26..<lhPos+28).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            let lhExtraLen = Int(data.subdata(in: lhPos+28..<lhPos+30).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            let dataStart = lhPos + 30 + lhFileNameLen + lhExtraLen

            if compressionMethod == 0 {
                // Store (no compression)
                guard dataStart + uncompressedSize <= data.count else { continue }
                let fileData = data.subdata(in: dataStart..<dataStart+uncompressedSize)
                try fileData.write(to: URL(fileURLWithPath: destPath))
            } else if compressionMethod == 8 {
                // Deflate
                let compressedData = data.subdata(in: dataStart..<dataStart+compressedSize)
                let decompressed = try inflateData(compressedData, uncompressedSize: uncompressedSize)
                try decompressed.write(to: URL(fileURLWithPath: destPath))
            }
            // Skip other compression methods
        }
    }

    /// Decompress deflate-compressed data using zlib.
    private func inflateData(_ data: Data, uncompressedSize: Int) throws -> Data {
        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: (data as NSData).bytes.bindMemory(to: Bytef.self, capacity: data.count))
        stream.avail_in = uInt(data.count)

        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw LVError.parseFailed
        }
        defer { inflateEnd(&stream) }

        var result = Data(count: uncompressedSize)
        let status = result.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Int32 in
            stream.next_out = ptr.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(uncompressedSize)
            return inflate(&stream, Z_FINISH)
        }

        guard status == Z_STREAM_END else { throw LVError.parseFailed }
        return result
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractCoverHref(opfXML: String, manifest: [String: String], opfDir: String) -> String? {
        // Method 1: meta name="cover" -> manifest item
        if let coverId = firstMatch(in: opfXML, pattern: "name=\"cover\"[^>]*content=\"([^\"]+)\""),
           let href = manifest[coverId] {
            return href
        }
        // Method 2: id="cover-image"
        if let href = manifest["cover-image"] { return href }
        // Method 3: look for "cover" in id
        for (id, href) in manifest where id.lowercased().contains("cover") {
            let checkPath = (opfDir as NSString).appendingPathComponent(href)
            if FileManager.default.fileExists(atPath: checkPath) { return href }
        }
        return nil
    }

    private func extractTextFromHTML(_ htmlData: Data) -> String {
        guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .ascii) else {
            return ""
        }

        var text = html

        // Extract body content
        if let bodyRange = text.range(of: "<body[^>]*>(.*?)</body>", options: .regularExpression) {
            text = String(text[bodyRange])
        }

        // Strip scripts and styles
        text = text.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])

        // Convert HTML to text
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        text = text.replacingOccurrences(of: "</h[1-6]>", with: "\n", options: [.regularExpression, .caseInsensitive])

        // Strip all remaining tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        text = text.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
