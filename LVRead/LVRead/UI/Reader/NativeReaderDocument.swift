import UIKit
import CoreText

struct NativeDocumentPage {
    let chapterIndex: Int
    let pageIndex: Int
    let chapterTitle: String
    let startOffset: Int
    let endOffset: Int
    let text: String
    let image: UIImage?
    var id: String { "\(chapterIndex):\(pageIndex):\(startOffset):\(endOffset)" }
}

struct NativeTextSelection {
    let text: String
    /// UTF-16 range relative to the current page text.
    let range: NSRange
    let anchorRect: CGRect
}

private final class NativeSelectionHandleView: UIView {
    let leading: Bool
    var color: UIColor = .systemBlue { didSet { setNeedsDisplay() } }

    init(leading: Bool) {
        self.leading = leading
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = leading ? "选区起点" : "选区终点"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

}

enum NativeDocumentTypography {
    static let topReadingStatusHeight: CGFloat = 44
    static let bottomReadingStatusHeight: CGFloat = 24

    static func absoluteLineOrigin(_ origin: CGPoint, pathOrigin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + pathOrigin.x, y: origin.y + pathOrigin.y)
    }

    static func attributed(_ text: String, settings: ReadingSettings, color: UIColor) -> NSAttributedString {
        let font = FontManager.shared.font(
            named: settings.fontFamily,
            size: CGFloat(min(max(settings.fontSize, 12), 32))
        )
        let style = NSMutableParagraphStyle()
        let y = font.lineHeight * CGFloat(max(0, settings.lineSpacing - 1))
        let paragraphValue = settings.paragraphSpacing ?? settings.lineSpacing
        let x = font.lineHeight * CGFloat(max(0, paragraphValue - 1))
        style.lineSpacing = y
        style.paragraphSpacing = x - y
        style.alignment = .justified
        return NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: style, .foregroundColor: color]
        )
    }

    static func insets(
        size: CGSize,
        safeAreaInsets: UIEdgeInsets,
        settings: ReadingSettings
    ) -> UIEdgeInsets {
        let horizontal = CGFloat(min(max(settings.pageMarginHorizontal, 5), 20)) * size.width / 100
        let statusExcludedHeight = max(
            1,
            size.height - safeAreaInsets.top - safeAreaInsets.bottom
                - topReadingStatusHeight - bottomReadingStatusHeight
        )
        let vertical = CGFloat(min(max(settings.pageMarginVertical, 2), 20)) * statusExcludedHeight / 100
        return UIEdgeInsets(
            top: safeAreaInsets.top + topReadingStatusHeight + vertical,
            left: horizontal,
            bottom: safeAreaInsets.bottom + bottomReadingStatusHeight + vertical,
            right: horizontal
        )
    }

    static func continuousInsets(size: CGSize, settings: ReadingSettings) -> UIEdgeInsets {
        let horizontal = CGFloat(min(max(settings.pageMarginHorizontal, 5), 20)) * size.width / 100
        return UIEdgeInsets(top: 0, left: horizontal, bottom: 0, right: horizontal)
    }

    /// CoreText 使用左下角原点；UIKit 的 bottom inset 必须映射为路径的 y。
    static func coreTextPathRect(size: CGSize, insets: UIEdgeInsets) -> CGRect {
        CGRect(
            x: insets.left,
            y: insets.bottom,
            width: max(1, size.width - insets.left - insets.right),
            height: max(1, size.height - insets.top - insets.bottom)
        )
    }
}

enum NativeDocumentPaginator {
    enum PaginationError: LocalizedError {
        case invalidSize
        case cannotFit

        var errorDescription: String? {
            self == .invalidSize ? "阅读区域尺寸无效" : "当前排版无法容纳正文"
        }
    }

