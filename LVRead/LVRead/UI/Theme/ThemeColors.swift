import UIKit

// MARK: - Brand Colors — 古色古香 (Classical Chinese Aesthetic)
extension UIColor {
    // Primary - 朱砂红 (Cinnabar Red)
    static let lvPrimary = UIColor(hex: "#C0392B")
    static let lvPrimaryLight = UIColor(hex: "#D4695E")
    static let lvPrimaryDark = UIColor(hex: "#9E2E22")

    // Secondary - 青瓷绿 (Celadon Green)
    static let lvSecondary = UIColor(hex: "#8DA47E")
    static let lvSecondaryLight = UIColor(hex: "#A8C09A")

    // Accent - 古铜金 (Bronze Gold)
    static let lvAccent = UIColor(hex: "#B8860B")
    static let lvAccentLight = UIColor(hex: "#D4A535")

    // Functional
    static let lvInfo = UIColor(hex: "#5B7EA6")
    static let lvWarning = UIColor(hex: "#D4A12A")
    static let lvError = UIColor(hex: "#C0392B")
    static let lvSuccess = UIColor(hex: "#8DA47E")

    // Background - 日间/夜间模式
    static let lvBgDay = UIColor(hex: "#F5F0E8")
    static let lvBgNight = UIColor(hex: "#1A1410")
    static let lvBgCard = UIColor(hex: "#F5F0E8")
    static let lvBgCardDark = UIColor(hex: "#2A2216")

    // Text - 墨色系
    static let lvTextPrimary = UIColor(hex: "#2C2416")
    static let lvTextSecondary = UIColor(hex: "#6B5D4F")
    static let lvTextTertiary = UIColor(hex: "#8C7E6F")
    static let lvTextPrimaryDark = UIColor(hex: "#F5F0E8")
    static let lvTextSecondaryDark = UIColor(hex: "#A89984")

    // Surface colors
    static let lvSurface = UIColor(hex: "#F5F0E8")
    static let lvSurfaceSecondary = UIColor(hex: "#EDE5D8")
    static let lvSurfaceElevated = UIColor(hex: "#F5F0E8")
    static let lvSurfaceDark = UIColor(hex: "#1E1812")
    static let lvSurfaceSecondaryDark = UIColor(hex: "#2A2216")

    // Divider / Border
    static let lvDivider = UIColor(hex: "#D4C9B5")
    static let lvDividerDark = UIColor(hex: "#3D3020")

    // Overlay
    static let lvOverlay = UIColor.black.withAlphaComponent(0.5)
    static let lvOverlayLight = UIColor.black.withAlphaComponent(0.3)

    // Category gradient colors
    static let categoryNovelStart = UIColor(hex: "#C0392B")
    static let categoryNovelEnd = UIColor(hex: "#D4695E")
    static let categoryTechStart = UIColor(hex: "#5B7EA6")
    static let categoryTechEnd = UIColor(hex: "#8DAFD1")
    static let categoryLitStart = UIColor(hex: "#B8860B")
    static let categoryLitEnd = UIColor(hex: "#D4A12A")
    static let categoryMagStart = UIColor(hex: "#8B6BAE")
    static let categoryMagEnd = UIColor(hex: "#B09CD4")

    // Semantic colors
    static let lvPrimaryText = UIColor(hex: "#2C2416")
    static let lvSecondaryText = UIColor(hex: "#6B5D4F")
    static let lvTertiaryText = UIColor(hex: "#8C7E6F")
    static let lvPrimaryBackground = UIColor(hex: "#F5F0E8")
    static let lvSecondaryBackground = UIColor(hex: "#F0EAD9")
    static let lvTertiaryBackground = UIColor(hex: "#EDE5D8")

    // Navigation bar
    static let navGradientStart = UIColor(hex: "#C0392B")
    static let navGradientEnd = UIColor(hex: "#D4695E")

    // Reading theme presets
    static let readingBgWhite = UIColor(hex: "#F5F0E8")
    static let readingBgWarmYellow = UIColor(hex: "#F2E8D5")
    static let readingBgMint = UIColor(hex: "#E0EAE0")
    static let readingBgLatte = UIColor(hex: "#EBDFD0")
    static let readingBgMidnight = UIColor(hex: "#1A1410")
    static let readingBgOLED = UIColor(hex: "#000000")

    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexSanitized.hasPrefix("#") { hexSanitized.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: nil)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    var isDark: Bool { luminance < 0.5 }

    func textColorForBackground() -> UIColor {
        isDark ? .white : .lvTextPrimary
    }

    var contrastingTextColor: UIColor {
        return isDark ? UIColor.white : UIColor(hex: "#2C2416")
    }

    func lighter(by percentage: CGFloat = 0.2) -> UIColor {
        return adjustBrightness(by: abs(percentage))
    }

    func darker(by percentage: CGFloat = 0.2) -> UIColor {
        return adjustBrightness(by: -abs(percentage))
    }

    private func adjustBrightness(by percentage: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            let newBrightness = max(min(b + percentage, 1.0), 0.0)
            return UIColor(hue: h, saturation: s, brightness: newBrightness, alpha: a)
        }
        return self
    }
}

// MARK: - Dark Mode Support
extension UIColor {
    static func adaptiveColor(light: UIColor, dark: UIColor) -> UIColor {
        return UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }

    static var lvAdaptiveBackground: UIColor {
        return adaptiveColor(light: lvBgDay, dark: lvBgNight)
    }

    static var lvAdaptiveTextPrimary: UIColor {
        return adaptiveColor(light: lvTextPrimary, dark: lvTextPrimaryDark)
    }

    static var lvAdaptiveTextSecondary: UIColor {
        return adaptiveColor(light: lvTextSecondary, dark: lvTextSecondaryDark)
    }

    static var lvAdaptiveSurface: UIColor {
        return adaptiveColor(light: lvSurface, dark: lvSurfaceDark)
    }

    static var lvAdaptiveSurfaceSecondary: UIColor {
        return adaptiveColor(light: lvSurfaceSecondary, dark: lvSurfaceSecondaryDark)
    }

    static var lvAdaptiveDivider: UIColor {
        return adaptiveColor(light: lvDivider, dark: lvDividerDark)
    }
}

// MARK: - Simple Global Logger (Debug only)
#if DEBUG
func LVLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function): \(message)")
}
#else
func LVLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    // Release builds: no-op
}
#endif
