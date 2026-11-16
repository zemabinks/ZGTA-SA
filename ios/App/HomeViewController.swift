import UIKit
import Security
import GameController

final class HomeViewController: NativeDEPanelViewController, UITextFieldDelegate {
    private let address = UITextField()
    private let code = UITextField()
    private let status = UILabel()
    private let play = UIButton(type: .system)
    private var checking = false
    private var connection:NativeMenuProfileClient?
    private var active=false

    init() {super.init(title:"MULTIPLAYER")}
    required init?(coder:NSCoder) {fatalError("Programmatic menu")}

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
        let scroll=NativeMenuScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints=false;contentView.addSubview(scroll)
        let content=scroll.column;content.axis = .vertical;content.spacing=12
        content.addArrangedSubview(label("CONNECT TO YOUR SERVER. DISCORD SIGN IN IS OPTIONAL.",size:16,color:.white))
        configureField(address,placeholder:"192.168.1.10:8766",secure:false)
        address.keyboardType = .URL;address.textContentType = .URL
        configureField(code,placeholder:"Join code, if required",secure:true)
        address.accessibilityLabel="Server address";code.accessibilityLabel="Join code"
        let row=UIStackView();row.axis = .horizontal;row.spacing=12;row.distribution = .fill
        for (name,field) in [("SERVER ADDRESS",address),("JOIN CODE",code)] {
            let column=UIStackView(arrangedSubviews:[label(name,size:15,color:.white),field])
            column.axis = .vertical;column.spacing=6;row.addArrangedSubview(column)
            registerMenuControl(field,activate:{field.becomeFirstResponder()})
        }
        address.widthAnchor.constraint(equalTo:row.widthAnchor,multiplier:0.6,constant:-6).isActive=true
        content.addArrangedSubview(row)
        play.setTitle("PLAY ON THIS SERVER",for:.normal);play.setTitleColor(.black,for:.normal)
        play.titleLabel?.font=menuFont(size:27);play.backgroundColor = .white
        play.heightAnchor.constraint(greaterThanOrEqualToConstant:48).isActive=true
        registerMenuControl(play);content.addArrangedSubview(play)
        let original=UIButton(type:.system)
        original.setTitle("JOIN ORIGINAL BROWSER WORLD",for:.normal);original.titleLabel?.font=bodyFont(size:17)
        original.addTarget(self,action:#selector(connectOriginalWorld),for:.touchUpInside)
        registerMenuControl(original);content.addArrangedSubview(original)
        let legacy=UIButton(type:.system);legacy.setTitle("JOIN SA-MP / OPEN.MP",for:.normal);legacy.titleLabel?.font=bodyFont(size:17)
        legacy.addTarget(self,action:#selector(connectLegacyWorld),for:.touchUpInside)
        registerMenuControl(legacy);content.addArrangedSubview(legacy)
        status.text="ENTER THE ADDRESS SHOWN BY ZGTA:SA SHARE ON YOUR MAC."
        status.textColor=UIColor.white.withAlphaComponent(0.8);status.font=bodyFont(size:15);status.numberOfLines=0
        status.accessibilityTraits.insert(.updatesFrequently);content.addArrangedSubview(status)
        let preferredBottom=scroll.bottomAnchor.constraint(equalTo:contentView.bottomAnchor);preferredBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:contentView.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:contentView.topAnchor),preferredBottom,
            scroll.bottomAnchor.constraint(lessThanOrEqualTo:contentView.bottomAnchor),
            scroll.bottomAnchor.constraint(lessThanOrEqualTo:view.keyboardLayoutGuide.topAnchor)
        ])
    }

    private func label(_ text: String, size: CGFloat, color: UIColor, bold: Bool = false) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = color
        result.font = bodyFont(size:size)
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
        field.font = bodyFont(size:17)
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

    override func viewWillAppear(_ animated:Bool) {super.viewWillAppear(animated);active=true}
    override func viewWillDisappear(_ animated:Bool) {
        active=false;connection?.cancelPendingRequests();checking=false;play.isEnabled=true
        view.endEditing(true);super.viewWillDisappear(animated)
    }
    @objc private func connectLegacyWorld() {
        guard active,!checking,presentedViewController==nil else{return}
        guard let assets=ServerAddress(address.text ?? "")else{status.text="ENTER YOUR MAC'S GAME FILES SERVER ABOVE FIRST.";return}
        let form=NativeSAMPConnectViewController(assets:assets,joinCode:code.text ?? "");form.modalPresentationStyle = .fullScreen
        form.onConnection = { [weak self,weak form] connection in
            guard let self,let form,self.presentedViewController === form else{return}
            form.dismiss(animated:false){[weak self]in
                guard let self,self.active,self.presentedViewController==nil else{return}
                let game=NativeGameViewController(server:assets,legacy:connection);game.modalPresentationStyle = .fullScreen
                self.present(game,animated:!self.menuMotionReduced)
            }
        }
        present(form,animated:!menuMotionReduced)
    }
    @objc private func connectOriginalWorld() {
        guard active,!checking,presentedViewController==nil else{return}
        guard let assets=ServerAddress(address.text ?? ""),assets.url.host?.lowercased() != "play.samp.directory" else{
            status.text="ENTER YOUR MAC'S GAME FILES SERVER ABOVE. THE ORIGINAL WORLD USES ITS OWN SIGN IN.";return
        }
        checking=true;play.isEnabled=false;status.text="CONNECTING TO YOUR GAME FILES SERVER…"
        let client=NativeMenuProfileClient(server:assets);connection=client
        client.connect(joinCode:code.text ?? ""){[weak self,weak client]result in
            guard let self,self.active,self.connection === client,self.presentedViewController==nil else{return}
            self.checking=false;self.play.isEnabled=true
            switch result{case .failure(let error):self.status.text=error.message
            case .success:self.presentOriginalWorld(assets:assets)}
        }
    }
    private func presentOriginalWorld(assets:ServerAddress){
        let login=NativeOriginalWorldSignInController();login.modalPresentationStyle = .fullScreen
        login.onConnection = { [weak self,weak login] connection in
            guard let self,let login,self.presentedViewController === login else{return}
            let deviceKey="originalWorld.device"
            let device=UserDefaults.standard.string(forKey:deviceKey) ?? UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
            UserDefaults.standard.set(device,forKey:deviceKey)
            login.dismiss(animated:false){[weak self] in
                guard let self,self.active,self.presentedViewController==nil,let origin=ServerAddress("https://play.samp.directory")else{return}
                let game=NativeGameViewController(server:assets,networkServer:origin,networkSession:connection.session,
                    flavor:.originalWorld(build:connection.build,deviceID:device))
                game.modalPresentationStyle = .fullScreen;self.present(game,animated:!self.menuMotionReduced)
            }
        }
        present(login,animated:!menuMotionReduced)
    }
    @objc private func connect() {
        guard active,!checking else{return}
        guard let server=ServerAddress(address.text ?? "") else{
            status.text="ENTER A VALID SERVER ADDRESS.";status.textColor = .systemOrange;return
        }
        checking=true;play.isEnabled=false;status.text="CONNECTING…";status.textColor = .white
        view.endEditing(true)
        let client=NativeMenuProfileClient(server:server);connection=client
        client.connect(joinCode:code.text ?? "") { [weak self,weak client] result in
            guard let self,self.active,self.connection === client,self.presentedViewController==nil else{return}
            self.checking=false;self.play.isEnabled=true
            switch result {
            case .failure(let error):self.status.text=error.message;self.status.textColor = .systemOrange
            case .success:
                UserDefaults.standard.set(server.url.absoluteString,forKey:"serverAddress")
                self.status.text="CONNECTED. LOADING NATIVE GAME…"
                let game=NativeGameViewController(server:server);game.modalPresentationStyle = .fullScreen
                NativeMenuKeyState.reset()
                self.present(game,animated:!self.menuMotionReduced)
            }
        }
    }

}

