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

    func testPaginationPreservesEveryUTF16CodeUnit() throws {
        let content = String(repeating: "中文🙂e\u{301}，分页不可缺字。\n", count: 80)
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

        XCTAssertEqual(pages.map(\.content).joined(), content)
        for pair in zip(pages, pages.dropFirst()) {
            XCTAssertEqual(pair.0.endCharOffset, pair.1.startCharOffset)
        }
        XCTAssertEqual(pages.first?.startCharOffset, 0)
        XCTAssertEqual(pages.last?.endCharOffset, content.utf16.count)
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
}
