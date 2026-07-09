import UIKit

struct PaperCurlSample {
    let location: CGPoint
    let translation: CGPoint
    let velocity: CGPoint
    let containerSize: CGSize

    var progress: CGFloat {
        PaperCurlPhysics.progress(
            translationX: translation.x,
            pageWidth: containerSize.width
        )
    }
}

enum PaperCurlPhysics {
    private static let distanceThreshold: CGFloat = 0.24
    private static let velocityThreshold: CGFloat = 650

    static func progress(translationX: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        return min(max(abs(translationX) / pageWidth, 0), 1)
    }

    static func shouldCommit(
        progress: CGFloat,
        velocityX: CGFloat,
        direction: PageFlipDirection
    ) -> Bool {
        if progress >= distanceThreshold { return true }
        let directionalVelocity: CGFloat
        switch direction {
        case .next:
            directionalVelocity = -velocityX
        case .prev:
            directionalVelocity = velocityX
        }
        return directionalVelocity >= velocityThreshold
    }

    static func completionDuration(
        progress: CGFloat,
        velocityX: CGFloat,
        pageWidth: CGFloat
    ) -> TimeInterval {
        guard pageWidth > 0 else { return 0.18 }
        let remainingDistance = (1 - min(max(progress, 0), 1)) * pageWidth
        let velocity = max(abs(velocityX), 400)
        let estimated = TimeInterval(remainingDistance / velocity)
        return min(max(estimated, 0.18), 0.48)
    }
}

enum PaperCurlAnimator {
    static var config = SimulationConfig.default

    static func animate(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        backgroundColor: UIColor,
        completion: @escaping () -> Void
    ) {
        if UIAccessibility.isReduceMotionEnabled {
            next.frame = current.frame
            next.alpha = 0
            container.insertSubview(next, aboveSubview: current)
            UIView.transition(
                from: current,
                to: next,
                duration: 0.18,
                options: [.transitionCrossDissolve, .showHideTransitionViews]
            ) { _ in completion() }
            return
        }

        let state = PageFlipState()
        beginInteractive(
            from: current,
            to: next,
            direction: direction,
            container: container,
            state: state
        )
        guard state.isActive else {
            current.alpha = 0
            next.alpha = 1
            completion()
            return
        }

        let width = max(container.bounds.width, 1)
        let translationX = direction == .next ? -width : width
        let sample = PaperCurlSample(
            location: CGPoint(x: direction == .next ? 0 : width, y: container.bounds.midY),
            translation: CGPoint(x: translationX, y: 0),
            velocity: .zero,
            containerSize: container.bounds.size
        )
        UIView.animate(
            withDuration: max(config.animationDuration, 0.18),
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            updateInteractive(sample: sample, state: state)
        } completion: { _ in
            state.cleanup()
            completion()
        }
    }

