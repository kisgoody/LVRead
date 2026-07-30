import Foundation

/// Returns the localized UI copy for a Simplified Chinese source key.
///
/// Keeping Chinese as the key makes untranslated copy fall back to the
/// product's original wording instead of exposing an internal identifier.
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
}

/// Localizes a printf-style format before inserting its values.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}

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