    static func pages(
        text: String,
        chapter: Chapter,
        chapterIndex: Int,
        size: CGSize,
        safeAreaInsets: UIEdgeInsets = .zero,
        textInsets: UIEdgeInsets? = nil,
        settings: ReadingSettings
    ) throws -> [NativeDocumentPage] {
        guard size.width > 0, size.height > 0 else { throw PaginationError.invalidSize }
        let source = text as NSString
        guard source.length > 0 else { return [] }
        let insets = textInsets ?? NativeDocumentTypography.insets(
            size: size,
            safeAreaInsets: safeAreaInsets,
            settings: settings
        )
        let textSize = CGSize(
            width: max(1, size.width - insets.left - insets.right),
            height: max(1, size.height - insets.top - insets.bottom)
        )
        var result: [NativeDocumentPage] = []
        var offset = 0
        while offset < source.length {
            let remaining = source.substring(from: offset)
            let value = NativeDocumentTypography.attributed(remaining, settings: settings, color: .label)
            let setter = CTFramesetterCreateWithAttributedString(value)
            let path = CGPath(rect: CGRect(origin: .zero, size: textSize), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw PaginationError.cannotFit }
            let length = min(visible.length, source.length - offset)
            result.append(
                NativeDocumentPage(
                    chapterIndex: chapterIndex,
                    pageIndex: result.count,
                    chapterTitle: chapter.title,
                    startOffset: offset,
                    endOffset: offset + length,
                    text: source.substring(with: NSRange(location: offset, length: length)),
                    image: nil
                )
            )
            offset += length
        }
        return result
    }
}

/// Loads and paginates chapters with the same cleanup rules for both the native
/// reader and the web-sync service. Instances are intentionally short-lived and
/// keep only the chapters touched by the current navigation request.
final class NativeDocumentChapterPaginator {
    private let book: Book
    private let chapters: [Chapter]
    private let size: CGSize
    private let safeAreaInsets: UIEdgeInsets
    private let textInsets: UIEdgeInsets?
    private let settings: ReadingSettings
    private let parser: FileParserProtocol
    private var contentCache: [Int: String] = [:]
    private var pageCache: [Int: [NativeDocumentPage]] = [:]

    init(
        book: Book,
        chapters: [Chapter],
        size: CGSize,
        safeAreaInsets: UIEdgeInsets,
        textInsets: UIEdgeInsets? = nil,
        settings: ReadingSettings
    ) {
        self.book = book
        self.chapters = chapters
        self.size = size
        self.safeAreaInsets = safeAreaInsets
        self.textInsets = textInsets
        self.settings = settings
        parser = BookImportManager.shared.parserFor(format: book.fileFormat)
    }

    func pages(at chapterIndex: Int) throws -> [NativeDocumentPage] {
        guard chapters.indices.contains(chapterIndex) else {
            throw ChapterError.indexOutOfRange
        }
        if let cached = pageCache[chapterIndex] { return cached }
        let chapter = chapters[chapterIndex]
        let text = try resolvedContent(at: chapterIndex)
        guard !text.isEmpty else {
            pageCache[chapterIndex] = []
            return []
        }
        let pages = try NativeDocumentPaginator.pages(
            text: text,
            chapter: chapter,
            chapterIndex: chapterIndex,
            size: size,
            safeAreaInsets: safeAreaInsets,
            textInsets: textInsets,
            settings: settings
        )
        pageCache[chapterIndex] = pages
        return pages
    }

    private func cleanedContent(at chapterIndex: Int) throws -> String {
        if let cached = contentCache[chapterIndex] { return cached }
        let chapter = chapters[chapterIndex]
        var text = try parser.parseChapterContent(
            filePath: book.resolvedFilePath(),
            chapter: chapter,
            encoding: book.encoding ?? "UTF-8"
        )
        text = NativeDocumentSanitizer.removeDuplicateHeading(from: text, title: chapter.title)
        text = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: text)
        contentCache[chapterIndex] = text
        return text
    }

    private func resolvedContent(at chapterIndex: Int) throws -> String {
        let chapter = chapters[chapterIndex]
        let content = try cleanedContent(at: chapterIndex)
        guard !ReaderChapterContentPolicy.isTitleOnly(
            content: content,
            chapterTitle: chapter.title
        ) else { return "" }

        var pendingTitles: [String] = []
        var followingTitle = chapter.title
        var previousIndex = chapterIndex - 1
        while previousIndex >= 0 {
            let previousChapter = chapters[previousIndex]
            let previousContent = try cleanedContent(at: previousIndex)
            guard ReaderChapterContentPolicy.isTitleOnly(
                content: previousContent,
                chapterTitle: previousChapter.title
            ) else { break }
            if !ReaderChapterContentPolicy.titlesMatch(previousChapter.title, followingTitle) {
                pendingTitles.insert(previousChapter.title, at: 0)
            }
            followingTitle = previousChapter.title
            previousIndex -= 1
        }

        return ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(
            in: ReaderChapterContentPolicy.merging(
                pendingTitles: pendingTitles,
                with: content
            )
        )
    }

    private enum ChapterError: LocalizedError {
        case indexOutOfRange

        var errorDescription: String? { "章节索引超出范围" }
    }
}

