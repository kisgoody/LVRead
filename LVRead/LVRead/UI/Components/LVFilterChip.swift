import UIKit

/// A filter chip component for selections
final class LVFilterChip: UIButton {
    
    enum ChipStyle {
        case selected
        case unselected
    }
    
    var chipStyle: ChipStyle = .unselected {
        didSet { applyStyle() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupChip()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    
    convenience init(title: String) {
        self.init(frame: .zero)
        setTitle(title, for: .normal)
    }
    
    private func setupChip() {
        titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        layer.cornerRadius = 14
        contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        applyStyle()
    }
    
    private func applyStyle() {
        switch chipStyle {
        case .selected:
            backgroundColor = .lvPrimary
            setTitleColor(.white, for: .normal)
            setTitleColor(.white.withAlphaComponent(0.7), for: .highlighted)
            
        case .unselected:
            backgroundColor = .lvSurfaceSecondary
            setTitleColor(.lvTextSecondary, for: .normal)
            setTitleColor(.lvTextPrimary, for: .highlighted)
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.7 : 1.0
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }
}

// MARK: - Filter Chip Group
final class LVFilterChipGroup: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var chips: [LVFilterChip] = []
    private var selectedIndex: Int = 0
    
    var onSelectionChanged: ((Int, String) -> Void)?
    
    var options: [String] = [] {
        didSet { setupChips() }
    }
    
    init(options: [String]) {
        self.options = options
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    
    private func setupView() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        scrollView.addSubview(stackView)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 36),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        
        setupChips()
    }
    
    private func setupChips() {
        // Remove existing chips
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll()
        
        for (index, title) in options.enumerated() {
            let chip = LVFilterChip(title: title)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(chip)
            chips.append(chip)
        }
        
        updateSelection()
    }
    
    @objc private func chipTapped(_ sender: LVFilterChip) {
        selectedIndex = sender.tag
        updateSelection()
        onSelectionChanged?(selectedIndex, options[selectedIndex])
    }
    
    private func updateSelection() {
        for (index, chip) in chips.enumerated() {
            chip.chipStyle = index == selectedIndex ? .selected : .unselected
        }
    }
    
    func select(index: Int) {
        guard index < options.count else { return }
        selectedIndex = index
        updateSelection()
    }
}
