import Foundation

struct ReadingSettings: Codable, Equatable, Hashable {
    var fontFamily: String
    var fontSize: Int
    var fontWeight: Int
    var lineSpacing: Double
    var paragraphSpacing: Double?
    var pageMarginHorizontal: Double
    var pageMarginVertical: Double
    var backgroundColor: String
    var backgroundImagePath: String?
    var backgroundImageOpacity: Double
    var brightness: Double
    var zodiacWatermark: ZodiacAnimal?
    var eyeCareFilter: EyeCareFilter
    var nightMode: Bool
    var pageFlipMode: PageFlipMode
    var autoReadEnabled: Bool
    var autoReadSpeed: Int
    var readingTheme: ReadingTheme

    // MARK: - 仿真翻页可配置参数
    /// 弯曲幅度 (0.1 ~ 1.0)
    var simulationCurlIntensity: Double
    /// 阴影透明度 (0.0 ~ 1.0)
    var simulationShadowOpacity: Double
    /// 翻页动画时长（秒）
    var simulationDuration: Double
    /// 回弹阻尼
    var simulationSpringDamping: Double

    static let `default` = ReadingSettings(
        fontFamily: "系统默认",
        fontSize: 24,
        fontWeight: 400,
        lineSpacing: 1.2,
        paragraphSpacing: 1.5,
        pageMarginHorizontal: 7.0,
        pageMarginVertical: 2.0,
        backgroundColor: "#FFFDF8",
        backgroundImagePath: Optional<String>.none,
        backgroundImageOpacity: 0.3,
        brightness: 1.0,
        zodiacWatermark: ZodiacAnimal.currentYearZodiac(),
        eyeCareFilter: EyeCareFilter.none,
        nightMode: false,
        pageFlipMode: PageFlipMode.simulation,
        autoReadEnabled: false,
        autoReadSpeed: 5,
        readingTheme: ReadingTheme.bookshelf,
        simulationCurlIntensity: 0.5,
        simulationShadowOpacity: 0.6,
        simulationDuration: 0.38,
        simulationSpringDamping: 0.55
    )

    static func applyingPadTypographyDefaults(to settings: ReadingSettings) -> ReadingSettings {
        let isBaseDefault = settings.fontSize == 24
            && settings.lineSpacing == 1.2
            && settings.paragraphSpacing == 1.5
        let isPreviousPadDefault = settings.fontSize == 32
            && settings.lineSpacing == 1.2
            && settings.paragraphSpacing == 1.6
        guard isBaseDefault || isPreviousPadDefault else { return settings }
        var updated = settings
        updated.fontSize = 28
        updated.paragraphSpacing = 1.6
        return updated
    }
}

enum EyeCareFilter: String, Codable, CaseIterable, Hashable {
    case none = "NONE"
    case warmYellow = "WARM_YELLOW"
    case mintGreen = "MINT_GREEN"

    var displayName: String {
        switch self {
        case .none: return L("冷白")
        case .warmYellow: return L("暖黄")
        case .mintGreen: return L("护眼绿")
        }
    }

    var filterColor: String {
        switch self {
        case .none: return "#FFFFFF"
        case .warmYellow: return "#FFF8E7"
        case .mintGreen: return "#C7EDCC"
        }
    }

    var overlayAlpha: Double {
        switch self {
        case .none: return 0
        case .warmYellow: return 0.22
        case .mintGreen: return 0.18
        }
    }
}

enum PageFlipMode: String, Codable, CaseIterable, Hashable {
    case simulation = "SIMULATION"
    case cover = "COVER"
    case slide = "SLIDE"
    case scroll = "SCROLL"
    case none = "NONE"

    var displayName: String {
        switch self {
        case .simulation: return L("仿真翻页")
        case .cover: return L("覆盖翻页")
        case .slide: return L("平移翻页")
        case .scroll: return L("上下滚动")
        case .none: return L("无动画")
        }
    }
}