enum NativeDocumentSanitizer {
    static func key(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    static func removeDuplicateHeading(
        from text: String,
        title: String
    ) -> String {
        let titleKey = key(title)
        guard !titleKey.isEmpty else { return text }
        var leading = true
        var kept = false
        var output: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let lineKey = key(line)
            if leading, lineKey.isEmpty {
                output.append(line)
            } else if leading, lineKey == titleKey {
                if !kept {
                    output.append(line)
                    kept = true
                }
            } else {
                leading = false
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }
}

enum NativeSpeechTextRange {
    fileprivate static let sentenceSeparators = CharacterSet(charactersIn: "。！？!?；;.…\n")
    private static let whitespace = CharacterSet.whitespacesAndNewlines

    static func sentence(in text: String, containing spokenRange: NSRange) -> NSRange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let location = min(max(spokenRange.location, 0), source.length - 1)

        var start = 0
        if location > 0 {
            let separator = source.rangeOfCharacter(
                from: sentenceSeparators,
                options: .backwards,
                range: NSRange(location: 0, length: location)
            )
            if separator.location != NSNotFound { start = NSMaxRange(separator) }
        }
        while start < source.length,
              whitespace.contains(UnicodeScalar(source.character(at: start))!) {
            start += 1
        }

        let searchStart = max(start, location)
        let separator = source.rangeOfCharacter(
            from: sentenceSeparators,
            range: NSRange(location: searchStart, length: source.length - searchStart)
        )
        var end = separator.location == NSNotFound ? source.length : NSMaxRange(separator)
        while end > start,
              whitespace.contains(UnicodeScalar(source.character(at: end - 1))!) {
            end -= 1
        }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}

struct NativeSpeechPageSegment {
    let pageID: String
    let utteranceRange: NSRange
    let pageRange: NSRange
}

struct NativeSpeechBuffer {
    let text: String
    let segments: [NativeSpeechPageSegment]
    let continuationPageID: String
    let continuationOffset: Int

    static func make(pages: [NativeDocumentPage], startIndex: Int, offset: Int) -> Self? {
        guard pages.indices.contains(startIndex), pages[startIndex].image == nil else { return nil }
        let firstPage = pages[startIndex]
        let firstSource = firstPage.text as NSString
        let start = min(max(offset, 0), firstSource.length)
        let remaining = firstSource.substring(from: start) as NSString
        let firstContent = remaining.rangeOfCharacter(from: .whitespacesAndNewlines.inverted)
        guard firstContent.location != NSNotFound else { return nil }

        let speechStart = start + firstContent.location
        var text = firstSource.substring(from: speechStart)
        var segments = [NativeSpeechPageSegment(
            pageID: firstPage.id,
            utteranceRange: NSRange(location: 0, length: (text as NSString).length),
            pageRange: NSRange(location: speechStart, length: firstSource.length - speechStart)
        )]
        var continuationPageID = firstPage.id
        var continuationOffset = firstSource.length

        guard !endsAtSentenceBoundary(text) else {
            return Self(
                text: text,
                segments: segments,
                continuationPageID: continuationPageID,
                continuationOffset: continuationOffset
            )
        }

        var index = startIndex + 1
        while pages.indices.contains(index) {
            let page = pages[index]
            guard page.chapterIndex == firstPage.chapterIndex, page.image == nil else { break }
            let source = page.text as NSString
            let separator = source.rangeOfCharacter(from: NativeSpeechTextRange.sentenceSeparators)
            let length = separator.location == NSNotFound ? source.length : NSMaxRange(separator)
            guard length > 0 else {
                index += 1
                continue
            }
            let utteranceStart = (text as NSString).length
            text += source.substring(to: length)
            segments.append(NativeSpeechPageSegment(
                pageID: page.id,
                utteranceRange: NSRange(location: utteranceStart, length: length),
                pageRange: NSRange(location: 0, length: length)
            ))
            continuationPageID = page.id
            continuationOffset = length
            if separator.location != NSNotFound { break }
            index += 1
        }

        return Self(
            text: text,
            segments: segments,
            continuationPageID: continuationPageID,
            continuationOffset: continuationOffset
        )
    }

    func segment(containing location: Int) -> NativeSpeechPageSegment? {
        segments.first {
            location >= $0.utteranceRange.location && location < NSMaxRange($0.utteranceRange)
        } ?? segments.last
    }

    private static func endsAtSentenceBoundary(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return true }
        if last == "\n" { return true }
        guard let scalar = text.unicodeScalars.reversed().first(where: {
            !CharacterSet.whitespaces.contains($0)
        }) else { return true }
        return NativeSpeechTextRange.sentenceSeparators.contains(scalar)
    }
}

enum NativeSpokenTextStyle {
    static func backgroundColor(for settings: ReadingSettings) -> UIColor {
        UIColor(hex: settings.readingTheme.accentColor).withAlphaComponent(
            settings.readingTheme.isDarkAppearance ? 0.42 : 0.28
        )
    }
}

final class NativeCoreTextView: UIView {
    var page: NativeDocumentPage?
    var settings: ReadingSettings = .default
    var readingSafeAreaInsets: UIEdgeInsets = .zero
    var textInsets: UIEdgeInsets?
    var highlights: [Highlight] = []
    var spokenRange: NSRange? {
        didSet { setNeedsDisplay() }
    }
    var selectionRange: NSRange? {
        didSet {
            setNeedsDisplay()
            setNeedsLayout()
        }
    }
    var selectionHandlesVisible = false {
        didSet {
            setNeedsDisplay()
            setNeedsLayout()
        }
    }
    var onSelectionAdjustmentBegan: (() -> Void)?
    var onSelectionChanged: ((NativeTextSelection) -> Void)?
    var onSelectionAdjustmentEnded: ((NativeTextSelection) -> Void)?
    private let leadingHandle = NativeSelectionHandleView(leading: true)
    private let trailingHandle = NativeSelectionHandleView(leading: false)
    private var leadingX: NSLayoutConstraint!
    private var leadingY: NSLayoutConstraint!
    private var trailingX: NSLayoutConstraint!
    private var trailingY: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSelectionHandles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectionHandles()
    }

