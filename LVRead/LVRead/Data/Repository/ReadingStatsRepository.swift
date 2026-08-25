import Foundation

struct ReadingPaceSummary: Equatable {
    let effectiveSeconds: Int
    let paceSeconds: Int
    let pages: Int
    let words: Int

    var wordsPerMinute: Int? {
        ReadingPace.wordsPerMinute(words: words, effectiveSeconds: paceSeconds)
    }
}

struct ReadingPacePoint: Equatable {
    let date: Date
    let summary: ReadingPaceSummary
}

enum ReadingPace {
    static let minimumEffectiveSeconds = 60

    static func wordsPerMinute(words: Int, effectiveSeconds: Int) -> Int? {
        guard words > 0, effectiveSeconds >= minimumEffectiveSeconds else { return nil }
        return Int((Double(words) * 60 / Double(effectiveSeconds)).rounded())
    }
}

// MARK: - Reading Stats Repository

final class ReadingStatsRepository {
    
    // MARK: - Singleton
    
    static let shared = ReadingStatsRepository()
    
    private let defaults: UserDefaults
    private let statsKey = "reading_stats"
    private let bookStatsKey = "reading_stats_by_book"
    private let minuteRemainderKey = "reading_stats_minute_remainder_seconds"
    private let hourlySecondsKey = "reading_stats_hourly_seconds"
    private let hourlyPaceSecondsKey = "reading_stats_hourly_pace_seconds"
    private let dailyPagesKey = "reading_stats_daily_pages"
    private let hourlyPagesKey = "reading_stats_hourly_pages"
    private let dailyCharactersKey = "reading_stats_daily_characters"
    private let hourlyCharactersKey = "reading_stats_hourly_characters"
    private let wordCountRuleVersionKey = "reading_stats_word_count_rule_version"
    private static let currentWordCountRuleVersion = 3
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateWordCountRuleIfNeeded()
    }
    
    // MARK: - Public API

    static func readableCharacterCount(in text: String) -> Int {
        let plainText = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        ).precomposedStringWithCanonicalMapping
        let pattern = #"(?=[\p{Latin}0-9]*\p{Latin})[\p{Latin}0-9]+(?:[.'’\-][\p{Latin}0-9]+)*|[0-9]+(?:[.,][0-9]+)*|\p{Han}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(
            in: plainText,
            range: NSRange(plainText.startIndex..., in: plainText)
        )
    }
    
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
    func addPagesRead(_ pages: Int, at date: Date = Date()) {
        guard pages > 0 else { return }
        updateStats { stats in
            stats.totalPagesRead += pages
        }
        addPageBreakdown(pages, at: date)
    }

    /// Record visible, non-whitespace characters read.
    func addCharactersRead(_ characters: Int, at date: Date = Date()) {
        guard characters > 0 else { return }
        updateStats { stats in
            stats.totalCharactersRead += characters
        }
        addCharacterBreakdown(characters, at: date)
    }

    func recordPageRead(bookId: String, characters: Int = 0, at date: Date = Date()) {
        let safeCharacters = max(0, characters)
        addPagesRead(1, at: date)
        addCharactersRead(safeCharacters, at: date)
        var values = getBookStats()
        var value = values[bookId] ?? BookReadingStat()
        value.pagesRead += 1
        value.charactersRead += safeCharacters
        var daily = value.daily[dateString(from: date)] ?? BookReadingDailyStat()
        daily.pagesRead += 1
        daily.charactersRead += safeCharacters
        value.daily[dateString(from: date)] = daily
        value.lastReadAt = date
        values[bookId] = value
        persistBookStats(values)
    }

    func recordSession(
        bookId: String,
        seconds: Int,
        pages: Int,
        characters: Int = 0,
        at date: Date = Date()
    ) {
        let safeSeconds = max(0, seconds)
        let safePages = max(0, pages)
        let safeCharacters = max(0, characters)
        addReadingTime(safeSeconds)
        addPagesRead(safePages)
        addCharactersRead(safeCharacters)

        var values = getBookStats()
        var value = values[bookId] ?? BookReadingStat()
        value.readingTimeSeconds += safeSeconds
        value.pagesRead += safePages
        value.charactersRead += safeCharacters
        var daily = value.daily[dateString(from: date)] ?? BookReadingDailyStat()
        daily.readingTimeSeconds += safeSeconds
        daily.pagesRead += safePages
        daily.charactersRead += safeCharacters
        value.daily[dateString(from: date)] = daily
        value.lastReadAt = date
        values[bookId] = value
        persistBookStats(values)
    }

    /// Records an active foreground reading interval and distributes it across
    /// every clock hour it overlaps. Background and lock-screen intervals must
    /// be paused by the caller and are therefore never included here.
    func recordActiveInterval(
        bookId: String,
        from start: Date,
        to end: Date,
        pages: Int,
        characters: Int = 0,
        countsTowardPace: Bool = true
    ) {
        guard end > start else {
            if pages > 0 { addPagesRead(pages) }
            if characters > 0 { addCharactersRead(characters) }
            return
        }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        recordSession(
            bookId: bookId,
            seconds: seconds,
            pages: pages,
            characters: characters,
            at: start
        )
        addHourlyReadingTime(from: start, to: end)
        guard countsTowardPace, seconds > 0 else { return }
        addHourlyPaceTime(from: start, to: end)
        var values = getBookStats()
        var value = values[bookId] ?? BookReadingStat()
        value.paceReadingTimeSeconds += seconds
        var daily = value.daily[dateString(from: start)] ?? BookReadingDailyStat()
        daily.paceReadingTimeSeconds += seconds
        value.daily[dateString(from: start)] = daily
        values[bookId] = value
        persistBookStats(values)
    }

    func hourlyReadingMinutes(for date: Date = Date()) -> [Double] {
        let prefix = hourlyDateKey(from: date) + "-"
        let values = hourlySeconds()
        return (0..<24).map { hour in
            Double(values[prefix + String(format: "%02d", hour)] ?? 0) / 60.0
        }
    }

    /// Chronological dates with precise hourly data or legacy daily totals.
    func hourlyReadingDates() -> [Date] {
        var keys = Set(hourlySeconds().keys.map { String($0.prefix(10)) })
        keys.formUnion(hourlyPaceSeconds().keys.map { String($0.prefix(10)) })
        for (key, minutes) in getStats().dailyReadingMinutes where minutes > 0 {
            keys.insert(key)
        }
        for (key, pages) in dailyPages() where pages > 0 {
            keys.insert(key)
        }
        for (key, pages) in hourlyPages() where pages > 0 {
            keys.insert(String(key.prefix(10)))
        }
        for (key, characters) in dailyCharacters() where characters > 0 {
            keys.insert(key)
        }
        for (key, characters) in hourlyCharacters() where characters > 0 {
            keys.insert(String(key.prefix(10)))
        }
        let dates = keys.compactMap(dateFromString).sorted()
        return dates.isEmpty ? [Calendar.current.startOfDay(for: Date())] : dates
    }

    func totalReadingMinutes(for date: Date) -> Double {
        let hourlyTotal = hourlyReadingMinutes(for: date).reduce(0, +)
        if hourlyTotal > 0 { return hourlyTotal }
        return Double(getStats().dailyReadingMinutes[hourlyDateKey(from: date)] ?? 0)
    }

    /// Integer values shared by the chart, point details and summary cards.
    func displayedHourlyMinutes(for date: Date) -> [Int] {
        hourlyReadingMinutes(for: date).map { Int(max($0, 0).rounded()) }
    }

    func displayedReadingMinutes(for date: Date) -> Int {
        let hourly = displayedHourlyMinutes(for: date)
        let hourlyTotal = hourly.reduce(0, +)
        if hourlyTotal > 0 { return hourlyTotal }
        return getStats().dailyReadingMinutes[hourlyDateKey(from: date)] ?? 0
    }

    func displayedHourlyPages(for date: Date) -> [Int] {
        let prefix = hourlyDateKey(from: date) + "-"
        let values = hourlyPages()
        return (0..<24).map { hour in
            values[prefix + String(format: "%02d", hour)] ?? 0
        }
    }

    func displayedReadingPages(for date: Date) -> Int {
        let hourlyTotal = displayedHourlyPages(for: date).reduce(0, +)
        if hourlyTotal > 0 { return hourlyTotal }
        return dailyPages()[hourlyDateKey(from: date)] ?? 0
    }

    func displayedHourlyCharacters(for date: Date) -> [Int] {
        let prefix = hourlyDateKey(from: date) + "-"
        let values = hourlyCharacters()
        return (0..<24).map { hour in
            values[prefix + String(format: "%02d", hour)] ?? 0
        }
    }

    func displayedReadingCharacters(for date: Date) -> Int {
        let hourlyTotal = displayedHourlyCharacters(for: date).reduce(0, +)
        if hourlyTotal > 0 { return hourlyTotal }
        return dailyCharacters()[hourlyDateKey(from: date)] ?? 0
    }

    func displayedHourlyPaceSeconds(for date: Date) -> [Int] {
        let prefix = hourlyDateKey(from: date) + "-"
        let values = hourlyPaceSeconds()
        return (0..<24).map { hour in
            values[prefix + String(format: "%02d", hour)] ?? 0
        }
    }

    func readingPaceSummary(for date: Date) -> ReadingPaceSummary {
        let preciseSeconds = hourlySeconds().reduce(0) { result, item in
            result + (item.key.hasPrefix(hourlyDateKey(from: date) + "-") ? item.value : 0)
        }
        return ReadingPaceSummary(
            effectiveSeconds: preciseSeconds > 0
                ? preciseSeconds
                : displayedReadingMinutes(for: date) * 60,
            paceSeconds: displayedHourlyPaceSeconds(for: date).reduce(0, +),
            pages: displayedReadingPages(for: date),
            words: displayedReadingCharacters(for: date)
        )
    }

    func readingPaceSummary(lastDays: Int?, endingAt endDate: Date = Date()) -> ReadingPaceSummary {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        let startDay = lastDays.flatMap {
            calendar.date(byAdding: .day, value: -max($0 - 1, 0), to: endDay)
        }
        let aggregate = hourlyReadingDates().filter { date in
            date <= endDay && (startDay.map { date >= $0 } ?? true)
        }.map { readingPaceSummary(for: $0) }.reduce(
            ReadingPaceSummary(effectiveSeconds: 0, paceSeconds: 0, pages: 0, words: 0)
        ) { result, summary in
            ReadingPaceSummary(
                effectiveSeconds: result.effectiveSeconds + summary.effectiveSeconds,
                paceSeconds: result.paceSeconds + summary.paceSeconds,
                pages: result.pages + summary.pages,
                words: result.words + summary.words
            )
        }
        guard lastDays == nil else { return aggregate }
        let stats = getStats()
        return ReadingPaceSummary(
            effectiveSeconds: max(aggregate.effectiveSeconds, stats.totalReadingTimeSeconds),
            paceSeconds: aggregate.paceSeconds,
            pages: max(aggregate.pages, stats.totalPagesRead),
            words: max(aggregate.words, stats.totalCharactersRead)
        )
    }

    func readingPacePoints(lastDays: Int?, endingAt endDate: Date = Date()) -> [ReadingPacePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: endDate)
        let start = lastDays.flatMap {
            calendar.date(byAdding: .day, value: -max($0 - 1, 0), to: today)
        }
        let paceDateKeys = Set(hourlyPaceSeconds().keys.map { String($0.prefix(10)) })
            .union(hourlyCharacters().keys.map { String($0.prefix(10)) })
        var dates = paceDateKeys.compactMap(dateFromString).filter { date in
            date < today
                && (start.map { date >= $0 } ?? true)
                && readingPaceSummary(for: date).wordsPerMinute != nil
        }
        dates.append(today)

        return dates.sorted().map {
            ReadingPacePoint(date: $0, summary: readingPaceSummary(for: $0))
        }
    }

    func readingTimeDistribution(lastDays: Int?, endingAt endDate: Date = Date()) -> (minutes: [Double], paceSeconds: [Int], pages: [Int], characters: [Int]) {
        let calendar = Calendar.current
        let endKey = hourlyDateKey(from: endDate)
        let startKey = lastDays.flatMap {
            calendar.date(byAdding: .day, value: -max($0 - 1, 0), to: endDate)
        }.map(hourlyDateKey)
        var secondsByHour = Array(repeating: 0, count: 24)
        var paceSecondsByHour = Array(repeating: 0, count: 24)
        var pagesByHour = Array(repeating: 0, count: 24)
        var charactersByHour = Array(repeating: 0, count: 24)

        for (key, seconds) in hourlySeconds() where isDateKey(String(key.prefix(10)), startingAt: startKey, endingAt: endKey) {
            if let hour = Int(key.suffix(2)), secondsByHour.indices.contains(hour) {
                secondsByHour[hour] += seconds
            }
        }
        for (key, seconds) in hourlyPaceSeconds() where isDateKey(String(key.prefix(10)), startingAt: startKey, endingAt: endKey) {
            if let hour = Int(key.suffix(2)), paceSecondsByHour.indices.contains(hour) {
                paceSecondsByHour[hour] += seconds
            }
        }
        for (key, pages) in hourlyPages() where isDateKey(String(key.prefix(10)), startingAt: startKey, endingAt: endKey) {
            if let hour = Int(key.suffix(2)), pagesByHour.indices.contains(hour) {
                pagesByHour[hour] += pages
            }
        }
        for (key, characters) in hourlyCharacters() where isDateKey(String(key.prefix(10)), startingAt: startKey, endingAt: endKey) {
            if let hour = Int(key.suffix(2)), charactersByHour.indices.contains(hour) {
                charactersByHour[hour] += characters
            }
        }
        return (secondsByHour.map { Double($0) / 60 }, paceSecondsByHour, pagesByHour, charactersByHour)
    }

    func hasReadingTimeDistributionBeyondSevenDays(endingAt endDate: Date = Date()) -> Bool {
        guard let startDate = Calendar.current.date(byAdding: .day, value: -6, to: endDate) else { return false }
        let startKey = hourlyDateKey(from: startDate)
        return hourlySeconds().keys.contains { String($0.prefix(10)) < startKey }
            || hourlyPaceSeconds().keys.contains { String($0.prefix(10)) < startKey }
            || hourlyPages().keys.contains { String($0.prefix(10)) < startKey }
            || hourlyCharacters().keys.contains { String($0.prefix(10)) < startKey }
    }

    func consistentReadingSummary(endingAt endDate: Date = Date()) -> (total: Int, weekly: Int) {
        let calendar = Calendar.current
        let weekly = (0..<7).reduce(0) { result, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else { return result }
            return result + displayedReadingMinutes(for: date)
        }
        let storedTotal = Int((Double(getStats().totalReadingTimeSeconds) / 60).rounded())
        let detailedTotal = hourlyReadingDates().reduce(0) {
            $0 + displayedReadingMinutes(for: $1)
        }
        return (max(storedTotal, detailedTotal, weekly), weekly)
    }

    private func isDateKey(_ dateKey: String, startingAt startKey: String?, endingAt endKey: String) -> Bool {
        guard dateKey <= endKey else { return false }
        return startKey.map { dateKey >= $0 } ?? true
    }

    func getBookStats() -> [String: BookReadingStat] {
        guard let data = defaults.data(forKey: bookStatsKey),
              let values = try? JSONDecoder().decode([String: BookReadingStat].self, from: data) else {
            return [:]
        }
        return values
    }

    func exportArchive() -> LVReadingStatsArchive {
        let stats = getStats()
        return LVReadingStatsArchive(
            format: "LVRead Reading Stats",
            version: 1,
            exportedAt: Date(),
            totalReadingSeconds: stats.totalReadingTimeSeconds,
            totalPagesRead: stats.totalPagesRead,
            totalCharactersRead: stats.totalCharactersRead,
            wordCountRuleVersion: Self.currentWordCountRuleVersion,
            dailyMinutes: stats.dailyReadingMinutes,
            hourlySeconds: hourlySeconds(),
            hourlyPaceSeconds: hourlyPaceSeconds(),
            dailyPages: dailyPages(),
            hourlyPages: hourlyPages(),
            dailyCharacters: dailyCharacters(),
            hourlyCharacters: hourlyCharacters()
        )
    }

    func overlappingDates(with archive: LVReadingStatsArchive) -> [String] {
        let existingDaily = Set(getStats().dailyReadingMinutes.keys)
        let existingHourly = Set(hourlySeconds().keys.map { String($0.prefix(10)) })
        let existingHourlyPace = Set(hourlyPaceSeconds().keys.map { String($0.prefix(10)) })
        let existingDailyPages = Set(dailyPages().keys)
        let existingHourlyPages = Set(hourlyPages().keys.map { String($0.prefix(10)) })
        let existingDailyCharacters = Set(dailyCharacters().keys)
        let existingHourlyCharacters = Set(hourlyCharacters().keys.map { String($0.prefix(10)) })
        let importedDaily = Set(archive.dailyMinutes.keys)
        let importedHourly = Set(archive.hourlySeconds.keys.map { String($0.prefix(10)) })
        let importedHourlyPace = archive.usesCurrentWordCountRule
            ? Set(archive.hourlyPaceSeconds.keys.map { String($0.prefix(10)) }) : []
        let importedDailyPages = Set(archive.dailyPages.keys)
        let importedHourlyPages = Set(archive.hourlyPages.keys.map { String($0.prefix(10)) })
        let importedDailyCharacters = archive.usesCurrentWordCountRule
            ? Set(archive.dailyCharacters.keys) : []
        let importedHourlyCharacters = archive.usesCurrentWordCountRule
            ? Set(archive.hourlyCharacters.keys.map { String($0.prefix(10)) }) : []
        let existing = existingDaily.union(existingHourly).union(existingHourlyPace)
            .union(existingDailyPages).union(existingHourlyPages)
            .union(existingDailyCharacters).union(existingHourlyCharacters)
        let imported = importedDaily.union(importedHourly).union(importedHourlyPace)
            .union(importedDailyPages).union(importedHourlyPages)
            .union(importedDailyCharacters).union(importedHourlyCharacters)
        return Array(existing.intersection(imported)).sorted()
    }

    func importArchive(_ archive: LVReadingStatsArchive, overwriteOverlaps: Bool) {
        let overlaps = Set(overlappingDates(with: archive))
        let originalStats = getStats()
        var stats = originalStats
        var minuteDelta = 0
        for (dateKey, minutes) in archive.dailyMinutes where overwriteOverlaps || !overlaps.contains(dateKey) {
            let oldValue = stats.dailyReadingMinutes[dateKey] ?? 0
            stats.dailyReadingMinutes[dateKey] = max(0, minutes)
            let delta = max(0, minutes) - oldValue
            minuteDelta += delta
            if let date = dateFromString(dateKey) {
                let calendar = Calendar.current
                let weekKey = "\(calendar.component(.year, from: date))-W\(calendar.component(.weekOfYear, from: date))"
                let oldWeek = stats.weeklyReadingMinutes[weekKey] ?? 0
                stats.weeklyReadingMinutes[weekKey] = max(0, oldWeek + delta)
            }
        }
        stats.totalReadingTimeSeconds = max(0, stats.totalReadingTimeSeconds + minuteDelta * 60)
        save(stats)

        var hourly = hourlySeconds()
        if overwriteOverlaps {
            hourly = hourly.filter { !overlaps.contains(String($0.key.prefix(10))) }
        }
        for (key, seconds) in archive.hourlySeconds {
            let dateKey = String(key.prefix(10))
            if overwriteOverlaps || !overlaps.contains(dateKey) {
                hourly[key] = max(0, seconds)
            }
        }
        if let data = try? JSONEncoder().encode(hourly) {
            defaults.set(data, forKey: hourlySecondsKey)
        }

        var hourlyPace = hourlyPaceSeconds()
        if overwriteOverlaps {
            hourlyPace = hourlyPace.filter { !overlaps.contains(String($0.key.prefix(10))) }
        }
        for (key, seconds) in archive.hourlyPaceSeconds where archive.usesCurrentWordCountRule {
            let dateKey = String(key.prefix(10))
            if overwriteOverlaps || !overlaps.contains(dateKey) {
                hourlyPace[key] = max(0, seconds)
            }
        }
        persist(hourlyPace, forKey: hourlyPaceSecondsKey)

        var dailyPageValues = dailyPages()
        var pageDelta = 0
        if overwriteOverlaps {
            for dateKey in overlaps {
                pageDelta -= dailyPageValues.removeValue(forKey: dateKey) ?? 0
            }
        }
        for (dateKey, pages) in archive.dailyPages where overwriteOverlaps || !overlaps.contains(dateKey) {
            let oldValue = dailyPageValues[dateKey] ?? 0
            dailyPageValues[dateKey] = max(0, pages)
            pageDelta += max(0, pages) - oldValue
        }
        stats = getStats()
        stats.totalPagesRead = max(0, stats.totalPagesRead + pageDelta)
        save(stats)
        persist(dailyPageValues, forKey: dailyPagesKey)

        var hourlyPageValues = hourlyPages()
        if overwriteOverlaps {
            hourlyPageValues = hourlyPageValues.filter { !overlaps.contains(String($0.key.prefix(10))) }
        }
        for (key, pages) in archive.hourlyPages {
            let dateKey = String(key.prefix(10))
            if overwriteOverlaps || !overlaps.contains(dateKey) {
                hourlyPageValues[key] = max(0, pages)
            }
        }
        persist(hourlyPageValues, forKey: hourlyPagesKey)

        var dailyCharacterValues = dailyCharacters()
        var characterDelta = 0
        if overwriteOverlaps {
            for dateKey in overlaps {
                characterDelta -= dailyCharacterValues.removeValue(forKey: dateKey) ?? 0
            }
        }
        for (dateKey, characters) in archive.dailyCharacters
        where archive.usesCurrentWordCountRule && (overwriteOverlaps || !overlaps.contains(dateKey)) {
            let oldValue = dailyCharacterValues[dateKey] ?? 0
            dailyCharacterValues[dateKey] = max(0, characters)
            characterDelta += max(0, characters) - oldValue
        }
        stats = getStats()
        stats.totalCharactersRead = max(0, stats.totalCharactersRead + characterDelta)
        save(stats)
        persist(dailyCharacterValues, forKey: dailyCharactersKey)

        var hourlyCharacterValues = hourlyCharacters()
        if overwriteOverlaps {
            hourlyCharacterValues = hourlyCharacterValues.filter { !overlaps.contains(String($0.key.prefix(10))) }
        }
        for (key, characters) in archive.hourlyCharacters where archive.usesCurrentWordCountRule {
            let dateKey = String(key.prefix(10))
            if overwriteOverlaps || !overlaps.contains(dateKey) {
                hourlyCharacterValues[key] = max(0, characters)
            }
        }
        persist(hourlyCharacterValues, forKey: hourlyCharactersKey)

        if overlaps.isEmpty {
            stats = getStats()
            stats.totalReadingTimeSeconds = originalStats.totalReadingTimeSeconds + max(
                archive.totalReadingSeconds,
                archive.dailyMinutes.values.reduce(0, +) * 60
            )
            stats.totalPagesRead = originalStats.totalPagesRead + max(
                archive.totalPagesRead,
                archive.dailyPages.values.reduce(0, +)
            )
            if archive.usesCurrentWordCountRule {
                stats.totalCharactersRead = originalStats.totalCharactersRead + max(
                    archive.totalCharactersRead,
                    archive.dailyCharacters.values.reduce(0, +)
                )
            }
            save(stats)
        }
    }

    func hasReadingRecords(on date: Date) -> Bool {
        let key = dateString(from: date)
        return getStats().dailyReadingMinutes[key] != nil
            || hourlySeconds().keys.contains { $0.hasPrefix("\(key)-") }
            || hourlyPaceSeconds().keys.contains { $0.hasPrefix("\(key)-") }
            || dailyPages()[key] != nil
            || hourlyPages().keys.contains { $0.hasPrefix("\(key)-") }
            || dailyCharacters()[key] != nil
            || hourlyCharacters().keys.contains { $0.hasPrefix("\(key)-") }
    }

    func deleteReadingRecords(on date: Date) {
        let key = dateString(from: date)
        var stats = getStats()
        let dailyMinutes = stats.dailyReadingMinutes.removeValue(forKey: key) ?? 0
        var hourly = hourlySeconds()
        var hourlyPace = hourlyPaceSeconds()
        var dailyPageValues = dailyPages()
        var hourlyPageValues = hourlyPages()
        var dailyCharacterValues = dailyCharacters()
        var hourlyCharacterValues = hourlyCharacters()
        let dailyPagesToDelete = dailyPageValues.removeValue(forKey: key) ?? 0
        let hourlyPagesToDelete = hourlyPageValues.reduce(0) { result, item in
            result + (item.key.hasPrefix("\(key)-") ? item.value : 0)
        }
        let pagesToDelete = dailyPagesToDelete > 0 ? dailyPagesToDelete : hourlyPagesToDelete
        let dailyCharactersToDelete = dailyCharacterValues.removeValue(forKey: key) ?? 0
        let hourlyCharactersToDelete = hourlyCharacterValues.reduce(0) { result, item in
            result + (item.key.hasPrefix("\(key)-") ? item.value : 0)
        }
        let charactersToDelete = dailyCharactersToDelete > 0 ? dailyCharactersToDelete : hourlyCharactersToDelete
        let hourlySecondsToDelete = hourly.reduce(0) { result, item in
            result + (item.key.hasPrefix("\(key)-") ? item.value : 0)
        }
        hourly = hourly.filter { !$0.key.hasPrefix("\(key)-") }
        hourlyPace = hourlyPace.filter { !$0.key.hasPrefix("\(key)-") }
        hourlyPageValues = hourlyPageValues.filter { !$0.key.hasPrefix("\(key)-") }
        hourlyCharacterValues = hourlyCharacterValues.filter { !$0.key.hasPrefix("\(key)-") }

        let calendar = Calendar.current
        let weekKey = "\(calendar.component(.year, from: date))-W\(calendar.component(.weekOfYear, from: date))"
        if let weeklyMinutes = stats.weeklyReadingMinutes[weekKey] {
            let remaining = max(0, weeklyMinutes - dailyMinutes)
            stats.weeklyReadingMinutes[weekKey] = remaining == 0 ? nil : remaining
        }
        let secondsToDelete = hourlySecondsToDelete > 0 ? hourlySecondsToDelete : dailyMinutes * 60
        stats.totalReadingTimeSeconds = max(0, stats.totalReadingTimeSeconds - secondsToDelete)
        stats.totalPagesRead = max(0, stats.totalPagesRead - pagesToDelete)
        stats.totalCharactersRead = max(0, stats.totalCharactersRead - charactersToDelete)
        save(stats)
        if let data = try? JSONEncoder().encode(hourly) {
            defaults.set(data, forKey: hourlySecondsKey)
        }
        persist(hourlyPace, forKey: hourlyPaceSecondsKey)
        persist(dailyPageValues, forKey: dailyPagesKey)
        persist(hourlyPageValues, forKey: hourlyPagesKey)
        persist(dailyCharacterValues, forKey: dailyCharactersKey)
        persist(hourlyCharacterValues, forKey: hourlyCharactersKey)

        var books = getBookStats()
        for bookID in books.keys {
            guard var value = books[bookID], let removed = value.daily.removeValue(forKey: key) else { continue }
            value.readingTimeSeconds = max(0, value.readingTimeSeconds - removed.readingTimeSeconds)
            value.paceReadingTimeSeconds = max(0, value.paceReadingTimeSeconds - removed.paceReadingTimeSeconds)
            value.pagesRead = max(0, value.pagesRead - removed.pagesRead)
            value.charactersRead = max(0, value.charactersRead - removed.charactersRead)
            books[bookID] = value
        }
        persistBookStats(books)
    }
    
    /// Mark a book as finished
    func markBookFinished() {
        updateStats { stats in
            stats.totalBooksRead += 1
        }
    }
    
    // MARK: - Private Helpers

    private func migrateWordCountRuleIfNeeded() {
        guard defaults.integer(forKey: wordCountRuleVersionKey) < Self.currentWordCountRuleVersion else { return }
        var stats = getStats()
        stats.totalCharactersRead = 0
        save(stats)

        var books = getBookStats()
        for key in books.keys {
            books[key]?.charactersRead = 0
            books[key]?.paceReadingTimeSeconds = 0
            let dateKeys = books[key].map { Array($0.daily.keys) } ?? []
            for dateKey in dateKeys {
                books[key]?.daily[dateKey]?.charactersRead = 0
                books[key]?.daily[dateKey]?.paceReadingTimeSeconds = 0
            }
        }
        if let data = try? JSONEncoder().encode(books) {
            defaults.set(data, forKey: bookStatsKey)
        }
        defaults.removeObject(forKey: dailyCharactersKey)
        defaults.removeObject(forKey: hourlyCharactersKey)
        defaults.removeObject(forKey: hourlyPaceSecondsKey)
        defaults.set(Self.currentWordCountRuleVersion, forKey: wordCountRuleVersionKey)
    }
    
    private func updateDailyMinutes(minutes: Int) {
        guard minutes > 0 else { return }
        
        let today = dateString(from: Date())
        
        updateStats { stats in
            let current = stats.dailyReadingMinutes[today] ?? 0
            stats.dailyReadingMinutes[today] = current + minutes
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
        }
    }

    private func addHourlyReadingTime(from start: Date, to end: Date) {
        var values = hourlySeconds()
        var cursor = start
        let calendar = Calendar.current
        while cursor < end {
            guard let nextHour = calendar.nextDate(
                after: cursor,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { break }
            let segmentEnd = min(end, nextHour)
            let key = hourlyKey(from: cursor)
            values[key, default: 0] += max(0, Int(segmentEnd.timeIntervalSince(cursor)))
            cursor = segmentEnd
        }

        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: hourlySecondsKey)
        }
    }

    private func addHourlyPaceTime(from start: Date, to end: Date) {
        var values = hourlyPaceSeconds()
        var cursor = start
        let calendar = Calendar.current
        while cursor < end {
            guard let nextHour = calendar.nextDate(
                after: cursor,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { break }
            let segmentEnd = min(end, nextHour)
            values[hourlyKey(from: cursor), default: 0] += max(0, Int(segmentEnd.timeIntervalSince(cursor)))
            cursor = segmentEnd
        }
        persist(values, forKey: hourlyPaceSecondsKey)
    }

    private func addPageBreakdown(_ pages: Int, at date: Date) {
        var daily = dailyPages()
        daily[hourlyDateKey(from: date), default: 0] += pages
        persist(daily, forKey: dailyPagesKey)

        var hourly = hourlyPages()
        hourly[hourlyKey(from: date), default: 0] += pages
        persist(hourly, forKey: hourlyPagesKey)
    }

    private func addCharacterBreakdown(_ characters: Int, at date: Date) {
        var daily = dailyCharacters()
        daily[hourlyDateKey(from: date), default: 0] += characters
        persist(daily, forKey: dailyCharactersKey)

        var hourly = hourlyCharacters()
        hourly[hourlyKey(from: date), default: 0] += characters
        persist(hourly, forKey: hourlyCharactersKey)
    }

    private func hourlySeconds() -> [String: Int] {
        guard let data = defaults.data(forKey: hourlySecondsKey),
              let values = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return values
    }

    private func hourlyPaceSeconds() -> [String: Int] {
        storedValues(forKey: hourlyPaceSecondsKey)
    }

    private func dailyPages() -> [String: Int] {
        storedValues(forKey: dailyPagesKey)
    }

    private func hourlyPages() -> [String: Int] {
        storedValues(forKey: hourlyPagesKey)
    }

    private func dailyCharacters() -> [String: Int] {
        storedValues(forKey: dailyCharactersKey)
    }

    private func hourlyCharacters() -> [String: Int] {
        storedValues(forKey: hourlyCharactersKey)
    }

    private func storedValues(forKey key: String) -> [String: Int] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return values
    }

    private func persist(_ values: [String: Int], forKey key: String) {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    private func persistBookStats(_ values: [String: BookReadingStat]) {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: bookStatsKey)
        }
    }

    private func hourlyKey(from date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return hourlyDateKey(from: date) + "-" + String(format: "%02d", hour)
    }

    private func hourlyDateKey(from date: Date) -> String {
        dateString(from: date)
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
    
}

