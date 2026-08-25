import Foundation

struct ReadingAdvice: Equatable {
    let kind: ReadingAdviceKind
    let text: String
}

enum ReadingAdviceKind: String {
    case dataInsufficient = "data.insufficient"
    case buildHistory = "history.build"
    case resumeReading = "reading.resume"
    case weeklyRecovery = "weekly.recovery"
    case spreadReadingDays = "weekly.spread"
    case keepRhythm = "weekly.keep"
    case preferredTime = "time.preferred"
    case lateNightReading = "time.late_night"
    case sustainableDuration = "duration.sustainable"
}

struct ReadingAdviceDay {
    let date: Date
    let minutes: Int
    let hourlyMinutes: [Double]
}

struct ReadingAdviceInput {
    let days: [ReadingAdviceDay]
    let now: Date
}

final class ReadingAdviceEngine {
    static let shared = ReadingAdviceEngine()

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func suggestions(now: Date = Date()) -> [ReadingAdvice] {
        let repository = ReadingStatsRepository.shared
        let days = (1...14).reversed().compactMap { offset -> ReadingAdviceDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else {
                return nil
            }
            return ReadingAdviceDay(
                date: date,
                minutes: repository.displayedReadingMinutes(for: date),
                hourlyMinutes: repository.hourlyReadingMinutes(for: date)
            )
        }
        return makeSuggestions(
            input: ReadingAdviceInput(
                days: days,
                now: now
            )
        )
    }

    func makeSuggestions(input: ReadingAdviceInput) -> [ReadingAdvice] {
        let recentDays = days(in: 1...14, input: input)
        let recentMinutes = recentDays.reduce(0) { $0 + $1.minutes }
        let recentActiveDays = recentDays.filter { $0.minutes > 0 }.count

        guard recentMinutes > 0 else {
            return [
                ReadingAdvice(
                    kind: .dataInsufficient,
                    text: L("完成一次阅读后，这里会根据阅读有效时长、频率和常用时段给出习惯建议。")
                )
            ]
        }

        var result = [primaryAdvice(input: input)]
        if let habitAdvice = secondaryHabitAdvice(days: recentDays) {
            result.append(habitAdvice)
        }

        if recentActiveDays < 3, result.first?.kind != .buildHistory {
            result[0] = buildHistoryAdvice(activeDays: recentActiveDays, minutes: recentMinutes)
        }
        return Array(result.prefix(2))
    }

    private func primaryAdvice(input: ReadingAdviceInput) -> ReadingAdvice {
        let recentDays = days(in: 1...14, input: input)
        let recentMinutes = recentDays.reduce(0) { $0 + $1.minutes }
        let recentActiveDays = recentDays.filter { $0.minutes > 0 }.count
        guard recentActiveDays >= 3 else {
            return buildHistoryAdvice(activeDays: recentActiveDays, minutes: recentMinutes)
        }

        if let inactiveDays = inactiveDayCount(input: input), inactiveDays >= 2 {
            return ReadingAdvice(
                kind: .resumeReading,
                text: LF(
                    "阅读记录已中断 %d 天，近期的阅读连续性发生了变化。可以留意接下来的阅读频率。",
                    inactiveDays
                )
            )
        }

        let currentDays = days(in: 1...7, input: input)
        let previousDays = days(in: 8...14, input: input)
        let currentMinutes = currentDays.reduce(0) { $0 + $1.minutes }
        let previousMinutes = previousDays.reduce(0) { $0 + $1.minutes }
        let currentActiveDays = currentDays.filter { $0.minutes > 0 }.count

        if previousMinutes >= 30, currentMinutes * 100 <= previousMinutes * 70 {
            return ReadingAdvice(
                kind: .weeklyRecovery,
                text: LF(
                    "近 7 个完整日阅读 %d 分钟，比此前 7 日少 %d 分钟，近期阅读频率或时长有所下降。",
                    currentMinutes,
                    previousMinutes - currentMinutes
                )
            )
        }

        if currentMinutes >= 40, currentActiveDays <= 2 {
            return ReadingAdvice(
                kind: .spreadReadingDays,
                text: LF(
                    "近 7 个完整日的 %d 分钟集中在 %d 个阅读日，阅读时间分布较集中。可以留意这种节奏是否影响休息。",
                    currentMinutes,
                    currentActiveDays
                )
            )
        }

        let average = currentActiveDays > 0 ? currentMinutes / currentActiveDays : 0
        return ReadingAdvice(
            kind: .keepRhythm,
            text: LF(
                "近 7 个完整日阅读 %d 天，共 %d 分钟，平均每个阅读日 %d 分钟，当前阅读节奏较稳定。",
                currentActiveDays,
                currentMinutes,
                average
            )
        )
    }

