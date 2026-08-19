import XCTest
import CoreText
@testable import LVRead

final class ReaderTextLayoutEngineTests: XCTestCase {

    func testOnlyIPadLandscapeSimulationUsesTwoPagesPerTurn() {
        let landscape = CGSize(width: 1_024, height: 768)
        let portrait = CGSize(width: 768, height: 1_024)

        XCTAssertTrue(NativeReaderPresentationPolicy.usesDoublePage(
            idiom: .pad,
            size: landscape,
            navigationMode: .simulation
        ))
        XCTAssertFalse(NativeReaderPresentationPolicy.usesDoublePage(
            idiom: .phone,
            size: landscape,
            navigationMode: .simulation
        ))
        XCTAssertFalse(NativeReaderPresentationPolicy.usesDoublePage(
            idiom: .pad,
            size: portrait,
            navigationMode: .simulation
        ))
        XCTAssertFalse(NativeReaderPresentationPolicy.usesDoublePage(
            idiom: .pad,
            size: landscape,
            navigationMode: .horizontal
        ))
        XCTAssertEqual(NativeReaderPresentationPolicy.pageTurnDistance(usesDoublePage: true), 2)
        XCTAssertEqual(NativeReaderPresentationPolicy.pageTurnDistance(usesDoublePage: false), 1)
    }

    func testBookThicknessMovesFromRightToLeftWithProgress() {
        let beginning = NativeBookThickness.widths(progress: 0)
        let middle = NativeBookThickness.widths(progress: 0.5)
        let end = NativeBookThickness.widths(progress: 1)

        XCTAssertLessThan(beginning.left, beginning.right)
        XCTAssertEqual(middle.left, middle.right, accuracy: 0.001)
        XCTAssertGreaterThan(end.left, end.right)
        XCTAssertEqual(beginning.left, NativeBookSpreadMetrics.minimumThickness)
        XCTAssertEqual(beginning.right, NativeBookSpreadMetrics.maximumThickness)
        XCTAssertGreaterThan(
            NativeBookSpreadMetrics.coverHorizontalOutset,
            NativeBookSpreadMetrics.maximumThickness
        )
        XCTAssertLessThan(
            NativeBookSpreadMetrics.coverVerticalOutset,
            NativeBookSpreadMetrics.coverHorizontalOutset
        )
        XCTAssertEqual(NativeBookSpreadMetrics.pageCornerRadius, 12)
        XCTAssertGreaterThan(
            NativeBookSpreadMetrics.coverCornerRadius,
            NativeBookSpreadMetrics.pageCornerRadius
        )
    }

    func testSpreadChromeKeepsControlsOnTheRequestedPage() {
        XCTAssertTrue(NativeReaderPageChrome.spreadLeft.showsBackButton)
        XCTAssertFalse(NativeReaderPageChrome.spreadLeft.showsChapter)
        XCTAssertFalse(NativeReaderPageChrome.spreadLeft.showsTimeAndBattery)
        XCTAssertFalse(NativeReaderPageChrome.spreadRight.showsBackButton)
        XCTAssertTrue(NativeReaderPageChrome.spreadRight.showsChapter)
        XCTAssertTrue(NativeReaderPageChrome.spreadRight.showsTimeAndBattery)
    }

    func testEveryEnglishFontPaginatesEnglishText() throws {
        let content = String(repeating: "Alice was beginning to get very tired of sitting by her sister. ", count: 80)
        for option in FontManager.shared.options(for: .english) where !option.id.hasPrefix("custom:") {
            var settings = ReadingSettings.default
            settings.fontFamily = option.id
            let ranges = try ReaderTextLayoutEngine.pageRanges(
                content: content,
                pageSize: CGSize(width: 390, height: 700),
                settings: settings
            )
            XCTAssertFalse(ranges.isEmpty, "English font failed: \(option.id)")
            XCTAssertEqual(ranges.last?.endOffset, (content as NSString).length)
        }
    }

