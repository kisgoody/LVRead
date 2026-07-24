import Foundation

struct ReadingAdvice: Equatable {
    let kind: ReadingAdviceKind
    let text: String
}

enum ReadingAdviceKind: String, CaseIterable {
    case dataInsufficient = "data.insufficient"
    case readingInactive = "reading.inactive"
    case trendDecline = "trend.decline"
    case trendGrowth = "trend.growth"
    case daysConcentrated = "days.concentrated"
    case streakStable = "streak.stable"
    case booksTooMany = "books.too_many"
    case bookDominant = "book.dominant"
    case timeOvernight = "time.overnight"
    case timeEarlyMorning = "time.early_morning"
    case timeMorning = "time.morning"
    case timeNoon = "time.noon"
    case timeAfternoon = "time.afternoon"
    case timeEvening = "time.evening"
    case timeNight = "time.night"
    case timeDualPeak = "time.dual_peak"
    case timeWeekPattern = "time.week_pattern"
    case timeShift = "time.shift"
    case timeFlexible = "time.flexible"

    var isTimeAdvice: Bool { rawValue.hasPrefix("time.") }
}

struct ReadingAdviceDay {
    let date: Date
    let minutes: Int
    let hourlyMinutes: [Double]
}

struct ReadingAdviceInput {
    let stats: ReadingStats
    let days: [ReadingAdviceDay]
    let books: [Book]
    let bookStats: [String: BookReadingStat]
    let now: Date
}

final class ReadingAdviceTemplateSelector {
    static let historyKey = "reading_advice_template_history_v1"

    private let defaults: UserDefaults
    private let randomIndex: (Int) -> Int
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }
    ) {
        self.defaults = defaults
        self.randomIndex = randomIndex
    }

    func selectIndex(for kind: ReadingAdviceKind, templateCount: Int) -> Int {
        guard templateCount > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }

        var history = defaults.dictionary(forKey: Self.historyKey) as? [String: [Int]] ?? [:]
        let recent = Array((history[kind.rawValue] ?? []).suffix(max(templateCount - 1, 0)))
        let available = Array(0..<templateCount).filter { !recent.contains($0) }
        let pool = available.isEmpty ? Array(0..<templateCount) : available
        let selected = pool[min(max(randomIndex(pool.count), 0), pool.count - 1)]
        history[kind.rawValue] = Array((recent + [selected]).suffix(max(templateCount - 1, 0)))
        defaults.set(history, forKey: Self.historyKey)
        return selected
    }
}

final class ReadingAdviceEngine {
    static let shared = ReadingAdviceEngine()

    private struct Candidate {
        let kind: ReadingAdviceKind
        let values: [String: String]
    }

    private struct TimeBucket {
        let kind: ReadingAdviceKind
        let hours: Range<Int>
        let displayRange: String
    }

    private let selector: ReadingAdviceTemplateSelector
    private let calendar: Calendar
    private var cachedSignature: String?
    private var cachedSuggestions: [ReadingAdvice] = []

    init(
        selector: ReadingAdviceTemplateSelector = ReadingAdviceTemplateSelector(),
        calendar: Calendar = .current
    ) {
        self.selector = selector
        self.calendar = calendar
    }

    func suggestions(now: Date = Date()) -> [ReadingAdvice] {
        let repository = ReadingStatsRepository.shared
        let stats = repository.getStats()
        let books = BookRepository.shared.getAll()
        let bookStats = repository.getBookStats()
        let days = (0..<14).reversed().compactMap { offset -> ReadingAdviceDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return ReadingAdviceDay(
                date: date,
                minutes: repository.displayedReadingMinutes(for: date),
                hourlyMinutes: repository.hourlyReadingMinutes(for: date)
            )
        }
        let input = ReadingAdviceInput(
            stats: stats,
            days: days,
            books: books,
            bookStats: bookStats,
            now: now
        )
        let signature = inputSignature(input)
        if signature == cachedSignature { return cachedSuggestions }
        cachedSignature = signature
        cachedSuggestions = makeSuggestions(input: input)
        return cachedSuggestions
    }

