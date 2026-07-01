import UIKit

// MARK: - Shared Page Flip Types

/// Direction of page turn.
enum PageFlipDirection {
    case next
    case prev
}

/// Interactive state for gesture-driven page flips.
final class PageFlipState {
    weak var containerView: UIView?
    weak var currentPageView: UIView?
    weak var nextPageView: UIView?

    var curlSnapshot: UIView?
    var curlShadow: CAGradientLayer?
    var curlBackSnapshot: UIView?

    var direction: PageFlipDirection = .next
    var progress: CGFloat = 0
    var isActive = false

    func cleanup() {
        curlSnapshot?.removeFromSuperview()
        curlShadow?.removeFromSuperlayer()
        curlBackSnapshot?.removeFromSuperview()
        curlSnapshot = nil
        curlShadow = nil
        curlBackSnapshot = nil
        isActive = false
    }
}
