import XCTest
import os.log
import UIKit
@testable import LVRead

// MARK: - ReadingStats Model Tests

final class ReadingStatsModelTests: XCTestCase {
    
    func testReadingStatsDefaultInit() throws {
        let stats = ReadingStats()
        XCTAssertEqual(stats.totalBooksRead, 0)
        XCTAssertEqual(stats.totalReadingTimeSeconds, 0)
        XCTAssertEqual(stats.totalPagesRead, 0)
        XCTAssertTrue(stats.dailyReadingMinutes.isEmpty)
        XCTAssertTrue(stats.weeklyReadingMinutes.isEmpty)
    }
    
    func testReadingStatsCustomInit() throws {
        let stats = ReadingStats(
            totalBooksRead: 5,
            totalReadingTimeSeconds: 7200,
            totalPagesRead: 350,
            dailyReadingMinutes: ["2026-06-27": 30],
            weeklyReadingMinutes: ["2026-W26": 120]
        )
        XCTAssertEqual(stats.totalBooksRead, 5)
        XCTAssertEqual(stats.totalReadingTimeSeconds, 7200)
        XCTAssertEqual(stats.totalPagesRead, 350)
        XCTAssertEqual(stats.dailyReadingMinutes["2026-06-27"], 30)
        XCTAssertEqual(stats.weeklyReadingMinutes["2026-W26"], 120)
    }
    
    func testTotalReadingHours() throws {
        let stats = ReadingStats(totalReadingTimeSeconds: 3600)
        XCTAssertEqual(stats.totalReadingHours, 1.0, accuracy: 0.01)
    }
    
    func testTotalReadingHoursZero() throws {
        let stats = ReadingStats()
        XCTAssertEqual(stats.totalReadingHours, 0.0, accuracy: 0.01)
    }
    
    func testAverageMinutesPerDay() throws {
        let stats = ReadingStats(dailyReadingMinutes: [
            "2026-06-25": 30,
            "2026-06-26": 45,
            "2026-06-27": 15
        ])
        XCTAssertEqual(stats.averageMinutesPerDay, 30.0, accuracy: 0.01)
    }
    
    func testAverageMinutesPerDayEmpty() throws {
        let stats = ReadingStats()
        XCTAssertEqual(stats.averageMinutesPerDay, 0.0, accuracy: 0.01)
    }
    
    func testReadingStatsCodable() throws {
        let stats = ReadingStats(
            totalBooksRead: 3,
            totalReadingTimeSeconds: 5400,
            totalPagesRead: 120
        )
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(ReadingStats.self, from: data)
        XCTAssertEqual(decoded.totalBooksRead, 3)
        XCTAssertEqual(decoded.totalReadingTimeSeconds, 5400)
        XCTAssertEqual(decoded.totalPagesRead, 120)
    }
}

// MARK: - ReadingStatsRepository Tests

final class ReadingStatsRepositoryTests: XCTestCase {
    
    func testAddReadingTime() throws {
        let repo = ReadingStatsRepository.shared
        let before = repo.getStats()
        repo.addReadingTime(120)
        let after = repo.getStats()
        XCTAssertEqual(after.totalReadingTimeSeconds, before.totalReadingTimeSeconds + 120)
    }
    
    func testAddPagesRead() throws {
        let repo = ReadingStatsRepository.shared
        let before = repo.getStats()
        repo.addPagesRead(10)
        let after = repo.getStats()
        XCTAssertEqual(after.totalPagesRead, before.totalPagesRead + 10)
    }

    func testRecordSessionUpdatesTotalsAndBookDimension() throws {
        let repo = ReadingStatsRepository.shared
        let bookId = "stats-test-\(UUID().uuidString)"
        let before = repo.getStats()

        repo.recordSession(bookId: bookId, seconds: 75, pages: 3)

        let after = repo.getStats()
        let bookStat = try XCTUnwrap(repo.getBookStats()[bookId])
        XCTAssertEqual(after.totalReadingTimeSeconds, before.totalReadingTimeSeconds + 75)
        XCTAssertEqual(after.totalPagesRead, before.totalPagesRead + 3)
        XCTAssertEqual(bookStat.readingTimeSeconds, 75)
        XCTAssertEqual(bookStat.pagesRead, 3)
    }

