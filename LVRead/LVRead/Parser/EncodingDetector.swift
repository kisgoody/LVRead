import Foundation

/// Detects text encoding by examining BOM and byte heuristics.
/// Handles UTF-8, UTF-16, GB18030/GBK/GB2312, and Big5.
final class EncodingDetector {

    private static let sampleSize = 4096

    // MARK: - Public API

    static func detectEncoding(filePath: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return "UTF-8" }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: sampleSize)
        guard !data.isEmpty else { return "UTF-8" }
        let bytes = [UInt8](data)

        if let bom = detectBOM(bytes) { return bom }
        if isValidUTF8(bytes) { return "UTF-8" }
        if let cjk = detectCJKEncoding(bytes) { return cjk }
        if let utf16 = detectUTF16WithoutBOM(bytes) { return utf16 }
        return "UTF-8"
    }

    /// Read entire file with robust multi-encoding fallback.
    /// For CJK files, uses NSString (CoreFoundation) which has superior
    /// Chinese encoding support compared to Swift's String.
    static func readWithEncoding(filePath: String, encoding: String) -> String? {
        let fn = (filePath as NSString).lastPathComponent
        print("[ENC] === readWithEncoding ===")
        print("[ENC] file=\(fn), detected=\(encoding)")

        // Step 1: NSString auto-detect for CJK
        if isCJK(encoding) {
            var used: UInt = 0
            let ns = try? NSString(contentsOfFile: filePath, usedEncoding: &used)
            let usedName = String.Encoding(rawValue: used).description
            print("[ENC] Step1 NSString(usedEncoding): result=\(ns != nil ? "got \(ns!.length) chars" : "nil"), usedEncoding=\(usedName)")
            if let ns = ns { return ns as String }
        }

        let nsEncoding = stringEncoding(from: encoding)

        // Step 2: String with detected encoding
        do {
            let str = try String(contentsOfFile: filePath, encoding: nsEncoding)
            print("[ENC] Step2 String(\(encoding)): SUCCESS \(str.count) chars")
            return str
        } catch {
            print("[ENC] Step2 String(\(encoding)): FAILED \(error.localizedDescription)")
        }

        // Step 3: UTF-8 fallback
        if nsEncoding != .utf8 {
            do {
                let str = try String(contentsOfFile: filePath, encoding: .utf8)
                print("[ENC] Step3 String(utf8): SUCCESS \(str.count) chars (file was actually UTF-8!)")
                return str
            } catch {
                print("[ENC] Step3 String(utf8): FAILED")
            }
        }

        // Step 4: NSString auto-detect (second attempt for non-CJK)
        var used2: UInt = 0
        let ns2 = try? NSString(contentsOfFile: filePath, usedEncoding: &used2)
        let used2Name = String.Encoding(rawValue: used2).description
        print("[ENC] Step4 NSString(usedEncoding)#2: result=\(ns2 != nil ? "got \(ns2!.length) chars" : "nil"), used=\(used2Name)")
        if let ns = ns2 { return ns as String }

        // Step 5: Raw data
        print("[ENC] Step5 Data(alwaysMapped)...")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: .alwaysMapped) else {
            print("[ENC] Step5 Data read FAILED")
            return nil
        }
        print("[ENC] Step5 Data read ok, size=\(data.count) bytes")
        let stripped = stripBOM(data)

        let ns3 = NSString(data: stripped, encoding: nsEncoding.rawValue)
        print("[ENC] Step6 NSString(data:\(encoding)): \(ns3 != nil ? "got \(ns3!.length) chars" : "nil")")
        if let ns = ns3 { return ns as String }

        // Step 6: Latin-1 last resort
        if let result = String(data: stripped, encoding: .isoLatin1) {
            print("[ENC] Step7 isoLatin1: got \(result.count) chars (fallback, may be mangled)")
            return result
        }

        print("[ENC] ALL STEPS FAILED")
        return nil
    }

    // MARK: - Private decoding

    private static func isCJK(_ encoding: String) -> Bool {
        let upper = encoding.uppercased()
        return ["GBK", "GB2312", "GB18030", "BIG5", "EUC-CN", "EUC-TW"].contains(upper)
    }

    // MARK: - BOM Detection

    private static func detectBOM(_ bytes: [UInt8]) -> String? {
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { return "UTF-8-BOM" }
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF { return "UTF-16BE" }
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE { return "UTF-16LE" }
        return nil
    }

    // MARK: - UTF-8 Validation (RFC 3629)

    private static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte <= 0x7F { i += 1; continue }
            let seqLen: Int
            if (byte & 0xE0) == 0xC0 { seqLen = 2 }
            else if (byte & 0xF0) == 0xE0 { seqLen = 3 }
            else if (byte & 0xF8) == 0xF0 { seqLen = 4 }
            else { return false }
            guard i + seqLen <= bytes.count else { break }
            for j in 1..<seqLen { if (bytes[i + j] & 0xC0) != 0x80 { return false } }
            switch seqLen {
            case 2:
                let cp = ((UInt32(byte) & 0x1F) << 6) | (UInt32(bytes[i + 1]) & 0x3F)
                if cp < 0x80 { return false }
            case 3:
                let cp = ((UInt32(byte) & 0x0F) << 12) | ((UInt32(bytes[i + 1]) & 0x3F) << 6) | (UInt32(bytes[i + 2]) & 0x3F)
                if cp < 0x0800 || (cp >= 0xD800 && cp <= 0xDFFF) { return false }
            case 4:
                let cp = ((UInt32(byte) & 0x07) << 18) | ((UInt32(bytes[i + 1]) & 0x3F) << 12) | ((UInt32(bytes[i + 2]) & 0x3F) << 6) | (UInt32(bytes[i + 3]) & 0x3F)
                if cp < 0x10000 || cp > 0x10FFFF { return false }
            default: return false
            }
            i += seqLen
        }
        return true
    }

    // MARK: - CJK Detection

    private static func detectCJKEncoding(_ bytes: [UInt8]) -> String? {
        var gbkScore = 0, big5Score = 0, totalPairs = 0, i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte <= 0x7F { i += 1; continue }
            guard i + 1 < bytes.count else { break }
            let next = bytes[i + 1]
            if byte >= 0x81 && byte <= 0xFE && next >= 0x40 && next <= 0xFE && next != 0x7F { gbkScore += 1; totalPairs += 1 }
            if byte >= 0xA1 && byte <= 0xF9 {
                if (next >= 0x40 && next <= 0x7E) || (next >= 0xA1 && next <= 0xFE) { big5Score += 1 }
            }
            i += 2
        }
        guard totalPairs > 4 else { return nil }
        return gbkScore > big5Score ? "GB18030" : "Big5"
    }

    // MARK: - UTF-16 Without BOM

    private static func detectUTF16WithoutBOM(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 2 else { return nil }
        var leZeros = 0, beZeros = 0, asciiCount = 0
        for i in stride(from: 0, to: bytes.count - 1, by: 2) {
            if bytes[i] == 0 && bytes[i + 1] != 0 && bytes[i + 1] <= 0x7F { beZeros += 1; asciiCount += 1 }
            if bytes[i + 1] == 0 && bytes[i] != 0 && bytes[i] <= 0x7F { leZeros += 1; asciiCount += 1 }
        }
        guard asciiCount > 4 else { return nil }
        if leZeros > beZeros && leZeros > asciiCount / 3 { return "UTF-16LE" }
        if beZeros > leZeros && beZeros > asciiCount / 3 { return "UTF-16BE" }
        return nil
    }

    // MARK: - Encoding name → String.Encoding

    static func stringEncoding(from name: String) -> String.Encoding {
        switch name.uppercased() {
        case "UTF-8", "UTF-8-BOM": return .utf8
        case "UTF-16BE": return .utf16BigEndian
        case "UTF-16LE": return .utf16LittleEndian
        case "GBK", "GB2312", "GB18030":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case "BIG5":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        default: return .utf8
        }
    }

    // MARK: - BOM stripping

    private static func stripBOM(_ data: Data) -> Data {
        guard data.count >= 2 else { return data }
        let prefix = data.prefix(3)
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) { return data.subdata(in: 3..<data.count) }
        if prefix.starts(with: [0xFE, 0xFF]) { return data.subdata(in: 2..<data.count) }
        if prefix.starts(with: [0xFF, 0xFE]) { return data.subdata(in: 2..<data.count) }
        return data
    }
}