/// HTTP cookies are shared between ports and session cookies can disappear on
/// app restart. Keep each Mac server's anonymous player token in the Keychain.
/// An unsigned Simulator build uses app preferences when Keychain is unavailable.
enum LocalGuestSession {
    private static let service = "com.zema.zgtasa.localGuest"
    private static let cookieName = "zgta_local"

    private static func account(for server: ServerAddress) -> String {
        server.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func fallbackKey(for server: ServerAddress) -> String {
        "localGuest.\(account(for: server))"
    }

    private static func valid(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
    }

    static func restore(for server: ServerAddress) {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies(for: server.url) ?? [] where cookie.name == cookieName {
            storage.deleteCookie(cookie)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: server),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let lookup = SecItemCopyMatching(query as CFDictionary, &item)
        let saved = lookup == errSecSuccess ? (item as? Data).flatMap {
            String(data: $0, encoding: .ascii)
        } : UserDefaults.standard.string(forKey: fallbackKey(for: server))
        guard let token = saved, valid(token),
              let host = server.url.host,
              let cookie = HTTPCookie(properties: [
                .name: cookieName, .value: token, .domain: host, .path: "/",
                .expires: Date().addingTimeInterval(365 * 24 * 60 * 60)
              ]) else { return }
        storage.setCookie(cookie)
    }

    static func remember(_ response: HTTPURLResponse, for server: ServerAddress) {
        guard let header = response.value(forHTTPHeaderField: "Set-Cookie"),
              let first = header.split(separator: ";", maxSplits: 1).first,
              first.hasPrefix("\(cookieName)="),
              let token = first.split(separator: "=", maxSplits: 1).last.map(String.init),
              valid(token) else { return }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: server)
        ]
        let data = Data(token.utf8)
        let updated = SecItemUpdate(key as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        var saved = updated == errSecSuccess
        if updated == errSecItemNotFound {
            var entry = key
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            saved = SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
        }
        if saved { UserDefaults.standard.removeObject(forKey: fallbackKey(for: server)) }
        else { UserDefaults.standard.set(token, forKey: fallbackKey(for: server)) }
    }
}


/// The viewport content has a required width independent of label/field
/// intrinsic sizes. Re-presenting after a fullscreen game/keyboard transition
/// therefore cannot solve the form as an arbitrarily narrow vertical column.
final class NativeMenuScrollView: UIScrollView {
    let column = UIStackView()
    private let viewportContent = UIView()
    private var columnWidth: NSLayoutConstraint!
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentInsetAdjustmentBehavior = .never
        keyboardDismissMode = .interactive
        showsHorizontalScrollIndicator = false
        viewportContent.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(viewportContent); viewportContent.addSubview(column)
        columnWidth = column.widthAnchor.constraint(equalToConstant: 940)
        NSLayoutConstraint.activate([
            viewportContent.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            viewportContent.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            viewportContent.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            viewportContent.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            viewportContent.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            column.centerXAnchor.constraint(equalTo: viewportContent.centerXAnchor),
            column.topAnchor.constraint(equalTo: viewportContent.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: viewportContent.bottomAnchor, constant: -8),
            columnWidth
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layoutSubviews() {
        if bounds.width > 24 {
            let width = min(940, bounds.width - 24)
            if abs(columnWidth.constant - width) > 0.25 { columnWidth.constant = width }
        }
        super.layoutSubviews()
    }
}