    func testActiveIntervalIsRecordedInHourlyDimension() throws {
        let repo = ReadingStatsRepository.shared
        let calendar = Calendar.current
        let start = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 10, second: 0, of: Date()))
        let before = repo.hourlyReadingMinutes()[12]

        repo.recordActiveInterval(
            bookId: "hourly-stats-test-\(UUID().uuidString)",
            from: start,
            to: start.addingTimeInterval(120),
            pages: 0
        )

        XCTAssertEqual(repo.hourlyReadingMinutes()[12], before + 2, accuracy: 0.01)
    }
    
    func testMarkBookFinished() throws {
        let repo = ReadingStatsRepository.shared
        let before = repo.getStats()
        repo.markBookFinished()
        let after = repo.getStats()
        XCTAssertEqual(after.totalBooksRead, before.totalBooksRead + 1)
    }
    
    func testCurrentStreak() throws {
        let repo = ReadingStatsRepository.shared
        let streak = ReadingAnalytics(stats: repo.getStats()).currentStreak
        XCTAssertGreaterThanOrEqual(streak, 0)
    }
    
    func testLongestStreak() throws {
        let repo = ReadingStatsRepository.shared
        let longest = ReadingAnalytics(stats: repo.getStats()).longestStreak
        XCTAssertGreaterThanOrEqual(longest, 0)
    }
    
    func testWeeklyChartData() throws {
        let repo = ReadingStatsRepository.shared
        let chartData = ReadingAnalytics(stats: repo.getStats()).weeklyChartData
        XCTAssertEqual(chartData.count, 7)
    }
}

final class LVModuleSubtitleProviderTests: XCTestCase {
    func testDailyModuleSubtitlesAreStableAndUnique() {
        let first = [
            LVModuleSubtitleProvider.subtitle(for: .shelf),
            LVModuleSubtitleProvider.subtitle(for: .notes),
            LVModuleSubtitleProvider.subtitle(for: .profile)
        ]
        let second = [
            LVModuleSubtitleProvider.subtitle(for: .shelf),
            LVModuleSubtitleProvider.subtitle(for: .notes),
            LVModuleSubtitleProvider.subtitle(for: .profile)
        ]

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, 3)
    }
}

final class BookRepositoryUpdateTests: XCTestCase {
    func testRenamingBookPreservesChaptersAndFilePath() throws {
        let repository = BookRepository.shared
        let id = "rename-test-\(UUID().uuidString)"
        let original = Book(
            id: id,
            title: "修改前",
            filePath: "Books/rename-test.epub",
            fileHash: UUID().uuidString,
            fileSize: 128,
            fileFormat: .epub,
            source: .localFile
        )
        _ = try repository.insert(original).get()
        repository.insertChapters([
            Chapter(bookId: id, title: "第一章", orderIndex: 0, internalHref: "chapter1.xhtml")
        ])

        var renamed = original
        renamed.title = "修改后"
        _ = try repository.update(renamed).get()

        let stored = try XCTUnwrap(repository.getById(id))
        XCTAssertEqual(stored.title, "修改后")
        XCTAssertEqual(stored.filePath, original.filePath)
        XCTAssertEqual(repository.getChapters(for: id).map(\.title), ["第一章"])
        _ = repository.delete(id)
    }
}

// MARK: - LVLogger Tests

final class LVLoggerTests: XCTestCase {
    
