import UIKit

enum NativeReaderPresentationPolicy {
    static func usesDoublePage(
        idiom: UIUserInterfaceIdiom,
        size: CGSize,
        navigationMode: ReaderNavigationMode
    ) -> Bool {
        idiom == .pad
            && size.width > size.height
            && navigationMode == .simulation
    }

    static func pageTurnDistance(usesDoublePage: Bool) -> Int {
        usesDoublePage ? 2 : 1
    }
}

enum NativeReaderPageChrome: Equatable {
    case single
    case spreadLeft
    case spreadRight

    var showsBackButton: Bool { self != .spreadRight }
    var showsChapter: Bool { self != .spreadLeft }
    var showsTimeAndBattery: Bool { self != .spreadLeft }

    var pageCorners: CACornerMask {
        switch self {
        case .single:
            return [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .spreadLeft:
            return [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        case .spreadRight:
            return [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
    }
}

enum NativeBookSpreadMetrics {
    static let pageHorizontalInset: CGFloat = 40
    static let pageVerticalInset: CGFloat = 24
    static let coverHorizontalOutset: CGFloat = 32
    static let coverVerticalOutset: CGFloat = 16
    static let minimumThickness: CGFloat = 8
    static let maximumThickness: CGFloat = 24
    static let extraTextInset: CGFloat = 16
    static let pageCornerRadius: CGFloat = 12
    static let coverCornerRadius: CGFloat = 18
}

struct NativeBookSpreadPalette {
    let stage: UIColor
    let paper: UIColor
    let control: UIColor
    let text: UIColor
    let accent: UIColor
    let outline: UIColor
    let textureLight: UIColor
    let textureDark: UIColor

    init(settings: ReadingSettings) {
        stage = UIColor(hex: settings.readingTheme.panelColor)
        // Use the persisted reading background, matching every reader mode and
        // WebReader's `--reader-bg`, including custom theme colors.
        paper = UIColor(hex: settings.backgroundColor)
        control = UIColor(hex: settings.readingTheme.controlSurfaceColor)
        text = UIColor(hex: settings.readingTheme.textColor)
        accent = UIColor(hex: settings.readingTheme.accentColor)
        outline = Self.mix(background: paper, foreground: text, foregroundAmount: 0.28)
        textureLight = Self.mix(background: paper, foreground: text, foregroundAmount: 0.12)
        textureDark = Self.mix(background: paper, foreground: text, foregroundAmount: 0.28)
    }

    private static func mix(
        background: UIColor,
        foreground: UIColor,
        foregroundAmount: CGFloat
    ) -> UIColor {
        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        guard background.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
              foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa) else {
            return foreground.withAlphaComponent(foregroundAmount)
        }
        let amount = min(max(foregroundAmount, 0), 1)
        return UIColor(
            red: br + (fr - br) * amount,
            green: bg + (fg - bg) * amount,
            blue: bb + (fb - bb) * amount,
            alpha: ba + (fa - ba) * amount
        )
    }
}

enum NativeBookThickness {
    static func widths(
        progress: CGFloat,
        maximum: CGFloat = NativeBookSpreadMetrics.maximumThickness
    ) -> (left: CGFloat, right: CGFloat) {
        let value = min(max(progress, 0), 1)
        let minimum = min(NativeBookSpreadMetrics.minimumThickness, maximum)
        let range = max(0, maximum - minimum)
        return (minimum + range * value, minimum + range * (1 - value))
    }
}

/// Transparent overlay that gives the iPad landscape spread a physical-book
/// cover, vertical page-edge texture, progress-based thickness and fixed spine.
final class NativeBookSpreadView: UIView {
    var settings: ReadingSettings = .default {
        didSet { setNeedsDisplay() }
    }
    var progress: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              bounds.width > NativeBookSpreadMetrics.coverHorizontalOutset * 2,
              bounds.height > NativeBookSpreadMetrics.coverVerticalOutset * 2 else { return }
        let pageRect = bounds.inset(by: UIEdgeInsets(
            top: NativeBookSpreadMetrics.coverVerticalOutset,
            left: NativeBookSpreadMetrics.coverHorizontalOutset,
            bottom: NativeBookSpreadMetrics.coverVerticalOutset,
            right: NativeBookSpreadMetrics.coverHorizontalOutset
        ))
        let thickness = NativeBookThickness.widths(progress: progress)
        let palette = NativeBookSpreadPalette(settings: settings)

        context.saveGState()
        UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: NativeBookSpreadMetrics.coverCornerRadius
        ).addClip()

        let leftEdge = CGRect(
            x: pageRect.minX - thickness.left,
            y: pageRect.minY,
            width: thickness.left,
            height: pageRect.height
        )
        let rightEdge = CGRect(
            x: pageRect.maxX,
            y: pageRect.minY,
            width: thickness.right,
            height: pageRect.height
        )
        drawVerticalPageTexture(
            context: context,
            palette: palette,
            edge: leftEdge,
            pageRect: pageRect,
            leftSide: true
        )
        drawVerticalPageTexture(
            context: context,
            palette: palette,
            edge: rightEdge,
            pageRect: pageRect,
            leftSide: false
        )

        let spineX = pageRect.midX
        let darkAppearance = settings.readingTheme.isDarkAppearance
        let leftSpineColors = darkAppearance
            ? [UIColor.clear, palette.text.withAlphaComponent(0.08), UIColor.black.withAlphaComponent(0.52)]
            : [UIColor.clear, UIColor.black.withAlphaComponent(0.14)]
        let rightSpineColors = darkAppearance
            ? [UIColor.black.withAlphaComponent(0.52), palette.text.withAlphaComponent(0.08), UIColor.clear]
            : [UIColor.black.withAlphaComponent(0.14), UIColor.clear]
        drawHorizontalGradient(
            context: context,
            colors: leftSpineColors,
            rect: CGRect(x: spineX - 24, y: pageRect.minY, width: 24, height: pageRect.height)
        )
        drawHorizontalGradient(
            context: context,
            colors: rightSpineColors,
            rect: CGRect(x: spineX, y: pageRect.minY, width: 24, height: pageRect.height)
        )
        drawHorizontalGradient(
            context: context,
            colors: darkAppearance
                ? [
                    UIColor.clear,
                    palette.text.withAlphaComponent(0.18),
                    UIColor.black.withAlphaComponent(0.68),
                    palette.text.withAlphaComponent(0.12),
                    UIColor.clear
                ]
                : [
                    UIColor.clear,
                    UIColor.black.withAlphaComponent(0.18),
                    UIColor.white.withAlphaComponent(0.28),
                    UIColor.black.withAlphaComponent(0.14),
                    UIColor.clear
                ],
            locations: [0, 0.36, 0.50, 0.64, 1],
            rect: CGRect(x: spineX - 7, y: pageRect.minY, width: 14, height: pageRect.height)
        )

        palette.outline.setStroke()
        let cover = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: NativeBookSpreadMetrics.coverCornerRadius
        )
        cover.lineWidth = 3
        cover.stroke()
        context.restoreGState()
    }

