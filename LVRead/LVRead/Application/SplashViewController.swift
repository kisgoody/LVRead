import UIKit

final class SplashViewController: UIViewController {

    var onComplete: (() -> Void)?

    private let imageView = UIImageView()
    private var didScheduleCompletion = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.image = UIImage(named: splashImageName)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = UIAccessibility.isReduceMotionEnabled ? 1 : 0
        imageView.isAccessibilityElement = false
        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scheduleCompletion()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState],
                animations: { self.imageView.alpha = 1 }
            )
        }
    }

    private func scheduleCompletion() {
        guard !didScheduleCompletion else { return }
        didScheduleCompletion = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.onComplete?()
        }
    }

    private var splashImageName: String {
        let language = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        let languageName = language.hasPrefix("zh") ? "Chinese" : "English"
        let deviceName = UIDevice.current.userInterfaceIdiom == .pad ? "Pad" : "Phone"
        return "Splash\(deviceName)\(languageName)"
    }
}