    func testLoggerLevelOrdering() throws {
        XCTAssertLessThan(LVLogger.Level.verbose, LVLogger.Level.debug)
        XCTAssertLessThan(LVLogger.Level.debug, LVLogger.Level.info)
        XCTAssertLessThan(LVLogger.Level.info, LVLogger.Level.warning)
        XCTAssertLessThan(LVLogger.Level.warning, LVLogger.Level.error)
    }
    
    func testLoggerOSLogTypeMapping() throws {
        XCTAssertEqual(LVLogger.Level.verbose.osLogType, OSLogType.debug)
        XCTAssertEqual(LVLogger.Level.debug.osLogType, OSLogType.debug)
        XCTAssertEqual(LVLogger.Level.info.osLogType, OSLogType.info)
        XCTAssertEqual(LVLogger.Level.warning.osLogType, OSLogType.default)
        XCTAssertEqual(LVLogger.Level.error.osLogType, OSLogType.error)
    }
    
    func testLoggerCategories() throws {
        XCTAssertEqual(LVLogger.Category.network.rawValue, "Network")
        XCTAssertEqual(LVLogger.Category.parser.rawValue, "Parser")
        XCTAssertEqual(LVLogger.Category.database.rawValue, "Database")
        XCTAssertEqual(LVLogger.Category.ui.rawValue, "UI")
        XCTAssertEqual(LVLogger.Category.general.rawValue, "General")
    }
    
    func testLoggerLogDoesNotCrash() throws {
        LVLogger.log("Test message")
        LVLogger.verbose("Verbose test")
        LVLogger.debug("Debug test")
        LVLogger.info("Info test")
        LVLogger.warning("Warning test")
        LVLogger.error("Error test")
        LVLogger.log("Categorized test", category: .network)
        LVLogger.log("DB test", category: .database)
    }
}

// MARK: - Bookmark Model Tests

final class BookmarkModelTests: XCTestCase {
    
    func testBookmarkInit() throws {
        let bm = Bookmark(bookId: "b1", chapterIndex: 0, pageOffset: 5, chapterTitle: "Ch1", snippet: "text")
        XCTAssertEqual(bm.bookId, "b1")
        XCTAssertEqual(bm.chapterIndex, 0)
        XCTAssertEqual(bm.pageOffset, 5)
        XCTAssertEqual(bm.chapterTitle, "Ch1")
        XCTAssertEqual(bm.snippet, "text")
        XCTAssertNotNil(bm.id)
        XCTAssertNotNil(bm.createdAt)
    }
    
    func testBookmarkEquality() throws {
        let id = UUID().uuidString
        let createdAt = Date()
        let bm1 = Bookmark(
            id: id,
            bookId: "b1",
            chapterIndex: 0,
            pageOffset: 5,
            createdAt: createdAt
        )
        let bm2 = Bookmark(
            id: id,
            bookId: "b1",
            chapterIndex: 0,
            pageOffset: 5,
            createdAt: createdAt
        )
        XCTAssertEqual(bm1, bm2)
    }
}

// MARK: - Highlight Model Tests

final class HighlightModelTests: XCTestCase {
    
    func testHighlightInit() throws {
        let h = Highlight(
            bookId: "b1",
            chapterIndex: 0,
            pageOffset: 0,
            startCharOffset: 0,
            endCharOffset: 5,
            text: "hello",
            color: "#FFD700",
            note: "my note"
        )
        XCTAssertEqual(h.text, "hello")
        XCTAssertEqual(h.color, "#FFD700")
        XCTAssertEqual(h.note, "my note")
    }
    
    func testHighlightWithoutNote() throws {
        let h = Highlight(
            bookId: "b1",
            chapterIndex: 0,
            pageOffset: 0,
            startCharOffset: 0,
            endCharOffset: 5,
            text: "hello",
            color: "#FF0000",
            note: nil
        )
        XCTAssertNil(h.note)
        XCTAssertTrue(h.isExcerpt)
        XCTAssertFalse(h.isComment)
    }

