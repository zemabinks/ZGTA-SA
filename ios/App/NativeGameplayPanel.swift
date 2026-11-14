import UIKit

/// Native touch interface for the server's jobs and garage. All rewards and
/// mission checks remain authoritative on the Mac.
final class NativeGameplayPanel: UIViewController {
    var onAction: ((String, [String: Any]) -> Void)?
    private let stack = UIStackView()
    private var state: [String: Any] = [:]
    private var page = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        render()
    }

    func update(_ next: [String: Any]) {
        state = next
        if isViewLoaded { render() }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let header = UIStackView()
        header.axis = .horizontal
        header.distribution = .fillEqually
        header.spacing = 5
        for (index, name) in ["JOBS & MISSIONS", "MY VEHICLES", "BUY VEHICLES", "CLOSE"].enumerated() {
            let button = makeButton(name, light: index == page)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if index == 3 { self.dismiss(animated: true) }
                else { self.page = index; self.render() }
            }, for: .touchUpInside)
            header.addArrangedSubview(button)
        }
        stack.addArrangedSubview(header)
        let divider = UIView()
        divider.backgroundColor = UIColor(red: 0.18, green: 0.44, blue: 0.83, alpha: 1)
        divider.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(divider)
        let cash = (state["cash"] as? NSNumber)?.intValue ?? 0
        addText("\(state["name"] as? String ?? "LOCAL PLAYER")    $\(cash)    XP \((state["xp"] as? NSNumber)?.intValue ?? 0)", size: 18, bold: true)
        switch page {
        case 0: renderJobs()
        case 1: renderGarage()
        default: renderCatalog()
        }
    }

    private func renderJobs() {
        if let job = state["job"] as? [String: Any] {
            let name = (job["name"] as? String) ?? (job["id"] as? String) ?? "MISSION"
            let mode = job["mode"] as? String ?? "distance"
            let stage = job["stage"] as? String ?? ""
            let target = job["target"] as? [String: Any]
            addText("\(name.uppercased())  ·  \(stage.uppercased())", size: 22, bold: true)
            if let target {
                let x = (target["x"] as? NSNumber)?.intValue ?? 0
                let y = (target["y"] as? NSNumber)?.intValue ?? 0
                let remaining = (job["remaining"] as? NSNumber)?.intValue ?? 0
                addText("\(target["name"] as? String ?? "OBJECTIVE")  ·  \(remaining) m\nCoordinates \(x), \(y)")
            } else if let remaining = job["remaining"] as? NSNumber {
                addText("Travel \(remaining.intValue) m more to finish.")
            }
            let remaining = (job["remaining"] as? NSNumber)?.doubleValue ?? 1e9
            let radius = (job["radius"] as? NSNumber)?.doubleValue ?? 0
            let close = remaining <= radius
            let onFoot = state["onFoot"] as? Bool == true
            let driving = state["driving"] as? Bool == true
            let marked = (job["vehicleId"] as? String) == (state["drivingVehicle"] as? String)
            if mode == "route" {
                let id = job["id"] as? String ?? ""
                let needsCar = id != "courier"
                let ready = close && (!needsCar || driving) &&
                    (!["taxi", "trucker", "medic", "carthief"].contains(id) || marked)
                if stage == "pickup" { addAction("COLLECT / LOAD", "job.pickup", enabled: ready) }
                else { addAction("DELIVER / DROP OFF", "job.complete", enabled: ready) }
            } else if mode == "checkpoints" {
                let index = (job["index"] as? NSNumber)?.intValue ?? 0
                let total = (job["total"] as? NSNumber)?.intValue ?? 0
                addAction(index == total ? "FINISH ROUTE" : "PASS CHECKPOINT",
                          index == total ? "job.complete" : "job.checkpoint",
                          enabled: close && driving)
            } else if mode == "fire" {
                if stage == "respond" { addAction("ARRIVE AT FIRE", "job.respond", enabled: close && driving && marked) }
                else if stage == "extinguish" { addAction("EXTINGUISH", "job.extinguish", enabled: close) }
                else { addAction("RESCUE", "job.complete", enabled: close && onFoot) }
            } else if mode == "heist" {
                addAction(stage == "plan" ? "TAKE HEIST BAG" : "DELIVER HEIST BAG",
                          stage == "plan" ? "heist.rob" : "job.complete", enabled: close)
            } else {
                addAction("COMPLETE TASK", "job.complete", enabled: close || mode == "flight")
            }
            addAction("END MISSION", "job.cancel", enabled: !(job["id"] as? String == "taxi" && marked))
        } else {
            addText("CHOOSE A JOB", size: 22, bold: true)
            let jobs = ((state["catalog"] as? [String: Any])?["jobs"] as? [[String: Any]]) ?? []
            for job in jobs {
                guard let id = job["id"] as? String else { continue }
                let pay = (job["pay"] as? NSNumber)?.intValue ?? 0
                addAction("\((job["name"] as? String ?? id).uppercased())  ·  $\(pay)",
                          "job.start", payload: ["job": id], enabled: state["connected"] as? Bool == true)
            }
        }
    }

    private func renderGarage() {
        let cars = state["cars"] as? [[String: Any]] ?? []
        let slots = state["garage"] as? [[String: Any]] ?? []
        if cars.isEmpty { addText("NO VEHICLES OWNED YET") }
        for (slot, car) in cars.enumerated() {
            let garage = slot < slots.count ? slots[slot] : [:]
            let name = car["name"] as? String ?? "Vehicle \(slot + 1)"
            let active = garage["active"] as? Bool == true
            addText("\(name.uppercased())  ·  \(active ? "OUT" : "STORED")", size: 18, bold: true)
            addAction(active ? "RECALL / RESPAWN" : "SPAWN", "car.spawn", payload: ["slot": slot])
            if active {
                addAction("STORE", "car.store", payload: ["slot": slot])
                addAction("REPAIR", "car.repair", payload: ["slot": slot])
                addAction("RESPRAY", "car.respray", payload: ["slot": slot])
            }
        }
    }

    private func renderCatalog() {
        let cars = ((state["catalog"] as? [String: Any])?["cars"] as? [[String: Any]]) ?? []
        addText("VEHICLE DEALERSHIP  ·  \(cars.count) MODELS", size: 20, bold: true)
        let cash = (state["cash"] as? NSNumber)?.intValue ?? 0
        for car in cars {
            guard let model = car["model"] as? NSNumber else { continue }
            let price = (car["price"] as? NSNumber)?.intValue ?? 0
            let name = (car["name"] as? String ?? "Vehicle").uppercased()
            addAction("\(name)  ·  $\(price)", "car.buy",
                      payload: ["model": model.intValue], enabled: cash >= price)
        }
    }

    private func addText(_ text: String, size: CGFloat = 15, bold: Bool = false) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: size, weight: bold ? .black : .medium, width: .condensed)
        stack.addArrangedSubview(label)
    }

    private func addAction(_ title: String, _ action: String, payload: [String: Any] = [:], enabled: Bool = true) {
        let button = makeButton(title, light: enabled)
        button.isEnabled = enabled
        button.contentHorizontalAlignment = .left
        button.addAction(UIAction { [weak self] _ in self?.onAction?(action, payload) }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private func makeButton(_ title: String, light: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .black, width: .condensed)
        button.titleLabel?.numberOfLines = 1
        button.setTitleColor(light ? .black : .white, for: .normal)
        button.backgroundColor = light ? .white : UIColor.white.withAlphaComponent(0.13)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 39).isActive = true
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 10)
        return button
    }
}
