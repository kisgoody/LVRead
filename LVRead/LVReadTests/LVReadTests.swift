import XCTest
@testable import LVRead

final class LVReadTests: XCTestCase {

    override func setUpWithError() throws {
        // Setup code before each test
    }

    override func tearDownWithError() throws {
        // Cleanup code after each test
    }

    // MARK: - ThemeColors Tests

    func testUIColorHexInitialization() throws {
        let color = UIColor(hex: "#FF5E3A")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.37, accuracy: 0.01)
        XCTAssertEqual(b, 0.23, accuracy: 0.01)
    }

    func testUIColorHexWithoutHash() throws {
        let color = UIColor(hex: "FFFFFF")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
    }

    func testColorLuminance() throws {
        let white = UIColor(hex: "#FFFFFF")
        let black = UIColor(hex: "#000000")
        
        XCTAssertTrue(white.luminance > black.luminance)
        XCTAssertTrue(white.isDark == false)
        XCTAssertTrue(black.isDark == true)
    }

    func testAdaptiveColor() throws {
        // Test that adaptive color works
        let adaptive = UIColor.adaptiveColor(light: .white, dark: .black)
        XCTAssertNotNil(adaptive)
    }

    // MARK: - BookSource Tests

    func testBookSourceDisplayNames() throws {
        XCTAssertEqual(BookSource.shareImport.displayName, "分享导入")
        XCTAssertEqual(BookSource.localFile.displayName, "本地文件")
        XCTAssertEqual(BookSource.lanTransfer.displayName, "同网传输")
    }

    func testFileFormatDisplayNames() throws {
        XCTAssertEqual(FileFormat.epub.displayName, "EPUB")
        XCTAssertEqual(FileFormat.txt.displayName, "TXT")
        XCTAssertEqual(FileFormat.pdf.displayName, "PDF")
    }

    // MARK: - ReadingSettings Tests

    func testDefaultReadingSettings() throws {
        let settings = ReadingSettings.default
        
        XCTAssertEqual(settings.fontSize, 24)
        XCTAssertEqual(settings.fontFamily, "系统默认")
        XCTAssertEqual(settings.lineSpacing, 1.4)
        XCTAssertEqual(settings.pageFlipMode, .cover)
    }

    func testReadingSettingsCodable() throws {
        let settings = ReadingSettings.default
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(ReadingSettings.self, from: data)
        
        XCTAssertEqual(settings.fontSize, decoded.fontSize)
        XCTAssertEqual(settings.fontFamily, decoded.fontFamily)
    }

    // MARK: - ReadingTheme Tests

    func testReadingThemeColors() throws {
        XCTAssertEqual(ReadingTheme.white.backgroundColor, "#FFFFFF")
        XCTAssertEqual(ReadingTheme.oled.backgroundColor, "#000000")
        XCTAssertEqual(ReadingTheme.warmYellow.textColor, "#3D3226")
    }

    // MARK: - PageFlipMode Tests

    func testPageFlipModeDisplayNames() throws {
        XCTAssertEqual(PageFlipMode.simulation.displayName, "仿真翻页")
        XCTAssertEqual(PageFlipMode.cover.displayName, "覆盖翻页")
        XCTAssertEqual(PageFlipMode.slide.displayName, "平移翻页")
    }

    // MARK: - EyeCareFilter Tests

    func testEyeCareFilterDisplayNames() throws {
        XCTAssertEqual(EyeCareFilter.none.displayName, "冷白")
        XCTAssertEqual(EyeCareFilter.warmYellow.displayName, "暖黄")
        XCTAssertEqual(EyeCareFilter.mintGreen.displayName, "护眼绿")
    }
}