    func testHighlightWithNoteIsComment() throws {
        let h = Highlight(
            bookId: "b1",
            chapterIndex: 0,
            pageOffset: 0,
            startCharOffset: 0,
            endCharOffset: 5,
            text: "hello",
            color: "#FF0000",
            note: "读后想法"
        )
        XCTAssertFalse(h.isExcerpt)
        XCTAssertTrue(h.isComment)
    }

    func testExcerptRangeRecoversAfterRepagination() throws {
        let text = "第一行\n第二行\n目标段落"
        let target = (text as NSString).range(of: "目标段落")
        let page = NativeDocumentPage(
            chapterIndex: 0,
            pageIndex: 0,
            chapterTitle: "测试",
            startOffset: 0,
            endOffset: (text as NSString).length,
            text: text,
            image: nil
        )
        let excerpt = Highlight(
            bookId: "b1",
            chapterIndex: 0,
            pageOffset: 0,
            startCharOffset: 0,
            endCharOffset: 4,
            text: "目标段落"
        )
        XCTAssertEqual(NativeCoreTextView.localRange(for: excerpt, page: page), target)
    }

    func testCoreTextLineOriginIncludesTextPathInsets() throws {
        let value = NativeDocumentTypography.absoluteLineOrigin(
            CGPoint(x: 12, y: 30),
            pathOrigin: CGPoint(x: 20, y: 80)
        )
        XCTAssertEqual(value, CGPoint(x: 32, y: 110))
    }

}

final class NativeReaderChromeStyleTests: XCTestCase {
    func testChromeSurfaceMatchesSettingsSheetInEveryVisibleTheme() {
        for theme in ReadingTheme.visibleThemes {
            var settings = ReadingSettings.default
            settings.readingTheme = theme
            let surface = NativeReaderChromeStyle.surface(for: settings)
            XCTAssertTrue(surface.isEqual(UIColor(hex: theme.panelColor)), theme.displayName)
        }
    }
}

final class NativeListeningPillLayoutTests: XCTestCase {
    func testExpandedPillFitsThreeEqualButtons() {
        XCTAssertEqual(
            NativeListeningPillLayout.expandedWidth,
            NativeListeningPillLayout.buttonSize * 3
        )
        XCTAssertEqual(
            NativeListeningPillLayout.collapsedWidth,
            NativeListeningPillLayout.buttonSize
        )
    }

    func testListeningControlsFollowMenuVisibility() {
        XCTAssertEqual(
            NativeListeningControlsVisibility.resolve(menuVisible: true, isListening: true),
            NativeListeningControlsVisibility(pillVisible: true, footerVisible: false)
        )
        XCTAssertEqual(
            NativeListeningControlsVisibility.resolve(menuVisible: false, isListening: true),
            NativeListeningControlsVisibility(pillVisible: false, footerVisible: true)
        )
        XCTAssertEqual(
            NativeListeningControlsVisibility.resolve(menuVisible: false, isListening: false),
            NativeListeningControlsVisibility(pillVisible: false, footerVisible: false)
        )
    }
}

final class NativeListeningInterruptionPolicyTests: XCTestCase {
    func testOnlyActivePlaybackResumesAfterInterruption() {
        XCTAssertTrue(
            NativeListeningInterruptionPolicy.shouldResume(isListening: true, isPaused: false)
        )
        XCTAssertFalse(
            NativeListeningInterruptionPolicy.shouldResume(isListening: true, isPaused: true)
        )
        XCTAssertFalse(
            NativeListeningInterruptionPolicy.shouldResume(isListening: false, isPaused: false)
        )
    }
}

final class WebSyncConnectionStateTests: XCTestCase {
    func testConnectionStatesHaveDistinctUserFacingTitles() {
        XCTAssertEqual(WebSyncConnectionState.disconnected.title, "断开连接")
        XCTAssertEqual(WebSyncConnectionState.connecting.title, "连接中")
        XCTAssertEqual(WebSyncConnectionState.connected.title, "已连接")
    }

