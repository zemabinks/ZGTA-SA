import UIKit
import simd

/// Displays the Mac server's authoritative inventory and archived shop offers.
/// Purchases and reloads are requests; this view never grants ammunition itself.
final class NativeWeaponShopPanel: UIViewController {
    var onAction: ((String, [String: Any]) -> Void)?
    var onNavigate: ((SIMD2<Float>) -> Void)?
    private var inventory: [String: Any] = [:]
    private var cash = 0
    private var onFoot = true
    private var packs = 1
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let titleLabel = NativeHUDTextLabel()
    private let closeButton = NativeHUDButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.94)
        titleLabel.text = "WEAPONS & AMMUNITION"
        titleLabel.menuFont = true; titleLabel.heavy = true
        titleLabel.textColor = .white; titleLabel.font = .systemFont(ofSize: 20)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        closeButton.setTitle("CLOSE", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
        view.addSubview(closeButton)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 85),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            scroll.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        render()
    }

    func update(_ inventory: [String: Any], cash: Int, onFoot: Bool = true) {
        self.inventory = inventory; self.cash = cash; self.onFoot = onFoot
        if isViewLoaded { render() }
    }

    private func render() {
        let offset = scroll.contentOffset
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        addText("CASH $\(cash)", bold: true)
        let selected = (inventory["selected"] as? NSNumber)?.intValue ?? 0
        let reloading = inventory["reload"] as? [String: Any]
        let owned = inventory["weapons"] as? [[String: Any]] ?? []
        addText("YOUR INVENTORY", bold: true)
        if owned.isEmpty { addText("FISTS") }
        for entry in owned {
            guard let id = (entry["id"] as? NSNumber)?.intValue else { continue }
            let name = (entry["name"] as? String ?? "WEAPON").uppercased()
            let loaded = (entry["clip"] as? NSNumber)?.intValue ?? 0
            let reserve = (entry["rest"] as? NSNumber)?.intValue ?? 0
            let ammo = id == 0 ? "" : " - \(loaded) LOADED / \(reserve) RESERVE"
            let fire = entry["fire"] as? String ?? ""
            let projectile = fire == "PROJECTILE" && [16, 17, 18, 35, 36, 39].contains(id)
            let area = fire == "AREA_EFFECT" && [37, 41, 42].contains(id)
            addAction("\(selected == id ? "SELECTED - " : "EQUIP - ")\(name)\(ammo)",
                      action: "weapon.select", payload: ["weapon": id],
                      enabled: selected != id && (id == 0 || fire == "INSTANT_HIT" || projectile || area))
        }
        if let current = owned.first(where: { ($0["id"] as? NSNumber)?.intValue == selected }), selected != 0 {
            let loaded = (current["clip"] as? NSNumber)?.intValue ?? 0
            let capacity = (current["capacity"] as? NSNumber)?.intValue ?? 0
            let reserve = (current["rest"] as? NSNumber)?.intValue ?? 0
            let remaining = (reloading?["remainingMs"] as? NSNumber)?.doubleValue ?? 0
            addAction(reloading == nil ? "RELOAD" : String(format: "RELOADING - %.1F S", remaining/1000),
                action: "weapon.reload", enabled: reloading == nil && loaded < capacity && reserve > 0)
        }
        addText("AMMU-NATION", bold: true)
        let nearest = inventory["nearestShop"] as? [String: Any]
        let within = nearest?["within"] as? Bool == true
        if let nearest {
            let name = nearest["name"] as? String ?? "Ammu-Nation"
            let distance = (nearest["distance"] as? NSNumber)?.doubleValue ?? 0
            addText("\(name.uppercased()) - \(Int(ceil(distance))) M")
            if let x = (nearest["x"] as? NSNumber)?.floatValue,
               let y = (nearest["y"] as? NSNumber)?.floatValue {
                let button = makeButton("MARK SHOP ON MAP", enabled: onNavigate != nil)
                button.addAction(UIAction { [weak self] _ in
                    self?.onNavigate?(SIMD2(x, y)); self?.dismiss(animated: true)
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        }
        if !within { addText("VISIT AN AMMU-NATION ENTRANCE OR COUNTER TO BUY.") }
        else if !onFoot { addText("LEAVE YOUR VEHICLE TO BUY.") }
        let quantityRow = UIStackView(); quantityRow.axis = .horizontal; quantityRow.spacing = 12
        let quantityLabel = NativeHUDTextLabel()
        quantityLabel.text = "AMMO PACKS: \(packs)"; quantityLabel.textColor = .white
        quantityLabel.font = .systemFont(ofSize: 15)
        quantityRow.addArrangedSubview(quantityLabel)
        let stepper = UIStepper(); stepper.minimumValue = 1; stepper.maximumValue = 20
        stepper.value = Double(packs); stepper.tintColor = .white
        stepper.addAction(UIAction { [weak self, weak stepper] _ in
            guard let self, let stepper else { return }
            self.packs = Int(stepper.value); self.render()
        }, for: .valueChanged)
        quantityRow.addArrangedSubview(stepper); stack.addArrangedSubview(quantityRow)
        let catalog = inventory["catalog"] as? [[String: Any]] ?? []
        for item in catalog {
            guard let id = (item["id"] as? NSNumber)?.intValue else { continue }
            let name = (item["name"] as? String ?? "ITEM").uppercased()
            let isArmour = item["fire"] as? String == "ARMOUR"
            let ownedAmmo = (item["totalAmmo"] as? NSNumber)?.intValue ?? 0
            let packSize = (item["ammo"] as? NSNumber)?.intValue ?? 1
            let count = isArmour ? 1 : min(packs, max(1, Int(ceil(Double(9999-ownedAmmo)/Double(max(1, packSize))))))
            let firstPrice = (item["nextPrice"] as? NSNumber)?.intValue ?? 0
            let refill = (item["refill"] as? NSNumber)?.intValue
            let basePrice = (item["price"] as? NSNumber)?.intValue ?? 0
            let total = firstPrice + max(0, count-1) * (refill ?? basePrice)
            let rounds = min(9999-ownedAmmo, packSize * count)
            let supported = item["nativeSupported"] as? Bool == true
            let full = ((item["totalAmmo"] as? NSNumber)?.intValue ?? 0) >= (isArmour ? 100 : 9999)
            addAction("BUY \(name) - $\(total)\(isArmour ? "" : " - \(rounds) ROUNDS")",
                action: "weapon.buy", payload: ["weapon": id, "packs": count],
                enabled: supported && within && onFoot && cash >= total && !full)
        }
        view.layoutIfNeeded()
        let maxOffset = max(0, scroll.contentSize.height-scroll.bounds.height)
        scroll.contentOffset = CGPoint(x: 0, y: max(0, min(offset.y, maxOffset)))
    }

    private func addText(_ text: String, bold: Bool = false) {
        let label = NativeHUDTextLabel(); label.text = text; label.numberOfLines = 0
        label.menuFont = bold; label.heavy = bold
        label.textColor = .white; label.font = .systemFont(ofSize: bold ? 18 : 14)
        stack.addArrangedSubview(label)
    }
    private func makeButton(_ title: String, enabled: Bool) -> NativeHUDButton {
        let button = NativeHUDButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title; configuration.baseForegroundColor = enabled ? .black : .white
        configuration.background.backgroundColor = enabled ? .white : UIColor.white.withAlphaComponent(0.12)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        button.configuration = configuration; button.isEnabled = enabled
        button.contentHorizontalAlignment = .left
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        return button
    }
    private func addAction(_ title: String, action: String, payload: [String: Any] = [:], enabled: Bool = true) {
        let button = makeButton(title, enabled: enabled)
        button.addAction(UIAction { [weak self] _ in self?.onAction?(action, payload) }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
    @objc private func closePanel() { dismiss(animated: true) }
}
