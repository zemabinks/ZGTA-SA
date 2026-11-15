import UIKit

/// Real self-hosted profile pages. Offline help has no account/network side effects.
final class NativeGameManagementController: NativeDEPanelViewController, UITextFieldDelegate {
    private enum Page {
        case index, profile, statistics, server, learn, controls(NativeGameBindings.Context, String), credits
        var title: String {
            switch self {
            case .index: return "GAME MANAGEMENT"
            case .profile: return "LOCAL PROFILE"
            case .statistics: return "STATISTICS"
            case .server: return "SERVER INFORMATION"
            case .learn: return "LEARN TO PLAY"
            case .controls(_, let name): return name
            case .credits: return "CREDITS"
            }
        }
    }
    private let server: ServerAddress?
    private let page: Page
    private var client: NativeMenuProfileClient?
    private let column = UIStackView()
    private let message = UILabel()
    private let details = UILabel()
    private let nameField = UITextField()
    private var saveButton: UIButton?
    private var retryButton: UIButton?
    private var active = false

    convenience init(server: ServerAddress? = nil) {
        let saved = UserDefaults.standard.string(forKey: "serverAddress").flatMap(ServerAddress.init)
        self.init(server: server ?? saved, page: .index)
    }

    private init(server: ServerAddress?, page: Page) {
        self.server = server
        self.page = page
        super.init(title: page.title)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic menu") }

    override func viewDidLoad() {
        super.viewDidLoad()
        active = true
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scroll)
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            column.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        switch page {
        case .index: buildIndex()
        case .profile: buildProfile(); loadPage()
        case .statistics, .server: buildDataPage(); loadPage()
        case .learn: buildLearn()
        case .controls(let context, _): buildControls(context)
        case .credits: buildCredits()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        active = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        active = false
        client?.cancelPendingRequests()
        view.endEditing(true)
        super.viewWillDisappear(animated)
    }

    private func label(_ text: String, heading: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = .white
        label.font = heading ? menuFont(size: 23) : bodyFont(size: 17)
        return label
    }

    @discardableResult
    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let control = menuButton(title, action: action)
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        column.addArrangedSubview(control)
        return control
    }

    private func open(_ page: Page) {
        guard active, presentedViewController == nil else { return }
        let next = NativeGameManagementController(server: server, page: page)
        next.modalPresentationStyle = .fullScreen
        present(next, animated: !menuMotionReduced)
    }

    private func buildIndex() {
        column.addArrangedSubview(label(server?.display ?? "NO SERVER SELECTED"))
        for (title, page) in [("LOCAL PROFILE", Page.profile), ("STATISTICS", .statistics),
                              ("SERVER INFORMATION", .server), ("LEARN TO PLAY", .learn), ("CREDITS", .credits)] {
            button(title) { [weak self] in self?.open(page) }
        }
        column.addArrangedSubview(label("YOUR LOCAL PROFILE IS SAVED ON THE SELECTED SERVER. MULTIPLAYER CONNECTS TO THAT SAME PROFILE. DISCORD IS OPTIONAL."))
    }

