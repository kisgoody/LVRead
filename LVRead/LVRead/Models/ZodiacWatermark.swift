import UIKit

enum ZodiacAnimal: String, Codable, CaseIterable, Hashable {
    case rat = "鼠"
    case ox = "牛"
    case tiger = "虎"
    case rabbit = "兔"
    case dragon = "龙"
    case snake = "蛇"
    case horse = "马"
    case goat = "羊"
    case monkey = "猴"
    case rooster = "鸡"
    case dog = "狗"
    case pig = "猪"

    var chineseName: String { rawValue }

    /// SF Symbol that best represents this animal for the toolbar icon
    var sfSymbol: String {
        switch self {
        case .rat: return "cursorarrow.square"
        case .ox: return "shield.fill"
        case .tiger: return "flame.fill"
        case .rabbit: return "hare.fill"
        case .dragon: return "bolt.fill"
        case .snake: return "line.diagonal"
        case .horse: return "figure.equestrian.sports"
        case .goat: return "circle.grid.cross.fill"
        case .monkey: return "figure.climbing"
        case .rooster: return "sunrise.fill"
        case .dog: return "pawprint.fill"
        case .pig: return "seal.fill"
        }
    }

    /// Returns the current year's zodiac based on Chinese lunar calendar.
    /// Uses the formula: (year - 4) % 12  (0 = Rat, 1 = Ox, ..., 11 = Pig)
    static func currentYearZodiac() -> ZodiacAnimal {
        let year = Calendar.current.component(.year, from: Date())
        let index = (year - 4) % 12
        return ZodiacAnimal.allCases[max(0, min(11, index))]
    }

    /// Load the zodiac image from Assets.xcassets/十二生肖/
    func loadImage() -> UIImage? {
        UIImage(named: "十二生肖/\(rawValue)")
    }

    /// Load image that works on older iOS (non-namespace asset folders)
    func loadImageCompat() -> UIImage? {
        if let img = loadImage() { return img }
        return UIImage(named: rawValue)
    }
}
