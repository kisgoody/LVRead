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
        case "系统默认": return firstAvailable(["PingFangSC-Regular"], size: size) ?? .systemFont(ofSize: size)
        case "宋体": return firstAvailable(["STSongti-SC-Regular", "Songti SC"], size: size) ?? designedFont(.serif, size: size)
        case "仿宋": return firstAvailable(["STFangsong", "FangSong", "STSong"], size: size)
            ?? transformedSongti(size: size, scaleX: 0.92, shear: 0)
        case "黑体": return UIFont(name: "STHeitiSC-Light", size: size) ?? .systemFont(ofSize: size)
        case "楷体": return firstAvailable(["STKaiti", "Kaiti SC", "STKaitiSC-Regular"], size: size)
            ?? transformedSongti(size: size, scaleX: 1, shear: -0.16)
        default:
            if let customFont = UIFont(name: name, size: size) {
                return customFont
            }
            return .systemFont(ofSize: size)
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
