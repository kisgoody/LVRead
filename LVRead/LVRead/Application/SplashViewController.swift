import UIKit

final class SplashViewController: UIViewController {
    
    var onComplete: (() -> Void)?
    
    // MARK: - Colors
    private let ricePaperCream = UIColor(hex: "#F5F0E8")
    private let inkColor = UIColor(hex: "#2C2416")
    private let cinnabarRed = UIColor(hex: "#C0392B")
    private let bronzeGold = UIColor(hex: "#B8860B")
    private let mountainNear = UIColor(hex: "#D4CBB8")
    private let mountainFar = UIColor(hex: "#E4DDD0")
    
    // MARK: - Views
    private let appNameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separatorLine = UIView()
    private let patternContainer = UIView()
    
    // MARK: - Layers
    private let mountainFarLayer = CAShapeLayer()
    private let mountainNearLayer = CAShapeLayer()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ricePaperCream
        setupMountainLayers()
        setupTextElements()
        setupSeparator()
        setupPattern()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMountainPaths()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAnimations()
        scheduleDismiss()
    }
    
    // MARK: - Mountain Silhouette
    
    private func setupMountainLayers() {
        mountainFarLayer.fillColor = mountainFar.cgColor
        mountainFarLayer.opacity = 0.5
        view.layer.addSublayer(mountainFarLayer)
        
        mountainNearLayer.fillColor = mountainNear.cgColor
        mountainNearLayer.opacity = 0.4
        view.layer.addSublayer(mountainNearLayer)
    }
    
    private func updateMountainPaths() {
        let w = view.bounds.width
        let h = view.bounds.height
        let baseY = h
        
        // Far mountains (taller, lighter)
        let farHeight = h * 0.28
        let farPath = mountainPath(
            width: w, baseY: baseY, mountainHeight: farHeight,
            peaks: [
                (0.05, 0.20), (0.18, 0.55), (0.30, 0.35),
                (0.42, 0.72), (0.55, 0.40), (0.64, 0.68),
                (0.78, 0.30), (0.88, 0.52), (0.95, 0.18),
            ]
        )
        mountainFarLayer.path = farPath.cgPath
        
        // Near mountains (shorter, darker)
        let nearHeight = h * 0.18
        let nearPath = mountainPath(
            width: w, baseY: baseY, mountainHeight: nearHeight,
            peaks: [
                (0.00, 0.25), (0.12, 0.60), (0.26, 0.35),
                (0.38, 0.78), (0.52, 0.45), (0.66, 0.85),
                (0.80, 0.40), (0.92, 0.55), (1.00, 0.20),
            ]
        )
        mountainNearLayer.path = nearPath.cgPath
    }
    
    private func mountainPath(width: CGFloat, baseY: CGFloat, mountainHeight: CGFloat,
                              peaks: [(CGFloat, CGFloat)]) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: baseY))
        
        for (i, peak) in peaks.enumerated() {
            let x = width * peak.0
            let y = baseY - mountainHeight * peak.1
            
            if i == 0 {
                let cp = CGPoint(x: x * 0.35, y: baseY - mountainHeight * 0.05)
                path.addQuadCurve(to: CGPoint(x: x, y: y), controlPoint: cp)
            } else {
                let prevX = width * peaks[i - 1].0
                let prevY = baseY - mountainHeight * peaks[i - 1].1
                let midX = (prevX + x) / 2
                let valleyDepth = mountainHeight * 0.02
                let midY = max(prevY, y) + valleyDepth
                path.addQuadCurve(to: CGPoint(x: x, y: y),
                                  controlPoint: CGPoint(x: midX, y: midY))
            }
        }
        
        path.addLine(to: CGPoint(x: width, y: baseY))
        path.close()
        return path
    }
    
    // MARK: - Text Elements
    
    private func setupTextElements() {
        appNameLabel.text = "LVRead"
        appNameLabel.font = {
            if let georgia = UIFont(name: "Georgia-Bold", size: 48) { return georgia }
            if let songti = UIFont(name: "STSongti-SC-Bold", size: 48) { return songti }
            return UIFont.systemFont(ofSize: 48, weight: .bold)
        }()
        appNameLabel.textColor = inkColor
        appNameLabel.textAlignment = .center
        appNameLabel.alpha = 0
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appNameLabel)
        
        subtitleLabel.text = "书香致远"
        subtitleLabel.font = {
            if let songti = UIFont(name: "STSongti-SC-Regular", size: 18) { return songti }
            if let georgia = UIFont(name: "Georgia", size: 18) { return georgia }
            return UIFont.systemFont(ofSize: 18, weight: .light)
        }()
        subtitleLabel.textColor = inkColor.withAlphaComponent(0.7)
        subtitleLabel.textAlignment = .center
        subtitleLabel.alpha = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            appNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            appNameLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -55),
            
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 12),
        ])
    }
    
    // MARK: - Separator
    
    private func setupSeparator() {
        separatorLine.backgroundColor = cinnabarRed
        separatorLine.alpha = 0
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separatorLine)
        
        NSLayoutConstraint.activate([
            separatorLine.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            separatorLine.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            separatorLine.widthAnchor.constraint(equalToConstant: 100),
            separatorLine.heightAnchor.constraint(equalToConstant: 1.5),
        ])
    }
    
    // MARK: - Classical Pattern
    
    private func setupPattern() {
        let count = 7
        let radius: CGFloat = 3.5
        let spacing: CGFloat = 14
        let totalW = CGFloat(count) * (radius * 2) + CGFloat(count - 1) * spacing
        
        patternContainer.alpha = 0
        patternContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(patternContainer)
        
        NSLayoutConstraint.activate([
            patternContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            patternContainer.topAnchor.constraint(equalTo: separatorLine.bottomAnchor, constant: 22),
            patternContainer.widthAnchor.constraint(equalToConstant: totalW),
            patternContainer.heightAnchor.constraint(equalToConstant: radius * 2),
        ])
        
        for i in 0..<count {
            let dot = CAShapeLayer()
            let cx = CGFloat(i) * (radius * 2 + spacing) + radius
            dot.path = UIBezierPath(ovalIn: CGRect(x: cx - radius, y: 0, width: radius * 2, height: radius * 2)).cgPath
            dot.fillColor = bronzeGold.cgColor
            patternContainer.layer.addSublayer(dot)
        }
    }
    
    // MARK: - Animation
    
    private func startAnimations() {
        let fadeViews: [(UIView, TimeInterval)] = [
            (appNameLabel, 0),
            (subtitleLabel, 0.35),
            (separatorLine, 0.7),
            (patternContainer, 1.0),
        ]
        
        for (view, delay) in fadeViews {
            UIView.animate(
                withDuration: 1.0,
                delay: delay,
                options: [.curveEaseInOut],
                animations: { view.alpha = 1.0 },
                completion: nil
            )
        }
    }
    
    private func scheduleDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.onComplete?()
        }
    }
}
