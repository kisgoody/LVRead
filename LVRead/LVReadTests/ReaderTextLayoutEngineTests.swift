import XCTest
@testable import LVRead

final class ReaderTextLayoutEngineTests: XCTestCase {

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
}