    static func beginInteractive(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        state: PageFlipState
    ) {
        state.cleanup()
        guard current.bounds.width > 0, current.bounds.height > 0 else { return }

        current.layoutIfNeeded()
        next.layoutIfNeeded()
        guard let pageImage = renderedImage(of: current), let cgImage = pageImage.cgImage else {
            current.alpha = 1
            next.alpha = 0
            return
        }

        state.containerView = container
        state.currentPageView = current
        state.nextPageView = next
        state.direction = direction
        state.progress = 0
        state.isActive = true

        next.frame = current.frame
        next.alpha = 1
        container.insertSubview(next, belowSubview: current)

        let host = UIView(frame: current.frame)
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = false
        host.clipsToBounds = false
        container.insertSubview(host, aboveSubview: next)
        state.paperHostView = host

        let sliceCount = max(16, min(24, Int(ceil(current.bounds.width / 22))))
        let sliceWidth = current.bounds.width / CGFloat(sliceCount)
        var wrappers: [UIView] = []
        var backs: [UIView] = []

        for index in 0..<sliceCount {
            let x = CGFloat(index) * sliceWidth
            let width = min(sliceWidth + 0.75, current.bounds.width - x + 0.75)
            guard let cropped = croppedImage(
                cgImage,
                pointsRect: CGRect(x: x, y: 0, width: width, height: current.bounds.height),
                sourceSize: current.bounds.size
            ) else { continue }

            let wrapper = UIView(frame: CGRect(x: x, y: 0, width: width, height: current.bounds.height))
            wrapper.backgroundColor = .clear
            wrapper.layer.allowsEdgeAntialiasing = true
            wrapper.layer.anchorPoint = CGPoint(x: direction == .next ? 0 : 1, y: 0.5)
            wrapper.layer.position = CGPoint(
                x: direction == .next ? x : x + width,
                y: current.bounds.midY
            )

            let front = UIImageView(frame: wrapper.bounds)
            front.image = UIImage(cgImage: cropped, scale: pageImage.scale, orientation: .up)
            front.contentMode = .scaleToFill
            front.layer.isDoubleSided = false
            wrapper.addSubview(front)

            let back = UIImageView(frame: wrapper.bounds)
            back.image = UIImage(cgImage: cropped, scale: pageImage.scale, orientation: .upMirrored)
            back.contentMode = .scaleToFill
            back.alpha = 0.52
            back.layer.isDoubleSided = false
            back.layer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
            wrapper.addSubview(back)

            let paperTint = UIView(frame: back.bounds)
            paperTint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            paperTint.backgroundColor = (current.backgroundColor ?? .white).withAlphaComponent(0.36)
            paperTint.isUserInteractionEnabled = false
            back.addSubview(paperTint)

            host.addSubview(wrapper)
            wrappers.append(wrapper)
            backs.append(back)
        }

        guard !wrappers.isEmpty else {
            state.cleanup()
            return
        }

        let crease = gradientLayer(
            colors: [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(config.shadowOpacity * 0.42).cgColor,
                UIColor.clear.cgColor
            ]
        )
        let highlight = gradientLayer(
            colors: [
                UIColor.clear.cgColor,
                UIColor.white.withAlphaComponent(0.42).cgColor,
                UIColor.clear.cgColor
            ]
        )
        let castShadow = gradientLayer(
            colors: direction == .next
                ? [
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(config.shadowOpacity * 0.34).cgColor
                ]
                : [
                    UIColor.black.withAlphaComponent(config.shadowOpacity * 0.34).cgColor,
                    UIColor.clear.cgColor
                ]
        )
        host.layer.addSublayer(castShadow)
        host.layer.addSublayer(crease)
        host.layer.addSublayer(highlight)

        state.paperFrontSlices = wrappers
        state.paperBackSlices = backs
        state.paperShadowLayers = [castShadow, crease]
        state.paperHighlightLayers = [highlight]
        current.alpha = 0

        updateInteractive(
            sample: PaperCurlSample(
                location: CGPoint(x: direction == .next ? current.bounds.maxX : 0, y: current.bounds.midY),
                translation: .zero,
                velocity: .zero,
                containerSize: current.bounds.size
            ),
            state: state
        )
    }

    static func updateInteractive(sample: PaperCurlSample, state: PageFlipState) {
        guard state.isActive,
              let host = state.paperHostView,
              let slices = state.paperFrontSlices,
              !slices.isEmpty else { return }

        let width = max(sample.containerSize.width, 1)
        let height = max(sample.containerSize.height, 1)
        let directionalDistance: CGFloat = state.direction == .next
            ? max(-sample.translation.x, 0)
            : max(sample.translation.x, 0)
        let progress = min(max(directionalDistance / width, 0), 1)
        let touchY = min(max(sample.location.y / height, 0), 1)
        let verticalBias = touchY - 0.5
        let directionSign: CGFloat = state.direction == .next ? -1 : 1

        for (index, slice) in slices.enumerated() {
            let ratio = CGFloat(index) / CGFloat(max(slices.count - 1, 1))
            let edgeDistance = state.direction == .next ? 1 - ratio : ratio
            let engagement = min(max((progress * 1.35 - edgeDistance * 0.34) / 0.92, 0), 1)
            let eased = engagement * engagement * (3 - 2 * engagement)
            let angle = CGFloat.pi * eased
            let horizontalTravel = directionSign * progress * width * (0.10 + edgeDistance * 0.82)
            let verticalTravel = verticalBias
                * height
                * 0.14
                * sin(.pi * ratio)
                * sin(angle)

            var transform = CATransform3DIdentity
            transform.m34 = -1 / max(520 + config.curlIntensity * 260, 1)
            transform = CATransform3DTranslate(transform, horizontalTravel, verticalTravel, 0)
            transform = CATransform3DRotate(
                transform,
                directionSign * angle * (0.72 + config.curlIntensity * 0.28),
                0,
                1,
                0
            )
            slice.layer.transform = transform
            if let backs = state.paperBackSlices, backs.indices.contains(index) {
                backs[index].alpha = 0.42 + eased * 0.26
            }
        }

        let foldX = state.direction == .next
            ? host.bounds.width * (1 - progress)
            : host.bounds.width * progress
        let shadowWidth = 72 + 54 * config.curlIntensity
        CATransaction.begin()
        CATransaction.setDisableActions(UIView.inheritedAnimationDuration == 0)
        if let castShadow = state.paperShadowLayers?.first {
            castShadow.frame = CGRect(
                x: foldX - (state.direction == .next ? shadowWidth : 0),
                y: 0,
                width: shadowWidth,
                height: host.bounds.height
            )
            castShadow.opacity = Float(min(config.shadowOpacity * (0.25 + progress), 1))
        }
        if let crease = state.paperShadowLayers?.last {
            crease.frame = CGRect(x: foldX - 18, y: 0, width: 36, height: host.bounds.height)
            crease.opacity = Float(min(config.shadowOpacity * (0.2 + progress), 1))
        }
        if let highlight = state.paperHighlightLayers?.first {
            highlight.frame = CGRect(x: foldX - 9, y: 0, width: 18, height: host.bounds.height)
            highlight.opacity = Float(min(0.25 + progress * 0.75, 1))
        }
        CATransaction.commit()

        state.progress = progress
        state.paperLastSample = sample
    }