    private func buildHistoryAdvice(activeDays: Int, minutes: Int) -> ReadingAdvice {
        ReadingAdvice(
            kind: .buildHistory,
            text: LF(
                "近 14 个完整日有 %d 个阅读日，共 %d 分钟。当前记录较少，暂不判断长期阅读习惯。",
                activeDays,
                minutes
            )
        )
    }

    private func preferredTimeAdvice(days: [ReadingAdviceDay]) -> ReadingAdvice? {
        let validDays = days.filter { $0.hourlyMinutes.count >= 24 }
        let totalMinutes = validDays.reduce(0.0) { result, day in
            result + day.hourlyMinutes.reduce(0) { $0 + filteredHour($1) }
        }
        guard totalMinutes >= 60 else { return nil }

        let windows = (0..<24).map { start -> (start: Int, minutes: Double, days: Int) in
            let next = (start + 1) % 24
            let minutes = validDays.reduce(0.0) {
                $0 + filteredHour($1.hourlyMinutes[start]) + filteredHour($1.hourlyMinutes[next])
            }
            let activeDays = validDays.filter {
                filteredHour($0.hourlyMinutes[start]) + filteredHour($0.hourlyMinutes[next]) > 0
            }.count
            return (start, minutes, activeDays)
        }
        guard let best = windows.max(by: { $0.minutes < $1.minutes }),
              best.days >= 3,
              best.minutes / totalMinutes >= 0.30 else { return nil }

        let range = String(
            format: "%02d:00–%02d:00",
            best.start,
            (best.start + 2) % 24
        )
        return ReadingAdvice(
            kind: .preferredTime,
            text: LF("近 14 个完整日最常在 %@ 阅读，这已经是相对稳定的常用阅读时段。", range)
        )
    }

    private func secondaryHabitAdvice(days: [ReadingAdviceDay]) -> ReadingAdvice? {
        lateNightAdvice(days: days)
            ?? sustainableDurationAdvice(days: days)
            ?? preferredTimeAdvice(days: days)
    }

    private func lateNightAdvice(days: [ReadingAdviceDay]) -> ReadingAdvice? {
        let validDays = days.filter { $0.hourlyMinutes.count >= 24 }
        let total = validDays.reduce(0.0) { result, day in
            result + day.hourlyMinutes.reduce(0) { $0 + filteredHour($1) }
        }
        guard total >= 60 else { return nil }
        let lateNightMinutes = validDays.reduce(0.0) { result, day in
            result + day.hourlyMinutes[0..<5].reduce(0) { $0 + filteredHour($1) }
        }
        let lateNightDays = validDays.filter {
            $0.hourlyMinutes[0..<5].contains { filteredHour($0) > 0 }
        }.count
        guard lateNightDays >= 3, lateNightMinutes / total >= 0.30 else { return nil }
        return ReadingAdvice(
            kind: .lateNightReading,
            text: LF(
                "近 14 个完整日有 %d 天在 00:00–05:00 阅读，共 %d 分钟。如果已经影响休息，可以关注深夜阅读时间的变化。",
                lateNightDays,
                Int(lateNightMinutes.rounded())
            )
        )
    }

    private func sustainableDurationAdvice(days: [ReadingAdviceDay]) -> ReadingAdvice? {
        let values = days.map(\.minutes).filter { $0 > 0 }.sorted()
        guard values.count >= 3 else { return nil }
        let median = values[values.count / 2]
        let deviations = values.map { abs($0 - median) }.sorted()
        let mad = deviations[deviations.count / 2]
        let maximum = values.last ?? median
        guard mad >= max(30, median / 2) || maximum - median >= max(30, median * 3 / 4) else {
            return nil
        }
        return ReadingAdvice(
            kind: .sustainableDuration,
            text: LF(
                "近 14 个完整日每个阅读日通常约 %d 分钟，单日最高 %d 分钟，阅读有效时长波动较大。可以留意高强度阅读后是否影响休息。",
                median,
                maximum
            )
        )
    }

    private func filteredHour(_ minutes: Double) -> Double {
        minutes >= 5 ? minutes : 0
    }

    private func inactiveDayCount(input: ReadingAdviceInput) -> Int? {
        guard let lastDate = input.days.last(where: { $0.minutes > 0 })?.date else {
            return nil
        }
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastDate),
            to: calendar.startOfDay(for: input.now)
        ).day
    }

    private func days(in offsets: ClosedRange<Int>, input: ReadingAdviceInput) -> [ReadingAdviceDay] {
        input.days.compactMap { day in
            let offset = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: day.date),
                to: calendar.startOfDay(for: input.now)
            ).day ?? Int.max
            guard offsets.contains(offset) else { return nil }
            return ReadingAdviceDay(
                date: day.date,
                minutes: max(day.minutes, 0),
                hourlyMinutes: day.hourlyMinutes.map { max($0, 0) }
            )
        }
    }
}
