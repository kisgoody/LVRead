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
        
        XCTAssertEqual(settings.fontSize, 24)
        XCTAssertEqual(settings.fontFamily, "系统默认")
        XCTAssertEqual(settings.lineSpacing, 1.2)
        XCTAssertEqual(settings.paragraphSpacing, 1.5)
        XCTAssertEqual(settings.pageFlipMode, .simulation)
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
        XCTAssertEqual(ReadingTheme.white.backgroundColor, "#F7F7F5")
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

    func testReaderFontCategoriesUseStableIdentifiers() {
        let manager = FontManager.shared
        let chinese = manager.options(for: .chinese)
        let english = manager.options(for: .english)

        XCTAssertEqual(chinese.first?.id, "system-zh")
        XCTAssertEqual(english.first?.id, "system-en")
        XCTAssertTrue(chinese.contains { $0.id == "pingfang-sc" })
        XCTAssertTrue(chinese.contains { $0.id == "pingfang-tc" })
        XCTAssertTrue(english.contains { $0.id == "sf-pro" })
        XCTAssertTrue(english.contains { $0.id == "new-york" })
        XCTAssertEqual(manager.category(for: "系统默认"), .chinese)
        XCTAssertEqual(manager.category(for: "system-en"), .english)
        XCTAssertEqual(manager.category(for: "new-york"), .english)
        XCTAssertEqual(manager.font(named: "pingfang-tc", size: 20).pointSize, 20)
        XCTAssertEqual(manager.font(named: "sf-pro", size: 20).pointSize, 20)
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

    func testWebSyncReaderHTMLSupportsOfflineCacheAndDoublePageCurl() {
        let html = WebSyncServer.shared.webReaderHTML()

        XCTAssertTrue(html.contains("<span>LVRead</span>"))
        XCTAssertTrue(html.contains("var(--reader-bg)"))
        XCTAssertTrue(html.contains("readerFontFamily"))
        XCTAssertTrue(html.contains("(Number(settings.fontSize) || 24) * 1.12"))
        XCTAssertTrue(html.contains("(Number(settings.lineSpacing) || 1.2) + .18"))
        XCTAssertTrue(html.contains("--reader-paragraph-spacing"))
        XCTAssertTrue(html.contains("indexedDB.open('lvread-web-reader'"))
        XCTAssertTrue(html.contains("/api/pages/cache"))
        XCTAssertTrue(html.contains("/api/progress/sync"))
        XCTAssertTrue(html.contains("/api/stats/reading-time"))
        XCTAssertTrue(html.contains("已到缓存数据最后一页，请重新连接 LVRead App"))
        XCTAssertTrue(html.contains("serviceWorker.register"))
        XCTAssertTrue(html.contains("网页阅读模式"))
        XCTAssertTrue(html.contains("data-mode=\"spread\""))
        XCTAssertTrue(html.contains("data-mode=\"single\""))
        XCTAssertTrue(html.contains("data-mode=\"mobile\""))
        XCTAssertTrue(html.contains(">仿真</button>"))
        XCTAssertTrue(html.contains(">手机</button>"))
        XCTAssertTrue(html.contains("mode-single .book-stage { width: min(1120px"))
        XCTAssertTrue(html.contains("function preloadTurn(direction)"))
        XCTAssertTrue(html.contains("leftPage.addEventListener('pointerdown'"))
        XCTAssertTrue(html.contains("renderSinglePagePair(first, second)"))
        XCTAssertTrue(html.contains("mode-single .right-page .page-inner { display: block; }"))
        XCTAssertTrue(html.contains("`${first.content || ''}${second.content || ''}`"))
        XCTAssertTrue(html.contains("sheetFrontNumber"))
        XCTAssertTrue(html.contains("elements.leftNo.textContent = pageLabel(targetLeft)"))
        XCTAssertTrue(html.contains("renderCurrent(false)"))
        XCTAssertTrue(html.contains("if (state.syncPromise) return state.syncPromise"))
        XCTAssertTrue(html.contains("requestedVersion !== state.progressVersion"))
        XCTAssertTrue(html.contains("oldSignature !== refreshedSignature"))
        XCTAssertTrue(html.contains("<kbd>J</kbd> 上一页"))
        XCTAssertTrue(html.contains("<kbd>→</kbd> <kbd>K</kbd> 下一页"))
        XCTAssertTrue(html.contains(".reader-shell.mode-spread .book-stage::before"))
        XCTAssertTrue(html.contains("function updateBookThickness()"))
        XCTAssertTrue(html.contains("--left-book-thickness"))
        XCTAssertTrue(html.contains("repeating-linear-gradient(\n        to right,"))
        XCTAssertTrue(html.contains(".book-thickness {\n      position: absolute;\n      z-index: 1;\n      top: 0;\n      bottom: 0;"))
        XCTAssertTrue(html.contains("right: calc(100% - 12px);"))
        XCTAssertTrue(html.contains("width: calc(var(--right-book-thickness) + 12px);"))
        XCTAssertFalse(html.contains("scaleX(-1)"))
        XCTAssertTrue(html.contains(".sheet-back .page-inner { opacity: 1; }"))
        XCTAssertTrue(html.contains("--book-height: min(736px, calc(100dvh - 200px));"))
        XCTAssertTrue(html.contains("pages.some(page => page.scrollHeight > page.clientHeight)"))
        XCTAssertTrue(html.contains("state.fontLayoutKey === layoutKey && state.fittedFontSize"))
        XCTAssertTrue(html.contains("page.style.fontSize = `${fontSize}px`"))
        XCTAssertTrue(html.contains("state.queuedDirection = direction"))
        XCTAssertTrue(html.contains("queueMicrotask(() => navigate(queuedDirection))"))
        XCTAssertTrue(html.contains("async function extendCacheAndNavigate(direction)"))
        XCTAssertTrue(html.contains("async function refreshCacheForNavigation()"))
        XCTAssertTrue(html.contains("function visibleUnitNeedsRefresh()"))
        XCTAssertTrue(html.contains("if (!missingSecondVisiblePage()) return true"))
        XCTAssertTrue(html.contains("refreshed = await refreshCache(true)"))
        XCTAssertTrue(html.contains("return navigate(direction, false)"))
        XCTAssertTrue(html.contains("!state.connected && state.cursor <= 0 && Boolean(state.cache.reachedBeginning)"))
        XCTAssertTrue(html.contains("function updateNavigationButtons()"))
        XCTAssertTrue(html.contains("Boolean(state.cache.reachedEnd)"))
        XCTAssertTrue(html.contains("async function refreshCacheWindow(syncFirst = true)"))
        XCTAssertTrue(html.contains("async function prefetchCacheWindow()"))
        XCTAssertTrue(html.contains("function cacheEndpoint() { return `/api/pages/cache?unit=${currentUnit()}`; }"))
        XCTAssertTrue(html.contains("state.prefetchedCache = normalizeCache(await api(cacheEndpoint()))"))
        XCTAssertTrue(html.contains("if (usePrefetchedCache(direction)) return navigate(direction, false)"))
        XCTAssertTrue(html.contains("if (isNearCacheBoundary()) prefetchCacheWindow()"))
        XCTAssertTrue(html.contains("state.cursor <= 6 * unit"))
        XCTAssertTrue(html.contains("remaining <= 16 * unit"))
        XCTAssertTrue(html.contains("await syncPendingReadingIntervals()"))
        XCTAssertTrue(html.contains("await reconcileProgressOnReconnect()"))
        XCTAssertTrue(html.contains("syncPendingProgress('furthest')"))
        XCTAssertTrue(html.contains("nextStrategy = 'replace'"))
        XCTAssertTrue(html.contains("if (state.connected) await refreshCacheWindow(false)"))
        XCTAssertTrue(html.contains("const readingInactivityMilliseconds = 2 * 60 * 1000"))
        XCTAssertTrue(html.contains("if (state.connected) return '';"))
        XCTAssertTrue(html.contains("if (message) showToast(message)"))
        XCTAssertTrue(html.contains("elements.turning.classList.contains('active')"))
        XCTAssertTrue(html.contains("aria-pressed=\"true\""))
        XCTAssertTrue(html.contains("lvread_web_reading_mode_v2"))
        XCTAssertTrue(html.contains("function gotoSpread(spreadIndex, animate = true)"))
        XCTAssertTrue(html.contains("window.gotoSpread = gotoSpread"))
        XCTAssertTrue(html.contains("matrix3d("))
        XCTAssertTrue(html.contains("pointermove"))
        XCTAssertTrue(html.contains("sheet-back"))
        XCTAssertTrue(html.contains("html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }"))
        XCTAssertFalse(html.contains("turn.js"))
    }

    func testWebReadingIntervalValidationCapsIdleAndFutureTime() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let valid = WebSyncServer.validatedWebReadingInterval(
            startMilliseconds: 1_999_940_000,
            endMilliseconds: 2_000_000_000,
            now: now
        )

        XCTAssertNotNil(valid)
        XCTAssertNil(WebSyncServer.validatedWebReadingInterval(
            startMilliseconds: 1_999_800_000,
            endMilliseconds: 2_000_000_000,
            now: now
        ))
        XCTAssertNil(WebSyncServer.validatedWebReadingInterval(
            startMilliseconds: 2_000_000_000,
            endMilliseconds: 2_000_400_000,
            now: now
        ))
    }

    func testReconnectProgressKeepsTheFurthestPositionOnlyForReconciliation() {
        XCTAssertFalse(WebSyncServer.shouldUseRequestedProgress(
            currentChapterIndex: 1,
            currentPageIndex: 8,
            requestedChapterIndex: 0,
            requestedPageIndex: 18,
            keepsFurthestProgress: true
        ))
        XCTAssertTrue(WebSyncServer.shouldUseRequestedProgress(
            currentChapterIndex: 1,
            currentPageIndex: 8,
            requestedChapterIndex: 1,
            requestedPageIndex: 9,
            keepsFurthestProgress: true
        ))
        XCTAssertTrue(WebSyncServer.shouldUseRequestedProgress(
            currentChapterIndex: 1,
            currentPageIndex: 8,
            requestedChapterIndex: 0,
            requestedPageIndex: 18,
            keepsFurthestProgress: false
        ))
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
