import XCTest
@testable import LVRead

// MARK: - Parser Tests

final class ParserTests: XCTestCase {

    // MARK: - FileFormat Tests
    
    func testFileFormatDetection() throws {
        XCTAssertEqual(FileFormat.epub, FileFormat(rawValue: "EPUB"))
        XCTAssertEqual(FileFormat.txt, FileFormat(rawValue: "TXT"))
        XCTAssertEqual(FileFormat.pdf, FileFormat(rawValue: "PDF"))
        XCTAssertEqual(FileFormat.mobi, FileFormat(rawValue: "MOBI"))
        XCTAssertEqual(FileFormat.azw3, FileFormat(rawValue: "AZW3"))
    }
    
    func testFileFormatDisplayNames() throws {
        XCTAssertEqual(FileFormat.epub.displayName, "EPUB")
        XCTAssertEqual(FileFormat.txt.displayName, "TXT")
        XCTAssertEqual(FileFormat.pdf.displayName, "PDF")
    }
    
    func testFileFormatBadgeColors() throws {
        XCTAssertEqual(FileFormat.epub.badgeColor, "#FF5E3A")
        XCTAssertEqual(FileFormat.pdf.badgeColor, "#7B2FFF")
        XCTAssertEqual(FileFormat.txt.badgeColor, "#00D4AA")
    }
    
    func testFileFormatIcons() throws {
        XCTAssertEqual(FileFormat.epub.icon, "book.closed.fill")
        XCTAssertEqual(FileFormat.pdf.icon, "doc.text.fill")
        XCTAssertEqual(FileFormat.txt.icon, "doc.plaintext.fill")
    }

    // MARK: - BookSource Tests
    
    func testBookSourceProperties() throws {
        XCTAssertEqual(BookSource.shareImport.displayName, "分享导入")
        XCTAssertEqual(BookSource.localFile.displayName, "本地文件")
        XCTAssertEqual(BookSource.lanTransfer.displayName, "同网传输")
        
        XCTAssertEqual(BookSource.shareImport.displayColor, "#00D4AA")
        XCTAssertEqual(BookSource.localFile.displayColor, "#3B82F6")
        XCTAssertEqual(BookSource.lanTransfer.displayColor, "#F59E0B")
        
        XCTAssertEqual(BookSource.shareImport.icon, "square.and.arrow.up")
        XCTAssertEqual(BookSource.localFile.icon, "folder")
        XCTAssertEqual(BookSource.lanTransfer.icon, "wifi")
    }

    // MARK: - Book Model Tests
    
    func testBookInitialization() throws {
        let book = Book(
            title: "Test Book",
            author: "Test Author",
            filePath: "/path/to/book.epub",
            fileHash: "abc123",
            fileSize: 1024,
            fileFormat: .epub,
            source: .localFile
        )
        
        XCTAssertEqual(book.title, "Test Book")
        XCTAssertEqual(book.author, "Test Author")
        XCTAssertEqual(book.fileFormat, .epub)
        XCTAssertEqual(book.source, .localFile)
    }
    
    func testBookDefaultAuthor() throws {
        let book = Book(
            title: "Test",
            author: "",
            filePath: "/path/to/book.txt",
            fileHash: "def456",
            fileSize: 512,
            fileFormat: .txt,
            source: .localFile
        )
        
        XCTAssertEqual(book.author, "未知作者")
    }
    
    func testBookProgressDisplay() throws {
        let book = Book(
            title: "Test",
            author: "Author",
            filePath: "/path/to/book.txt",
            fileHash: "ghi789",
            fileSize: 512,
            fileFormat: .txt,
            source: .localFile,
            readingProgress: ReadingProgress(
                currentChapterIndex: 0,
                currentPageOffset: 10,
                totalPages: 100,
                progressPercent: 50.0,
                lastReadTimestamp: Date()
            )
        )
        
        XCTAssertEqual(book.progressPercentDisplay, "50.0%")
    }