    private func buildProfile() {
        column.addArrangedSubview(label("EDIT YOUR NAME ON THIS SERVER", heading: true))
        addMessage()
        column.addArrangedSubview(details)
        nameField.font = bodyFont(size: 20)
        nameField.textColor = .white
        nameField.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        nameField.layer.borderWidth = 1
        nameField.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        nameField.attributedPlaceholder = NSAttributedString(string: "PROFILE NAME", attributes: [.foregroundColor: UIColor.lightGray])
        nameField.autocorrectionType = .no
        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.accessibilityLabel = "Local profile name"
        let inset = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 48))
        nameField.leftView = inset
        nameField.leftViewMode = .always
        nameField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        nameField.isEnabled = false
        column.addArrangedSubview(nameField)
        registerMenuControl(nameField, activate: { [weak self] in self?.nameField.becomeFirstResponder() })
        saveButton = button("SAVE NAME") { [weak self] in self?.saveName() }
        saveButton?.isEnabled = false
        retryButton = button("RELOAD PROFILE") { [weak self] in self?.loadPage() }
        column.addArrangedSubview(label("YOUR EXISTING GUEST NAME, PROGRESS AND OWNED ASSETS BELONG TO THIS SERVER. RENAMING PRESERVES THEM. NAMES ARE LIMITED AND FORMATTED BY THE SERVER."))
    }

    private func addMessage() {
        message.font = bodyFont(size: 17)
        message.textColor = .white
        message.numberOfLines = 0
        message.accessibilityTraits.insert(.updatesFrequently)
        details.font = bodyFont(size: 18)
        details.textColor = .white
        details.numberOfLines = 0
        column.addArrangedSubview(message)
    }

    private func buildDataPage() {
        addMessage()
        column.addArrangedSubview(details)
        retryButton = button("REFRESH") { [weak self] in self?.loadPage() }
        if case .statistics = page {
            column.addArrangedSubview(label("SAVED PROGRESSION FROM YOUR SELF-HOSTED WORLD."))
        }
    }

    private func loadPage() {
        guard active else { return }
        guard let server else {
            message.text = "NO SERVER SELECTED. OPEN MULTIPLAYER TO SET UP YOUR MAC SERVER."
            retryButton?.isEnabled = false
            return
        }
        if client == nil { client = NativeMenuProfileClient(server: server) }
        setLoading("LOADING FROM \(server.display)…")
        switch page {
        case .profile:
            client?.loadProfile { [weak self] result in
                guard let self, self.active else { return }
                self.completeProfile(result)
            }
        case .statistics:
            client?.loadStatistics { [weak self] result in
                guard let self, self.active else { return }
                self.finishLoading()
                switch result {
                case .failure(let error): self.show(error)
                case .success(let statistics):
                    self.message.text = statistics.name.uppercased()
                    self.details.text = statistics.rows.map { "\($0.title):  \($0.value)" }.joined(separator: "\n\n")
                }
            }
        case .server:
            client?.loadServerInfo { [weak self] result in
                guard let self, self.active else { return }
                self.finishLoading()
                switch result {
                case .failure(let error): self.show(error)
                case .success(let info):
                    self.message.text = "ONLINE — \(server.display)"
                    self.details.text = "CONNECTED PLAYERS: \(info.players)\n\nACCOUNTS: LOCAL GUEST PROFILES\n\nDISCORD SIGN IN: \(info.discordLoginAvailable ? "AVAILABLE, OPTIONAL" : "NOT CONFIGURED")\n\nJOIN CODE: \(info.joinCodeRequired ? "ENABLED" : "NOT REQUIRED")\n\nLAN LISTENER: \(info.lanAccessible ? "ENABLED" : "DISABLED")\n\nSERVER FEATURES\n" + info.features.joined(separator: "\n")
                }
            }
        default: break
        }
    }

    private func setLoading(_ text: String) {
        message.text = text
        message.textColor = .white
        retryButton?.isEnabled = false
        saveButton?.isEnabled = false
        nameField.isEnabled = false
    }

    private func finishLoading() { retryButton?.isEnabled = true }

    private func show(_ error: NativeMenuProfileClient.Failure) {
        message.text = error.message
        message.textColor = UIColor(red: 1, green: 0.75, blue: 0.4, alpha: 1)
        // A failed refresh must not leave old counters labelled as current.
        details.text = nil
    }

    private func completeProfile(_ result: Result<NativeMenuProfileClient.Profile, NativeMenuProfileClient.Failure>) {
        finishLoading()
        switch result {
        case .failure(let error): show(error)
        case .success(let profile):
            message.text = "LOCAL PROFILE READY"
            message.textColor = .white
            details.text = "PLAYER \(profile.number) — \(profile.name)"
            nameField.text = profile.name
            nameField.isEnabled = true
            saveButton?.isEnabled = true
        }
    }

    private func saveName() {
        guard active, nameField.isEnabled, let client else { return }
        let proposed = nameField.text ?? ""
        view.endEditing(true)
        setLoading("SAVING NAME…")
        client.rename(proposed) { [weak self] result in
            guard let self, self.active else { return }
            self.completeProfile(result)
            if case .success = result { self.message.text = "NAME SAVED" }
            else { self.nameField.isEnabled = true; self.saveButton?.isEnabled = true }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func buildLearn() {
        column.addArrangedSubview(label("MOVE WITH THE LEFT TOUCH STICK. DRAG THE RIGHT LOOK AREA TO TURN THE CAMERA. BUTTONS CHANGE WITH YOUR CURRENT ACTION. A CONNECTED CONTROLLER OR KEYBOARD CAN ALSO PLAY."))
        var melee = NativeGameBindings.Context(); melee.melee = true
        let topics: [(String, NativeGameBindings.Context)] = [
            ("ON FOOT", .init()), ("MELEE", melee), ("CLIMBING", .init(mode: .climb)),
            ("SWIMMING", .init(mode: .swim)), ("JETPACK", .init(mode: .jetpack)),
            ("PARACHUTE", .init(mode: .parachute)), ("CARS", .init(mode: .vehicle("car"))),
            ("MOTORCYCLES", .init(mode: .vehicle("bike"))), ("BICYCLES", .init(mode: .vehicle("bicycle"))),
            ("BOATS", .init(mode: .vehicle("boat"))), ("PLANES", .init(mode: .vehicle("plane"))),
            ("HELICOPTERS", .init(mode: .vehicle("helicopter")))
        ]
        for (title, context) in topics { button(title) { [weak self] in self?.open(.controls(context, title)) } }
    }

    private func buildControls(_ context: NativeGameBindings.Context) {
        column.addArrangedSubview(label(NativeGameBindings.legend(context), heading: true))
        column.addArrangedSubview(label("PAD LABELS USE XBOX BUTTON NAMES. ANALOG TRIGGERS PROVIDE THE NATIVE AIM/FIRE AND GAS/BRAKE CONTROLS."))
        if context.mode == .foot {
            column.addArrangedSubview(label("R3 / KEYPAD 1: LOOK BEHIND\nV / HOME / PAD OPTIONS: CAMERA"))
        }
        if context.mode == .foot && !context.melee {
            column.addArrangedSubview(label("C: CROUCH — DELETE / CAPS: AIM\nR / PAD UP: RELOAD\nM: MAP — T: CHAT — J: JOBS\nG: ANIMATIONS — TAB: NEARBY ACTION"))
        }
        if context.melee { column.addArrangedSubview(label("GUARD AND BLOCK ARE AVAILABLE WHEN YOUR WEAPON'S FIGHTING STYLE SUPPORTS THEM.")) }
        column.addArrangedSubview(label("THIS HELP USES THE CURRENT NATIVE CONTROL BINDINGS. JOBS AND SERVER ACTIONS DEPEND ON YOUR HOSTED WORLD."))
    }

    private func buildCredits() {
        column.addArrangedSubview(label("ZGTA:SA", heading: true))
        column.addArrangedSubview(label("NATIVE SAN ANDREAS MULTIPLAYER CLIENT AND INDEPENDENT SELF-HOSTED SERVER.\n\nGRAND THEFT AUTO: SAN ANDREAS AND ITS ORIGINAL GAME CONTENT ARE BY ROCKSTAR GAMES. ZGTA:SA IS AN INDEPENDENT PROJECT.\n\nNATIVE PHYSICS USES RAPIER. SOURCE, DEPENDENCY DETAILS AND SELF-HOSTING INSTRUCTIONS ARE AVAILABLE BELOW.\n\nORIGINAL GAME FILES STAY IN YOUR LOCAL INSTALLATION."))
        button("PROJECT SOURCE & SELF-HOSTING") { [weak self] in self?.openLink("https://github.com/zemabinks/ZGTA-SA") }
        button("RAPIER PHYSICS") { [weak self] in self?.openLink("https://rapier.rs/") }
        button("COMMUNITY DISCORD — OPTIONAL") { [weak self] in self?.openLink("https://discord.gg/Cg39cguVUa") }
    }

    private func openLink(_ value: String) {
        guard active, let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }
}