    static func finishInteractive(
        commit requestedCommit: Bool,
        velocityX: CGFloat,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard state.isActive, let last = state.paperLastSample else {
            state.cleanup()
            completion(false)
            return
        }

        let commit = requestedCommit && PaperCurlPhysics.shouldCommit(
            progress: state.progress,
            velocityX: velocityX,
            direction: state.direction
        )
        let targetTranslation = CGPoint(
            x: commit
                ? (state.direction == .next ? -last.containerSize.width : last.containerSize.width)
                : 0,
            y: 0
        )
        let targetLocation = CGPoint(
            x: commit
                ? (state.direction == .next ? 0 : last.containerSize.width)
                : (state.direction == .next ? last.containerSize.width : 0),
            y: last.location.y
        )
        let target = PaperCurlSample(
            location: targetLocation,
            translation: targetTranslation,
            velocity: CGPoint(x: velocityX, y: 0),
            containerSize: last.containerSize
        )

        let animator: UIViewPropertyAnimator
        if commit {
            let duration = PaperCurlPhysics.completionDuration(
                progress: state.progress,
                velocityX: velocityX,
                pageWidth: last.containerSize.width
            )
            animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut)
        } else {
            let initialVelocity = CGVector(
                dx: velocityX / max(last.containerSize.width, 1),
                dy: 0
            )
            animator = UIViewPropertyAnimator(
                duration: max(config.animationDuration * 0.8, 0.22),
                timingParameters: UISpringTimingParameters(
                    dampingRatio: min(max(config.springDamping, 0.35), 1),
                    initialVelocity: initialVelocity
                )
            )
        }

        state.paperAnimator = animator
        animator.addAnimations {
            updateInteractive(sample: target, state: state)
        }
        animator.addCompletion { _ in
            state.paperAnimator = nil
            state.cleanup()
            completion(commit)
        }
        animator.startAnimation()
    }

    private static func renderedImage(of view: UIView) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    private static func croppedImage(
        _ image: CGImage,
        pointsRect: CGRect,
        sourceSize: CGSize
    ) -> CGImage? {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scaleX = CGFloat(image.width) / sourceSize.width
        let scaleY = CGFloat(image.height) / sourceSize.height
        let pixelRect = CGRect(
            x: pointsRect.minX * scaleX,
            y: pointsRect.minY * scaleY,
            width: min(pointsRect.width * scaleX, CGFloat(image.width) - pointsRect.minX * scaleX),
            height: min(pointsRect.height * scaleY, CGFloat(image.height) - pointsRect.minY * scaleY)
        ).integral
        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        return image.cropping(to: pixelRect)
    }

    private static func gradientLayer(colors: [CGColor]) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.colors = colors
        layer.locations = colors.count == 3 ? [0, 0.5, 1] : [0, 1]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.opacity = 0
        return layer
    }
}
