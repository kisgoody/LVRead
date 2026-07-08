import UIKit

// MARK: - Configurable Simulation Parameters
/// 对外提供可配置的仿真翻页参数
struct SimulationConfig {
    /// 纸张弯曲幅度 (0.1 ~ 1.0)，越大弯折越深，默认 0.5
    var curlIntensity: CGFloat = 0.5
    /// 阴影透明度 (0.0 ~ 1.0)，默认 0.6
    var shadowOpacity: CGFloat = 0.6
    /// 翻页动画基础时长（秒），默认 0.38
    var animationDuration: TimeInterval = 0.38
    /// 回弹弹簧阻尼系数 (0.1 ~ 1.0)，越小越弹，默认 0.55
    var springDamping: CGFloat = 0.55
    /// 回弹初始速度，默认 0.5
    var initialVelocity: CGFloat = 0.5

    static let `default` = SimulationConfig()
}

/// 3D 拟真纸质翻页动画
///
/// 实现原理：
/// 将页面垂直切分为多条 strip，每条独���应用 3D 旋转变换，
/// 组合形成纸张弯曲曲面效果。配合分层渐变阴影模拟卷曲光影、
/// 页面重叠透出淡影，以及物理惯性阻尼回弹。
///
/// 关键改进：
/// - 多段 strip 曲面 → 逼真的纸张弯折
/// - 明暗渐变阴影 → 卷曲区域层次感
/// - 弹簧阻尼回弹 → 滑动不足时自动复位
/// - 可配置参数 → 外部控制弯曲幅度/阴影/时长
enum SimulationAnimator {
    /// 页面切分条数 —— 越高曲面越平滑，性能消耗越大
    private static let stripCount = 12

    /// 可配置参数，修改后影响后续所有动画
    static var config = SimulationConfig.default

    // MARK: - Tap-initiated Curl

    static func animate(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        backgroundColor: UIColor,
        completion: @escaping () -> Void
    ) {
        let isForward = direction == .next

        // 0. 准备目标页
        next.alpha = 1
        container.insertSubview(next, belowSubview: current)

        // 1. 截取当前页快照
        guard let snapshot = current.snapshotView(afterScreenUpdates: true) else {
            current.alpha = 0
            completion()
            return
        }
        snapshot.frame = current.frame
        snapshot.backgroundColor = backgroundColor
        container.addSubview(snapshot)
        current.alpha = 0

        // 2. 将快照切分成条，搭建分层结构
        let (strips, backFaces, shadowLayer, nextPagePeek) = buildCurlLayers(
            snapshot: snapshot,
            direction: direction,
            container: container,
            backgroundColor: backgroundColor
        )

        // 3. 动画参数
        let d = config.animationDuration
        let intensityFactor: CGFloat = 0.35 + config.curlIntensity * 0.65  // 0.5 ~ 1.0
        let maxAngle: CGFloat = .pi / 2 * intensityFactor

        // 书脊侧 anchor 的条先开始，形成逐条卷起的波浪效果
        let stripDelay = d * 0.12 / CGFloat(strips.count)

        UIView.animateKeyframes(withDuration: d, delay: 0, options: [.calculationModeCubic]) {
            for (i, strip) in strips.enumerated() {
                let progress = CGFloat(i + 1) / CGFloat(strips.count)
                let angle = maxAngle * progress * progress  // 非线性曲线
                let relativeDelay = Double(i) * stripDelay
                let relativeDuration = d * (0.5 + 0.5 * (1.0 - progress))

                UIView.addKeyframe(withRelativeStartTime: relativeDelay / d,
                                   relativeDuration: relativeDuration / d) {
                    var t = CATransform3DIdentity
                    t.m34 = -1.0 / (500.0 + config.curlIntensity * 200.0)
                    let finalAngle: CGFloat = isForward ? -angle : angle
                    strip.layer.transform = CATransform3DRotate(t, finalAngle, 0, 1, 0)
                }
            }

            // 阴影逐渐消失
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                shadowLayer.opacity = 0
            }

            // 下一页淡影逐渐显现
            if let peek = nextPagePeek {
                UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8) {
                    peek.alpha = config.shadowOpacity * 0.25
                }
            }

