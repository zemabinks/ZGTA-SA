import UIKit

/// A small native composer for the local world's shared chat. The server echoes
/// accepted messages back over WebSocket, so the history shows confirmed lines.
final class NativeChatPanel: UIViewController, UITextFieldDelegate {
    var onSend: ((String) -> Void)?
    private let history = UITextView()
    private let input = UITextField()
    private let card = UIView()
    private var lines: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        view.addSubview(card)

        let title = NativeHUDTextLabel()
        title.menuFont = true
        title.heavy = true
        title.text = "LOCAL CHAT"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .black, width: .condensed)
        title.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(title)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "Close chat"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeChat), for: .touchUpInside)
        card.addSubview(close)

        history.backgroundColor = .clear
        history.textColor = .white
        history.font = .systemFont(ofSize: 12, weight: .medium, width: .condensed)
        history.isEditable = false
        history.isSelectable = true
        history.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(history)

        input.placeholder = "Message or /command"
        input.attributedPlaceholder = NSAttributedString(string: "Message or /command",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.55)])
        input.textColor = .white
        input.font = .systemFont(ofSize: 15, weight: .medium)
        input.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        input.layer.cornerRadius = 8
        input.setLeftPadding(10)
        input.returnKeyType = .send
        input.autocorrectionType = .yes
        input.delegate = self
        input.accessibilityLabel = "Chat message"
        input.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(input)

        let send = UIButton(type: .system)
        send.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        send.tintColor = .white
        send.accessibilityLabel = "Send chat message"
        send.translatesAutoresizingMaskIntoConstraints = false
        send.addTarget(self, action: #selector(sendChat), for: .touchUpInside)
        card.addSubview(send)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            card.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            card.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 32),
            close.heightAnchor.constraint(equalTo: close.widthAnchor),
            history.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            history.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            history.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            history.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.19),
            input.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            input.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -8),
            input.topAnchor.constraint(equalTo: history.bottomAnchor, constant: 5),
            input.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            input.heightAnchor.constraint(equalToConstant: 42),
            send.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            send.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            send.widthAnchor.constraint(equalToConstant: 36),
            send.heightAnchor.constraint(equalTo: send.widthAnchor)
        ])
        update(lines)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        input.becomeFirstResponder()
    }

    func update(_ next: [String]) {
        lines = next
        guard isViewLoaded else { return }
        history.text = next.suffix(12).joined(separator: "\n")
        if !history.text.isEmpty {
            history.scrollRangeToVisible(NSRange(location: max(0, history.text.utf16.count - 1), length: 1))
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendChat()
        return true
    }

    @objc private func sendChat() {
        guard let text = input.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        onSend?(text)
        dismiss(animated: true)
    }

    @objc private func closeChat() { dismiss(animated: true) }
}

private extension UITextField {
    func setLeftPadding(_ width: CGFloat) {
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        leftView = padding
        leftViewMode = .always
    }
}
