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

    // Simulation (strip-based curl)
    var curlSnapshot: UIView?
    var curlStrips: [UIView]?
    var curlBackSnapshots: [UIView]?
    var curlShadow: CAGradientLayer?
    var curlPeekLayer: UIView?

    // Legacy (reserved for backward compatibility)
    var curlBackSnapshot: UIView?

    var direction: PageFlipDirection = .next
    var progress: CGFloat = 0
    var isActive = false

    func cleanup() {
        curlStrips?.forEach { $0.removeFromSuperview() }
        curlBackSnapshots?.forEach { $0.removeFromSuperview() }
        curlSnapshot?.removeFromSuperview()
        curlShadow?.removeFromSuperlayer()
        curlPeekLayer?.removeFromSuperview()
        curlBackSnapshot?.removeFromSuperview()
        curlStrips = nil
        curlBackSnapshots = nil
        curlSnapshot = nil
        curlShadow = nil
        curlPeekLayer = nil
        curlBackSnapshot = nil
        isActive = false
    }
}