            // 背面反白动画
            for (i, back) in backFaces.enumerated() {
                let relativeDelay2 = Double(i) * stripDelay
                let relDur = d * 0.6
                UIView.addKeyframe(withRelativeStartTime: relativeDelay2 / d,
                                   relativeDuration: relDur / d) {
                    back.alpha = 0.97
                }
            }
        } completion: { _ in
            // 收尾清理
            shadowLayer.removeFromSuperlayer()
            nextPagePeek?.removeFromSuperview()
            backFaces.forEach { $0.removeFromSuperview() }
            strips.forEach { $0.removeFromSuperview() }
            snapshot.removeFromSuperview()
            current.layer.transform = CATransform3DIdentity
            current.alpha = 0
            next.alpha = 1
            completion()
        }
    }

    // MARK: - Interactive Curl

    static func beginInteractive(
        from current: UIView,
        direction: PageFlipDirection,
        container: UIView,
        state: PageFlipState
    ) {
        guard let snapshot = current.snapshotView(afterScreenUpdates: true) else { return }
        snapshot.frame = current.frame
        container.addSubview(snapshot)
        state.curlSnapshot = snapshot

        let (strips, backFaces, shadowLayer, peekLayer) = buildCurlLayers(
            snapshot: snapshot,
            direction: direction,
            container: container,
            backgroundColor: current.backgroundColor ?? .white
        )
        state.curlStrips = strips
        state.curlBackSnapshots = backFaces
        state.curlShadow = shadowLayer
        state.curlPeekLayer = peekLayer

        current.alpha = 0
    }

    static func updateInteractive(progress: CGFloat, state: PageFlipState) {
        guard let strips = state.curlStrips, !strips.isEmpty else { return }
        let isForward = state.direction == .next
        let p = max(0, min(1, progress))
        let intensityFactor: CGFloat = 0.35 + config.curlIntensity * 0.65
        let maxAngle: CGFloat = .pi / 2 * intensityFactor
        let easedP = easeOutCubic(p)

        for (i, strip) in strips.enumerated() {
            let ratio = CGFloat(i + 1) / CGFloat(strips.count)
            let angle = maxAngle * ratio * ratio * easedP
            var t = CATransform3DIdentity
            t.m34 = -1.0 / (500.0 + config.curlIntensity * 200.0)
            strip.layer.transform = CATransform3DRotate(t, isForward ? -angle : angle, 0, 1, 0)
        }

        // 渐变阴影和淡影
        let shadowAlpha = (1.0 - easedP * 0.92) * config.shadowOpacity
        state.curlShadow?.opacity = Float(shadowAlpha)

        if let peek = state.curlPeekLayer {
            let peekAlpha = easedP * config.shadowOpacity * 0.25
            peek.alpha = min(peekAlpha, config.shadowOpacity * 0.25)
        }

        if let backs = state.curlBackSnapshots {
            for (i, back) in backs.enumerated() {
                let ratio = CGFloat(i + 1) / CGFloat(backs.count)
                back.alpha = 0.97 * easedP * ratio
            }
        }
    }

    static func finishInteractive(
        commit: Bool,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard let strips = state.curlStrips, !strips.isEmpty else {
            state.cleanup()
            completion(false)
            return
        }

        let isForward = state.direction == .next
        let d = commit ? config.animationDuration * 0.45 : config.animationDuration * 0.65
        let intensityFactor: CGFloat = 0.35 + config.curlIntensity * 0.65
        let maxAngle: CGFloat = .pi / 2 * intensityFactor

        if commit {
            // 【提交翻页】—— 惯性卷曲完成
            let stripDelay = d * 0.1 / CGFloat(strips.count)
            UIView.animateKeyframes(withDuration: d, delay: 0, options: [.calculationModeCubic]) {
                for (i, strip) in strips.enumerated() {
                    let progress = CGFloat(i + 1) / CGFloat(strips.count)
                    let angle = maxAngle * progress * progress
                    let delay = Double(i) * stripDelay

                    UIView.addKeyframe(withRelativeStartTime: delay / d,
                                       relativeDuration: (d - delay) / d) {
                        var t = CATransform3DIdentity
                        t.m34 = -1.0 / (500.0 + config.curlIntensity * 200.0)
                        strip.layer.transform = CATransform3DRotate(t, isForward ? -angle : angle, 0, 1, 0)
                    }
                }
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1.0) {
                    state.curlShadow?.opacity = 0
                    state.curlPeekLayer?.alpha = config.shadowOpacity * 0.25
                }
            } completion: { _ in
                state.cleanup()
                completion(true)
            }
        } else {
            // 【回弹复位】—— 物理阻尼回弹
            UIView.animate(
                withDuration: d,
                delay: 0,
                usingSpringWithDamping: config.springDamping,
                initialSpringVelocity: config.initialVelocity,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                for strip in strips {
                    strip.layer.transform = CATransform3DIdentity
                }
                state.curlShadow?.opacity = Float(config.shadowOpacity)
                state.curlPeekLayer?.alpha = 0
                if let backs = state.curlBackSnapshots {
                    for back in backs { back.alpha = 0 }
                }
            } completion: { _ in
                state.cleanup()
                completion(false)
            }
        }
    }

    // MARK: - Helpers

    /// 构建分层条带结构
    /// - Returns: (strips, backFaces, shadowLayer, nextPagePeek)
    private static func buildCurlLayers(
        snapshot: UIView,
        direction: PageFlipDirection,
        container: UIView,
        backgroundColor: UIColor
    ) -> ([UIView], [UIView], CAGradientLayer, UIView?) {
        let isForward = direction == .next
        let snapBounds = snapshot.bounds
        let stripW = snapBounds.width / CGFloat(stripCount)

        var strips: [UIView] = []
        var backFaces: [UIView] = []

        for i in 0..<stripCount {
            let x = CGFloat(i) * stripW

            // 条带视图
            let strip = UIView(frame: CGRect(x: x, y: 0, width: stripW + 0.5, height: snapBounds.height))
            strip.clipsToBounds = true
            strip.backgroundColor = backgroundColor

            // 把快照的对应区域渲染到条带中
            if let cgImage = snapshot.layer.contents as! CGImage? {
                let cgWidth = CGFloat(cgImage.width)
                let cgHeight = CGFloat(cgImage.height)
                let ratioW = cgWidth / max(snapBounds.width, 1)
                let ratioH = cgHeight / max(snapBounds.height, 1)
                let cropRect = CGRect(
                    x: x * ratioW,
                    y: 0,
                    width: (stripW + 0.5) * ratioW,
                    height: snapBounds.height * ratioH
                )
                if let cropped = cgImage.cropping(to: cropRect) {
                    let imgLayer = CALayer()
                    imgLayer.frame = strip.bounds
                    imgLayer.contents = cropped
                    strip.layer.addSublayer(imgLayer)
                }
            }

            // 条带的 anchorPoint 在书脊侧
            let anchorX: CGFloat = isForward ? 0.0 : 1.0
            strip.layer.anchorPoint = CGPoint(x: anchorX, y: 0.5)
            strip.layer.position = CGPoint(
                x: isForward ? 0 : strip.bounds.width,
                y: strip.bounds.midY
            )

            snapshot.addSubview(strip)
            strips.append(strip)

            // 背面反白视图 —— 模拟纸张翻过去的背面
            let back = UIView(frame: strip.bounds)
            back.backgroundColor = backgroundColor.withAlphaComponent(0)
            back.isUserInteractionEnabled = false
            strip.addSubview(back)
            backFaces.append(back)
        }

        // 【分层光影阴影】—— 卷曲区域的明暗渐变
        let shadowLayer = makeMultiStopShadow(
            frame: snapBounds,
            direction: direction,
            opacity: config.shadowOpacity
        )
        snapshot.layer.addSublayer(shadowLayer)

        // 【页面重叠处淡影】—— 透出下一页
        let peekLayer: UIView?
        if isForward {
            let peek = UIView(frame: snapBounds)
            peek.backgroundColor = backgroundColor
            peek.alpha = 0
            peek.isUserInteractionEnabled = false
            snapshot.insertSubview(peek, at: 0)
            peekLayer = peek
        } else {
            // 向前翻暂无淡影
            peekLayer = nil
        }

        return (strips, backFaces, shadowLayer, peekLayer)
    }

    /// 多层渐变阴影 —— 模拟卷曲处到平坦处的光照过渡
    private static func makeMultiStopShadow(
        frame: CGRect,
        direction: PageFlipDirection,
        opacity: CGFloat
    ) -> CAGradientLayer {
        let isForward = direction == .next
        let shadow = CAGradientLayer()
        shadow.frame = frame

        // 四层渐变：从卷曲边缘到平整处逐步减淡
        shadow.colors = [
            UIColor.black.withAlphaComponent(opacity * 0.45).cgColor,
            UIColor.black.withAlphaComponent(opacity * 0.25).cgColor,
            UIColor.black.withAlphaComponent(opacity * 0.10).cgColor,
            UIColor.black.withAlphaComponent(opacity * 0.03).cgColor,
            UIColor.clear.cgColor
        ]
        shadow.locations = [0.0, 0.25, 0.50, 0.75, 1.0]
        shadow.startPoint = CGPoint(x: isForward ? 1 : 0, y: 0.5)
        shadow.endPoint = CGPoint(x: isForward ? 0 : 1, y: 0.5)
        return shadow
    }

    /// easeOutCubic 缓动函数
    private static func easeOutCubic(_ x: CGFloat) -> CGFloat {
        1.0 - pow(1.0 - x, 3)
    }
}
