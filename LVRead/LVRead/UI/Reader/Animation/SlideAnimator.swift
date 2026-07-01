import UIKit

/// Both pages push together: the current page slides out while
/// the next page slides in from the opposite side.
enum SlideAnimator {

    // MARK: - Tap-initiated slide

    static func animate(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        completion: @escaping () -> Void
    ) {
        let isForward = direction == .next
        let w = container.bounds.width
        let curTarget: CGFloat = isForward ? -w : w
        let nextStart: CGFloat = isForward ? w : -w

        next.transform = CGAffineTransform(translationX: nextStart, y: 0)
        next.alpha = 1
        container.insertSubview(next, belowSubview: current)

        // Subtle dim on current page as it slides away
        let dimOverlay = UIView(frame: current.bounds)
        dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0)
        dimOverlay.isUserInteractionEnabled = false
        current.addSubview(dimOverlay)

        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.5,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            current.transform = CGAffineTransform(translationX: curTarget, y: 0)
            next.transform = .identity
            dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.04)
        } completion: { _ in
            dimOverlay.removeFromSuperview()
            current.transform = .identity
            current.alpha = 0
            next.alpha = 1
            completion()
        }
    }

    // MARK: - Interactive slide

    static func updateInteractive(progress: CGFloat, state: PageFlipState) {
        guard let current = state.currentPageView,
              let next = state.nextPageView,
              let container = state.containerView else { return }
        let w = container.bounds.width
        let isForward = state.direction == .next
        let curOff: CGFloat = isForward ? -w * progress : w * progress
        let nextOff: CGFloat = isForward ? w * (1.0 - progress) : -w * (1.0 - progress)
        current.transform = CGAffineTransform(translationX: curOff, y: 0)
        next.transform = CGAffineTransform(translationX: nextOff, y: 0)
    }

    static func finishInteractive(
        commit: Bool,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard let current = state.currentPageView,
              let next = state.nextPageView,
              let container = state.containerView else {
            state.cleanup()
            completion(false)
            return
        }
        let w = container.bounds.width
        let isForward = state.direction == .next

        if commit {
            let curOff: CGFloat = isForward ? -w : w
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: .curveEaseOut
            ) {
                current.transform = CGAffineTransform(translationX: curOff, y: 0)
                next.transform = .identity
            } completion: { _ in
                state.cleanup()
                completion(true)
            }
        } else {
            let nextBack: CGFloat = isForward ? w : -w
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.35,
                options: []
            ) {
                current.transform = .identity
                next.transform = CGAffineTransform(translationX: nextBack, y: 0)
            } completion: { _ in
                state.cleanup()
                completion(false)
            }
        }
    }
}
