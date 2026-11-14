import UIKit

enum Style {
    static let background = UIColor(red: 0.035, green: 0.055, blue: 0.10, alpha: 1)
    static let panel = UIColor(red: 0.075, green: 0.11, blue: 0.18, alpha: 1)
    static let cyan = UIColor(red: 0.32, green: 0.80, blue: 0.97, alpha: 1)
    static let text = UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)
    static let secondary = UIColor(red: 0.66, green: 0.74, blue: 0.85, alpha: 1)

    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = textColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private static var textColor: UIColor { text }

    static func button(_ title: String, symbol: String, filled: Bool) -> UIButton {
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 10
        config.cornerStyle = .large
        config.baseBackgroundColor = filled ? cyan : panel
        config.baseForegroundColor = filled ? background : text
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        let button = UIButton(configuration: config)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        return button
    }
}
