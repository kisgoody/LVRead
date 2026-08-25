import UIKit

final class FontManager {
    enum Category: Int, CaseIterable {
        case chinese
        case english

        var title: String {
            switch self {
            case .chinese: return L("中文")
            case .english: return "English"
            }
        }
    }

    struct Option {
        let id: String
        let title: String
    }

    static let shared = FontManager()
    private init() {}

    private let chineseOptions = [
        Option(id: "system-zh", title: L("系统默认")),
        Option(id: "pingfang-sc", title: L("苹方简体")),
        Option(id: "pingfang-tc", title: L("苹方繁体")),
        Option(id: "songti-sc", title: L("宋体")),
        Option(id: "fangsong-sc", title: L("仿宋")),
        Option(id: "heiti-sc", title: L("黑体")),
        Option(id: "kaiti-sc", title: L("楷体"))
    ]

    private let englishOptions = [
        Option(id: "system-en", title: L("系统默认")),
        Option(id: "sf-pro", title: "SF Pro"),
        Option(id: "new-york", title: "New York"),
        Option(id: "georgia", title: "Georgia"),
        Option(id: "avenir-next", title: "Avenir Next"),
        Option(id: "helvetica-neue", title: "Helvetica Neue")
    ]

    func options(for category: Category) -> [Option] {
        let systemOptions = category == .chinese ? chineseOptions : englishOptions
        let customOptions = (loadCustomFonts() ?? []).map {
            Option(id: "custom:\($0)", title: $0)
        }
        return systemOptions + customOptions
    }

    func category(for name: String) -> Category {
        let id = normalizedIdentifier(name)
        return englishOptions.contains(where: { $0.id == id }) ? .english : .chinese
    }

    func isSelected(_ name: String, option: Option) -> Bool {
        normalizedIdentifier(name) == option.id
    }

    func isSelected(_ name: String, displayName: String) -> Bool {
        normalizedIdentifier(name) == normalizedIdentifier(displayName)
    }

    var availableFonts: [String] {
        var fonts = [L("系统默认"), L("宋体"), L("仿宋"), L("黑体"), L("楷体")]
        if let customFonts = loadCustomFonts() {
            fonts.append(contentsOf: customFonts)
        }
        return fonts
    }

    func font(named name: String, size: CGFloat) -> UIFont {
        switch normalizedIdentifier(name) {
        case "system-zh", "system-en":
            return .systemFont(ofSize: size)
        case "pingfang-sc":
            return firstAvailable(["PingFangSC-Regular"], size: size) ?? .systemFont(ofSize: size)
        case "pingfang-tc":
            return firstAvailable(["PingFangTC-Regular", "PingFangHK-Regular"], size: size)
                ?? firstAvailable(["PingFangSC-Regular"], size: size)
                ?? .systemFont(ofSize: size)
        case "songti-sc":
            return firstAvailable(["STSongti-SC-Regular", "Songti SC"], size: size) ?? designedFont(.serif, size: size)
        case "fangsong-sc":
            return firstAvailable(["STFangsong", "FangSong", "STSong"], size: size)
            ?? transformedSongti(size: size, scaleX: 0.92, shear: 0)
        case "heiti-sc":
            return UIFont(name: "STHeitiSC-Light", size: size) ?? .systemFont(ofSize: size)
        case "kaiti-sc":
            return firstAvailable(["STKaiti", "Kaiti SC", "STKaitiSC-Regular"], size: size)
            ?? transformedSongti(size: size, scaleX: 1, shear: -0.16)
        case "sf-pro":
            return .systemFont(ofSize: size)
        case "new-york":
            return designedFont(.serif, size: size)
        case "georgia":
            return firstAvailable(["Georgia"], size: size) ?? designedFont(.serif, size: size)
        case "avenir-next":
            return firstAvailable(["AvenirNext-Regular"], size: size) ?? .systemFont(ofSize: size)
        case "helvetica-neue":
            return firstAvailable(["HelveticaNeue"], size: size) ?? .systemFont(ofSize: size)
        default:
            let customName = name.hasPrefix("custom:") ? String(name.dropFirst("custom:".count)) : name
            return UIFont(name: customName, size: size) ?? .systemFont(ofSize: size)
        }
    }

    private func normalizedIdentifier(_ name: String) -> String {
        switch name {
        case "系统默认", "System": return "system-zh"
        case "苹方简体", "PingFang SC": return "pingfang-sc"
        case "苹方繁体", "PingFang TC": return "pingfang-tc"
        case "宋体", "Song": return "songti-sc"
        case "仿宋", "Fang Song": return "fangsong-sc"
        case "黑体", "Hei": return "heiti-sc"
        case "楷体", "Kai": return "kaiti-sc"
        default: return name
        }
    }

    private func firstAvailable(_ names: [String], size: CGFloat) -> UIFont? {
        names.lazy.compactMap { UIFont(name: $0, size: size) }.first
    }

    private func designedFont(
        _ design: UIFontDescriptor.SystemDesign,
        size: CGFloat,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        descriptor = descriptor.withDesign(design) ?? descriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    private func transformedSongti(size: CGFloat, scaleX: CGFloat, shear: CGFloat) -> UIFont {
        let base = firstAvailable(["STSongti-SC-Light", "STSongti-SC-Regular", "Songti SC"], size: size)
            ?? designedFont(.serif, size: size)
        let matrix = CGAffineTransform(a: scaleX, b: 0, c: shear, d: 1, tx: 0, ty: 0)
        return UIFont(descriptor: base.fontDescriptor.withMatrix(matrix), size: size)
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
