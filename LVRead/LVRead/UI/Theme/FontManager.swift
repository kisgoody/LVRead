import UIKit

final class FontManager {
    static let shared = FontManager()
    private init() {}

    var availableFonts: [String] {
        var fonts = [L("系统默认"), L("宋体"), L("仿宋"), L("黑体"), L("楷体")]
        if let customFonts = loadCustomFonts() {
            fonts.append(contentsOf: customFonts)
        }
        return fonts
    }

    func font(named name: String, size: CGFloat) -> UIFont {
        if ["系统默认", "System"].contains(name) {
            return firstAvailable(["PingFangSC-Regular"], size: size) ?? .systemFont(ofSize: size)
        }
        if ["宋体", "Song"].contains(name) {
            return firstAvailable(["STSongti-SC-Regular", "Songti SC"], size: size) ?? designedFont(.serif, size: size)
        }
        if ["仿宋", "Fang Song"].contains(name) {
            return firstAvailable(["STFangsong", "FangSong", "STSong"], size: size)
            ?? transformedSongti(size: size, scaleX: 0.92, shear: 0)
        }
        if ["黑体", "Hei"].contains(name) {
            return UIFont(name: "STHeitiSC-Light", size: size) ?? .systemFont(ofSize: size)
        }
        if ["楷体", "Kai"].contains(name) {
            return firstAvailable(["STKaiti", "Kaiti SC", "STKaitiSC-Regular"], size: size)
            ?? transformedSongti(size: size, scaleX: 1, shear: -0.16)
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
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
