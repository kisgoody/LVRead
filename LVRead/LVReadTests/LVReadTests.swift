import CryptoKit
import Security
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
        
        XCTAssertEqual(settings.fontSize, 23)
        XCTAssertEqual(settings.fontFamily, "系统默认")
        XCTAssertEqual(settings.lineSpacing, 1.3)
        XCTAssertEqual(settings.paragraphSpacing, 1.5)
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

    func testReadingThemeGroupsAndDefaults() {
        XCTAssertEqual(
            ReadingTheme.lightThemes,
            [.bookshelf, .white, .warmYellow, .mint, .latte]
        )
        XCTAssertEqual(
            ReadingTheme.darkThemes,
            [.bookshelfNight, .midnight, .oled]
        )
        XCTAssertEqual(ReadingSettings.default.readingTheme, .bookshelf)
        XCTAssertTrue(ReadingTheme.darkThemes.allSatisfy(\.isDarkAppearance))
        XCTAssertTrue(ReadingTheme.lightThemes.allSatisfy { !$0.isDarkAppearance })
    }

    func testReaderChineseFontChoicesResolveDifferently() {
        let manager = FontManager.shared
        let system = manager.font(named: "系统默认", size: 20).fontDescriptor
        let song = manager.font(named: "宋体", size: 20).fontDescriptor
        let fang = manager.font(named: "仿宋", size: 20).fontDescriptor
        let kai = manager.font(named: "楷体", size: 20).fontDescriptor

        XCTAssertNotEqual(system, song)
        XCTAssertNotEqual(song, fang)
        XCTAssertNotEqual(fang, kai)
    }

    // MARK: - Web Sync Certificate Tests

    func testWebSyncIdentityKeepsStableRootAndMatchingHost() throws {
        let first = try WebSyncIdentityManager.shared.makeIdentity()
        let second = try WebSyncIdentityManager.shared.makeIdentity()
        let rootData = try Data(contentsOf: first.rootCertificateURL)
        let fingerprint = SHA256.hash(data: rootData)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")

        XCTAssertTrue(first.hostName.hasPrefix("lvread-"))
        XCTAssertTrue(first.hostName.hasSuffix(".local"))
        XCTAssertEqual(first.hostName, second.hostName)
        XCTAssertEqual(first.rootFingerprint, second.rootFingerprint)
        XCTAssertEqual(first.rootFingerprint, fingerprint)
        guard let rootCertificate = SecCertificateCreateWithData(nil, rootData as CFData) else {
            XCTFail("无法解析根证书")
            return
        }

        var leafCertificate: SecCertificate?
        XCTAssertEqual(SecIdentityCopyCertificate(first.secIdentity, &leafCertificate), errSecSuccess)
        guard let leafCertificate else {
            XCTFail("TLS 身份缺少服务证书")
            return
        }

        let policy = SecPolicyCreateSSL(true, first.hostName as CFString)
        var trust: SecTrust?
        XCTAssertEqual(
            SecTrustCreateWithCertificates([leafCertificate, rootCertificate] as CFArray, policy, &trust),
            errSecSuccess
        )
        guard let trust else {
            XCTFail("无法创建证书信任链")
            return
        }
        XCTAssertEqual(SecTrustSetAnchorCertificates(trust, [rootCertificate] as CFArray), errSecSuccess)
        XCTAssertEqual(SecTrustSetAnchorCertificatesOnly(trust, true), errSecSuccess)
        var trustError: CFError?
        XCTAssertTrue(
            SecTrustEvaluateWithError(trust, &trustError),
            trustError.map { CFErrorCopyDescription($0) as String } ?? "证书信任校验失败"
        )
    }

    func testWebSyncUsesStableDistinctBookTokens() {
        let server = WebSyncServer.shared
        let first = server.stableToken(for: "web-sync-test-book-a")
        let repeated = server.stableToken(for: "web-sync-test-book-a")
        let secondBook = server.stableToken(for: "web-sync-test-book-b")

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, secondBook)
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(secondBook.count, 32)
    }

    func testWebSyncReaderHTMLUsesAppThemeAndConsistentTypography() {
        let html = WebSyncServer.shared.webReaderHTML()

        XCTAssertTrue(html.contains("<span>LVRead</span>"))
        XCTAssertTrue(html.contains("var(--reader-bg)"))
        XCTAssertTrue(html.contains("readerFontFamily"))
        XCTAssertFalse(html.contains("fitReadingText"))
        XCTAssertTrue(html.contains("(Number(d.fontSize)||23)*1.12"))
        XCTAssertTrue(html.contains("(Number(d.lineSpacing)||1.3)+.2"))
        XCTAssertTrue(html.contains("{cache:'no-store'}"))
        XCTAssertTrue(html.contains("settingschange',function(e){applySettings(JSON.parse(e.data))"))
        XCTAssertTrue(html.contains("setInterval(function(){loadPage();loadSettings();},2000)"))
        XCTAssertFalse(html.contains("readingChapterTitle"))
        XCTAssertTrue(html.contains("contentEl.textContent=d.content"))
        XCTAssertTrue(html.contains("情况一：手机端未打开同步开关"))
        XCTAssertTrue(html.contains("情况二：同步已打开，但 App 进入了后台"))
        XCTAssertTrue(html.contains("serviceWorker.register"))
        XCTAssertFalse(html.contains("disconnect-notice"))
        XCTAssertTrue(html.contains("d.error==='end_of_book'"))
        XCTAssertTrue(html.contains("d.error==='beginning_of_book'"))
        XCTAssertFalse(html.contains("setTimeout(loadPage,700)"))
        XCTAssertFalse(html.contains("contentEl.textContent='翻页失败：'"))
        XCTAssertTrue(html.contains("网页阅读模式"))
        XCTAssertTrue(html.contains("data-mode=\"default\""))
        XCTAssertTrue(html.contains("data-mode=\"mobile\""))
        XCTAssertTrue(html.contains("aria-pressed=\"true\""))
        XCTAssertTrue(html.contains("lvread_web_reading_mode"))
        XCTAssertTrue(html.contains("classList.toggle('mobile-portrait'"))
        XCTAssertTrue(html.contains("html,body{height:100%;overflow:hidden;}"))
        XCTAssertTrue(html.contains("function resizePortraitText()"))
        XCTAssertTrue(html.contains("contentEl.scrollHeight>available"))
    }

    func testWebSyncPageSnapshotDecodesLegacyValueWithoutLayout() throws {
        let data = try XCTUnwrap(
            "{\"pageIndex\":2,\"content\":\"正文\",\"chapterTitle\":\"第一章\",\"chapterIndex\":0,\"totalPages\":8}"
                .data(using: .utf8)
        )
        let snapshot = try JSONDecoder().decode(WebSyncServer.PageSnapshot.self, from: data)

        XCTAssertEqual(snapshot.pageIndex, 2)
        XCTAssertNil(snapshot.layout)
    }

    func testWebSyncConnectionStateTitlesMatchSwitchLifecycle() {
        XCTAssertEqual(WebSyncConnectionState.disconnected.title, "同步已关闭")
        XCTAssertEqual(WebSyncConnectionState.connecting.title, "等待连接")
        XCTAssertEqual(WebSyncConnectionState.connected.title, "连接成功")
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
