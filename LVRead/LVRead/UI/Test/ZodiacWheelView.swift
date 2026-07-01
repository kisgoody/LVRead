import UIKit

// MARK: - 十二生肖轮盘自定义 View
final class ZodiacWheelView: UIView {

    // MARK: 十二生肖数据
    private enum ZodiacAnimal: Int, CaseIterable {
        case rat = 0, ox, tiger, rabbit, dragon, snake
        case horse, goat, monkey, rooster, dog, pig

        var name: String {
            switch self {
            case .rat:    return "鼠"
            case .ox:     return "牛"
            case .tiger:  return "虎"
            case .rabbit: return "兔"
            case .dragon: return "龙"
            case .snake:  return "蛇"
            case .horse:  return "马"
            case .goat:   return "羊"
            case .monkey: return "猴"
            case .rooster:return "鸡"
            case .dog:    return "狗"
            case .pig:    return "猪"
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = side * 0.46

        // 背景：象牙白底盘
        ctx.setFillColor(UIColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1.0).cgColor)
        let bgPath = UIBezierPath(ovalIn: CGRect(x: center.x - outerRadius - 4,
                                                   y: center.y - outerRadius - 4,
                                                   width: (outerRadius + 4) * 2,
                                                   height: (outerRadius + 4) * 2))
        bgPath.fill()

        // 外圈金边
        ctx.setStrokeColor(UIColor(red: 0.72, green: 0.45, blue: 0.20, alpha: 1.0).cgColor)
        ctx.setLineWidth(3)
        let outerRing = UIBezierPath(ovalIn: CGRect(x: center.x - outerRadius,
                                                     y: center.y - outerRadius,
                                                     width: outerRadius * 2,
                                                     height: outerRadius * 2))
        outerRing.stroke()

        // 绘制 12 只生肖动物
        let animalRadius = outerRadius * 0.74
        let animalSize = outerRadius * 0.32

        for (index, animal) in ZodiacAnimal.allCases.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * (2 * CGFloat.pi / 12)
            let animalCenter = CGPoint(
                x: center.x + animalRadius * cos(angle),
                y: center.y + animalRadius * sin(angle)
            )
            drawAnimal(animal, at: animalCenter, size: animalSize, angle: angle, in: ctx)

            // 生肖文字标签
            let labelRadius = outerRadius * 1.12
            let labelPoint = CGPoint(
                x: center.x + labelRadius * cos(angle),
                y: center.y + labelRadius * sin(angle)
            )
            drawLabel(animal.name, at: labelPoint, angle: angle)
        }

        // 中心太极图
        let taijiRadius = outerRadius * 0.28
        drawTaiji(center: center, radius: taijiRadius, in: ctx)
    }

    // MARK: - 太极图