    // MARK: - Chapter Model Tests
    
    func testChapterInitialization() throws {
        let chapter = Chapter(
            bookId: "book-123",
            title: "第一章 初入江湖",
            level: 1,
            orderIndex: 0,
            startOffset: 0,
            endOffset: 1000,
            pageCount: 10
        )
        
        XCTAssertEqual(chapter.title, "第一章 初入江湖")
        XCTAssertEqual(chapter.level, 1)
        XCTAssertEqual(chapter.orderIndex, 0)
    }

    // MARK: - ReadingSettings Tests
    
    func testReadingSettingsDefault() throws {
        let settings = ReadingSettings.default
        
        XCTAssertEqual(settings.fontSize, 23)
        XCTAssertEqual(settings.fontFamily, "系统默认")
        XCTAssertEqual(settings.lineSpacing, 1.3)
        XCTAssertEqual(settings.paragraphSpacing, 1.5)
        XCTAssertEqual(settings.pageMarginHorizontal, 7.0)
        XCTAssertEqual(settings.brightness, 1.0)
        XCTAssertEqual(settings.pageFlipMode, .cover)
        XCTAssertEqual(settings.nightMode, false)
        XCTAssertEqual(settings.autoReadEnabled, false)
        XCTAssertEqual(settings.autoReadSpeed, 5)
    }
    
    func testReadingSettingsCodable() throws {
        let settings = ReadingSettings.default
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ReadingSettings.self, from: data)
        
