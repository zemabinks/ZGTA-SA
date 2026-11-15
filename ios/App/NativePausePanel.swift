import UIKit
import GameController

/// Compact native in-game menu. The multiplayer world keeps running while
/// the presenting controller suppresses gameplay input behind this overlay.
final class NativePausePanel: UIViewController {
    var cameraName: (() -> String)?
    var onCamera: (() -> Void)?
    var onJobs: (() -> Void)?
    var onAnimations: (() -> Void)?
    var onRadio: (() -> Void)?
    var onFlightGear: (() -> Void)?
    var onLeave: (() -> Void)?
    var weatherName: (() -> String)?
    var onWeather: (() -> Void)?
    var driving = false
    var controlsHint:String?
    var escapeHandoff=NativeModalKeyHandoff()
    private var cameraButton: NativeHUDButton?
    private var weatherButton: NativeHUDButton?
    private var menuHandlers:[(GCControllerButtonInput,GCControllerButtonValueChangedHandler?)]=[]
    private var connectionObserver:NSObjectProtocol?
    override var canBecomeFirstResponder:Bool {true}
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated);becomeFirstResponder()
        installMenuHandlers()
        connectionObserver=NotificationCenter.default.addObserver(forName:.GCControllerDidConnect,object:nil,queue:.main) { [weak self] _ in self?.installMenuHandlers() }
    }
    override func viewDidDisappear(_ animated:Bool) {
        super.viewDidDisappear(animated)
        for (button,handler) in menuHandlers {button.pressedChangedHandler=handler}
        menuHandlers=[]
        if let connectionObserver {NotificationCenter.default.removeObserver(connectionObserver)}
        connectionObserver=nil
    }
    private func installMenuHandlers() {
        for controller in GCController.controllers() {
            guard let button=controller.extendedGamepad?.buttonMenu,!menuHandlers.contains(where:{$0.0===button}) else {continue}
            menuHandlers.append((button,button.pressedChangedHandler))
            var menuEdge=NativeReleaseEdge(pressed:button.isPressed)
            button.pressedChangedHandler = { [weak self] _,_,pressed in
                DispatchQueue.main.async {
                    if menuEdge.update(pressed:pressed) {self?.dismiss(animated:true)}
                }
            }
        }
    }
    override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        if presses.contains(where:{$0.key?.keyCode == .keyboardEscape}) {
            if escapeHandoff.press() {dismiss(animated:true)}
            return
        }
        super.pressesBegan(presses,with:event)
    }
    override func pressesEnded(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        if presses.contains(where:{$0.key?.keyCode == .keyboardEscape}) {escapeHandoff.release()}
        super.pressesEnded(presses,with:event)
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        let stack = UIStackView();stack.axis = .vertical;stack.spacing = 8
        let scroll=UIScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false;scroll.addSubview(stack)
        let preferred = scroll.widthAnchor.constraint(equalToConstant:520);preferred.priority = .defaultHigh
        let fittingHeight=scroll.heightAnchor.constraint(equalTo:stack.heightAnchor);fittingHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.centerXAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerXAnchor),
            scroll.centerYAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerYAnchor),
            preferred,scroll.widthAnchor.constraint(lessThanOrEqualTo:view.safeAreaLayoutGuide.widthAnchor,multiplier:0.78),
            scroll.heightAnchor.constraint(lessThanOrEqualTo:view.safeAreaLayoutGuide.heightAnchor,constant:-24),fittingHeight,
            stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor)
        ])
        let title = NativeHUDTextLabel();title.text = "ZGTA: SAN ANDREAS"
        title.menuFont = true;title.font = .systemFont(ofSize:26);title.textColor = .white;title.textAlignment = .center
        title.heightAnchor.constraint(equalToConstant:38).isActive = true;stack.addArrangedSubview(title)
        func button(_ name: String,_ action: @escaping () -> Void) -> NativeHUDButton {
            let result = NativeHUDButton(frame:.zero)
            result.setTitle(name,for:.normal);result.setTitleColor(.white,for:.normal)
            result.backgroundColor = UIColor.white.withAlphaComponent(0.09)
            result.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor;result.layer.borderWidth = 1
            result.heightAnchor.constraint(equalToConstant:38).isActive = true
            result.addAction(UIAction { _ in action() },for:.touchUpInside)
            stack.addArrangedSubview(result);return result
        }
        _ = button("RESUME") { [weak self] in self?.dismiss(animated:true) }
        _ = button("JOBS / GARAGE") { [weak self] in self?.dismiss(animated:true,completion:self?.onJobs) }
        _ = button("PROJECT SOURCE · AGPL") {
            if let url = URL(string:"https://github.com/zemabinks/ZGTA-SA") {
                UIApplication.shared.open(url)
            }
        }
        cameraButton = button("CAMERA: \(cameraName?().uppercased() ?? "MIDDLE")") { [weak self] in
            guard let self else { return };self.onCamera?()
            self.cameraButton?.setTitle("CAMERA: \(self.cameraName?().uppercased() ?? "MIDDLE")",for:.normal)
        }
        if driving { _ = button("NEXT RADIO STATION") { [weak self] in self?.onRadio?() } }
        else { _ = button("ANIMATIONS") { [weak self] in self?.dismiss(animated:true,completion:self?.onAnimations) } }
        if !driving {_ = button("FLIGHT EQUIPMENT") { [weak self] in self?.dismiss(animated:true,completion:self?.onFlightGear) }}
        weatherButton = button("WEATHER: \(weatherName?().uppercased() ?? "SERVER")") { [weak self] in
            guard let self else { return };self.onWeather?()
            self.weatherButton?.setTitle("WEATHER: \(self.weatherName?().uppercased() ?? "SERVER")",for:.normal)
        }
        _ = button("RETURN TO MAIN MENU") { [weak self] in self?.dismiss(animated:true,completion:self?.onLeave) }
        let hint = NativeHUDTextLabel();hint.text = controlsHint ?? NativeGameBindings.legend(.init(mode:driving ? .vehicle("car"):.foot))
        hint.numberOfLines=0
        hint.font = .systemFont(ofSize:13);hint.textColor = .white;hint.textAlignment = .center
        hint.heightAnchor.constraint(greaterThanOrEqualToConstant:60).isActive = true;stack.addArrangedSubview(hint)
    }
}