    func testTextRectIsHorizontallyCentered() {
        var settings = ReadingSettings.default
        settings.pageMarginHorizontal = 10

        let layout = ReaderTextLayoutEngine.layout(
            pageSize: CGSize(width: 400, height: 800),
            settings: settings
        )

        XCTAssertEqual(layout.textRect.minX, 40, accuracy: 0.001)
        XCTAssertEqual(400 - layout.textRect.maxX, 40, accuracy: 0.001)
    }

    func testParagraphUsesJustifiedAlignment() {
        let value = ReaderTextLayoutEngine.attributedString(
            content: "中文正文用于验证段落样式",
            settings: .default
        )
        let paragraph = value.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle

        XCTAssertEqual(paragraph?.alignment, .justified)
    }

    func testParagraphSpacingIsDesiredHeightMinusLineSpacingHeight() {
        var settings = ReadingSettings.default
        settings.lineSpacing = 1.4
        settings.paragraphSpacing = 2.0

        let layout = ReaderTextLayoutEngine.layout(
            pageSize: CGSize(width: 390, height: 844),
            settings: settings
        )

        let x = layout.font.lineHeight * 1.0
        let y = layout.font.lineHeight * 0.4
        XCTAssertEqual(layout.paragraphStyle.lineSpacing, y, accuracy: 0.001)
        XCTAssertEqual(layout.paragraphStyle.paragraphSpacing, x - y, accuracy: 0.001)
    }

    func testMissingParagraphSpacingFallsBackToLineSpacing() throws {
        let encoded = try JSONEncoder().encode(ReadingSettings.default)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "paragraphSpacing")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let settings = try JSONDecoder().decode(ReadingSettings.self, from: legacyData)