    private func drawTaiji(center: CGPoint, radius: CGFloat, in ctx: CGContext) {
        ctx.setStrokeColor(UIColor(red: 0.72, green: 0.45, blue: 0.20, alpha: 1.0).cgColor)
        ctx.setLineWidth(2)
        let outer = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2))
        outer.stroke()

        let halfR = radius / 2

        // 白色半圆（左半）
        ctx.setFillColor(UIColor.white.cgColor)
        let whiteHalf = UIBezierPath()
        whiteHalf.move(to: CGPoint(x: center.x, y: center.y - radius))
        whiteHalf.addArc(withCenter: center, radius: radius,
                         startAngle: -CGFloat.pi / 2, endAngle: CGFloat.pi / 2, clockwise: true)
        whiteHalf.close()
        whiteHalf.fill()

        // 黑色半圆（右半）
        ctx.setFillColor(UIColor.black.cgColor)
        let blackHalf = UIBezierPath()
        blackHalf.move(to: CGPoint(x: center.x, y: center.y - radius))
        blackHalf.addArc(withCenter: center, radius: radius,
                         startAngle: -CGFloat.pi / 2, endAngle: CGFloat.pi / 2, clockwise: false)
        blackHalf.close()
        blackHalf.fill()

        // 上方小圆（黑中白点）
        let topSmallCenter = CGPoint(x: center.x, y: center.y - halfR)
        ctx.setFillColor(UIColor.black.cgColor)
        let topSmall = UIBezierPath(ovalIn: CGRect(x: topSmallCenter.x - halfR,
                                                    y: topSmallCenter.y - halfR,
                                                    width: halfR * 2, height: halfR * 2))
        topSmall.fill()
        let dotR = halfR * 0.32
        ctx.setFillColor(UIColor.white.cgColor)
        let topDot = UIBezierPath(ovalIn: CGRect(x: topSmallCenter.x - dotR,
                                                  y: topSmallCenter.y - dotR,
                                                  width: dotR * 2, height: dotR * 2))
        topDot.fill()

        // 下方小圆（白中黑点）
        let bottomSmallCenter = CGPoint(x: center.x, y: center.y + halfR)
        ctx.setFillColor(UIColor.white.cgColor)
        let bottomSmall = UIBezierPath(ovalIn: CGRect(x: bottomSmallCenter.x - halfR,
                                                       y: bottomSmallCenter.y - halfR,
                                                       width: halfR * 2, height: halfR * 2))
        bottomSmall.fill()
        ctx.setFillColor(UIColor.black.cgColor)
        let bottomDot = UIBezierPath(ovalIn: CGRect(x: bottomSmallCenter.x - dotR,
                                                     y: bottomSmallCenter.y - dotR,
                                                     width: dotR * 2, height: dotR * 2))
        bottomDot.fill()
    }

    // MARK: - 生肖文字

    private func drawLabel(_ text: String, at point: CGPoint, angle: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor(red: 0.35, green: 0.18, blue: 0.05, alpha: 1.0)
        ]
        let size = text.size(withAttributes: attributes)
        let textRect = CGRect(x: point.x - size.width / 2,
                              y: point.y - size.height / 2,
                              width: size.width,
                              height: size.height)
        text.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - 动物绘制调度

    private func drawAnimal(_ animal: ZodiacAnimal, at center: CGPoint,
                            size: CGFloat, angle: CGFloat, in ctx: CGContext) {
        let s = size / 2
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)

        // 内圈底色圆
        ctx.setFillColor(UIColor(red: 0.975, green: 0.95, blue: 0.88, alpha: 1.0).cgColor)
        ctx.setStrokeColor(UIColor(red: 0.72, green: 0.45, blue: 0.20, alpha: 0.4).cgColor)
        ctx.setLineWidth(0.8)
        let bgCircle = UIBezierPath(ovalIn: CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
        bgCircle.fill()
        bgCircle.stroke()

        // 动物用深棕色填充+描边
        let animalColor = UIColor(red: 0.18, green: 0.10, blue: 0.02, alpha: 1.0)
        ctx.setFillColor(animalColor.cgColor)
        ctx.setStrokeColor(animalColor.cgColor)
        ctx.setLineWidth(0.6)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let ds = s * 0.68

        switch animal {
        case .rat:    drawRat(size: ds)
        case .ox:     drawOx(size: ds)
        case .tiger:  drawTiger(size: ds)
        case .rabbit: drawRabbit(size: ds)
        case .dragon: drawDragon(size: ds)
        case .snake:  drawSnake(size: ds)
        case .horse:  drawHorse(size: ds)
        case .goat:   drawGoat(size: ds)
        case .monkey: drawMonkey(size: ds)
        case .rooster:drawRooster(size: ds)
        case .dog:    drawDog(size: ds)
        case .pig:    drawPig(size: ds)
        }

        ctx.restoreGState()
    }

    // MARK: - 鼠 (Rat)

    private func drawRat(size: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -size * 0.55, y: size * 0.15))
        p.addCurve(to: CGPoint(x: -size * 0.15, y: -size * 0.1),
                   controlPoint1: CGPoint(x: -size * 0.55, y: -size * 0.45),
                   controlPoint2: CGPoint(x: -size * 0.35, y: -size * 0.5))
        p.addCurve(to: CGPoint(x: size * 0.45, y: -size * 0.15),
                   controlPoint1: CGPoint(x: size * 0.05, y: size * 0.3),
                   controlPoint2: CGPoint(x: size * 0.45, y: size * 0.3))
        p.addLine(to: CGPoint(x: size * 0.7, y: -size * 0.25))
        p.addLine(to: CGPoint(x: size * 0.55, y: -size * 0.1))
        p.addCurve(to: CGPoint(x: size * 0.2, y: size * 0.35),
                   controlPoint1: CGPoint(x: size * 0.55, y: size * 0.25),
                   controlPoint2: CGPoint(x: size * 0.4, y: size * 0.45))
        p.addCurve(to: CGPoint(x: -size * 0.55, y: size * 0.15),
                   controlPoint1: CGPoint(x: -size * 0.1, y: size * 0.25),
                   controlPoint2: CGPoint(x: -size * 0.4, y: size * 0.35))
        p.close()
        p.fill()
        p.stroke()

        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: -size * 0.5, y: size * 0.2))
        tail.addCurve(to: CGPoint(x: -size * 0.85, y: -size * 0.5),
                      controlPoint1: CGPoint(x: -size * 0.9, y: size * 0.3),
                      controlPoint2: CGPoint(x: -size * 0.8, y: -size * 0.25))
        tail.lineWidth = 1.8
        tail.stroke()
    }

    // MARK: - 牛 (Ox)

    private func drawOx(size: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -size * 0.5, y: size * 0.2))
        p.addCurve(to: CGPoint(x: -size * 0.3, y: -size * 0.4),
                   controlPoint1: CGPoint(x: -size * 0.55, y: -size * 0.15),
                   controlPoint2: CGPoint(x: -size * 0.45, y: -size * 0.4))
        p.addLine(to: CGPoint(x: size * 0.3, y: -size * 0.4))
        p.addCurve(to: CGPoint(x: size * 0.5, y: size * 0.2),
                   controlPoint1: CGPoint(x: size * 0.45, y: -size * 0.15),
                   controlPoint2: CGPoint(x: size * 0.55, y: size * 0.05))
        p.addCurve(to: CGPoint(x: -size * 0.5, y: size * 0.2),
                   controlPoint1: CGPoint(x: size * 0.3, y: size * 0.5),
                   controlPoint2: CGPoint(x: -size * 0.3, y: size * 0.5))
        p.close()
        p.fill()
        p.stroke()

        let horn = UIBezierPath()
        horn.move(to: CGPoint(x: -size * 0.35, y: -size * 0.4))
        horn.addCurve(to: CGPoint(x: -size * 0.15, y: -size * 0.85),
                      controlPoint1: CGPoint(x: -size * 0.5, y: -size * 0.7),
                      controlPoint2: CGPoint(x: -size * 0.3, y: -size * 0.85))
        horn.stroke()
        let horn2 = UIBezierPath()
        horn2.move(to: CGPoint(x: size * 0.35, y: -size * 0.4))
        horn2.addCurve(to: CGPoint(x: size * 0.15, y: -size * 0.85),
                       controlPoint1: CGPoint(x: size * 0.5, y: -size * 0.7),
                       controlPoint2: CGPoint(x: size * 0.3, y: -size * 0.85))
        horn2.stroke()
    }

    // MARK: - 虎 (Tiger)

    private func drawTiger(size: CGFloat) {
        let p = UIBezierPath()
        p.addArc(withCenter: .zero, radius: size * 0.55,
                 startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        p.fill()
        p.stroke()

        let ear1 = UIBezierPath()
        ear1.move(to: CGPoint(x: -size * 0.35, y: -size * 0.4))
        ear1.addLine(to: CGPoint(x: -size * 0.5, y: -size * 0.8))
        ear1.addLine(to: CGPoint(x: -size * 0.1, y: -size * 0.5))
        ear1.close()
        ear1.fill()
        let ear2 = UIBezierPath()
        ear2.move(to: CGPoint(x: size * 0.35, y: -size * 0.4))
        ear2.addLine(to: CGPoint(x: size * 0.5, y: -size * 0.8))
        ear2.addLine(to: CGPoint(x: size * 0.1, y: -size * 0.5))
        ear2.close()
        ear2.fill()

        ctxSaveAndDraw {
            let s1 = UIBezierPath()
            s1.move(to: CGPoint(x: -size * 0.15, y: -size * 0.65))
            s1.addLine(to: CGPoint(x: -size * 0.1, y: -size * 0.2))
            s1.stroke()
            let s2 = UIBezierPath()
            s2.move(to: CGPoint(x: 0, y: -size * 0.65))
            s2.addLine(to: CGPoint(x: 0, y: -size * 0.2))
            s2.stroke()
            let s3 = UIBezierPath()
            s3.move(to: CGPoint(x: size * 0.15, y: -size * 0.65))
            s3.addLine(to: CGPoint(x: size * 0.1, y: -size * 0.2))
            s3.stroke()
        }
    }

    // MARK: - 兔 (Rabbit)

    private func drawRabbit(size: CGFloat) {
        let body = UIBezierPath(ovalIn: CGRect(x: -size * 0.35, y: -size * 0.1,
                                                 width: size * 0.7, height: size * 0.7))
        body.fill()
        body.stroke()

        let ear1 = UIBezierPath()
        ear1.move(to: CGPoint(x: -size * 0.2, y: -size * 0.15))
        ear1.addLine(to: CGPoint(x: -size * 0.1, y: -size * 0.9))
        ear1.addLine(to: CGPoint(x: size * 0.05, y: -size * 0.15))
        ear1.close()
        ear1.fill()
        ear1.stroke()
        let ear2 = UIBezierPath()
        ear2.move(to: CGPoint(x: size * 0.05, y: -size * 0.2))
        ear2.addLine(to: CGPoint(x: size * 0.2, y: -size * 0.85))
        ear2.addLine(to: CGPoint(x: size * 0.3, y: -size * 0.15))
        ear2.close()
        ear2.fill()
        ear2.stroke()
    }

    // MARK: - 龙 (Dragon)

    private func drawDragon(size: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -size * 0.6, y: size * 0.3))
        p.addCurve(to: CGPoint(x: size * 0.15, y: -size * 0.6),
                   controlPoint1: CGPoint(x: -size * 0.7, y: -size * 0.3),
                   controlPoint2: CGPoint(x: -size * 0.2, y: -size * 0.7))
        p.addCurve(to: CGPoint(x: size * 0.6, y: size * 0.4),
                   controlPoint1: CGPoint(x: size * 0.5, y: -size * 0.5),
                   controlPoint2: CGPoint(x: size * 0.7, y: 0))
        p.lineWidth = 3
        p.stroke()

        let head = UIBezierPath(ovalIn: CGRect(x: size * 0.45, y: size * 0.25,
                                                 width: size * 0.3, height: size * 0.3))
        head.fill()
        head.stroke()

        let horn = UIBezierPath()
        horn.move(to: CGPoint(x: size * 0.55, y: size * 0.25))
        horn.addLine(to: CGPoint(x: size * 0.65, y: -size * 0.1))
        horn.addLine(to: CGPoint(x: size * 0.7, y: size * 0.3))
        horn.fill()
    }

    // MARK: - 蛇 (Snake)

    private func drawSnake(size: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -size * 0.15, y: size * 0.5))
        p.addCurve(to: CGPoint(x: size * 0.5, y: -size * 0.3),
                   controlPoint1: CGPoint(x: -size * 0.6, y: 0),
                   controlPoint2: CGPoint(x: size * 0.1, y: -size * 0.7))
        p.addCurve(to: CGPoint(x: size * 0.1, y: size * 0.5),
                   controlPoint1: CGPoint(x: size * 0.9, y: size * 0.1),
                   controlPoint2: CGPoint(x: size * 0.4, y: size * 0.5))
        p.lineWidth = 3
        p.stroke()

        let head = UIBezierPath(ovalIn: CGRect(x: -size * 0.35, y: size * 0.35,
                                                 width: size * 0.35, height: size * 0.25))
        head.fill()
        head.stroke()
    }

    // MARK: - 马 (Horse)

    private func drawHorse(size: CGFloat) {
        let face = UIBezierPath()
        face.move(to: CGPoint(x: -size * 0.2, y: size * 0.45))
        face.addLine(to: CGPoint(x: -size * 0.25, y: -size * 0.55))
        face.addCurve(to: CGPoint(x: size * 0.25, y: -size * 0.55),
                      controlPoint1: CGPoint(x: -size * 0.25, y: -size * 0.8),
                      controlPoint2: CGPoint(x: size * 0.25, y: -size * 0.8))
        face.addLine(to: CGPoint(x: size * 0.2, y: size * 0.45))
        face.addCurve(to: CGPoint(x: -size * 0.2, y: size * 0.45),
                      controlPoint1: CGPoint(x: size * 0.4, y: size * 0.6),
                      controlPoint2: CGPoint(x: -size * 0.4, y: size * 0.6))
        face.close()
        face.fill()
        face.stroke()

        let mane = UIBezierPath()
        mane.move(to: CGPoint(x: size * 0.15, y: -size * 0.55))
        mane.addCurve(to: CGPoint(x: size * 0.45, y: -size * 0.1),
                      controlPoint1: CGPoint(x: size * 0.55, y: -size * 0.6),
                      controlPoint2: CGPoint(x: size * 0.55, y: -size * 0.3))
        mane.stroke()
    }

    // MARK: - 羊 (Goat)

    private func drawGoat(size: CGFloat) {
        let body = UIBezierPath(ovalIn: CGRect(x: -size * 0.4, y: -size * 0.2,
                                                 width: size * 0.8, height: size * 0.6))
        body.fill()
        body.stroke()

        let horn1 = UIBezierPath()
        horn1.move(to: CGPoint(x: -size * 0.3, y: -size * 0.2))
        horn1.addCurve(to: CGPoint(x: -size * 0.1, y: -size * 0.1),
                       controlPoint1: CGPoint(x: -size * 0.8, y: -size * 0.6),
                       controlPoint2: CGPoint(x: -size * 0.5, y: -size * 0.6))
        horn1.stroke()
        let horn2 = UIBezierPath()
        horn2.move(to: CGPoint(x: size * 0.3, y: -size * 0.2))
        horn2.addCurve(to: CGPoint(x: size * 0.1, y: -size * 0.1),
                       controlPoint1: CGPoint(x: size * 0.8, y: -size * 0.6),
                       controlPoint2: CGPoint(x: size * 0.5, y: -size * 0.6))
        horn2.stroke()

        let face = UIBezierPath(ovalIn: CGRect(x: -size * 0.2, y: -size * 0.3,
                                                width: size * 0.4, height: size * 0.3))
        face.fill()
        face.stroke()
    }

    // MARK: - 猴 (Monkey)

    private func drawMonkey(size: CGFloat) {
        let face = UIBezierPath(ovalIn: CGRect(x: -size * 0.4, y: -size * 0.3,
                                                 width: size * 0.8, height: size * 0.65))
        face.fill()
        face.stroke()

        let ear1 = UIBezierPath(ovalIn: CGRect(x: -size * 0.55, y: -size * 0.4,
                                                width: size * 0.25, height: size * 0.3))
        ear1.fill()
        ear1.stroke()
        let ear2 = UIBezierPath(ovalIn: CGRect(x: size * 0.3, y: -size * 0.4,
                                                width: size * 0.25, height: size * 0.3))
        ear2.fill()
        ear2.stroke()

        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: size * 0.1, y: size * 0.3))
        tail.addCurve(to: CGPoint(x: size * 0.7, y: -size * 0.4),
                      controlPoint1: CGPoint(x: size * 0.5, y: size * 0.5),
                      controlPoint2: CGPoint(x: size * 0.8, y: 0))
        tail.lineWidth = 1.8
        tail.stroke()
    }

    // MARK: - 鸡 (Rooster)

    private func drawRooster(size: CGFloat) {
        let body = UIBezierPath(ovalIn: CGRect(x: -size * 0.3, y: -size * 0.2,
                                                 width: size * 0.6, height: size * 0.7))
        body.fill()
        body.stroke()

        let comb = UIBezierPath()
        comb.move(to: CGPoint(x: -size * 0.15, y: -size * 0.25))
        comb.addCurve(to: CGPoint(x: 0, y: -size * 0.8),
                      controlPoint1: CGPoint(x: -size * 0.3, y: -size * 0.6),
                      controlPoint2: CGPoint(x: -size * 0.15, y: -size * 0.8))
        comb.addCurve(to: CGPoint(x: size * 0.15, y: -size * 0.25),
                      controlPoint1: CGPoint(x: size * 0.15, y: -size * 0.8),
                      controlPoint2: CGPoint(x: size * 0.25, y: -size * 0.55))
        comb.close()
        comb.fill()

        let tailFeather = UIBezierPath()
        tailFeather.move(to: CGPoint(x: size * 0.2, y: size * 0.4))
        tailFeather.addCurve(to: CGPoint(x: size * 0.75, y: -size * 0.1),
                             controlPoint1: CGPoint(x: size * 0.6, y: size * 0.5),
                             controlPoint2: CGPoint(x: size * 0.8, y: size * 0.2))
        tailFeather.addCurve(to: CGPoint(x: size * 0.3, y: size * 0.2),
                             controlPoint1: CGPoint(x: size * 0.7, y: -size * 0.3),
                             controlPoint2: CGPoint(x: size * 0.5, y: 0))
        tailFeather.fill()
    }

    // MARK: - 狗 (Dog)

    private func drawDog(size: CGFloat) {
        let face = UIBezierPath(ovalIn: CGRect(x: -size * 0.35, y: -size * 0.2,
                                                 width: size * 0.7, height: size * 0.6))
        face.fill()
        face.stroke()

        let ear1 = UIBezierPath()
        ear1.move(to: CGPoint(x: -size * 0.3, y: -size * 0.2))
        ear1.addCurve(to: CGPoint(x: -size * 0.25, y: size * 0.35),
                      controlPoint1: CGPoint(x: -size * 0.7, y: 0),
                      controlPoint2: CGPoint(x: -size * 0.55, y: size * 0.35))
        ear1.addLine(to: CGPoint(x: -size * 0.1, y: -size * 0.1))
        ear1.close()
        ear1.fill()
        ear1.stroke()
        let ear2 = UIBezierPath()
        ear2.move(to: CGPoint(x: size * 0.3, y: -size * 0.2))
        ear2.addCurve(to: CGPoint(x: size * 0.25, y: size * 0.35),
                      controlPoint1: CGPoint(x: size * 0.7, y: 0),
                      controlPoint2: CGPoint(x: size * 0.55, y: size * 0.35))
        ear2.addLine(to: CGPoint(x: size * 0.1, y: -size * 0.1))
        ear2.close()
        ear2.fill()
        ear2.stroke()
    }

    // MARK: - 猪 (Pig)

    private func drawPig(size: CGFloat) {
        let body = UIBezierPath(ovalIn: CGRect(x: -size * 0.5, y: -size * 0.3,
                                                 width: size, height: size * 0.75))
        body.fill()
        body.stroke()

        let ear1 = UIBezierPath()
        ear1.move(to: CGPoint(x: -size * 0.35, y: -size * 0.3))
        ear1.addLine(to: CGPoint(x: -size * 0.5, y: -size * 0.7))
        ear1.addLine(to: CGPoint(x: -size * 0.1, y: -size * 0.35))
        ear1.close()
        ear1.fill()
        let ear2 = UIBezierPath()
        ear2.move(to: CGPoint(x: size * 0.35, y: -size * 0.3))
        ear2.addLine(to: CGPoint(x: size * 0.5, y: -size * 0.7))
        ear2.addLine(to: CGPoint(x: size * 0.1, y: -size * 0.35))
        ear2.close()
        ear2.fill()

        let snout = UIBezierPath(ovalIn: CGRect(x: -size * 0.18, y: size * 0.1,
                                                  width: size * 0.36, height: size * 0.22))
        snout.fill()

        let leg1 = UIBezierPath()
        leg1.move(to: CGPoint(x: -size * 0.3, y: size * 0.4))
        leg1.addLine(to: CGPoint(x: -size * 0.3, y: size * 0.65))
        leg1.stroke()
        let leg2 = UIBezierPath()
        leg2.move(to: CGPoint(x: size * 0.3, y: size * 0.4))
        leg2.addLine(to: CGPoint(x: size * 0.3, y: size * 0.65))
        leg2.stroke()
    }
}

// MARK: - Helper

private func ctxSaveAndDraw(_ block: () -> Void) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState()
    block()
    ctx.restoreGState()
}
