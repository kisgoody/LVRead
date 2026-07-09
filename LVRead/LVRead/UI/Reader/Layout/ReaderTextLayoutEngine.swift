import UIKit

/// Shared CoreText input used by pagination and page rendering.
struct ReaderTextLayout {
    let font: UIFont
    let paragraphStyle: NSParagraphStyle
    let textRect: CGRect
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
        paragraph.lineSpacing = font.lineHeight * CGFloat(max(settings.lineSpacing - 1, 0))
        paragraph.paragraphSpacing = font.lineHeight * CGFloat(max(settings.paragraphSpacing, 0))
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

    private static func clampedPercentage(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 49))
    }
}
