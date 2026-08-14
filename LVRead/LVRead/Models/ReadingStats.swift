import Foundation

struct ReadingStats: Codable {
    var totalBooksRead: Int
    var totalReadingTimeSeconds: Int
    var totalPagesRead: Int
    var dailyReadingMinutes: [String: Int]
    var weeklyReadingMinutes: [String: Int]

    init(totalBooksRead: Int = 0,
         totalReadingTimeSeconds: Int = 0,
         totalPagesRead: Int = 0,
         dailyReadingMinutes: [String: Int] = [:],
         weeklyReadingMinutes: [String: Int] = [:]) {
        self.totalBooksRead = totalBooksRead
        self.totalReadingTimeSeconds = totalReadingTimeSeconds
        self.totalPagesRead = totalPagesRead
        self.dailyReadingMinutes = dailyReadingMinutes
        self.weeklyReadingMinutes = weeklyReadingMinutes
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
