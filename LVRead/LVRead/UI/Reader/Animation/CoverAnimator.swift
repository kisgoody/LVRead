import UIKit

/// Cover transition: the current page moves away when advancing, while the
/// previous page slides over the current page when going back.
enum CoverAnimator {

    struct Offsets: Equatable {
        let current: CGFloat
        let incoming: CGFloat
    }

    static func offsets(
        progress: CGFloat,
        length: CGFloat,
        direction: PageFlipDirection
    ) -> Offsets {
        let value = min(1, max(0, progress))
        switch direction {
        case .next:
            return Offsets(current: -length * value, incoming: 0)
        case .prev:
            return Offsets(current: 0, incoming: -length * (1 - value))
        }
    }

    // MARK: - Tap-initiated cover

    static func animate(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        container: UIView,
        completion: @escaping () -> Void
    ) {
        let state = PageFlipState()
        beginInteractive(
            from: current,
            to: next,
            direction: direction,
            axis: .horizontal,
            container: container,
            state: state
        )
        finishInteractive(commit: true, state: state) { _ in
            completion()
        }
    }

    // MARK: - Interactive cover

    static func beginInteractive(
        from current: UIView,
        to next: UIView,
        direction: PageFlipDirection,
        axis: CoverFlipAxis,
        container: UIView,
        state: PageFlipState
    ) {
        state.containerView = container
        state.currentPageView = current
        state.nextPageView = next
        state.direction = direction
        state.coverAxis = axis
        state.progress = 0
        state.isActive = true
        next.frame = current.frame
        next.alpha = 1

        if direction == .next {
            container.insertSubview(next, belowSubview: current)
        } else {
            container.insertSubview(next, aboveSubview: current)
        }
        apply(progress: 0, state: state)
        state.coverShadow = makeShadow(for: direction == .next ? current : next, axis: axis)
    }

    static func updateInteractive(progress: CGFloat, state: PageFlipState) {
        guard state.isActive else { return }
        state.progress = min(1, max(0, progress))
        apply(progress: state.progress, state: state)
    }

    static func finishInteractive(
        commit: Bool,
        state: PageFlipState,
        completion: @escaping (Bool) -> Void
    ) {
        guard state.isActive,
              state.nextPageView != nil,
              state.currentPageView != nil,
              state.containerView != nil else {
            state.cleanup()
            completion(false)
            return
        }

        if commit {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                apply(progress: 1, state: state)
                state.coverShadow?.opacity = 0
            } completion: { _ in
                state.cleanup()
                completion(true)
            }
        } else {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.25,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                apply(progress: 0, state: state)
            } completion: { _ in
                state.cleanup()
                completion(false)
            }
        }
    }

    private static func apply(progress: CGFloat, state: PageFlipState) {
        guard let current = state.currentPageView,
              let next = state.nextPageView,
              let container = state.containerView else { return }
        let length = state.coverAxis == .horizontal
            ? container.bounds.width
            : container.bounds.height
        let values = offsets(progress: progress, length: length, direction: state.direction)
        current.transform = transform(offset: values.current, axis: state.coverAxis)
        next.transform = transform(offset: values.incoming, axis: state.coverAxis)
    }

    private static func transform(offset: CGFloat, axis: CoverFlipAxis) -> CGAffineTransform {
        switch axis {
        case .horizontal: return CGAffineTransform(translationX: offset, y: 0)
        case .vertical: return CGAffineTransform(translationX: 0, y: offset)
        }
    }

    private static func makeShadow(for movingView: UIView, axis: CoverFlipAxis) -> CAGradientLayer {
        let thickness: CGFloat = 12
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.16).cgColor
        ]
        layer.locations = [0, 1]
        switch axis {
        case .horizontal:
            layer.frame = CGRect(
                x: max(0, movingView.bounds.width - thickness),
                y: 0,
                width: thickness,
                height: movingView.bounds.height
            )
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 0.5)
        case .vertical:
            layer.frame = CGRect(
                x: 0,
                y: max(0, movingView.bounds.height - thickness),
                width: movingView.bounds.width,
                height: thickness
            )
            layer.startPoint = CGPoint(x: 0.5, y: 0)
            layer.endPoint = CGPoint(x: 0.5, y: 1)
        }
        movingView.layer.addSublayer(layer)
        return layer
    }
}
