import UIKit

class ZodiacDemoVC: UIViewController {
    private let zodiacView = ZodiacPaperCutView()
    private let nameLabel = UILabel()
    private let prevBtn = UIButton(type: .system)
    private let nextBtn = UIButton(type: .system)
    private var currentIdx = 0
    private let names = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "剪纸十二生肖"
//        setupLayout()
//        refreshUI()
//        view.backgroundColor = .white

                // 创建轮盘视图，给一个正方形区域
                let side = min(view.bounds.width, view.bounds.height) * 0.9
                let wheel = ZodiacWheelView(frame: CGRect(x: 0, y: 0, width: side, height: side))
                wheel.center = view.center
                wheel.backgroundColor = .clear   // 透明背景，让 draw 里的象牙白底盘露出来
                view.addSubview(wheel)
    }
    
    private func setupLayout() {
        zodiacView.translatesAutoresizingMaskIntoConstraints = false
        zodiacView.backgroundColor = #colorLiteral(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        view.addSubview(zodiacView)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        nameLabel.textAlignment = .center
        view.addSubview(nameLabel)
        
        prevBtn.setTitle("上一个", for: .normal)
        prevBtn.addTarget(self, action: #selector(prev), for: .touchUpInside)
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(prevBtn)
        
        nextBtn.setTitle("下一个", for: .normal)
        nextBtn.addTarget(self, action: #selector(getter: next), for: .touchUpInside)
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nextBtn)
        
        NSLayoutConstraint.activate([
            zodiacView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zodiacView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            zodiacView.widthAnchor.constraint(equalToConstant: 320),
            zodiacView.heightAnchor.constraint(equalToConstant: 320),
            
            nameLabel.topAnchor.constraint(equalTo: zodiacView.bottomAnchor, constant: 30),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            prevBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            prevBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            prevBtn.widthAnchor.constraint(equalToConstant: 110),
            
            nextBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            nextBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -80),
            nextBtn.widthAnchor.constraint(equalToConstant: 110)
        ])
    }
    
    private func refreshUI() {
        zodiacView.zodiacIndex = currentIdx
        nameLabel.text = "当前：\(names[currentIdx])"
    }
    
    @objc private func prev() {
        currentIdx = currentIdx - 1 < 0 ? 11 : currentIdx - 1
        refreshUI()
    }
    
    @objc private func next() {
        currentIdx = (currentIdx + 1) % 12
        refreshUI()
    }
}
