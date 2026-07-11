import Foundation

// MARK: - Reading Stats Repository

final class ReadingStatsRepository {
    
    // MARK: - Singleton
    
    static let shared = ReadingStatsRepository()
    
    private let defaults = UserDefaults.standard
    private let statsKey = "reading_stats"
    private let bookStatsKey = "reading_stats_by_book"
    private let minuteRemainderKey = "reading_stats_minute_remainder_seconds"
    
    private init() {}
    
    // MARK: - Public API
    
    func getStats() -> ReadingStats {
        guard let data = defaults.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(ReadingStats.self, from: data) else {
            return ReadingStats()
        }
        return stats
    }
    
    func save(_ stats: ReadingStats) {
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: statsKey)
        }
    }
    
    func updateStats(_ update: (inout ReadingStats) -> Void) {
        var stats = getStats()
        update(&stats)
        save(stats)
    }
    
    // MARK: - Statistics Update Methods
    
    /// Add reading time in seconds
    func addReadingTime(_ seconds: Int) {
        guard seconds > 0 else { return }
        updateStats { stats in
            stats.totalReadingTimeSeconds += seconds
        }
        let accumulatedSeconds = defaults.integer(forKey: minuteRemainderKey) + seconds
        let wholeMinutes = accumulatedSeconds / 60
        defaults.set(accumulatedSeconds % 60, forKey: minuteRemainderKey)
        updateDailyMinutes(minutes: wholeMinutes)
        updateWeeklyMinutes(minutes: wholeMinutes)
    }
    
    /// Record pages read
    func addPagesRead(_ pages: Int) {
        guard pages > 0 else { return }
        updateStats { stats in
            stats.totalPagesRead += pages
        }
    }

    func recordSession(bookId: String, seconds: Int, pages: Int) {
        let safeSeconds = max(0, seconds)
        let safePages = max(0, pages)
        addReadingTime(safeSeconds)
        addPagesRead(safePages)

        var values = getBookStats()
        var value = values[bookId] ?? BookReadingStat()
        value.readingTimeSeconds += safeSeconds
        value.pagesRead += safePages
        value.lastReadAt = Date()
        values[bookId] = value
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: bookStatsKey)
        }
    }

    func getBookStats() -> [String: BookReadingStat] {
        guard let data = defaults.data(forKey: bookStatsKey),
              let values = try? JSONDecoder().decode([String: BookReadingStat].self, from: data) else {
            return [:]
        }
        return values
    }
    
    /// Mark a book as finished
    func markBookFinished() {
        updateStats { stats in
            stats.totalBooksRead += 1
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateDailyMinutes(minutes: Int) {
        guard minutes > 0 else { return }
        
        let today = dateString(from: Date())
        
        updateStats { stats in
            let current = stats.dailyReadingMinutes[today] ?? 0
            stats.dailyReadingMinutes[today] = current + minutes
            
            // Keep only last 30 days
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            stats.dailyReadingMinutes = stats.dailyReadingMinutes.filter { key, _ in
                guard let date = dateFromString(key) else { return false }
                return date >= thirtyDaysAgo
            }
        }
    }
    
    private func updateWeeklyMinutes(minutes: Int) {
        guard minutes > 0 else { return }
        
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.year, from: Date())
        let key = "\(year)-W\(weekOfYear)"
        
        updateStats { stats in
            let current = stats.weeklyReadingMinutes[key] ?? 0
            stats.weeklyReadingMinutes[key] = current + minutes
            
            // Keep only last 12 weeks
            let twelveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -12, to: Date())!
            stats.weeklyReadingMinutes = stats.weeklyReadingMinutes.filter { key, _ in
                guard let weekStart = parseWeekKey(key) else { return false }
                return weekStart >= twelveWeeksAgo
            }
        }
    }
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
    
    private func parseWeekKey(_ key: String) -> Date? {
        // Simple parsing - returns a date within the week
        let parts = key.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }
        
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.weekOfYear = week
        return calendar.date(from: dateComponents)
    }
}

struct BookReadingStat: Codable, Equatable {
    var readingTimeSeconds: Int = 0
    var pagesRead: Int = 0
    var lastReadAt: Date = .distantPast
}

// MARK: - Reading Analytics

struct ReadingAnalytics {
    
    let stats: ReadingStats
    
    // MARK: - Summary Stats
    
    var totalReadingTimeFormatted: String {
        let hours = stats.totalReadingTimeSeconds / 3600
        let minutes = (stats.totalReadingTimeSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)小时 \(minutes)分钟"
        }
        return "\(minutes)分钟"
    }
    
    var totalBooksRead: Int {
        stats.totalBooksRead
    }
    
    var totalPagesRead: Int {
        stats.totalPagesRead
    }
    
    // MARK: - Daily Stats
    
    var todayReadingMinutes: Int {
        let today = dateString(from: Date())
        return stats.dailyReadingMinutes[today] ?? 0
    }
    
    var weeklyReadingMinutes: Int {
        let calendar = Calendar.current
        let today = Date()
        var total = 0
        
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let key = dateString(from: date)
                total += stats.dailyReadingMinutes[key] ?? 0
            }
        }
        return total
    }
    
    var monthlyReadingMinutes: Int {
        let calendar = Calendar.current
        let today = Date()
        var total = 0
        
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let key = dateString(from: date)
                total += stats.dailyReadingMinutes[key] ?? 0
            }
        }
        return total
    }
    
    // MARK: - Streaks
    
    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var date = Date()
        
        while true {
            let key = dateString(from: date)
            if let minutes = stats.dailyReadingMinutes[key], minutes > 0 {
                streak += 1
                date = calendar.date(byAdding: .day, value: -1, to: date)!
            } else {
                break
            }
        }
        
        return streak
    }
    
    var longestStreak: Int {
        guard !stats.dailyReadingMinutes.isEmpty else { return 0 }
        
        let sortedDates = stats.dailyReadingMinutes.keys.sorted()
        var maxStreak = 0
        var currentStreak = 0
        var previousDate: Date?
        
        let calendar = Calendar.current
        
        for dateString in sortedDates {
            guard let date = dateFromString(dateString) else { continue }
            
            if let prev = previousDate {
                let daysDiff = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if daysDiff == 1 {
                    currentStreak += 1
                } else {
                    maxStreak = max(maxStreak, currentStreak)
                    currentStreak = 1
                }
            } else {
                currentStreak = 1
            }
            
            previousDate = date
        }
        
        return max(maxStreak, currentStreak)
    }
    
    // MARK: - Charts Data
    
    var weeklyChartData: [(date: String, minutes: Int)] {
        let calendar = Calendar.current
        let today = Date()
        
        var result: [(String, Int)] = []
        
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let key = dateString(from: date)
                let minutes = stats.dailyReadingMinutes[key] ?? 0
                
                let formatter = DateFormatter()
                formatter.dateFormat = "MM/dd"
                result.append((formatter.string(from: date), minutes))
            }
        }
        
        return result
    }
    
    // MARK: - Helpers
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

// MARK: - Reading Stats View Model

final class ReadingStatsViewModel: ObservableObject {
    
    @Published private(set) var analytics: ReadingAnalytics?
    @Published private(set) var isLoading: Bool = false
    
    func loadAnalytics() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stats = ReadingStatsRepository.shared.getStats()
            let analytics = ReadingAnalytics(stats: stats)
            
            DispatchQueue.main.async {
                self?.analytics = analytics
                self?.isLoading = false
            }
        }
    }
    
    func refresh() {
        loadAnalytics()
    }
}
