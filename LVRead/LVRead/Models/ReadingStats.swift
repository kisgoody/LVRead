import Foundation

struct ReadingStats: Codable {
    var totalBooksRead: Int
    var totalReadingTimeSeconds: Int
    var totalPagesRead: Int
    var totalCharactersRead: Int
    var dailyReadingMinutes: [String: Int]
    var weeklyReadingMinutes: [String: Int]

    init(totalBooksRead: Int = 0,
         totalReadingTimeSeconds: Int = 0,
         totalPagesRead: Int = 0,
         totalCharactersRead: Int = 0,
         dailyReadingMinutes: [String: Int] = [:],
         weeklyReadingMinutes: [String: Int] = [:]) {
        self.totalBooksRead = totalBooksRead
        self.totalReadingTimeSeconds = totalReadingTimeSeconds
        self.totalPagesRead = totalPagesRead
        self.totalCharactersRead = totalCharactersRead
        self.dailyReadingMinutes = dailyReadingMinutes
        self.weeklyReadingMinutes = weeklyReadingMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case totalBooksRead
        case totalReadingTimeSeconds
        case totalPagesRead
        case totalCharactersRead
        case dailyReadingMinutes
        case weeklyReadingMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalBooksRead = try container.decodeIfPresent(Int.self, forKey: .totalBooksRead) ?? 0
        totalReadingTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .totalReadingTimeSeconds) ?? 0
        totalPagesRead = try container.decodeIfPresent(Int.self, forKey: .totalPagesRead) ?? 0
        totalCharactersRead = try container.decodeIfPresent(Int.self, forKey: .totalCharactersRead) ?? 0
        dailyReadingMinutes = try container.decodeIfPresent([String: Int].self, forKey: .dailyReadingMinutes) ?? [:]
        weeklyReadingMinutes = try container.decodeIfPresent([String: Int].self, forKey: .weeklyReadingMinutes) ?? [:]
    }

    var totalReadingHours: Double {
        Double(totalReadingTimeSeconds) / 3600.0
    }

    var averageMinutesPerDay: Double {
        guard !dailyReadingMinutes.isEmpty else { return 0 }
        let total = dailyReadingMinutes.values.reduce(0, +)
        return Double(total) / Double(dailyReadingMinutes.count)
    }
}
