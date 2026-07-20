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
        fontSize: 23,
        fontWeight: 400,
        lineSpacing: 1.3,
        paragraphSpacing: 1.5,
        pageMarginHorizontal: 7.0,
        pageMarginVertical: 2.0,
        backgroundColor: "#F5F2EC",
        backgroundImagePath: Optional<String>.none,
        backgroundImageOpacity: 0.3,
        brightness: 1.0,
        zodiacWatermark: ZodiacAnimal.currentYearZodiac(),
        eyeCareFilter: EyeCareFilter.none,
        nightMode: false,
        pageFlipMode: PageFlipMode.cover,
        autoReadEnabled: false,
        autoReadSpeed: 5,
        readingTheme: ReadingTheme.bookshelf,
        simulationCurlIntensity: 0.5,
        simulationShadowOpacity: 0.6,
        simulationDuration: 0.38,
        simulationSpringDamping: 0.55
    )
}

enum EyeCareFilter: String, Codable, CaseIterable, Hashable {
    case none = "NONE"
    case warmYellow = "WARM_YELLOW"
    case mintGreen = "MINT_GREEN"

    var displayName: String {
        switch self {
        case .none: return "冷白"
        case .warmYellow: return "暖黄"
        case .mintGreen: return "护眼绿"
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
        case .simulation: return "仿真翻页"
        case .cover: return "覆盖翻页"
        case .slide: return "平移翻页"
        case .scroll: return "上下滚动"
        case .none: return "无动画"
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
        case .white: return "#FFFFFF"
        case .warmYellow: return "#FBF0D9"
        case .mint: return "#E8F5E9"
        case .latte: return "#EFE3D3"
        case .bookshelf: return "#F5F2EC"
        case .bookshelfNight: return "#1A1410"
        case .midnight: return "#1A1D2E"
        case .oled: return "#000000"
        case .custom: return "#FFFFFF"
        }
    }

    var textColor: String {
        switch self {
        case .white, .mint: return "#1A1A1A"
        case .warmYellow: return "#3D3226"
        case .latte: return "#4A3728"
        case .bookshelf: return "#24211D"
        case .bookshelfNight: return "#F5F0E8"
        case .midnight: return "#C8CCD8"
        case .oled: return "#B0B0B0"
        case .custom: return "#1A1A1A"
        }
    }

    var accentColor: String {
        switch self {
        case .white, .oled: return "#FF5E3A"
        case .warmYellow: return "#E8784A"
        case .mint: return "#00A86B"
        case .latte: return "#C67B5C"
        case .bookshelf: return "#236D67"
        case .bookshelfNight: return "#8FD8D0"
        case .midnight: return "#7B8FFF"
        case .custom: return "#FF5E3A"
        }
    }

    var panelColor: String {
        switch self {
        case .white: return "#F7F7F5"
        case .warmYellow: return "#F4E5C8"
        case .mint: return "#DCEFE1"
        case .latte: return "#E7D2BA"
        case .bookshelf: return "#FFFDF8"
        case .bookshelfNight: return "#20231F"
        case .midnight: return "#24283A"
        case .oled: return "#111111"
        case .custom: return "#F7F7F5"
        }
    }

    var controlSurfaceColor: String {
        switch self {
        case .white: return "#FFFFFF"
        case .warmYellow: return "#FFF6E5"
        case .mint: return "#F0FAF2"
        case .latte: return "#F5E7D8"
        case .bookshelf: return "#FFFDF8"
        case .bookshelfNight: return "#292D28"
        case .midnight: return "#30364D"
        case .oled: return "#1C1C1C"
        case .custom: return "#FFFFFF"
        }
    }

    /// UIPageViewController 仿真翻页使用的背面色。
    /// 与正面保持同一色相，并通过轻微明度差表现纸张背面。
    var pageBackColor: String {
        switch self {
        case .white: return "#F2EFE8"
        case .warmYellow: return "#EAD7B5"
        case .mint: return "#D5E8D8"
        case .latte: return "#DCC4AA"
        case .bookshelf: return "#E8E0D4"
        case .bookshelfNight: return "#15110E"
        case .midnight: return "#141725"
        case .oled: return "#050505"
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
        case .white, .custom: return "素白"
        case .warmYellow: return "暖黄"
        case .mint: return "薄荷"
        case .latte: return "拿铁"
        case .bookshelf: return "青白"
        case .bookshelfNight: return "青岚"
        case .midnight: return "墨蓝"
        case .oled: return "纯黑"
        }
    }
}