    private func drawHorizontalGradient(
        context: CGContext,
        colors: [UIColor],
        locations: [CGFloat]? = nil,
        rect: CGRect
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        ) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        context.restoreGState()
    }

    private func drawVerticalPageTexture(
        context: CGContext,
        palette: NativeBookSpreadPalette,
        edge: CGRect,
        pageRect: CGRect,
        leftSide: Bool
    ) {
        let radius = NativeBookSpreadMetrics.pageCornerRadius
        let halfWidth = pageRect.width / 2
        let pageHalf = CGRect(
            x: leftSide ? pageRect.minX : pageRect.midX,
            y: pageRect.minY,
            width: halfWidth,
            height: pageRect.height
        )
        let textureRect = CGRect(
            x: leftSide ? edge.minX : pageRect.maxX - radius,
            y: pageRect.minY,
            width: edge.width + radius,
            height: pageRect.height
        )
        let roundedPage = UIBezierPath(
            roundedRect: pageHalf,
            byRoundingCorners: leftSide ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        let textureClip = UIBezierPath(rect: textureRect)
        textureClip.append(roundedPage)
        textureClip.usesEvenOddFillRule = true

        context.saveGState()
        context.addPath(textureClip.cgPath)
        context.clip(using: .evenOdd)
        var x = textureRect.minX
        while x < textureRect.maxX {
            palette.textureLight.setFill()
            UIRectFill(CGRect(x: x, y: textureRect.minY, width: min(2, textureRect.maxX - x), height: textureRect.height))
            x += 2
            guard x < textureRect.maxX else { break }
            palette.textureDark.setFill()
            UIRectFill(CGRect(x: x, y: textureRect.minY, width: min(1, textureRect.maxX - x), height: textureRect.height))
            x += 1
        }
        context.restoreGState()

        palette.outline.withAlphaComponent(0.20).setStroke()
        UIBezierPath(rect: edge.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}
