import UIKit

/// 匹配参考图 国风剪纸十二生肖线稿 View
/// 注意：仅笔画有颜色，不做颜色填充
class ZodiacPaperCutView: UIView {

    // 0鼠 1牛 2虎 3兔 4龙 5蛇 6马 7羊 8猴 9鸡 10狗 11猪
    var zodiacIndex: Int = 0 {
        didSet { setNeedsDisplay() }
    }

    // 剪纸红色描边
    private let strokeRed = UIColor(red: 0.83, green: 0.04, blue: 0.07, alpha: 1.0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setStrokeColor(strokeRed.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let centerX = rect.midX
        let centerY = rect.midY
        let baseScale = min(rect.width, rect.height) * 0.42

        switch zodiacIndex {
        case 0: drawRat(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 1: drawOx(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 2: drawTiger(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 3: drawRabbit(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 4: drawDragon(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 5: drawSnake(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 6: drawHorse(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 7: drawGoat(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 8: drawMonkey(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 9: drawRooster(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 10: drawDog(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        case 11: drawPig(ctx: ctx, cx: centerX, cy: centerY, s: baseScale)
        default: break
        }
    }
}

// MARK: 12生肖独立轮廓线稿绘制
extension ZodiacPaperCutView {

    private func drawRat(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.75, y: cy + s*0.4))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.9, y: cy - s*0.2), control: CGPoint(x: cx - s*1.1, y: cy))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.3, y: cy - s*0.7), control: CGPoint(x: cx - s*0.6, y: cy - s*1.0))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.4, y: cy - s*0.3), control: CGPoint(x: cx + s*0.5, y: cy - s*0.8))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.55, y: cy + s*0.35), control: CGPoint(x: cx + s*0.7, y: cy + s*0.1))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.2, y: cy + s*0.5), control: CGPoint(x: cx + s*0.4, y: cy + s*0.65))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.75, y: cy + s*0.4), control: CGPoint(x: cx - s*0.4, y: cy + s*0.7))
        path.closeSubpath()

        path.addArc(center: CGPoint(x: cx - s*0.65, y: cy - s*0.68), radius: s*0.26, startAngle: 0, endAngle: .pi*2, clockwise: false)
        path.addArc(center: CGPoint(x: cx - s*0.22, y: cy - s*0.72), radius: s*0.18, startAngle: 0, endAngle: .pi*2, clockwise: false)

        path.move(to: CGPoint(x: cx + s*0.52, y: cy + s*0.1))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.7, y: cy - s*0.45), control: CGPoint(x: cx + s*0.9, y: cy - s*0.1))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.48, y: cy - s*0.6), control: CGPoint(x: cx + s*0.5, y: cy - s*0.75))

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawOx(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.82, y: cy - s*0.1))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.9, y: cy - s*0.45), control: CGPoint(x: cx - s*1.05, y: cy - s*0.25))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.4, y: cy - s*0.72), control: CGPoint(x: cx - s*0.6, y: cy - s*0.95))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.35, y: cy - s*0.68), control: CGPoint(x: cx + s*0.1, y: cy - s*0.92))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.42, y: cy - s*0.2), control: CGPoint(x: cx + s*0.6, y: cy - s*0.4))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.3, y: cy + s*0.45), control: CGPoint(x: cx + s*0.5, y: cy + s*0.25))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.7, y: cy + s*0.42), control: CGPoint(x: cx - s*0.6, y: cy + s*0.68))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.82, y: cy - s*0.1), control: CGPoint(x: cx - s*0.95, y: cy + s*0.15))
        path.closeSubpath()

        path.move(to: CGPoint(x: cx - s*0.38, y: cy - s*0.66))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.52, y: cy - s*0.9), control: CGPoint(x: cx - s*0.68, y: cy - s*0.78))
        path.move(to: CGPoint(x: cx + s*0.22, y: cy - s*0.64))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.4, y: cy - s*0.88), control: CGPoint(x: cx + s*0.55, y: cy - s*0.76))

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawTiger(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.78, y: cy + s*0.38))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.85, y: cy - s*0.22), control: CGPoint(x: cx - s*1.02, y: cy))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.32, y: cy - s*0.75), control: CGPoint(x: cx - s*0.55, y: cy - s*1.0))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.36, y: cy - s*0.7), control: CGPoint(x: cx + s*0.05, y: cy - s*0.98))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.48, y: cy - s*0.1), control: CGPoint(x: cx + s*0.68, y: cy - s*0.35))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.62, y: cy + s*0.25), control: CGPoint(x: cx + s*0.72, y: cy + s*0.05))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.78, y: cy + s*0.38), control: CGPoint(x: cx - s*0.5, y: cy + s*0.62))
        path.closeSubpath()

        path.addArc(center: CGPoint(x: cx - s*0.52, y: cy - s*0.68), radius: s*0.2, startAngle: 0, endAngle: .pi*2, clockwise: false)
        path.addArc(center: CGPoint(x: cx + s*0.28, y: cy - s*0.66), radius: s*0.2, startAngle: 0, endAngle: .pi*2, clockwise: false)

        path.move(to: CGPoint(x: cx + s*0.45, y: cy - s*0.05))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.78, y: cy + s*0.1), control: CGPoint(x: cx + s*0.92, y: cy - s*0.2))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.65, y: cy + s*0.4), control: CGPoint(x: cx + s*0.6, y: cy + s*0.55))

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawRabbit(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.62, y: cy + s*0.4))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.7, y: cy - s*0.15), control: CGPoint(x: cx - s*0.88, y: cy + s*0.08))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.25, y: cy - s*0.78), control: CGPoint(x: cx - s*0.45, y: cy - s*1.08))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.32, y: cy - s*0.72), control: CGPoint(x: cx + s*0.02, y: cy - s*1.05))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.55, y: cy - s*0.1), control: CGPoint(x: cx + s*0.78, y: cy - s*0.38))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.42, y: cy + s*0.48), control: CGPoint(x: cx + s*0.65, y: cy + s*0.22))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.62, y: cy + s*0.4), control: CGPoint(x: cx - s*0.4, y: cy + s*0.72))
        path.closeSubpath()

        path.move(to: CGPoint(x: cx - s*0.18, y: cy - s*0.72))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.08, y: cy - s*1.32), control: CGPoint(x: cx - s*0.3, y: cy - s*1.15))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.02, y: cy - s*0.74), control: CGPoint(x: cx + s*0.18, y: cy - s*1.12))

        path.move(to: CGPoint(x: cx + s*0.18, y: cy - s*0.7))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.32, y: cy - s*1.3), control: CGPoint(x: cx + s*0.02, y: cy - s*1.1))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.42, y: cy - s*0.68), control: CGPoint(x: cx + s*0.58, y: cy - s*1.08))

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawDragon(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.65, y: cy - s*0.25))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.3, y: cy - s*0.78), control: CGPoint(x: cx - s*0.88, y: cy - s*0.7))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.35, y: cy - s*0.55), control: CGPoint(x: cx + s*0.1, y: cy - s*1.05))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.72, y: cy + s*0.1), control: CGPoint(x: cx + s*0.95, y: cy - s*0.3))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.38, y: cy + s*0.52), control: CGPoint(x: cx + s*0.6, y: cy + s*0.75))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.42, y: cy + s*0.32), control: CGPoint(x: cx - s*0.15, y: cy + s*0.7))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.65, y: cy - s*0.25), control: CGPoint(x: cx - s*0.82, y: cy + s*0.05))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawSnake(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx + s*0.68, y: cy - s*0.65))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.42, y: cy - s*0.45), control: CGPoint(x: cx + s*0.98, y: cy - s*0.1))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.48, y: cy + s*0.35), control: CGPoint(x: cx - s*0.95, y: cy - s*0.05))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.62, y: cy + s*0.42), control: CGPoint(x: cx + s*0.2, y: cy + s*0.75))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.68, y: cy - s*0.65), control: CGPoint(x: cx + s*0.92, y: cy - s*0.2))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawHorse(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.8, y: cy + s*0.45))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.92, y: cy - s*0.1), control: CGPoint(x: cx - s*1.1, y: cy + s*0.18))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.38, y: cy - s*0.7), control: CGPoint(x: cx - s*0.6, y: cy - s*1.02))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.45, y: cy - s*0.25), control: CGPoint(x: cx + s*0.12, y: cy - s*0.6))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.72, y: cy + s*0.32), control: CGPoint(x: cx + s*0.98, y: cy + s*0.05))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.8, y: cy + s*0.45), control: CGPoint(x: cx - s*0.4, y: cy + s*0.78))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawGoat(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.75, y: cy + s*0.42))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.82, y: cy - s*0.08), control: CGPoint(x: cx - s*0.98, y: cy + s*0.18))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.35, y: cy - s*0.62), control: CGPoint(x: cx - s*0.52, y: cy - s*0.9))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.32, y: cy - s*0.58), control: CGPoint(x: cx + s*0.02, y: cy - s*0.88))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.4, y: cy + s*0.45), control: CGPoint(x: cx + s*0.62, y: cy + s*0.15))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.75, y: cy + s*0.42), control: CGPoint(x: cx - s*0.45, y: cy + s*0.72))
        path.closeSubpath()

        path.addArc(center: CGPoint(x: cx - s*0.42, y: cy - s*0.55), radius: s*0.22, startAngle: 0, endAngle: .pi*1.7, clockwise: false)
        path.addArc(center: CGPoint(x: cx + s*0.22, y: cy - s*0.52), radius: s*0.22, startAngle: 0, endAngle: .pi*1.7, clockwise: false)

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawMonkey(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()

        path.addEllipse(in: CGRect(x: cx-s*0.55, y: cy-s*0.68, width: s*1.1, height: s*0.95))

        path.move(to: CGPoint(x: cx - s*0.48, y: cy - s*0.05))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.62, y: cy + s*0.42), control: CGPoint(x: cx - s*0.78, y: cy + s*0.18))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.45, y: cy + s*0.52), control: CGPoint(x: cx + s*0.1, y: cy + s*0.85))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.52, y: cy - s*0.12), control: CGPoint(x: cx + s*0.8, y: cy + s*0.15))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.48, y: cy - s*0.05), control: CGPoint(x: cx - s*0.1, y: cy - s*0.35))
        path.closeSubpath()

        path.addArc(center: CGPoint(x: cx - s*0.62, y: cy - s*0.42), radius: s*0.18, startAngle: 0, endAngle: .pi*2, clockwise: false)
        path.addArc(center: CGPoint(x: cx + s*0.48, y: cy - s*0.4), radius: s*0.18, startAngle: 0, endAngle: .pi*2, clockwise: false)

        path.move(to: CGPoint(x: cx + s*0.48, y: cy + s*0.32))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.75, y: cy + s*0.92), control: CGPoint(x: cx + s*0.98, y: cy + s*0.45))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.38, y: cy + s*1.12), control: CGPoint(x: cx + s*0.42, y: cy + s*1.25))

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawRooster(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.68, y: cy + s*0.42))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.8, y: cy - s*0.15), control: CGPoint(x: cx - s*0.98, y: cy + s*0.1))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.22, y: cy - s*0.68), control: CGPoint(x: cx - s*0.42, y: cy - s*0.98))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.48, y: cy - s*0.42), control: CGPoint(x: cx + s*0.1, y: cy - s*0.82))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.55, y: cy + s*0.45), control: CGPoint(x: cx + s*0.82, y: cy + s*0.08))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.68, y: cy + s*0.42), control: CGPoint(x: cx - s*0.3, y: cy + s*0.78))
        path.closeSubpath()

        path.move(to: CGPoint(x: cx - s*0.05, y: cy - s*0.65))
        path.addLine(to: CGPoint(x: cx + s*0.08, y: cy - s*0.92))
        path.addLine(to: CGPoint(x: cx + s*0.22, y: cy - s*0.68))

        path.move(to: CGPoint(x: cx - s*0.65, y: cy - s*0.08))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.92, y: cy - s*0.42), control: CGPoint(x: cx - s*1.12, y: cy - s*0.15))

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawDog(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.68, y: cy + s*0.45))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.75, y: cy - s*0.1), control: CGPoint(x: cx - s*0.92, y: cy + s*0.18))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.28, y: cy - s*0.62), control: CGPoint(x: cx - s*0.48, y: cy - s*0.92))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.42, y: cy - s*0.58), control: CGPoint(x: cx + s*0.08, y: cy - s*0.9))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.52, y: cy + s*0.42), control: CGPoint(x: cx + s*0.8, y: cy + s*0.08))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.68, y: cy + s*0.45), control: CGPoint(x: cx - s*0.32, y: cy + s*0.78))
        path.closeSubpath()

        path.addEllipse(in: CGRect(x: cx-s*0.7, y: cy-s*0.45, width: s*0.25, height: s*0.55))
        path.addEllipse(in: CGRect(x: cx+s*0.45, y: cy-s*0.42, width: s*0.25, height: s*0.55))

        path.addArc(center: CGPoint(x: cx, y: cy), radius: s*0.15, startAngle: 0, endAngle: .pi*2, clockwise: false)

        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawPig(ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - s*0.78, y: cy + s*0.42))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.85, y: cy - s*0.02), control: CGPoint(x: cx - s*1.05, y: cy + s*0.18))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.32, y: cy - s*0.65), control: CGPoint(x: cx - s*0.52, y: cy - s*0.98))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.62, y: cy - s*0.45), control: CGPoint(x: cx + s*0.15, y: cy - s*0.92))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.82, y: cy + s*0.38), control: CGPoint(x: cx + s*1.05, y: cy + s*0.02))
        path.addQuadCurve(to: CGPoint(x: cx - s*0.78, y: cy + s*0.42), control: CGPoint(x: cx - s*0.35, y: cy + s*0.75))
        path.closeSubpath()

        path.addEllipse(in: CGRect(x: cx-s*0.62, y: cy-s*0.55, width: s*0.3, height: s*0.45))
        path.addEllipse(in: CGRect(x: cx+s*0.48, y: cy-s*0.52, width: s*0.3, height: s*0.45))
        path.addEllipse(in: CGRect(x: cx-s*0.42, y: cy-s*0.15, width: s*0.42, height: s*0.32))

        path.move(to: CGPoint(x: cx + s*0.78, y: cy + s*0.12))
        path.addQuadCurve(to: CGPoint(x: cx + s*0.98, y: cy + s*0.18), control: CGPoint(x: cx + s*1.12, y: cy + s*0.05))

        ctx.addPath(path)
        ctx.strokePath()
    }
}
