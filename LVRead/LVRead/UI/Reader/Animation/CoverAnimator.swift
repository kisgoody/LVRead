import UIKit

/// Next page slides over the current page with a smooth parallax effect,
/// similar to iBooks cover mode.
enum CoverAnimator {

    // MARK: - Tap-initiated cover

    static func animate(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        completion: @escaping () -> Void
    ) {
        let isForward = direction == .next
        let w = container.bounds.width
        let startX: CGFloat = isForward ? w : -w

        next.transform = CGAffineTransform(translationX: startX, y: 0)
        next.alpha = 1
        container.insertSubview(next, aboveSubview: current)

        // Shadow on leading edge
        let shadowW: CGFloat = 12
        let shadowLayer = CAGradientLayer()
        shadowLayer.frame = CGRect(
            x: isForward ? -shadowW : next.bounds.width,
            y: 0,
            width: shadowW,
            height: next.bounds.height
        )
        shadowLayer.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.12).cgColor,
            UIColor.black.withAlphaComponent(0.2).cgColor
        ]
        shadowLayer.locations = [0.0, 0.5, 1.0]
        shadowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shadowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        next.layer.addSublayer(shadowLayer)

        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            current.transform = CGAffineTransform(translationX: -startX * 0.25, y: 0)
            current.alpha = 0.55
            next.transform = .identity
            shadowLayer.opacity = 0
        } completion: { _ in
            shadowLayer.removeFromSuperlayer()
            current.transform = .identity
            current.alpha = 1
            next.alpha = 1
            completion()
        }
    }

    // MARK: - Interactive cover

    static func updateInteractive(progress: CGFloat, state: PageFlipState) {
        guard let current = state.currentPageView,
              let next = state.nextPageView,
              let container = state.containerView else { return }
        let w = container.bounds.width
        let isForward = state.direction == .next
        let offset: CGFloat = isForward ? w * (1.0 - progress) : -w * (1.0 - progress)
        next.transform = CGAffineTransform(translationX: offset, y: 0)
        current.alpha = 1.0 - progress * 0.45
    }

    static func finishInteractive(
        commit: Bool,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard let next = state.nextPageView,
              let current = state.currentPageView,
              let container = state.containerView else {
            state.cleanup()
            completion(false)
            return
        }
        let w = container.bounds.width

        if commit {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: .curveEaseOut
            ) {
                next.transform = .identity
                current.alpha = 0.55
            } completion: { _ in
                state.cleanup()
                completion(true)
            }
        } else {
            let isForward = state.direction == .next
            let backOff: CGFloat = isForward ? w : -w
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.62,
                initialSpringVelocity: 0.35,
                options: []
            ) {
                next.transform = CGAffineTransform(translationX: backOff, y: 0)
                current.alpha = 1
            } completion: { _ in
                state.cleanup()
                completion(false)
            }
        }
    }
}