        XCTAssertNil(settings.paragraphSpacing)
        let layout = ReaderTextLayoutEngine.layout(
            pageSize: CGSize(width: 390, height: 844),
            settings: settings
        )
        XCTAssertEqual(layout.paragraphStyle.paragraphSpacing, 0, accuracy: 0.001)
    }

    func testPaginationPreservesEveryUTF16CodeUnit() throws {
        let content = String(repeating: "中文🙂e\u{301}，分页不可缺字。\n", count: 80)
        let expected = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: content)
        let chapter = Chapter(
            bookId: "book-1",
            title: "测试章节",
            orderIndex: 0
        )

        let pages = try ReaderTextLayoutEngine.pages(
            content: content,
            chapter: chapter,
            chapterIndex: 0,
            pageSize: CGSize(width: 320, height: 480),
            settings: .default
        )

        XCTAssertEqual(pages.map(\.content).joined(), expected)
        for pair in zip(pages, pages.dropFirst()) {
            XCTAssertEqual(pair.0.endCharOffset, pair.1.startCharOffset)
        }
        XCTAssertEqual(pages.first?.startCharOffset, 0)
        XCTAssertEqual(pages.last?.endCharOffset, expected.utf16.count)
    }

    func testTextContentCollapsesRepeatedLineBreaksBeforePagination() throws {
        let content = "第一段\r\n\r\n第二段\n\n\n第三段\r第四段\u{2028}\u{2028}第五段"
        let ranges = try ReaderTextLayoutEngine.pageRanges(
            content: content,
            pageSize: CGSize(width: 390, height: 844),
            settings: .default
        )

        let expected = "第一段\n第二段\n第三段\n第四段\n第五段"
        XCTAssertEqual(ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: content), expected)
        XCTAssertEqual(ranges.last?.endOffset, expected.utf16.count)
    }

    func testSmallPageNeverProducesZeroLengthRange() throws {
        var settings = ReadingSettings.default
        settings.fontSize = 32

        let ranges = try ReaderTextLayoutEngine.pageRanges(
            content: "一二三四五六七八九十",
            pageSize: CGSize(width: 80, height: 80),
            settings: settings
        )

        XCTAssertFalse(ranges.isEmpty)
        XCTAssertTrue(ranges.allSatisfy { $0.length > 0 })
    }

    func testEmptyContentReturnsNoPages() throws {
        let ranges = try ReaderTextLayoutEngine.pageRanges(
            content: "",
            pageSize: CGSize(width: 320, height: 480),
            settings: .default
        )

        XCTAssertTrue(ranges.isEmpty)
    }

    func testShortChapterWithBodyIsPreserved() {
        XCTAssertFalse(
            ReaderChapterContentPolicy.isTitleOnly(
                content: "序言\n这是正文。",
                chapterTitle: "序言"
            )
        )
    }

    func testEmptyOrMatchingTitleContentIsTitleOnly() {
        XCTAssertTrue(
            ReaderChapterContentPolicy.isTitleOnly(
                content: "\n　\t",
                chapterTitle: "分隔章"
            )
        )
        XCTAssertTrue(
            ReaderChapterContentPolicy.isTitleOnly(
                content: " 第 一 章\n",
                chapterTitle: "第一章"
            )
        )
    }

    func testEquivalentAdjacentTitlesAreDeduplicated() {
        XCTAssertTrue(
            ReaderChapterContentPolicy.titlesMatch("第一章", " 第 一 章\n")
        )
    }

    func testDifferentTitleOnlyChapterIsMergedWithNextChapter() {
        let merged = ReaderChapterContentPolicy.merging(
            pendingTitles: ["序幕"],
            with: "第一章\n真正的正文内容。"
        )

        XCTAssertEqual(merged, "序幕\n\n第一章\n真正的正文内容。")
    }

    func testRepeatedLeadingChapterTitlesAreRemovedBeforePagination() {
        let result = ReaderChapterContentPolicy.removingRepeatedLeadingTitles(
            from: "第一章\n 第 一 章 \n\n正文中的第一章不应删除。",
            chapterTitle: "第一章"
        )

        XCTAssertEqual(result, "第一章\n\n正文中的第一章不应删除。")
    }

    func testDuplicateLeadingTitlesAlwaysKeepOneTitle() {
        let result = ReaderChapterContentPolicy.removingRepeatedLeadingTitles(
            from: "第一章\n\n后续正文。",
            chapterTitle: "第一章"
        )

        XCTAssertEqual(result, "第一章\n\n后续正文。")
    }

    func testNativeDuplicateHeadingsAlwaysKeepOneTitle() {
        let result = NativeDocumentSanitizer.removeDuplicateHeading(
            from: "第一章\n 第 一 章 \n正文内容。",
            title: "第一章"
        )

        XCTAssertEqual(result, "第一章\n正文内容。")
    }

    func testDirectoryDeduplicatesAllEquivalentTitles() {
        let chapters = [
            Chapter(bookId: "book", title: "第一章", orderIndex: 0),
            Chapter(bookId: "book", title: " 第 一 章 ", orderIndex: 1),
            Chapter(bookId: "book", title: "第二章", orderIndex: 2),
            Chapter(bookId: "book", title: "第一章", orderIndex: 3)
        ]

        let entries = ReaderChapterContentPolicy.directoryEntries(from: chapters)

        XCTAssertEqual(entries.map(\.chapter.title), ["第一章", "第二章"])
        XCTAssertEqual(entries[0].sourceIndices, [0, 1, 3])
        XCTAssertEqual(entries[1].sourceIndex, 2)
    }

    func testNativeDocumentPaginationHasNoGaps() throws {
        let text = String(repeating: "原生CoreText分页必须连续且不能缺字。\n", count: 100)
        let normalizedText = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: text)
        let chapter = Chapter(bookId: "book", title: "第一章", orderIndex: 0)
        let pages = try NativeDocumentPaginator.pages(
            text: normalizedText,
            chapter: chapter,
            chapterIndex: 0,
            size: CGSize(width: 390, height: 720),
            settings: .default
        )
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.text).joined(), normalizedText)
        for pair in zip(pages, pages.dropFirst()) {
            XCTAssertEqual(pair.0.endOffset, pair.1.startOffset)
        }
    }

    func testNativePaginationNeverKeepsABottomClippedLine() throws {
        var settings = ReadingSettings.default
        settings.fontSize = 24
        settings.lineSpacing = 1.2
        let size = CGSize(width: 260, height: 118)
        let text = String(repeating: "第一行和第二行之间必须按完整行分页，不能裁切底部文字。", count: 24)
        let chapter = Chapter(bookId: "book", title: "第一章", orderIndex: 0)

        let pages = try NativeDocumentPaginator.pages(
            text: text,
            chapter: chapter,
            chapterIndex: 0,
            size: size,
            textInsets: .zero,
            settings: settings
        )

        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.text).joined(), text)
        for page in pages {
            let attributed = NativeDocumentTypography.attributed(page.text, settings: settings, color: .label)
            let frame = CTFramesetterCreateFrame(
                CTFramesetterCreateWithAttributedString(attributed),
                CFRange(location: 0, length: 0),
                CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
                nil
            )
            let complete = NativeDocumentTypography.completeVisibleRange(
                in: frame,
                pathHeight: size.height
            )
            XCTAssertEqual(complete.length, attributed.length)
        }
    }

    func testNativeBottomInsetUsesCompactStatusArea() {
        var settings = ReadingSettings.default
        settings.pageMarginVertical = 2
        let size = CGSize(width: 390, height: 844)
        let safeArea = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        let insets = NativeDocumentTypography.insets(
            size: size,
            safeAreaInsets: safeArea,
            settings: settings
        )
        let contentHeight = size.height - safeArea.top - safeArea.bottom
            - NativeDocumentTypography.topReadingStatusHeight
            - NativeDocumentTypography.bottomReadingStatusHeight
        let expectedBottom = safeArea.bottom
            + NativeDocumentTypography.bottomReadingStatusHeight
            + contentHeight * 0.02

        XCTAssertEqual(insets.bottom, expectedBottom, accuracy: 0.001)
        XCTAssertEqual(NativeDocumentTypography.bottomReadingStatusHeight, 24)
    }

    func testNativeCoreTextPathMapsUIKitTopAndBottomInsetsCorrectly() {
        let size = CGSize(width: 390, height: 844)
        let insets = UIEdgeInsets(top: 120, left: 24, bottom: 72, right: 24)

        let pathRect = NativeDocumentTypography.coreTextPathRect(
            size: size,
            insets: insets
        )

        XCTAssertEqual(pathRect.minY, insets.bottom, accuracy: 0.001)
        XCTAssertEqual(size.height - pathRect.maxY, insets.top, accuracy: 0.001)
        XCTAssertEqual(pathRect.width, size.width - insets.left - insets.right, accuracy: 0.001)
    }

    func testContinuousPageSpacingFollowsLineAndParagraphSettings() {
        var settings = ReadingSettings.default
        settings.lineSpacing = 1.4
        settings.paragraphSpacing = 2.0
        let font = FontManager.shared.font(
            named: settings.fontFamily,
            size: CGFloat(settings.fontSize)
        )

        XCTAssertEqual(
            NativeDocumentTypography.continuousPageSpacing(after: "正文", settings: settings),
            font.lineHeight * 0.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NativeDocumentTypography.continuousPageSpacing(after: "正文\n", settings: settings),
            font.lineHeight,
            accuracy: 0.001
        )
    }

    func testNativeWindowRejectsStaleBackwardReload() {
        let current = NativeDocumentPage(
            chapterIndex: 4,
            pageIndex: 3,
            chapterTitle: "第五章",
            startOffset: 300,
            endOffset: 400,
            text: "当前页",
            image: nil
        )
        let staleWindow = [
            NativeDocumentPage(
                chapterIndex: 0,
                pageIndex: 0,
                chapterTitle: "第一章",
                startOffset: 0,
                endOffset: 100,
                text: "旧页面",
                image: nil
            )
        ]

        XCTAssertNil(
            NativeDocumentWindowResolver.targetIndex(
                in: staleWindow,
                requestedTarget: 0,
                preserving: current
            )
        )
        XCTAssertEqual(
            NativeDocumentWindowResolver.targetIndex(
                in: staleWindow,
                requestedTarget: 0,
                preserving: nil
            ),
            0
        )

        let repaginatedWindow = [
            NativeDocumentPage(
                chapterIndex: 4,
                pageIndex: 2,
                chapterTitle: "第五章",
                startOffset: 250,
                endOffset: 350,
                text: "重新分页后的当前页",
                image: nil
            )
        ]
        XCTAssertEqual(
            NativeDocumentWindowResolver.targetIndex(
                in: repaginatedWindow,
                requestedTarget: 0,
                preserving: current
            ),
            0
        )
    }
}
