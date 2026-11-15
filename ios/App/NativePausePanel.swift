import UIKit

/// Compact native in-game menu. The multiplayer world keeps running while
/// the presenting controller suppresses gameplay input behind this overlay.
final class NativePausePanel: UIViewController {
    var cameraName: (() -> String)?
    var onCamera: (() -> Void)?
    var onAnimations: (() -> Void)?
    var onRadio: (() -> Void)?
    var onLeave: (() -> Void)?
    var weatherName: (() -> String)?
    var onWeather: (() -> Void)?
    var driving = false
    private var cameraButton: NativeHUDButton?
    private var weatherButton: NativeHUDButton?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        let stack = UIStackView();stack.axis = .vertical;stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(stack)
        let preferred = stack.widthAnchor.constraint(equalToConstant:520);preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerYAnchor),
            preferred,stack.widthAnchor.constraint(lessThanOrEqualTo:view.safeAreaLayoutGuide.widthAnchor,multiplier:0.78)
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
        cameraButton = button("CAMERA: \(cameraName?().uppercased() ?? "MIDDLE")") { [weak self] in
            guard let self else { return };self.onCamera?()
            self.cameraButton?.setTitle("CAMERA: \(self.cameraName?().uppercased() ?? "MIDDLE")",for:.normal)
        }
        if driving { _ = button("NEXT RADIO STATION") { [weak self] in self?.onRadio?() } }
        else { _ = button("ANIMATIONS") { [weak self] in self?.dismiss(animated:true,completion:self?.onAnimations) } }
        weatherButton = button("WEATHER: \(weatherName?().uppercased() ?? "SERVER")") { [weak self] in
            guard let self else { return };self.onWeather?()
            self.weatherButton?.setTitle("WEATHER: \(self.weatherName?().uppercased() ?? "SERVER")",for:.normal)
        }
        _ = button("RETURN TO MAIN MENU") { [weak self] in self?.dismiss(animated:true,completion:self?.onLeave) }
        let hint = NativeHUDTextLabel();hint.text = "V: CAMERA VIEW    WASD: MOVE    ARROWS: LOOK"
        hint.font = .systemFont(ofSize:13);hint.textColor = .white;hint.textAlignment = .center
        hint.heightAnchor.constraint(equalToConstant:22).isActive = true;stack.addArrangedSubview(hint)
    }
}
