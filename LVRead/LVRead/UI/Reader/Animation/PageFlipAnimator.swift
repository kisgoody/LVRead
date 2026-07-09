import UIKit

// MARK: - Page Flip Animator (Dispatcher)

/// Lightweight dispatcher that routes to the appropriate animator.
/// All animation implementations live in their own files.
enum PageFlipAnimator {

    /// Animate a full page turn (tap-initiated).
    static func animateTap(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        mode: PageFlipMode,
        backgroundColor: UIColor,
        container: UIView,
        completion: @escaping () -> Void
    ) {
        switch mode {
        case .simulation:
            PaperCurlAnimator.animate(
                from: current, to: next,
                direction: direction, container: container,
                backgroundColor: backgroundColor,
                completion: completion
            )
        case .cover:
            CoverAnimator.animate(
                from: current, to: next,
                direction: direction, container: container,
                completion: completion
            )
        case .slide:
            SlideAnimator.animate(
                from: current, to: next,
                direction: direction, container: container,
                completion: completion
            )
        case .none:
            current.alpha = 0
            next.alpha = 1
            completion()
        case .scroll:
            completion()
        }
    }

    static func beginInteractive(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        mode: PageFlipMode,
        container: UIView,
        state: PageFlipState
    ) {
        state.containerView = container
        state.currentPageView = current
        state.nextPageView = next
        state.direction = direction
        state.progress = 0
       state.isActive = true
       next.frame = current.frame
       next.alpha = 1
        switch mode {
        case .simulation:
            PaperCurlAnimator.beginInteractive(
                from: current, to: next, direction: direction,
                container: container, state: state
            )
        case .cover:
            // Cover: next slides OVER current — must be above in z-order
            let w = container.bounds.width
            let isForward = direction == .next
            next.transform = CGAffineTransform(
                translationX: isForward ? w : -w, y: 0
            )
            container.insertSubview(next, aboveSubview: current)
        case .slide:
            // Slide: pages push each other — next is revealed from below
            let w = container.bounds.width
            let isForward = direction == .next
            next.transform = CGAffineTransform(
                translationX: isForward ? w : -w, y: 0
            )
            container.insertSubview(next, belowSubview: current)
        default: break
        }
    }

    static func updateInteractive(
        sample: PaperCurlSample,
        mode: PageFlipMode,
        state: PageFlipState
    ) {
        guard state.isActive else { return }
        let p = min(1, max(0, sample.progress))
        state.progress = p
        switch mode {
        case .simulation:
            PaperCurlAnimator.updateInteractive(sample: sample, state: state)
        case .cover:
            CoverAnimator.updateInteractive(progress: p, state: state)
        case .slide:
            SlideAnimator.updateInteractive(progress: p, state: state)
        default: break
        }
    }

    static func finishInteractive(
        commit: Bool,
        velocityX: CGFloat,
        mode: PageFlipMode,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard state.isActive else { completion(false); return }
        switch mode {
        case .simulation:
            PaperCurlAnimator.finishInteractive(
                commit: commit,
                velocityX: velocityX,
                state: state,
                completion: completion
            )
        case .cover:
            CoverAnimator.finishInteractive(commit: commit, state: state, completion: completion)
        case .slide:
            SlideAnimator.finishInteractive(commit: commit, state: state, completion: completion)
        case .none, .scroll:
            state.cleanup()
            completion(commit)
        }
    }
}