    func makeSuggestions(input: ReadingAdviceInput) -> [ReadingAdvice] {
        let recentDays = days(in: 0...13, input: input)
        let recentMinutes = recentDays.reduce(0) { $0 + $1.minutes }
        let activeDays = recentDays.filter { $0.minutes > 0 }.count
        guard recentMinutes >= 60, activeDays >= 3 else {
            return [render(Candidate(kind: .dataInsufficient, values: [:]))]
        }

        let currentDays = days(in: 0...6, input: input)
        let previousDays = days(in: 7...13, input: input)
        let currentMinutes = currentDays.reduce(0) { $0 + $1.minutes }
        let previousMinutes = previousDays.reduce(0) { $0 + $1.minutes }
        let currentActiveDays = currentDays.filter { $0.minutes > 0 }.count
        let streak = currentStreak(stats: input.stats, now: input.now)
        let inProgressBooks = input.books.filter {
            $0.readingProgress.progressPercent > 0 && $0.readingProgress.progressPercent < 100
        }

        var candidates: [ReadingAdviceKind: Candidate] = [:]
        if let inactiveDays = inactiveDayCount(stats: input.stats, now: input.now), inactiveDays >= 3 {
            candidates[.readingInactive] = Candidate(
                kind: .readingInactive,
                values: ["days": "\(inactiveDays)"]
            )
        }
        if previousMinutes >= 60 {
            if currentMinutes * 100 <= previousMinutes * 70 {
                let percent = (previousMinutes - currentMinutes) * 100 / previousMinutes
                candidates[.trendDecline] = Candidate(
                    kind: .trendDecline,
                    values: [
                        "current": "\(currentMinutes)",
                        "previous": "\(previousMinutes)",
                        "percent": "\(percent)"
                    ]
                )
            } else if currentMinutes * 100 >= previousMinutes * 120 {
                let percent = (currentMinutes - previousMinutes) * 100 / previousMinutes
                candidates[.trendGrowth] = Candidate(
                    kind: .trendGrowth,
                    values: [
                        "current": "\(currentMinutes)",
                        "previous": "\(previousMinutes)",
                        "percent": "\(percent)"
                    ]
                )
            }
        }
        if currentMinutes >= 60, currentActiveDays <= 2 {
            candidates[.daysConcentrated] = Candidate(kind: .daysConcentrated, values: [:])
        }
        if streak >= 3 {
            candidates[.streakStable] = Candidate(
                kind: .streakStable,
                values: ["days": "\(streak)"]
            )
        }
        if inProgressBooks.count > 3 {
            candidates[.booksTooMany] = Candidate(
                kind: .booksTooMany,
                values: ["count": "\(inProgressBooks.count)"]
            )
        }
        if let dominant = dominantBook(input: input) {
            candidates[.bookDominant] = Candidate(
                kind: .bookDominant,
                values: ["book": dominant.title]
            )
        }
        if let timeCandidate = timeCandidate(input: input) {
            candidates[timeCandidate.kind] = timeCandidate
        }

        let actionOrder: [ReadingAdviceKind] = [
            .readingInactive, .trendDecline, .timeOvernight, .booksTooMany, .daysConcentrated
        ]
        let action = actionOrder.compactMap { candidates[$0] }.first

        var discoveryOrder: [ReadingAdviceKind] = [
            .trendGrowth, .streakStable, .bookDominant,
            .timeWeekPattern, .timeDualPeak, .timeShift,
            .timeEarlyMorning, .timeMorning, .timeNoon, .timeAfternoon,
            .timeEvening, .timeNight, .timeFlexible
        ]
        if action != nil {
            discoveryOrder.removeAll { $0 == .timeOvernight }
        }
        var selected = [Candidate]()
        if let action { selected.append(action) }
        for candidate in discoveryOrder.compactMap({ candidates[$0] }) {
            guard selected.count < 2,
                  !selected.contains(where: { $0.kind == candidate.kind }),
                  !candidate.kind.isTimeAdvice
                    || !selected.contains(where: { $0.kind.isTimeAdvice }) else { continue }
            selected.append(candidate)
        }
        if selected.isEmpty {
            return [render(Candidate(kind: .dataInsufficient, values: [:]))]
        }
        return selected.prefix(2).map(render)
    }

