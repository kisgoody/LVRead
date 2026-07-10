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

enum NativeDocumentTypography {
    static let topReadingStatusHeight: CGFloat = 44
    static let bottomReadingStatusHeight: CGFloat = 24

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
        settings: ReadingSettings
    ) throws -> [NativeDocumentPage] {
        guard size.width > 0, size.height > 0 else { throw PaginationError.invalidSize }
        let source = text as NSString
        guard source.length > 0 else { return [] }
        let insets = NativeDocumentTypography.insets(
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

final class NativeCoreTextView: UIView {
    var page: NativeDocumentPage?
    var settings: ReadingSettings = .default
    var readingSafeAreaInsets: UIEdgeInsets = .zero

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
        let insets = NativeDocumentTypography.insets(
            size: bounds.size,
            safeAreaInsets: readingSafeAreaInsets,
            settings: settings
        )
        let attributed = NativeDocumentTypography.attributed(
            page.text,
            settings: settings,
            color: UIColor(hex: settings.readingTheme.textColor)
        )
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributed),
            CFRange(location: 0, length: 0),
            CGPath(
                rect: NativeDocumentTypography.coreTextPathRect(
                    size: bounds.size,
                    insets: insets
                ),
                transform: nil
            ),
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    func paragraph(at point: CGPoint) -> String? {
        guard let page else { return nil }
        let values = page.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        let ratio = min(max(point.y / max(bounds.height, 1), 0), 0.999)
        return values[min(Int(ratio * CGFloat(values.count)), values.count - 1)]
    }
}