    func testOnlyConnectedBookUsesActiveAppearance() {
        XCTAssertTrue(WebSyncConnectionState.connected.isActive(for: "book-1", activeBookID: "book-1"))
        XCTAssertFalse(WebSyncConnectionState.connected.isActive(for: "book-2", activeBookID: "book-1"))
        XCTAssertFalse(WebSyncConnectionState.connecting.isActive(for: "book-1", activeBookID: "book-1"))
    }
}

final class NativeSpeechTextRangeTests: XCTestCase {
    func testSpokenWordExpandsToItsChineseSentence() throws {
        let text = "第一句。正在朗读这一句！第三句。"
        let spoken = (text as NSString).range(of: "朗读")
        let range = try XCTUnwrap(NativeSpeechTextRange.sentence(in: text, containing: spoken))
        XCTAssertEqual((text as NSString).substring(with: range), "正在朗读这一句！")
    }

    func testLastSentenceWithoutPunctuationIsHighlighted() throws {
        let text = "第一句。最后一句"
        let spoken = (text as NSString).range(of: "最后")
        let range = try XCTUnwrap(NativeSpeechTextRange.sentence(in: text, containing: spoken))
        XCTAssertEqual((text as NSString).substring(with: range), "最后一句")
    }

    func testSpeechBufferKeepsCrossPageSentenceInOneUtterance() throws {
        let first = NativeDocumentPage(
            chapterIndex: 0,
            pageIndex: 0,
            chapterTitle: "测试",
            startOffset: 0,
            endOffset: 6,
            text: "这是一个跨页",
            image: nil
        )
        let second = NativeDocumentPage(
            chapterIndex: 0,
            pageIndex: 1,
            chapterTitle: "测试",
            startOffset: 6,
            endOffset: 14,
            text: "的完整句子。下一句",
            image: nil
        )
        let buffer = try XCTUnwrap(NativeSpeechBuffer.make(pages: [first, second], startIndex: 0, offset: 0))
        XCTAssertEqual(buffer.text, "这是一个跨页的完整句子。")
        XCTAssertEqual(buffer.segments.count, 2)
        XCTAssertEqual(buffer.continuationPageID, second.id)
        XCTAssertEqual(buffer.continuationOffset, 6)
    }
}

// MARK: - Chapter Model Tests

final class ChapterModelTests: XCTestCase {
    
    func testChapterInit() throws {
        let chapter = Chapter(bookId: "book-1", title: "第一章", level: 1, orderIndex: 0)
        XCTAssertEqual(chapter.bookId, "book-1")
        XCTAssertEqual(chapter.title, "第一章")
        XCTAssertEqual(chapter.level, 1)
        XCTAssertEqual(chapter.orderIndex, 0)
        XCTAssertNotNil(chapter.id)
    }
}

// MARK: - LanDevice Model Tests

final class LanDeviceModelTests: XCTestCase {
    
    func testLanDeviceInit() throws {
        let device = LanDevice(
            id: "device-1",
            deviceName: "iPhone",
            ipAddress: "192.168.1.100",
            port: 8080
        )
        XCTAssertEqual(device.deviceName, "iPhone")
        XCTAssertEqual(device.ipAddress, "192.168.1.100")
        XCTAssertEqual(device.port, 8080)
    }
}

// MARK: - TransferTask Model Tests

final class TransferTaskModelTests: XCTestCase {
    
    func testTransferTaskInit() throws {
        let task = TransferTask(
            targetDeviceId: "device-1",
            direction: .send,
            bookIds: ["book-1"],
            totalBytes: 1_024_000
        )
        XCTAssertEqual(task.targetDeviceId, "device-1")
        XCTAssertEqual(task.direction, .send)
        XCTAssertEqual(task.bookIds, ["book-1"])
        XCTAssertEqual(task.totalBytes, 1_024_000)
        XCTAssertEqual(task.progress, 0.0)
        XCTAssertEqual(task.status, .pending)
    }
}