    private func render(_ candidate: Candidate) -> ReadingAdvice {
        let values = Self.templates[candidate.kind] ?? [""]
        let index = selector.selectIndex(for: candidate.kind, templateCount: values.count)
        var text = values[index]
        candidate.values.forEach {
            text = text.replacingOccurrences(of: "{\($0.key)}", with: $0.value)
        }
        return ReadingAdvice(kind: candidate.kind, text: text)
    }

    private func days(in offsets: ClosedRange<Int>, input: ReadingAdviceInput) -> [ReadingAdviceDay] {
        input.days.filter { day in
            let value = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: day.date),
                to: calendar.startOfDay(for: input.now)
            ).day ?? Int.max
            return offsets.contains(value)
        }
    }

    private func currentStreak(stats: ReadingStats, now: Date) -> Int {
        var result = 0
        var date = now
        while stats.dailyReadingMinutes[dateKey(date)] ?? 0 > 0 {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return result
    }

    private func inactiveDayCount(stats: ReadingStats, now: Date) -> Int? {
        let lastDate = stats.dailyReadingMinutes
            .filter { $0.value > 0 }
            .keys
            .compactMap(parseDate)
            .max()
        guard let lastDate else { return nil }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastDate),
            to: calendar.startOfDay(for: now)
        ).day
    }

    private func dominantBook(input: ReadingAdviceInput) -> Book? {
        guard let cutoff = calendar.date(byAdding: .day, value: -14, to: input.now) else { return nil }
        let recent = input.bookStats.filter { $0.value.lastReadAt >= cutoff && $0.value.readingTimeSeconds > 0 }
        let total = recent.values.reduce(0) { $0 + $1.readingTimeSeconds }
        guard total > 0,
              let dominant = recent.max(by: { $0.value.readingTimeSeconds < $1.value.readingTimeSeconds }),
              dominant.value.readingTimeSeconds * 100 >= total * 60 else { return nil }
        return input.books.first { $0.id == dominant.key }
    }

    private func timeCandidate(input: ReadingAdviceInput) -> Candidate? {
        let active = input.days.filter { $0.hourlyMinutes.reduce(0, +) > 0 }
        let hourlyTotal = active.reduce(0.0) { $0 + $1.hourlyMinutes.reduce(0, +) }
        guard hourlyTotal >= 120, active.count >= 5 else { return nil }

        let buckets = Self.timeBuckets.map { bucket -> (TimeBucket, Double, Int) in
            let total = active.reduce(0.0) { result, day in
                result + sum(day.hourlyMinutes, hours: bucket.hours)
            }
            let occurrences = active.filter { sum($0.hourlyMinutes, hours: bucket.hours) > 0 }.count
            return (bucket, total, occurrences)
        }

        if let overnight = buckets.first(where: { $0.0.kind == .timeOvernight }),
           overnight.1 / hourlyTotal >= 0.30,
           overnight.2 >= 3 {
            return Candidate(
                kind: .timeOvernight,
                values: ["range": bestRange(hours: overnight.0.hours, days: active)]
            )
        }
        if let weekPattern = weekPatternCandidate(days: active) { return weekPattern }
        if let dualPeak = dualPeakCandidate(buckets: buckets, total: hourlyTotal) { return dualPeak }
        if let shift = shiftCandidate(input: input) { return shift }
        if let stable = buckets
            .filter({ $0.0.kind != .timeOvernight && $0.1 / hourlyTotal >= 0.35 && $0.2 >= 3 })
            .max(by: { $0.1 < $1.1 }) {
            return Candidate(
                kind: stable.0.kind,
                values: ["range": bestRange(hours: stable.0.hours, days: active)]
            )
        }
        let aggregate = aggregateHours(active)
        if let peak = peakWindow(in: aggregate), peak.minutes / hourlyTotal < 0.25 {
            return Candidate(kind: .timeFlexible, values: [:])
        }
        return nil
    }

    private func weekPatternCandidate(days: [ReadingAdviceDay]) -> Candidate? {
        let weekdays = days.filter {
            let weekday = calendar.component(.weekday, from: $0.date)
            return weekday != 1 && weekday != 7
        }
        let weekends = days.filter {
            let weekday = calendar.component(.weekday, from: $0.date)
            return weekday == 1 || weekday == 7
        }
        guard weekdays.count >= 3, weekends.count >= 2 else { return nil }
        let weekdayHours = aggregateHours(weekdays)
        let weekendHours = aggregateHours(weekends)
        guard weekdayHours.reduce(0, +) >= 30,
              weekendHours.reduce(0, +) >= 30,
              let weekdayPeak = peakWindow(in: weekdayHours),
              let weekendPeak = peakWindow(in: weekendHours),
              circularHourDistance(weekdayPeak.start, weekendPeak.start) >= 2 else { return nil }
        return Candidate(
            kind: .timeWeekPattern,
            values: [
                "range": hourRange(start: weekdayPeak.start),
                "range2": hourRange(start: weekendPeak.start)
            ]
        )
    }

    private func dualPeakCandidate(
        buckets: [(TimeBucket, Double, Int)],
        total: Double
    ) -> Candidate? {
        let ranked = buckets
            .filter { $0.1 / total >= 0.20 }
            .sorted { $0.1 > $1.1 }
        guard let first = ranked.first,
              let second = ranked.dropFirst().first(where: {
                  areNonAdjacent(first.0.kind, $0.0.kind)
              }) else { return nil }
        return Candidate(
            kind: .timeDualPeak,
            values: ["range": first.0.displayRange, "range2": second.0.displayRange]
        )
    }

    private func shiftCandidate(input: ReadingAdviceInput) -> Candidate? {
        let current = days(in: 0...6, input: input)
        let previous = days(in: 7...13, input: input)
        let currentHours = aggregateHours(current)
        let previousHours = aggregateHours(previous)
        guard currentHours.reduce(0, +) >= 60,
              previousHours.reduce(0, +) >= 60,
              let currentPeak = peakWindow(in: currentHours),
              let previousPeak = peakWindow(in: previousHours),
              circularHourDistance(currentPeak.start, previousPeak.start) >= 3 else { return nil }
        return Candidate(
            kind: .timeShift,
            values: [
                "oldRange": hourRange(start: previousPeak.start),
                "newRange": hourRange(start: currentPeak.start)
            ]
        )
    }

    private func aggregateHours(_ days: [ReadingAdviceDay]) -> [Double] {
        days.reduce(into: Array(repeating: 0, count: 24)) { result, day in
            for index in 0..<min(day.hourlyMinutes.count, 24) {
                result[index] += max(day.hourlyMinutes[index], 0)
            }
        }
    }

    private func peakWindow(in hours: [Double]) -> (start: Int, minutes: Double)? {
        guard hours.count >= 24 else { return nil }
        return (0..<24)
            .map { ($0, hours[$0] + hours[($0 + 1) % 24]) }
            .max { $0.1 < $1.1 }
    }

    private func bestRange(hours: Range<Int>, days: [ReadingAdviceDay]) -> String {
        let aggregate = aggregateHours(days)
        let starts = hours.count > 1 ? hours.lowerBound..<(hours.upperBound - 1) : hours
        let start = starts.max {
            aggregate[$0] + aggregate[($0 + 1) % 24]
                < aggregate[$1] + aggregate[($1 + 1) % 24]
        } ?? hours.lowerBound
        return hourRange(start: start)
    }

    private func hourRange(start: Int) -> String {
        String(format: "%02d:00～%02d:00", start, (start + 2) % 24)
    }

    private func sum(_ values: [Double], hours: Range<Int>) -> Double {
        hours.reduce(0) { result, hour in
            guard values.indices.contains(hour) else { return result }
            return result + max(values[hour], 0)
        }
    }

    private func circularHourDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let distance = abs(lhs - rhs)
        return min(distance, 24 - distance)
    }

    private func areNonAdjacent(_ lhs: ReadingAdviceKind, _ rhs: ReadingAdviceKind) -> Bool {
        guard let lhsIndex = Self.timeBuckets.firstIndex(where: { $0.kind == lhs }),
              let rhsIndex = Self.timeBuckets.firstIndex(where: { $0.kind == rhs }) else { return false }
        let distance = abs(lhsIndex - rhsIndex)
        return distance > 1 && distance < Self.timeBuckets.count - 1
    }

    private func inputSignature(_ input: ReadingAdviceInput) -> String {
        let dayValues = input.days.map { day in
            let hourly = day.hourlyMinutes.map { String(format: "%.2f", $0) }.joined(separator: ",")
            return "\(dateKey(day.date)):\(day.minutes):\(hourly)"
        }.joined(separator: "|")
        let books = input.books
            .map { "\($0.id):\($0.readingProgress.progressPercent)" }
            .sorted()
            .joined(separator: "|")
        let bookStats = input.bookStats
            .map { "\($0.key):\($0.value.readingTimeSeconds):\($0.value.lastReadAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        return "\(dateKey(input.now))#\(dayValues)#\(books)#\(bookStats)"
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static let timeBuckets: [TimeBucket] = [
        .init(kind: .timeOvernight, hours: 0..<5, displayRange: "00:00～05:00"),
        .init(kind: .timeEarlyMorning, hours: 5..<8, displayRange: "05:00～08:00"),
        .init(kind: .timeMorning, hours: 8..<11, displayRange: "08:00～11:00"),
        .init(kind: .timeNoon, hours: 11..<14, displayRange: "11:00～14:00"),
        .init(kind: .timeAfternoon, hours: 14..<18, displayRange: "14:00～18:00"),
        .init(kind: .timeEvening, hours: 18..<21, displayRange: "18:00～21:00"),
        .init(kind: .timeNight, hours: 21..<24, displayRange: "21:00～24:00")
    ]

    static let templates: [ReadingAdviceKind: [String]] = [
        .dataInsufficient: [
            "再完成几次阅读后，将根据你的阅读节奏生成更准确的建议。",
            "当前阅读记录还比较少，继续阅读一段时间后可以发现你的习惯。",
            "暂时没有足够的数据判断阅读趋势，新的记录会让建议更加准确。",
            "阅读数据正在积累，后续将从时间、频率和书籍偏好分析你的习惯。",
            "继续保持几次自然阅读，系统会逐步识别适合你的阅读节奏。"
        ],
        .readingInactive: [
            "距离上次阅读已经 {days} 天，可以从最近阅读的书继续。",
            "最近 {days} 天没有阅读记录，不妨先读一个短章节找回节奏。",
            "阅读暂时中断了 {days} 天，可以从上次停留的位置重新开始。",
            "已有 {days} 天没有继续阅读，今天可以安排一次轻量阅读。",
            "最近的阅读节奏有所停顿，继续一本熟悉的书会更容易恢复。"
        ],
        .trendDecline: [
            "最近 7 天阅读 {current} 分钟，比前 7 天减少 {percent}%，可以选择熟悉的时段恢复阅读。",
            "本周阅读时间有所下降，可以从最近在读的书开始一次短阅读。",
            "最近一周比上一周少读了 {percent}%，不妨先恢复最容易坚持的阅读时段。",
            "阅读时间从 {previous} 分钟下降到 {current} 分钟，可以尝试减少同时在读的书。",
            "最近阅读频率有所放缓，选择篇幅较短的章节会更容易重新进入状态。"
        ],
        .trendGrowth: [
            "最近 7 天阅读时间比前 7 天增加 {percent}%，当前节奏正在提升。",
            "本周已经阅读 {current} 分钟，比上一周更加稳定。",
            "最近一周的阅读投入明显增加，可以继续保持当前安排。",
            "阅读时间从 {previous} 分钟提升到 {current} 分钟，这个节奏值得继续。",
            "最近的阅读表现比上一周期更活跃，当前习惯正在逐渐形成。"
        ],
        .daysConcentrated: [
            "本周阅读主要集中在少数几天，分散到更多日期会更容易保持习惯。",
            "最近的阅读时间比较集中，可以尝试在其他日期增加一次短阅读。",
            "你在少数日期完成了大部分阅读，适当分散可以让节奏更加稳定。",
            "本周阅读总量不错，但日期分布较集中，可以增加几个轻量阅读日。",
            "阅读时间集中在 1～2 天，拆分成多次短阅读可能更容易持续。"
        ],
        .streakStable: [
            "已连续阅读 {days} 天，当前阅读习惯比较稳定。",
            "连续 {days} 天都有阅读记录，这个节奏值得继续保持。",
            "你已经坚持阅读 {days} 天，稳定性正在逐步增强。",
            "最近 {days} 天保持了连续阅读，可以继续沿用当前安排。",
            "连续阅读达到 {days} 天，说明目前的阅读时间比较适合你。"
        ],
        .booksTooMany: [
            "当前有 {count} 本书同时在读，建议优先继续最近阅读的 1～2 本。",
            "在读书籍已经达到 {count} 本，可以先推进进度最高的书。",
            "同时阅读 {count} 本书可能会分散注意力，可以暂时确定一条阅读主线。",
            "当前阅读内容比较分散，建议从最近打开的书中选择一本优先完成。",
            "有 {count} 本书处于阅读中，可以减少切换，让阅读进度更加连贯。"
        ],
        .bookDominant: [
            "最近主要在阅读《{book}》，可以继续保持这条阅读主线。",
            "《{book}》占据了近期大部分阅读时间，是你当前最主要的阅读内容。",
            "最近的阅读重点集中在《{book}》，继续推进会更容易保持连贯。",
            "《{book}》是近期阅读时间最多的书，可以优先完成当前章节。",
            "近期阅读明显偏向《{book}》，你的阅读主线已经比较清晰。"
        ],
        .timeOvernight: [
            "最近多次在 {range} 阅读，如果条件允许，可以适当提前阅读时间。",
            "凌晨是你近期阅读比较集中的时段，可以留意是否影响第二天的状态。",
            "近期经常在 {range} 继续阅读，可以尝试将部分内容安排到更早的时间。",
            "最近的阅读高峰出现在凌晨，适当提前开始可能更容易兼顾阅读和休息。",
            "{range} 出现了较多阅读记录，可以考虑把长时间阅读调整到晚间更早的时候。"
        ],
        .timeEarlyMorning: [
            "清晨 {range} 是你最稳定的阅读时段，可以继续保持。",
            "你经常在 {range} 开始阅读，清晨已经成为主要阅读时间。",
            "最近的阅读高峰集中在 {range}，这段安静时间可能比较适合你。",
            "清晨阅读出现得比较稳定，可以优先把需要连续理解的内容安排在这里。",
            "从近期记录看，{range} 是你最容易进入阅读状态的时间。"
        ],
        .timeMorning: [
            "最近主要在 {range} 阅读，上午是你当前最集中的阅读时段。",
            "你经常在 {range} 保持阅读，可以继续保留这一时间安排。",
            "上午的阅读记录比较稳定，{range} 可能是你注意力较集中的时段。",
            "近期阅读高峰出现在 {range}，适合继续推进当前阅读主线。",
            "从阅读数据看，你在 {range} 更容易保持连续阅读。"
        ],
        .timeNoon: [
            "午间 {range} 是你经常阅读的时段，可以继续安排篇幅适中的章节。",
            "最近的阅读主要集中在 {range}，午间已经形成稳定的阅读习惯。",
            "你经常利用 {range} 阅读，可以优先选择容易暂停和继续的内容。",
            "午间阅读记录比较稳定，保持当前节奏有助于增加阅读频率。",
            "{range} 是你近期较活跃的阅读时间，可以继续保留这段阅读间隙。"
        ],
        .timeAfternoon: [
            "最近主要在 {range} 阅读，下午是你当前较稳定的阅读时段。",
            "你经常在 {range} 继续阅读，可以把这段时间用于推进在读书籍。",
            "下午的阅读记录比较集中，{range} 可能更符合你当前的安排。",
            "近期阅读高峰出现在 {range}，可以继续沿用这一节奏。",
            "从最近的数据看，你在 {range} 更容易留出完整的阅读时间。"
        ],
        .timeEvening: [
            "晚间 {range} 是你最主要的阅读时段，可以优先保留。",
            "最近大部分阅读发生在 {range}，晚间已经形成稳定节奏。",
            "你经常在 {range} 进入阅读状态，可以把当前主线书籍安排在这里。",
            "晚间阅读记录比较稳定，{range} 适合继续推进较长章节。",
            "从近期记录看，{range} 是你最容易保持连续阅读的时间。"
        ],
        .timeNight: [
            "最近主要在 {range} 阅读，睡前是你较稳定的阅读时段。",
            "你经常在 {range} 结束一天的阅读，可以继续保持适合自己的节奏。",
            "夜间阅读主要集中在 {range}，可以优先选择节奏平稳的内容。",
            "{range} 是近期阅读最活跃的时间，可以继续作为固定阅读时段。",
            "从最近的数据看，你更习惯在 {range} 安静阅读。"
        ],
        .timeDualPeak: [
            "阅读主要集中在 {range} 和 {range2}，可以分别安排不同篇幅的内容。",
            "你在 {range}、{range2} 都有稳定记录，已经形成两个主要阅读时段。",
            "近期阅读呈现双高峰，{range} 和 {range2} 都比较适合你。",
            "阅读时间主要分布在 {range} 与 {range2}，可以根据当天安排灵活选择。",
            "你通常在 {range} 或 {range2} 阅读，这两个时间共同构成了当前节奏。"
        ],
        .timeWeekPattern: [
            "工作日主要在 {range} 阅读，周末则偏向 {range2}，可以分别保持两种节奏。",
            "工作日和周末的阅读时间不同，可以按两类日期分别安排。",
            "工作日高峰为 {range}，周末高峰为 {range2}，时间分布比较清晰。",
            "平日更适合 {range}，周末更适合 {range2}，可以继续采用不同安排。",
            "阅读时段会随工作日和周末变化，两种节奏都已经比较稳定。"
        ],
        .timeShift: [
            "最近阅读时间从 {oldRange} 转移到 {newRange}，阅读习惯正在变化。",
            "近期主要阅读时段变为 {newRange}，比之前明显提前或推迟。",
            "阅读高峰从 {oldRange} 移动到 {newRange}，可以观察新时段是否更容易坚持。",
            "最近一周更常在 {newRange} 阅读，与前一周的 {oldRange} 有所不同。",
            "当前阅读时间正在向 {newRange} 集中，可以继续观察这一变化。"
        ],
        .timeFlexible: [
            "阅读时间比较灵活，目前没有明显固定时段。",
            "近期阅读分布在多个时间段，可以根据每天的空闲时间安排。",
            "阅读时间较为分散，暂时没有形成单一高峰。",
            "当前没有特别集中的阅读时间，灵活安排可能更适合你。",
            "最近在不同时间都有阅读记录，你的阅读节奏偏向灵活型。"
        ]
    ]
}
