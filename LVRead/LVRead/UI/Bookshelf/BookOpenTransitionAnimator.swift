import UIKit

final class BookOpenTransitionSource {
    weak var itemView: UIView?
    private let initialFrameInWindow: CGRect
    private let dismissalItemProvider: (() -> UIView?)?
    private let dismissalFrameProvider: (() -> CGRect?)?

    init(
        itemView: UIView,
        dismissalItemProvider: (() -> UIView?)? = nil,
        dismissalFrameProvider: (() -> CGRect?)? = nil
    ) {
        self.itemView = itemView
        self.dismissalItemProvider = dismissalItemProvider
        self.dismissalFrameProvider = dismissalFrameProvider
        initialFrameInWindow = itemView.convert(itemView.bounds, to: nil)
    }

    func frame(in view: UIView, isPresenting: Bool) -> CGRect {
        let targetView = isPresenting ? itemView : dismissalItemProvider?()
        if let targetView, targetView.window != nil {
            return targetView.convert(targetView.bounds, to: view)
        }
        if !isPresenting, let frame = dismissalFrameProvider?() {
            return view.convert(frame, from: nil)
        }
        return view.convert(initialFrameInWindow, from: nil)
    }

    func prepare(isPresenting: Bool) {
        if isPresenting {
            itemView?.isHidden = true
        } else {
            itemView?.isHidden = false
            dismissalItemProvider?()?.isHidden = true
        }
    }

    func complete(isPresenting: Bool, completed: Bool) {
        if isPresenting {
            itemView?.isHidden = completed
        } else {
            itemView?.isHidden = !completed
            dismissalItemProvider?()?.isHidden = false
        }
    }
}

final class BookOpenTransitionAnimator: NSObject, UIViewControllerTransitioningDelegate {
    private let source: BookOpenTransitionSource?

    init(source: BookOpenTransitionSource?) {
        self.source = source
        super.init()
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        BookScaleAnimator(isPresenting: true, source: self.source)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        BookScaleAnimator(isPresenting: false, source: source)
    }
}

private final class BookScaleAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool
    private let source: BookOpenTransitionSource?

    init(isPresenting: Bool, source: BookOpenTransitionSource?) {
        self.isPresenting = isPresenting
        self.source = source
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.16 : 0.42
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        if isPresenting {
            toView.frame = transitionContext.finalFrame(for: toViewController)
            container.addSubview(toView)
        } else {
            container.insertSubview(toView, belowSubview: fromView)
        }

        guard !UIAccessibility.isReduceMotionEnabled, let source else {
            crossDissolve(from: fromView, to: toView, using: transitionContext)
            return
        }
        let sourceFrame = source.frame(in: container, isPresenting: isPresenting)
        guard sourceFrame.width > 0, sourceFrame.height > 0 else {
            crossDissolve(from: fromView, to: toView, using: transitionContext)
            return
        }

        let readerView = isPresenting ? toView : fromView
        let fullScreenCenter = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        let scale = CGAffineTransform(
            scaleX: sourceFrame.width / max(readerView.bounds.width, 1),
            y: sourceFrame.height / max(readerView.bounds.height, 1)
        )
        let originalCornerRadius = readerView.layer.cornerRadius
        let originalMasksToBounds = readerView.layer.masksToBounds

        readerView.isUserInteractionEnabled = false
        readerView.layer.masksToBounds = true
        source.prepare(isPresenting: isPresenting)
        if isPresenting {
            readerView.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
            readerView.transform = scale
            readerView.layer.cornerRadius = 12
            readerView.alpha = 0.94
        }

        let timing = isPresenting
            ? UICubicTimingParameters(controlPoint1: CGPoint(x: 0.22, y: 1), controlPoint2: CGPoint(x: 0.36, y: 1))
            : UICubicTimingParameters(controlPoint1: CGPoint(x: 0.64, y: 0), controlPoint2: CGPoint(x: 0.78, y: 0))
        let animator = UIViewPropertyAnimator(
            duration: transitionDuration(using: transitionContext),
            timingParameters: timing
        )
        animator.addAnimations {
            readerView.center = self.isPresenting
                ? fullScreenCenter
                : CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
            readerView.transform = self.isPresenting ? .identity : scale
            readerView.layer.cornerRadius = self.isPresenting ? 0 : 12
            readerView.alpha = self.isPresenting ? 1 : 0.94
        }
        animator.addCompletion { position in
            let completed = position == .end && !transitionContext.transitionWasCancelled
            readerView.transform = .identity
            readerView.center = fullScreenCenter
            readerView.layer.cornerRadius = originalCornerRadius
            readerView.layer.masksToBounds = originalMasksToBounds
            readerView.alpha = 1
            readerView.isUserInteractionEnabled = true
            source.complete(isPresenting: self.isPresenting, completed: completed)
            transitionContext.completeTransition(completed)
        }
        animator.startAnimation()
    }

    private func crossDissolve(
        from fromView: UIView,
        to toView: UIView,
        using transitionContext: UIViewControllerContextTransitioning
    ) {
        let readerView = isPresenting ? toView : fromView
        if isPresenting { readerView.alpha = 0 }
        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { readerView.alpha = self.isPresenting ? 1 : 0 },
            completion: { _ in
                readerView.alpha = 1
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        )
    }
}
