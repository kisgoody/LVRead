import UIKit

/// 3D page-curl animation inspired by Apple Books.
/// Uses CoreAnimation 3D transforms for a realistic page-turning effect.
enum SimulationAnimator {

    // MARK: - Tap-initiated curl

    static func animate(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        backgroundColor: UIColor,
        completion: @escaping () -> Void
    ) {
        let isForward = direction == .next

        next.alpha = 1
        container.insertSubview(next, belowSubview: current)

        guard let curl = current.snapshotView(afterScreenUpdates: true) else {
            current.alpha = 0
            completion()
            return
        }
        curl.frame = current.frame
        curl.backgroundColor = backgroundColor
        container.addSubview(curl)

        // Back-face: a solid page-reverse surface for realism
        let backFace = UIView(frame: curl.bounds)
        backFace.backgroundColor = backgroundColor
        curl.addSubview(backFace)

        // Anchor at spine
        let anchorX: CGFloat = isForward ? 0.0 : 1.0
        curl.layer.anchorPoint = CGPoint(x: anchorX, y: 0.5)
        curl.layer.position = CGPoint(
            x: isForward ? container.bounds.minX : container.bounds.maxX,
            y: container.bounds.midY
        )

        // Shadow along curl edge
        let shadow = makeShadow(frame: curl.bounds, direction: direction)
        curl.layer.addSublayer(shadow)

        current.alpha = 0

        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 600.0  // perspective
        let angle: CGFloat = isForward ? -.pi * 0.5 : .pi * 0.5

        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            curl.layer.transform = CATransform3DRotate(transform, angle, 0, 1, 0)
            shadow.opacity = 0
        } completion: { _ in
            curl.removeFromSuperview()
            current.layer.transform = CATransform3DIdentity
            current.alpha = 0
            next.alpha = 1
            completion()
        }
    }

    // MARK: - Interactive curl

    static func beginInteractive(
        from current: UIView,
        direction: PageFlipDirection,
        container: UIView,
        state: PageFlipState
    ) {
        let isForward = direction == .next

        guard let curl = current.snapshotView(afterScreenUpdates: true) else { return }
        curl.frame = current.frame
        container.addSubview(curl)
        state.curlSnapshot = curl

        let backFace = UIView(frame: curl.bounds)
        backFace.backgroundColor = current.backgroundColor ?? .white
        curl.addSubview(backFace)
        state.curlBackSnapshot = backFace

        let anchorX: CGFloat = isForward ? 0.0 : 1.0
        curl.layer.anchorPoint = CGPoint(x: anchorX, y: 0.5)
        curl.layer.position = CGPoint(
            x: isForward ? container.bounds.minX : container.bounds.maxX,
            y: container.bounds.midY
        )

        let shadow = makeShadow(frame: curl.bounds, direction: direction)
        curl.layer.addSublayer(shadow)
        state.curlShadow = shadow

        current.alpha = 0
    }

    static func updateInteractive(progress: CGFloat, state: PageFlipState) {
        guard let curl = state.curlSnapshot else { return }
        let isForward = state.direction == .next
        var t = CATransform3DIdentity
        t.m34 = -1.0 / 600.0
        let angle = progress * (isForward ? -.pi * 0.5 : .pi * 0.5)
        curl.layer.transform = CATransform3DRotate(t, angle, 0, 1, 0)
        state.curlShadow?.opacity = Float(1.0 - progress * 0.85)
    }

    static func finishInteractive(
        commit: Bool,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard let curl = state.curlSnapshot else {
            state.cleanup()
            completion(false)
            return
        }
        let isForward = state.direction == .next
        var t = CATransform3DIdentity
        t.m34 = -1.0 / 600.0

        if commit {
            let angle: CGFloat = isForward ? -.pi * 0.5 : .pi * 0.5
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: .curveEaseIn
            ) {
                curl.layer.transform = CATransform3DRotate(t, angle, 0, 1, 0)
                state.curlShadow?.opacity = 0
            } completion: { _ in
                state.cleanup()
                completion(true)
            }
        } else {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.55,
                initialSpringVelocity: 0.5,
                options: []
            ) {
                curl.layer.transform = CATransform3DIdentity
                state.curlShadow?.opacity = 1
            } completion: { _ in
                state.cleanup()
                completion(false)
            }
        }
    }

    // MARK: - Helpers

    private static func makeShadow(frame: CGRect, direction: PageFlipDirection) -> CAGradientLayer {
        let isForward = direction == .next
        let shadow = CAGradientLayer()
        shadow.frame = frame
        shadow.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.06).cgColor,
            UIColor.black.withAlphaComponent(0.15).cgColor,
            UIColor.black.withAlphaComponent(0.28).cgColor
        ]
        shadow.locations = [0.0, 0.3, 0.65, 1.0]
        shadow.startPoint = CGPoint(x: isForward ? 1 : 0, y: 0.5)
        shadow.endPoint = CGPoint(x: isForward ? 0 : 1, y: 0.5)
        return shadow
    }
}