struct LVReadingStatsArchive: Codable, Equatable {
    let format: String
    let version: Int
    let exportedAt: Date
    let totalReadingSeconds: Int
    let totalPagesRead: Int
    let totalCharactersRead: Int
    let wordCountRuleVersion: Int
    let dailyMinutes: [String: Int]
    let hourlySeconds: [String: Int]
    let hourlyPaceSeconds: [String: Int]
    let dailyPages: [String: Int]
    let hourlyPages: [String: Int]
    let dailyCharacters: [String: Int]
    let hourlyCharacters: [String: Int]

    init(
        format: String,
        version: Int,
        exportedAt: Date,
        totalReadingSeconds: Int = 0,
        totalPagesRead: Int = 0,
        totalCharactersRead: Int = 0,
        wordCountRuleVersion: Int = 3,
        dailyMinutes: [String: Int],
        hourlySeconds: [String: Int],
        hourlyPaceSeconds: [String: Int] = [:],
        dailyPages: [String: Int] = [:],
        hourlyPages: [String: Int] = [:],
        dailyCharacters: [String: Int] = [:],
        hourlyCharacters: [String: Int] = [:]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.totalReadingSeconds = totalReadingSeconds
        self.totalPagesRead = totalPagesRead
        self.totalCharactersRead = totalCharactersRead
        self.wordCountRuleVersion = wordCountRuleVersion
        self.dailyMinutes = dailyMinutes
        self.hourlySeconds = hourlySeconds
        self.hourlyPaceSeconds = hourlyPaceSeconds
        self.dailyPages = dailyPages
        self.hourlyPages = hourlyPages
        self.dailyCharacters = dailyCharacters
        self.hourlyCharacters = hourlyCharacters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        totalReadingSeconds = try container.decodeIfPresent(Int.self, forKey: .totalReadingSeconds) ?? 0
        totalPagesRead = try container.decodeIfPresent(Int.self, forKey: .totalPagesRead) ?? 0
        totalCharactersRead = try container.decodeIfPresent(Int.self, forKey: .totalCharactersRead) ?? 0
        wordCountRuleVersion = try container.decodeIfPresent(Int.self, forKey: .wordCountRuleVersion) ?? 1
        dailyMinutes = try container.decode([String: Int].self, forKey: .dailyMinutes)
        hourlySeconds = try container.decode([String: Int].self, forKey: .hourlySeconds)
        hourlyPaceSeconds = try container.decodeIfPresent([String: Int].self, forKey: .hourlyPaceSeconds) ?? [:]
        dailyPages = try container.decodeIfPresent([String: Int].self, forKey: .dailyPages) ?? [:]
        hourlyPages = try container.decodeIfPresent([String: Int].self, forKey: .hourlyPages) ?? [:]
        dailyCharacters = try container.decodeIfPresent([String: Int].self, forKey: .dailyCharacters) ?? [:]
        hourlyCharacters = try container.decodeIfPresent([String: Int].self, forKey: .hourlyCharacters) ?? [:]
    }

