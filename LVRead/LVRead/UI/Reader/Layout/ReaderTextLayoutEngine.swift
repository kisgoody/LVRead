import UIKit
import CoreText

enum ReaderTextContentSanitizer {
    /// 将连续的换行序列统一折叠为一个 `\n`，保留正常段落边界并去除多余空行。
    static func collapsingExcessiveLineBreaks(in content: String) -> String {
        var result = ""
        result.reserveCapacity(content.count)
        var previousWasLineBreak = false
        for character in content {
            let isLineBreak = character.unicodeScalars.allSatisfy { CharacterSet.newlines.contains($0) }
            if isLineBreak {
                if !previousWasLineBreak { result.append("\n") }
                previousWasLineBreak = true
            } else {
                result.append(character)
                previousWasLineBreak = false
            }
        }
        return result
    }
}

/// Shared CoreText input used by pagination and page rendering.
struct ReaderTextLayout {
    let font: UIFont
    let paragraphStyle: NSParagraphStyle
    let textRect: CGRect
}

struct ReaderPageRange: Equatable {
    let location: Int
    let length: Int

    var endOffset: Int { location + length }
}

enum ReaderTextLayoutError: LocalizedError, Equatable {
    case invalidPageSize(CGSize)
    case noVisibleText(offset: Int)
    case discontinuousRanges

    var errorDescription: String? {
        switch self {
        case let .invalidPageSize(size):
            return "Invalid reader page size: \(size)"
        case let .noVisibleText(offset):
            return "CoreText could not fit text at UTF-16 offset \(offset)"
        case .discontinuousRanges:
            return "CoreText returned discontinuous page ranges"
        }
    }
}

/// Produces deterministic reader typography and geometry.
enum ReaderTextLayoutEngine {

    static func layout(pageSize: CGSize, settings: ReadingSettings) -> ReaderTextLayout {
        let width = max(pageSize.width, 1)
        let height = max(pageSize.height, 1)
        let horizontalMargin = clampedPercentage(settings.pageMarginHorizontal) * width / 100
        let verticalMargin = clampedPercentage(settings.pageMarginVertical) * height / 100
        let font = FontManager.shared.font(
            named: settings.fontFamily,
            size: CGFloat(max(settings.fontSize, 1))
        )

        let paragraph = NSMutableParagraphStyle()
        let y = font.lineHeight * CGFloat(max(settings.lineSpacing - 1, 0))
        let paragraphValue = settings.paragraphSpacing ?? settings.lineSpacing
        let x = font.lineHeight * CGFloat(max(paragraphValue - 1, 0))
        paragraph.lineSpacing = y
        paragraph.paragraphSpacing = x - y
        paragraph.alignment = .justified

        return ReaderTextLayout(
            font: font,
            paragraphStyle: paragraph,
            textRect: CGRect(
                x: horizontalMargin,
                y: verticalMargin,
                width: max(width - horizontalMargin * 2, 1),
                height: max(height - verticalMargin * 2, 1)
            )
        )
    }

    static func attributedString(
        content: String,
        settings: ReadingSettings,
        foregroundColor: UIColor? = nil
    ) -> NSAttributedString {
        let layout = layout(pageSize: CGSize(width: 1, height: 1), settings: settings)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: layout.font,
            .paragraphStyle: layout.paragraphStyle
        ]
        if let foregroundColor {
            attributes[.foregroundColor] = foregroundColor
        }
        return NSAttributedString(string: content, attributes: attributes)
    }

    static func pageRanges(
        content: String,
        pageSize: CGSize,
        settings: ReadingSettings
    ) throws -> [ReaderPageRange] {
        let content = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: content)
        guard pageSize.width > 0, pageSize.height > 0 else {
            throw ReaderTextLayoutError.invalidPageSize(pageSize)
        }
        guard !content.isEmpty else { return [] }

        let attributed = attributedString(content: content, settings: settings)
        let textLength = attributed.length
        let metrics = layout(pageSize: pageSize, settings: settings)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let framePath = CGPath(
            rect: CGRect(origin: .zero, size: metrics.textRect.size),
            transform: nil
        )
        var result: [ReaderPageRange] = []
        var offset = 0

        while offset < textLength {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: offset, length: 0),
                framePath,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            let proposedEnd = min(visible.location + visible.length, textLength)
            guard visible.location == offset, proposedEnd > offset else {
                throw ReaderTextLayoutError.noVisibleText(offset: offset)
            }

            let endOffset = safeComposedSequenceEnd(
                proposedEnd: proposedEnd,
                startOffset: offset,
                text: content
            )
            guard endOffset > offset else {
                throw ReaderTextLayoutError.noVisibleText(offset: offset)
            }

            result.append(
                ReaderPageRange(location: offset, length: endOffset - offset)
            )
            offset = endOffset
        }

        let rangesAreContinuous = result.count == 1
            || zip(result, result.dropFirst()).allSatisfy { pair in
                pair.0.endOffset == pair.1.location
                    && pair.0.length > 0
                    && pair.1.length > 0
            }
        guard result.first?.location == 0,
              result.last?.endOffset == textLength,
              rangesAreContinuous else {
            throw ReaderTextLayoutError.discontinuousRanges
        }
        return result
    }

    static func pages(
        content: String,
        chapter: Chapter,
        chapterIndex: Int,
        pageSize: CGSize,
        settings: ReadingSettings
    ) throws -> [PageData] {
        let normalizedContent = ReaderTextContentSanitizer.collapsingExcessiveLineBreaks(in: content)
        let source = normalizedContent as NSString
        return try pageRanges(
            content: normalizedContent,
            pageSize: pageSize,
            settings: settings
        ).enumerated().map { index, range in
            PageData(
                pageIndex: index,
                startCharOffset: range.location,
                endCharOffset: range.endOffset,
                content: source.substring(
                    with: NSRange(location: range.location, length: range.length)
                ),
                chapterTitle: chapter.title,
                chapterIndex: chapterIndex
            )
        }
    }

    private static func clampedPercentage(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 49))
    }

    private static func safeComposedSequenceEnd(
        proposedEnd: Int,
        startOffset: Int,
        text: String
    ) -> Int {
        guard proposedEnd > startOffset else { return startOffset }
        let source = text as NSString
        let lastSequence = source.rangeOfComposedCharacterSequence(at: proposedEnd - 1)
        if NSMaxRange(lastSequence) <= proposedEnd {
            return proposedEnd
        }
        if lastSequence.location > startOffset {
            return lastSequence.location
        }
        return min(NSMaxRange(lastSequence), source.length)
    }
}
