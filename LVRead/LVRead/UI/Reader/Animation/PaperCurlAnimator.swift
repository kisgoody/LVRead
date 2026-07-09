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
