import UIKit

/// San Andreas art with the current ZGTA V Native menu's layout language.
final class MainMenuViewController: UIViewController {
    private let addressLine = MainMenuViewController.menuLabel("SET UP YOUR MAC SERVER TO PLAY", size: 13, color: .white)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let art = UIImageView(image: UIImage(named: "SoloCard"))
        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        art.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(art)
        let shade = UIView()
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.43)
        shade.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shade)
        NSLayoutConstraint.activate([art.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                     art.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                     art.topAnchor.constraint(equalTo: view.topAnchor),
                                     art.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     shade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                     shade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                     shade.topAnchor.constraint(equalTo: view.topAnchor),
                                     shade.bottomAnchor.constraint(equalTo: view.bottomAnchor)])

        let scroll = NativeMenuScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let content = scroll.column
        content.axis = .vertical
        content.spacing = 8

        let header = UIView()
        header.backgroundColor = UIColor.white.withAlphaComponent(0.96)
        let title = Self.menuLabel("ZGTA: SAN ANDREAS", size: 28, color: .black, bold: true)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        NSLayoutConstraint.activate([header.heightAnchor.constraint(equalToConstant: 57),
                                     title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
                                     title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
                                     title.centerYAnchor.constraint(equalTo: header.centerYAnchor)])
        content.addArrangedSubview(header)
        let rule = UIView()
        rule.backgroundColor = UIColor(red: 0.17, green: 0.43, blue: 0.84, alpha: 1)
        rule.heightAnchor.constraint(equalToConstant: 5).isActive = true
        content.addArrangedSubview(rule)

        let bar = UIStackView()
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        bar.spacing = 5
        for name in ["FREE ROAM", "MULTIPLAYER"] {
            let button = menuButton(name, filled: false)
            button.addTarget(self, action: #selector(openSetup), for: .touchUpInside)
            bar.addArrangedSubview(button)
        }
        content.addArrangedSubview(bar)

        let panel = UIView()
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.79)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
                                     stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
                                     stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 15),
                                     stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -15)])
        stack.addArrangedSubview(Self.menuLabel("YOUR CITY. YOUR SERVER.", size: 25, color: .white, bold: true))
        stack.addArrangedSubview(Self.menuLabel("PLAY SOLO OR WITH FRIENDS ON YOUR MAC'S LOCAL WORLD. DISCORD SIGN IN IS OPTIONAL.", size: 15, color: UIColor.white.withAlphaComponent(0.82)))
        addressLine.textColor = UIColor.white.withAlphaComponent(0.74)
        stack.addArrangedSubview(addressLine)
        let play = menuButton("CONNECT AND PLAY", filled: true)
        play.addTarget(self, action: #selector(openSetup), for: .touchUpInside)
        stack.addArrangedSubview(play)
        content.addArrangedSubview(panel)

        let footer = Self.menuLabel("NATIVE iOS PREVIEW  ·  GAME FILES STAY ON YOUR MAC", size: 12,
                                    color: UIColor.white.withAlphaComponent(0.85))
        footer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        content.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let saved = UserDefaults.standard.string(forKey: "serverAddress"), !saved.isEmpty {
            addressLine.text = "LAST SERVER: \(saved.uppercased())"
        }
    }

    private static func menuLabel(_ title: String, size: CGFloat, color: UIColor, bold: Bool = false) -> UILabel {
        let result = UILabel()
        result.text = title
        result.textColor = color
        result.font = .systemFont(ofSize: size, weight: bold ? .black : .regular, width: .condensed)
        result.numberOfLines = 0
        return result
    }

    private func menuButton(_ title: String, filled: Bool) -> UIButton {
        let result = UIButton(type: .system)
        result.setTitle(title, for: .normal)
        result.setTitleColor(filled ? .black : .white, for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: 21, weight: .black, width: .condensed)
        result.backgroundColor = filled ? .white : UIColor.black.withAlphaComponent(0.80)
        result.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return result
    }

    @objc private func openSetup() {
        guard presentedViewController == nil else { return }
        let setup = HomeViewController()
        setup.modalPresentationStyle = .fullScreen
        present(setup, animated: true)
    }
}