        XCTAssertEqual(settings.fontSize, decoded.fontSize)
        XCTAssertEqual(settings.fontFamily, decoded.fontFamily)
        XCTAssertEqual(settings.lineSpacing, decoded.lineSpacing)
        XCTAssertEqual(settings.pageFlipMode, decoded.pageFlipMode)
    }
    
    func testReadingSettingsCopy() throws {
        var settings = ReadingSettings.default
        settings.fontSize = 24
        settings.fontFamily = "宋体"
        
        XCTAssertEqual(settings.fontSize, 24)
        XCTAssertEqual(settings.fontFamily, "宋体")
        XCTAssertEqual(ReadingSettings.default.fontSize, 23) // Original unchanged
    }

    // MARK: - ReadingTheme Tests
    
    func testReadingThemeProperties() throws {
        XCTAssertEqual(ReadingTheme.white.backgroundColor, "#FFFFFF")
        XCTAssertEqual(ReadingTheme.white.textColor, "#1A1A1A")
        XCTAssertEqual(ReadingTheme.oled.backgroundColor, "#000000")
        XCTAssertEqual(ReadingTheme.warmYellow.textColor, "#3D3226")
    }
    
    func testAllReadingThemes() throws {
        let themes: [ReadingTheme] = [.white, .warmYellow, .mint, .latte, .midnight, .oled]
        for theme in themes {
            XCTAssertFalse(theme.backgroundColor.isEmpty)
            XCTAssertFalse(theme.textColor.isEmpty)
            XCTAssertFalse(theme.accentColor.isEmpty)
        }
    }

    // MARK: - PageFlipMode Tests
    
    func testPageFlipModeDisplayNames() throws {
        XCTAssertEqual(PageFlipMode.simulation.displayName, "仿真翻页")
        XCTAssertEqual(PageFlipMode.cover.displayName, "覆盖翻页")
        XCTAssertEqual(PageFlipMode.slide.displayName, "平移翻页")
        XCTAssertEqual(PageFlipMode.scroll.displayName, "上下滚动")
        XCTAssertEqual(PageFlipMode.none.displayName, "无动画")
    }
    
    func testAllPageFlipModes() throws {
        let modes: [PageFlipMode] = [.simulation, .cover, .slide, .scroll, .none]
        XCTAssertEqual(modes.count, 5)
    }

    // MARK: - EyeCareFilter Tests
    
    func testEyeCareFilterProperties() throws {
        XCTAssertEqual(EyeCareFilter.none.displayName, "冷白")
        XCTAssertEqual(EyeCareFilter.warmYellow.displayName, "暖黄")
        XCTAssertEqual(EyeCareFilter.mintGreen.displayName, "护眼绿")
    }
    
    func testEyeCareFilterColors() throws {
        XCTAssertEqual(EyeCareFilter.none.filterColor, "#FFFFFF")
        XCTAssertEqual(EyeCareFilter.warmYellow.filterColor, "#FFF8E7")
        XCTAssertEqual(EyeCareFilter.mintGreen.filterColor, "#C7EDCC")
    }

    // MARK: - BookMetadata Tests
    
    func testBookMetadataInitialization() throws {
        let chapter = Chapter(
            bookId: "book-1",
            title: "第一章",
            level: 1,
            orderIndex: 0
        )
        
        let metadata = BookMetadata(
            title: "Test Book",
            author: "Author",
            coverImageData: nil,
            chapters: [chapter],
            encoding: "UTF-8",
            totalCharCount: 10000
        )
        
        XCTAssertEqual(metadata.title, "Test Book")
        XCTAssertEqual(metadata.author, "Author")
        XCTAssertEqual(metadata.chapters.count, 1)
        XCTAssertEqual(metadata.encoding, "UTF-8")
        XCTAssertEqual(metadata.totalCharCount, 10000)
    }

    // MARK: - ReadingProgress Tests
    
    func testReadingProgressInitialization() throws {
        let progress = ReadingProgress(
            currentChapterIndex: 2,
            currentPageOffset: 15,
            totalPages: 100,
            progressPercent: 37.5,
            lastReadTimestamp: Date()
        )
        
        XCTAssertEqual(progress.currentChapterIndex, 2)
        XCTAssertEqual(progress.currentPageOffset, 15)
        XCTAssertEqual(progress.totalPages, 100)
        XCTAssertEqual(progress.progressPercent, 37.5)
    }
    
    func testReadingProgressDefault() throws {
        let progress = ReadingProgress()
        
        XCTAssertEqual(progress.currentChapterIndex, 0)
        XCTAssertEqual(progress.currentPageOffset, 0)
        XCTAssertEqual(progress.totalPages, 0)
        XCTAssertEqual(progress.progressPercent, 0.0)
    }

    // MARK: - Bookmark Tests
    
    func testBookmarkInitialization() throws {
        let bookmark = Bookmark(
            bookId: "book-1",
            chapterIndex: 1,
            pageOffset: 5,
            chapterTitle: "第一章",
            snippet: "这是书签摘录"
        )
        
        XCTAssertEqual(bookmark.bookId, "book-1")
        XCTAssertEqual(bookmark.chapterIndex, 1)
        XCTAssertEqual(bookmark.pageOffset, 5)
        XCTAssertEqual(bookmark.chapterTitle, "第一章")
        XCTAssertEqual(bookmark.snippet, "这是书签摘录")
    }

    // MARK: - Highlight Tests
    
    func testHighlightInitialization() throws {
        let highlight = Highlight(
            bookId: "book-1",
            chapterIndex: 1,
            pageOffset: 10,
            startCharOffset: 5,
            endCharOffset: 15,
            text: "这是高亮文本",
            color: "#FFD700",
            note: "这是笔记"
        )
        
        XCTAssertEqual(highlight.text, "这是高亮文本")
        XCTAssertEqual(highlight.color, "#FFD700")
        XCTAssertEqual(highlight.note, "这是笔记")
    }

    // MARK: - BookStats Tests
    
    func testBookStatsInitialization() throws {
        let stats = BookStats(
            totalChapters: 10,
            totalChars: 500000,
            fileSizeBytes: 1024000
        )
        
        XCTAssertEqual(stats.totalChapters, 10)
        XCTAssertEqual(stats.totalChars, 500000)
        XCTAssertEqual(stats.fileSizeBytes, 1024000)
    }
}