enum ReadingTheme: String, Codable, CaseIterable, Hashable {
    case white = "WHITE"
    case warmYellow = "WARM_YELLOW"
    case mint = "MINT"
    case latte = "LATTE"
    case bookshelf = "BOOKSHELF"
    case bookshelfNight = "BOOKSHELF_NIGHT"
    case midnight = "MIDNIGHT"
    case oled = "OLED"
    case custom = "CUSTOM"

    static let lightThemes: [ReadingTheme] = [.bookshelf, .white, .warmYellow, .mint, .latte]
    static let darkThemes: [ReadingTheme] = [.bookshelfNight, .midnight, .oled]
    static let visibleThemes: [ReadingTheme] = lightThemes + darkThemes

    var isDarkAppearance: Bool {
        Self.darkThemes.contains(self)
    }

    var backgroundColor: String {
        switch self {
        case .white: return "#F7F7F5"
        case .warmYellow: return "#F4E5C8"
        case .mint: return "#DCEFE1"
        case .latte: return "#E7D2BA"
        case .bookshelf: return "#FCFAF5"
        case .bookshelfNight: return "#191D1B"
        case .midnight: return "#1B1F2B"
        case .oled: return "#000000"
        case .custom: return "#F7F7F5"
        }
    }

    var textColor: String {
        switch self {
        case .white: return "#000000"
        case .mint: return "#000000"
        case .warmYellow: return "#000000"
        case .latte: return "#000000"
        case .bookshelf: return "#000000"
        case .bookshelfNight: return "#F5F0E8"
        case .midnight: return "#C8CCD8"
        case .oled: return "#B0B0B0"
        case .custom: return "#1A1A1A"
        }
    }

    var accentColor: String {
        switch self {
        case .white: return "#465C82"
        case .oled: return "#A6B8D8"
        case .warmYellow: return "#9A4C2D"
        case .mint: return "#2F7056"
        case .latte: return "#925438"
        case .bookshelf: return "#286D65"
        case .bookshelfNight: return "#8CC4B8"
        case .midnight: return "#9BAAEB"
        case .custom: return "#FF5E3A"
        }
    }

    var panelColor: String {
        switch self {
        case .white: return "#FFFFFF"
        case .warmYellow: return "#FAF1E0"
        case .mint: return "#F0F5EE"
        case .latte: return "#F3EADF"
        case .bookshelf: return "#F1EFE7"
        case .bookshelfNight: return "#232925"
        case .midnight: return "#252B39"
        case .oled: return "#121212"
        case .custom: return "#FFFFFF"
        }
    }

    var controlSurfaceColor: String {
        switch self {
        case .white: return "#F0F0ED"
        case .warmYellow: return "#FFF8EA"
        case .mint: return "#F8FAF5"
        case .latte: return "#FAF3EA"
        case .bookshelf: return "#FFFDFA"
        case .bookshelfNight: return "#2E3630"
        case .midnight: return "#30394A"
        case .oled: return "#202020"
        case .custom: return "#FFFFFF"
        }
    }

    /// UIPageViewController 仿真翻页使用的背面色。
    /// 与正面保持同一色相，并通过轻微明度差表现纸张背面。
    var pageBackColor: String {
        switch self {
        case .white: return "#EFEFEB"
        case .warmYellow: return "#EBDDC3"
        case .mint: return "#DCE7DC"
        case .latte: return "#DFCFBC"
        case .bookshelf: return "#EFEAE0"
        case .bookshelfNight: return "#141815"
        case .midnight: return "#161A25"
        case .oled: return "#080808"
        case .custom: return backgroundColor
        }
    }

    /// 当前页文字在背面的透印强度。
    var pageBackTextOpacity: CGFloat {
        switch self {
        case .midnight, .bookshelfNight: return 0.14
        case .oled: return 0.10
        default: return 0.18
        }
    }

    var displayName: String {
        switch self {
        case .white, .custom: return L("素白")
        case .warmYellow: return L("暖黄")
        case .mint: return L("薄荷")
        case .latte: return L("拿铁")
        case .bookshelf: return L("青白")
        case .bookshelfNight: return L("青岚")
        case .midnight: return L("墨蓝")
        case .oled: return L("纯黑")
        }
    }
}