    override func draw(_ rect: CGRect) {
        guard let page, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor(hex: settings.readingTheme.backgroundColor).cgColor)
        context.fill(bounds)
        if let image = page.image {
            let scale = min(bounds.width / max(image.size.width, 1), bounds.height / max(image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(
                in: CGRect(
                    x: (bounds.width - size.width) / 2,
                    y: (bounds.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
            )
            return
        }
        let insets = textInsets ?? NativeDocumentTypography.insets(
            size: bounds.size,
            safeAreaInsets: readingSafeAreaInsets,
            settings: settings
        )
        let attributed = NSMutableAttributedString(attributedString: NativeDocumentTypography.attributed(
            page.text,
            settings: settings,
            color: UIColor(hex: settings.readingTheme.textColor)
        ))
        let textLength = attributed.length
        if let spokenRange {
            let lower = min(max(spokenRange.location, 0), textLength)
            let upper = min(max(NSMaxRange(spokenRange), lower), textLength)
            if upper > lower {
                attributed.addAttribute(
                    .backgroundColor,
                    value: NativeSpokenTextStyle.backgroundColor(for: settings),
                    range: NSRange(location: lower, length: upper - lower)
                )
            }
        }
        if let selectionRange {
            let lower = min(max(selectionRange.location, 0), textLength)
            let upper = min(max(NSMaxRange(selectionRange), lower), textLength)
            if upper > lower {
                attributed.addAttribute(
                    .backgroundColor,
                    value: UIColor(hex: settings.readingTheme.accentColor).withAlphaComponent(0.18),
                    range: NSRange(location: lower, length: upper - lower)
                )
            }
        }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let pathRect = NativeDocumentTypography.coreTextPathRect(
            size: bounds.size,
            insets: insets
        )
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributed),
            CFRange(location: 0, length: 0),
            CGPath(rect: pathRect, transform: nil),
            nil
        )
        CTFrameDraw(frame, context)
        drawExcerptUnderlines(in: context, frame: frame, pathOrigin: pathRect.origin, page: page)
        drawSelectionHandles(in: context, frame: frame, pathOrigin: pathRect.origin)
        context.restoreGState()
    }

    private func drawSelectionHandles(in context: CGContext, frame: CTFrame, pathOrigin: CGPoint) {
        guard selectionHandlesVisible, let selectionRange else { return }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        origins = origins.map { NativeDocumentTypography.absoluteLineOrigin($0, pathOrigin: pathOrigin) }

        func metrics(at index: Int, preferPreviousLine: Bool) -> (x: CGFloat, top: CGFloat, bottom: CGFloat)? {
            guard let lineIndex = lines.indices.first(where: { lineIndex in
                let range = CTLineGetStringRange(lines[lineIndex])
                let upper = range.location + range.length
                return index >= range.location && (index < upper || (preferPreviousLine && index == upper))
            }) else { return nil }
            let line = lines[lineIndex]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let origin = origins[lineIndex]
            return (
                origin.x + CTLineGetOffsetForStringIndex(line, index, nil),
                origin.y + ascent,
                origin.y - descent
            )
        }

        guard let start = metrics(at: selectionRange.location, preferPreviousLine: false),
              let end = metrics(at: NSMaxRange(selectionRange), preferPreviousLine: true) else { return }
        let color = UIColor(hex: settings.readingTheme.accentColor)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: start.x - 1, y: start.bottom, width: 2, height: start.top - start.bottom))
        context.fillEllipse(in: CGRect(x: start.x - 5, y: start.top - 5, width: 10, height: 10))
        context.fill(CGRect(x: end.x - 1, y: end.bottom, width: 2, height: end.top - end.bottom))
        context.fillEllipse(in: CGRect(x: end.x - 5, y: end.bottom - 5, width: 10, height: 10))
    }

    private func drawExcerptUnderlines(
        in context: CGContext,
        frame: CTFrame,
        pathOrigin: CGPoint,
        page: NativeDocumentPage
    ) {
        let excerpts = highlights.filter(\.isExcerpt)
        guard !excerpts.isEmpty else { return }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        origins = origins.map { NativeDocumentTypography.absoluteLineOrigin($0, pathOrigin: pathOrigin) }
        context.setStrokeColor(UIColor(hex: settings.readingTheme.accentColor).cgColor)
        context.setLineWidth(1.2)

        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineLower = lineRange.location
            let lineUpper = lineRange.location + lineRange.length
            for excerpt in excerpts {
                guard let localRange = Self.localRange(for: excerpt, page: page) else { continue }
                let lower = max(lineLower, localRange.location)
                let upper = min(lineUpper, NSMaxRange(localRange))
                guard upper > lower else { continue }
                let startX = origins[lineIndex].x + CTLineGetOffsetForStringIndex(line, lower, nil)
                let endX = origins[lineIndex].x + CTLineGetOffsetForStringIndex(line, upper, nil)
                var descent: CGFloat = 0
                CTLineGetTypographicBounds(line, nil, &descent, nil)
                let underlineY = origins[lineIndex].y - descent - 2
                context.beginPath()
                context.move(to: CGPoint(x: startX, y: underlineY))
                var x = startX
                while x < endX {
                    x = min(x + 2, endX)
                    context.addLine(to: CGPoint(x: x, y: underlineY + sin((x - startX) * .pi / 4)))
                }
                context.strokePath()
            }
        }
    }

    func paragraphSelection(at point: CGPoint) -> NativeTextSelection? {
        guard let page, page.image == nil, !page.text.isEmpty else { return nil }
        let insets = textInsets ?? NativeDocumentTypography.insets(
            size: bounds.size,
            safeAreaInsets: readingSafeAreaInsets,
            settings: settings
        )
        let pathRect = NativeDocumentTypography.coreTextPathRect(size: bounds.size, insets: insets)
        let coreTextPoint = CGPoint(x: point.x, y: bounds.height - point.y)
        guard pathRect.insetBy(dx: -8, dy: -8).contains(coreTextPoint) else { return nil }

        let attributed = NativeDocumentTypography.attributed(
            page.text,
            settings: settings,
            color: UIColor(hex: settings.readingTheme.textColor)
        )
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributed),
            CFRange(location: 0, length: 0),
            CGPath(rect: pathRect, transform: nil),
            nil
        )
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return nil }
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        origins = origins.map { NativeDocumentTypography.absoluteLineOrigin($0, pathOrigin: pathRect.origin) }

        let lineIndex = lines.indices.min { lhs, rhs in
            abs(origins[lhs].y - coreTextPoint.y) < abs(origins[rhs].y - coreTextPoint.y)
        } ?? 0
        let line = lines[lineIndex]
        let origin = origins[lineIndex]
        let stringIndex = CTLineGetStringIndexForPosition(
            line,
            CGPoint(x: coreTextPoint.x - origin.x, y: 0)
        )
        guard stringIndex != kCFNotFound else { return nil }

        let source = page.text as NSString
        var range = source.paragraphRange(for: NSRange(location: min(stringIndex, source.length - 1), length: 0))
        while range.length > 0,
              CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: range.location))!) {
            range.location += 1
            range.length -= 1
        }
        while range.length > 0,
              CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: NSMaxRange(range) - 1))!) {
            range.length -= 1
        }
        guard range.length > 0 else { return nil }

        return selection(for: range)
    }

    static func localRange(for highlight: Highlight, page: NativeDocumentPage) -> NSRange? {
        let source = page.text as NSString
        let proposed = NSRange(
            location: highlight.startCharOffset - page.startOffset,
            length: highlight.endCharOffset - highlight.startCharOffset
        )
        if proposed.location >= 0, NSMaxRange(proposed) <= source.length,
           source.substring(with: proposed) == highlight.text {
            return proposed
        }
        let recovered = source.range(of: highlight.text)
        return recovered.location == NSNotFound ? nil : recovered
    }

    private func configureSelectionHandles() {
        [leadingHandle, trailingHandle].forEach {
            addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                $0.widthAnchor.constraint(equalToConstant: 44),
                $0.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
        leadingX = leadingHandle.centerXAnchor.constraint(equalTo: leadingAnchor)
        leadingY = leadingHandle.centerYAnchor.constraint(equalTo: topAnchor)
        trailingX = trailingHandle.centerXAnchor.constraint(equalTo: leadingAnchor)
        trailingY = trailingHandle.centerYAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([leadingX, leadingY, trailingX, trailingY])
        leadingHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(selectionHandlePanned(_:))))
        trailingHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(selectionHandlePanned(_:))))
    }

    private func updateSelectionHandles() {
        let visible = selectionHandlesVisible && selectionRange != nil
        leadingHandle.isHidden = !visible
        trailingHandle.isHidden = !visible
        guard visible, let selectionRange, let points = handlePoints(for: selectionRange) else { return }
        let accent = UIColor(hex: settings.readingTheme.accentColor)
        leadingHandle.color = accent
        trailingHandle.color = accent
        leadingX.constant = points.start.x
        // 起点圆点贴住首字形顶部，终点圆点贴住末字形底部。
        leadingY.constant = points.start.y + 13
        trailingX.constant = points.end.x
        trailingY.constant = points.end.y - 7
    }

    @objc private func selectionHandlePanned(_ gesture: UIPanGestureRecognizer) {
        guard let handle = gesture.view as? NativeSelectionHandleView,
              let range = selectionRange else { return }
        if gesture.state == .began { onSelectionAdjustmentBegan?() }
        if gesture.state == .changed || gesture.state == .ended,
           let index = characterIndex(at: gesture.location(in: self)) {
            let sourceLength = (page?.text as NSString?)?.length ?? 0
            let nextRange: NSRange
            if handle.leading {
                let start = min(max(index, 0), NSMaxRange(range) - 1)
                nextRange = NSRange(location: start, length: NSMaxRange(range) - start)
            } else {
                let end = min(max(index, range.location + 1), sourceLength)
                nextRange = NSRange(location: range.location, length: end - range.location)
            }
            if let selection = selection(for: nextRange) {
                selectionRange = selection.range
                onSelectionChanged?(selection)
                if gesture.state == .ended { onSelectionAdjustmentEnded?(selection) }
            }
        }
    }

    private func selection(for range: NSRange) -> NativeTextSelection? {
        guard let page else { return nil }
        let source = page.text as NSString
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= source.length,
              let anchorRect = selectionBounds(for: range) else { return nil }
        return NativeTextSelection(
            text: source.substring(with: range),
            range: range,
            anchorRect: anchorRect
        )
    }

    private func selectionBounds(for range: NSRange) -> CGRect? {
        guard let layout = textLayout() else { return nil }
        var result: CGRect?
        for lineIndex in layout.lines.indices {
            let line = layout.lines[lineIndex]
            let lineRange = CTLineGetStringRange(line)
            let lower = max(range.location, lineRange.location)
            let upper = min(NSMaxRange(range), lineRange.location + lineRange.length)
            guard upper > lower else { continue }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let origin = layout.origins[lineIndex]
            let value = CGRect(
                x: origin.x + CTLineGetOffsetForStringIndex(line, lower, nil),
                y: bounds.height - origin.y - ascent,
                width: max(
                    CTLineGetOffsetForStringIndex(line, upper, nil)
                        - CTLineGetOffsetForStringIndex(line, lower, nil),
                    1
                ),
                height: ascent + descent
            )
            result = result.map { $0.union(value) } ?? value
        }
        return result
    }

    private func characterIndex(at point: CGPoint) -> Int? {
        guard let layout = textLayout() else { return nil }
        let converted = CGPoint(x: point.x, y: bounds.height - point.y)
        let lineIndex = layout.lines.indices.min {
            abs(layout.origins[$0].y - converted.y) < abs(layout.origins[$1].y - converted.y)
        } ?? 0
        let index = CTLineGetStringIndexForPosition(
            layout.lines[lineIndex],
            CGPoint(x: converted.x - layout.origins[lineIndex].x, y: 0)
        )
        return index == kCFNotFound ? nil : index
    }

    private func handlePoints(for range: NSRange) -> (start: CGPoint, end: CGPoint)? {
        guard let layout = textLayout() else { return nil }
        func point(at index: Int, preferPreviousLine: Bool, topEdge: Bool) -> CGPoint? {
            let match = layout.lines.indices.first { lineIndex in
                let value = CTLineGetStringRange(layout.lines[lineIndex])
                let upper = value.location + value.length
                return index >= value.location && (index < upper || (preferPreviousLine && index == upper))
            }
            guard let lineIndex = match else { return nil }
            let line = layout.lines[lineIndex]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            return CGPoint(
                x: layout.origins[lineIndex].x + CTLineGetOffsetForStringIndex(line, index, nil),
                y: bounds.height - layout.origins[lineIndex].y + (topEdge ? -ascent : descent)
            )
        }
        guard let start = point(at: range.location, preferPreviousLine: false, topEdge: true),
              let end = point(at: NSMaxRange(range), preferPreviousLine: true, topEdge: false) else { return nil }
        return (start, end)
    }

    private func textLayout() -> (lines: [CTLine], origins: [CGPoint])? {
        guard let page, page.image == nil, !page.text.isEmpty else { return nil }
        let insets = textInsets ?? NativeDocumentTypography.insets(
            size: bounds.size,
            safeAreaInsets: readingSafeAreaInsets,
            settings: settings
        )
        let attributed = NativeDocumentTypography.attributed(
            page.text,
            settings: settings,
            color: UIColor(hex: settings.readingTheme.textColor)
        )
        let pathRect = NativeDocumentTypography.coreTextPathRect(size: bounds.size, insets: insets)
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributed),
            CFRange(location: 0, length: 0),
            CGPath(rect: pathRect, transform: nil),
            nil
        )
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return nil }
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        origins = origins.map { NativeDocumentTypography.absoluteLineOrigin($0, pathOrigin: pathRect.origin) }
        return (lines, origins)
    }
}
