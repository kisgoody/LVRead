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

    // Paper curl renderer
    var paperHostView: UIView?
    var paperFrontSlices: [UIView]?
    var paperBackSlices: [UIView]?
    var paperShadowLayers: [CAGradientLayer]?
    var paperHighlightLayers: [CAGradientLayer]?
    var paperAnimator: UIViewPropertyAnimator?
    var paperLastSample: PaperCurlSample?

    var direction: PageFlipDirection = .next
    var progress: CGFloat = 0
    var isActive = false

    func cleanup() {
        paperAnimator?.stopAnimation(true)
        paperFrontSlices?.forEach { $0.removeFromSuperview() }
        paperBackSlices?.forEach { $0.removeFromSuperview() }
        paperShadowLayers?.forEach { $0.removeFromSuperlayer() }
        paperHighlightLayers?.forEach { $0.removeFromSuperlayer() }
        paperHostView?.removeFromSuperview()
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
        paperAnimator = nil
        paperFrontSlices = nil
        paperBackSlices = nil
        paperShadowLayers = nil
        paperHighlightLayers = nil
        paperHostView = nil
        paperLastSample = nil
        currentPageView?.transform = .identity
        currentPageView?.layer.transform = CATransform3DIdentity
        currentPageView?.alpha = 1
        nextPageView?.transform = .identity
        nextPageView?.layer.transform = CATransform3DIdentity
        nextPageView?.alpha = 0
        isActive = false
    }
}
