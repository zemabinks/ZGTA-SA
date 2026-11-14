import UIKit
import GameController

final class HomeViewController: UIViewController, UITextFieldDelegate {
    private let address = UITextField()
    private let code = UITextField()
    private let status = UILabel()
    private let play = UIButton(type: .system)
    private var checking = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLayout()
        address.text = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        address.delegate = self
        code.delegate = self
        play.addTarget(self, action: #selector(connect), for: .touchUpInside)
    }

    private func buildLayout() {
        let art = UIImageView(image: UIImage(named: "SoloCard"))
        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        art.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(art)
        let shade = UIView()
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.54)
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

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let header = UIView()
        header.backgroundColor = .white
        let title = label("CONNECT TO YOUR MAC", size: 26, color: .black, bold: true)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        let back = UIButton(type: .system)
        back.setTitle("BACK", for: .normal)
        back.setTitleColor(.black, for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 19, weight: .black, width: .condensed)
        back.translatesAutoresizingMaskIntoConstraints = false
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        header.addSubview(back)
        NSLayoutConstraint.activate([header.heightAnchor.constraint(equalToConstant: 55),
                                     title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
                                     title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                                     back.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -15),
                                     back.centerYAnchor.constraint(equalTo: header.centerYAnchor)])
        content.addArrangedSubview(header)
        let rule = UIView()
        rule.backgroundColor = UIColor(red: 0.17, green: 0.43, blue: 0.84, alpha: 1)
        rule.heightAnchor.constraint(equalToConstant: 5).isActive = true
        content.addArrangedSubview(rule)
        let panel = UIView()
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.83)
        content.addArrangedSubview(panel)
        let fields = UIStackView()
        fields.axis = .vertical
        fields.spacing = 8
        fields.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(fields)
        NSLayoutConstraint.activate([fields.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
                                     fields.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
                                     fields.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
                                     fields.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)])
        fields.addArrangedSubview(label("PLAY ON THE SAME WI-FI. DISCORD IS OPTIONAL.", size: 15, color: .white))
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fill
        configureField(address, placeholder: "192.168.1.10:8766", secure: false)
        address.keyboardType = .URL
        address.textContentType = .URL
        configureField(code, placeholder: "Join code, if needed", secure: true)
        row.addArrangedSubview(address)
        row.addArrangedSubview(code)
        fields.addArrangedSubview(label("SERVER ADDRESS                                   JOIN CODE", size: 12, color: UIColor.white.withAlphaComponent(0.74), bold: true))
        fields.addArrangedSubview(row)
        address.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.6, constant: -5).isActive = true
        play.setTitle("PLAY ON THIS SERVER", for: .normal)
        play.setTitleColor(.black, for: .normal)
        play.titleLabel?.font = .systemFont(ofSize: 22, weight: .black, width: .condensed)
        play.backgroundColor = .white
        play.heightAnchor.constraint(equalToConstant: 48).isActive = true
        fields.addArrangedSubview(play)
        status.text = "ENTER THE ADDRESS SHOWN BY ZGTA:SA SHARE ON YOUR MAC."
        status.textColor = UIColor.white.withAlphaComponent(0.75)
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.numberOfLines = 2
        fields.addArrangedSubview(status)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -24),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 940)
        ])
        let width = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24)
        width.priority = .defaultHigh
        width.isActive = true
    }

    private func label(_ text: String, size: CGFloat, color: UIColor, bold: Bool = false) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = color
        result.font = .systemFont(ofSize: size, weight: bold ? .black : .regular, width: .condensed)
        result.numberOfLines = 0
        return result
    }

    private func configureField(_ field: UITextField, placeholder: String, secure: Bool) {
        field.placeholder = placeholder
        field.attributedPlaceholder = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.5)])
        field.textColor = .white
        field.tintColor = .white
        field.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        field.font = .systemFont(ofSize: 17)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.isSecureTextEntry = secure
        field.returnKeyType = .done
        field.heightAnchor.constraint(equalToConstant: 45).isActive = true
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 45))
        field.leftViewMode = .always
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if textField === address { code.becomeFirstResponder() }
        return true
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func connect() {
        guard !checking else { return }
        guard let server = ServerAddress(address.text ?? "") else {
            status.text = "ENTER A VALID SERVER ADDRESS."
            status.textColor = .systemOrange
            return
        }
        checking = true
        play.isEnabled = false
        status.text = "CHECKING SERVER…"
        status.textColor = .white
        let joinCode = code.text ?? ""
        var request = URLRequest(url: server.path("api/local/status"))
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let http = response as? HTTPURLResponse
            if error == nil, http?.statusCode == 200 {
                self.authenticate(server)
            } else if http?.statusCode == 401, !joinCode.isEmpty {
                var join = URLRequest(url: server.path("api/local/join"))
                join.httpMethod = "POST"
                join.setValue("application/json", forHTTPHeaderField: "Content-Type")
                join.httpBody = try? JSONSerialization.data(withJSONObject: ["code": joinCode])
                URLSession.shared.dataTask(with: join) { [weak self] _, joinResponse, joinError in
                    guard let self else { return }
                    if joinError == nil, (joinResponse as? HTTPURLResponse)?.statusCode == 200 {
                        self.authenticate(server)
                    } else {
                        self.finish(error: "JOIN CODE WAS REJECTED")
                    }
                }.resume()
            } else {
                self.finish(error: http?.statusCode == 401
                            ? "ENTER THE JOIN CODE SHOWN ON YOUR MAC"
                            : "COULD NOT REACH THE MAC GAME SERVER")
            }
        }.resume()
    }

    private func authenticate(_ server: ServerAddress) {
        URLSession.shared.dataTask(with: server.path("api/auth/me")) { [weak self] _, response, error in
            guard let self else { return }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200 else {
                self.finish(error: "LOCAL PLAYER LOGIN FAILED")
                return
            }
            DispatchQueue.main.async {
                self.checking = false
                self.play.isEnabled = true
                UserDefaults.standard.set(server.url.absoluteString, forKey: "serverAddress")
                self.status.text = "CONNECTED. LOADING NATIVE GAME…"
                self.status.textColor = .white
                let game = NativeGameViewController(server: server)
                game.modalPresentationStyle = .fullScreen
                self.present(game, animated: true)
            }
        }.resume()
    }

    private func finish(error: String) {
        DispatchQueue.main.async {
            self.checking = false
            self.play.isEnabled = true
            self.status.text = error
            self.status.textColor = .systemOrange
        }
    }
}