    var usesCurrentWordCountRule: Bool {
        wordCountRuleVersion >= 3
    }
}

struct BookReadingDailyStat: Codable, Equatable {
    var readingTimeSeconds = 0
    var paceReadingTimeSeconds = 0
    var pagesRead = 0
    var charactersRead = 0
}

struct BookReadingStat: Codable, Equatable {
    var readingTimeSeconds: Int
    var paceReadingTimeSeconds: Int
    var pagesRead: Int
    var charactersRead: Int
    var lastReadAt: Date
    var daily: [String: BookReadingDailyStat]

    init(
        readingTimeSeconds: Int = 0,
        paceReadingTimeSeconds: Int = 0,
        pagesRead: Int = 0,
        charactersRead: Int = 0,
        lastReadAt: Date = .distantPast,
        daily: [String: BookReadingDailyStat] = [:]
    ) {
        self.readingTimeSeconds = readingTimeSeconds
        self.paceReadingTimeSeconds = paceReadingTimeSeconds
        self.pagesRead = pagesRead
        self.charactersRead = charactersRead
        self.lastReadAt = lastReadAt
        self.daily = daily
    }

    private enum CodingKeys: String, CodingKey {
        case readingTimeSeconds
        case paceReadingTimeSeconds
        case pagesRead
        case charactersRead
        case lastReadAt
        case daily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readingTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .readingTimeSeconds) ?? 0
        paceReadingTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .paceReadingTimeSeconds) ?? 0
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
        charactersRead = try container.decodeIfPresent(Int.self, forKey: .charactersRead) ?? 0
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt) ?? .distantPast
        daily = try container.decodeIfPresent([String: BookReadingDailyStat].self, forKey: .daily) ?? [:]
    }
}

// MARK: - Reading Analytics

struct ReadingAnalytics {
    
    let stats: ReadingStats
    
    // MARK: - Summary Stats
    
    var totalReadingTimeFormatted: String {
        let hours = stats.totalReadingTimeSeconds / 3600
        let minutes = (stats.totalReadingTimeSeconds % 3600) / 60
        
        if hours > 0 {
            return LF("%d 小时 %d 分钟", hours, minutes)
        }
        return LF("%d 分钟", minutes)
    }
    
    var totalBooksRead: Int {
        stats.totalBooksRead
    }
    
    var totalPagesRead: Int {
        stats.totalPagesRead
    }

    var totalCharactersRead: Int {
        stats.totalCharactersRead
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
