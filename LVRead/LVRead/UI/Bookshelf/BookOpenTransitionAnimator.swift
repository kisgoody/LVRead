import UIKit

final class BookOpenTransitionAnimator: NSObject, UIViewControllerTransitioningDelegate {
    private let sourceFrame: CGRect

    init(sourceFrame: CGRect) {
        self.sourceFrame = sourceFrame
        super.init()
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        BookOpenPresentAnimator(sourceFrame: sourceFrame)
    }
}

private final class BookOpenPresentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceFrame: CGRect

    init(sourceFrame: CGRect) {
        self.sourceFrame = sourceFrame
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.58
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: transitionContext.viewController(forKey: .to)!)
        toView.frame = finalFrame
        toView.alpha = 0
        container.addSubview(toView)

        let pageView = UIView(frame: sourceFrame)
        pageView.backgroundColor = LVBookshelfModuleStyle.pageBackground
        pageView.layer.cornerRadius = 10
        pageView.layer.masksToBounds = true
        container.addSubview(pageView)

        let coverView = UIView(frame: sourceFrame)
        coverView.backgroundColor = LVBookshelfModuleStyle.accent
        coverView.layer.cornerRadius = 10
        coverView.layer.masksToBounds = true
        coverView.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        coverView.layer.position = CGPoint(x: sourceFrame.minX, y: sourceFrame.midY)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 700
        coverView.layer.transform = perspective
        container.addSubview(coverView)

        let spine = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: sourceFrame.height))
        spine.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        coverView.addSubview(spine)

        UIView.animateKeyframes(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.calculationModeCubic],
            animations: {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.48) {
                    pageView.frame = finalFrame
                    pageView.layer.cornerRadius = 0
                    coverView.layer.transform = CATransform3DRotate(perspective, -.pi * 0.82, 0, 1, 0)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.28, relativeDuration: 0.72) {
                    toView.alpha = 1
                }
                UIView.addKeyframe(withRelativeStartTime: 0.46, relativeDuration: 0.54) {
                    coverView.alpha = 0
                }
            },
            completion: { finished in
                coverView.removeFromSuperview()
                pageView.removeFromSuperview()
                transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
            }
        )
    }
}
