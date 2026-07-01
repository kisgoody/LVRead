import Foundation

extension String {
    var containsChineseCharacters: Bool {
        range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    func truncate(maxLength: Int, ellipsis: String = "...") -> String {
        count <= maxLength ? self : String(prefix(maxLength)) + ellipsis
    }

    var sanitizedFilename: String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalidChars).joined(separator: "_")
    }
}
