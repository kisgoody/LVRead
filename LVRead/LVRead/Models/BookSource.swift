import Foundation

enum BookSource: String, Codable, CaseIterable {
    case shareImport = "SHARE_IMPORT"
    case localFile = "LOCAL_FILE"
    case lanTransfer = "LAN_TRANSFER"

    var displayName: String {
        switch self {
        case .shareImport: return L("分享导入")
        case .localFile: return L("本地文件")
        case .lanTransfer: return L("同网传输")
        }
    }

    var displayColor: String {
        switch self {
        case .shareImport: return "#00D4AA"
        case .localFile: return "#3B82F6"
        case .lanTransfer: return "#F59E0B"
        }
    }
    
    var icon: String {
        switch self {
        case .shareImport: return "square.and.arrow.up"
        case .localFile: return "folder"
        case .lanTransfer: return "wifi"
        }
    }
}

enum FileFormat: String, Codable, CaseIterable {
    case epub = "EPUB"
    case txt = "TXT"
    case pdf = "PDF"

    var displayName: String { rawValue.uppercased() }
    
    var badgeColor: String {
        switch self {
        case .epub: return "#FF5E3A"
        case .pdf: return "#7B2FFF"
        case .txt: return "#00D4AA"
        }
    }

    var supportsShareImport: Bool { self == .txt }
    
    var icon: String {
        switch self {
        case .epub: return "book.closed.fill"
        case .pdf: return "doc.text.fill"
        case .txt: return "doc.plaintext.fill"
        }
    }
}
