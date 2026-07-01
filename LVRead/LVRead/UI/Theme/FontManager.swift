import UIKit

final class FontManager {
    static let shared = FontManager()
    private init() {}

    var availableFonts: [String] {
        var fonts = ["系统默认", "宋体", "仿宋", "黑体", "楷体"]
        if let customFonts = loadCustomFonts() {
            fonts.append(contentsOf: customFonts)
        }
        return fonts
    }

    func font(named name: String, size: CGFloat) -> UIFont {
        switch name {
        case "系统默认": return .systemFont(ofSize: size)
        case "宋体": return UIFont(name: "STSongti-SC-Regular", size: size) ?? .systemFont(ofSize: size)
        case "仿宋": return UIFont(name: "STFangsong", size: size) ?? .systemFont(ofSize: size)
        case "黑体": return UIFont(name: "STHeitiSC-Light", size: size) ?? .systemFont(ofSize: size)
        case "楷体": return UIFont(name: "STKaiti", size: size) ?? .systemFont(ofSize: size)
        default:
            if let customFont = UIFont(name: name, size: size) {
                return customFont
            }
            return .systemFont(ofSize: size)
        }
    }

    func registerCustomFont(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else { return nil }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterGraphicsFont(font, &error) {
            return font.postScriptName as String?
        }
        return nil
    }

    private func loadCustomFonts() -> [String]? {
        let fontsDir = customFontsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: fontsDir) else { return nil }
        let fontFiles = files.filter { $0.hasSuffix(".ttf") || $0.hasSuffix(".otf") }
        return fontFiles.isEmpty ? nil : fontFiles.map { ($0 as NSString).deletingPathExtension }
    }

    func customFontsDirectory() -> String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let fontsDir = (docs as NSString).appendingPathComponent("CustomFonts")
        try? FileManager.default.createDirectory(atPath: fontsDir, withIntermediateDirectories: true)
        return fontsDir
    }
}
