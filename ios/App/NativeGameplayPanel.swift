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
        let changed = !NSDictionary(dictionary: state).isEqual(NSDictionary(dictionary: next))
        state = next
        // State arrives every few seconds. Rebuilding a focused text field would
        // discard a group message or cash amount before the player can send it.
        if changed && isViewLoaded && !isEditingText { render() }
    }

    private var isEditingText: Bool {
        stack.arrangedSubviews.contains { view in
            (view as? UIStackView)?.arrangedSubviews.contains { $0 is UITextField && $0.isFirstResponder } == true
        }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let header = UIStackView()
        header.axis = .horizontal
        header.distribution = .fillEqually
        header.spacing = 5
        for (index, name) in ["JOBS", "GARAGE", "VEHICLES", "WORLD", "SOCIAL", "CLOSE"].enumerated() {
            let button = makeButton(name, light: index == page)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if index == 5 { self.dismiss(animated: true) }
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
        case 2: renderCatalog()
        case 3: renderWorld()
        default: renderSocial()
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
        let cash = (state["cash"] as? NSNumber)?.intValue ?? 0
        if cars.isEmpty { addText("NO VEHICLES OWNED YET") }
        for (slot, car) in cars.enumerated() {
            let garage = slot < slots.count ? slots[slot] : [:]
            let name = car["name"] as? String ?? "Vehicle \(slot + 1)"
            let active = garage["active"] as? Bool == true
            addText("\(name.uppercased())  ·  \(active ? "OUT" : "STORED")", size: 18, bold: true)
            addAction(active ? "RECALL / RESPAWN" : "SPAWN", "car.spawn", payload: ["slot": slot])
            if active {
                let near = state["onFoot"] as? Bool == true &&
                    ((garage["distance"] as? NSNumber)?.doubleValue ?? .infinity) <= 18
                addAction("STORE", "car.store", payload: ["slot": slot], enabled: near)
                if let parking = state["homeParking"] as? [String: Any],
                   parking["within"] as? Bool == true {
                    addAction("PARK AT \(parking["name"] as? String ?? "HOME")", "car.parkhome",
                              payload: ["slot": slot], enabled: near)
                }
                let repair = (garage["repairCost"] as? NSNumber)?.intValue ?? 0
                if repair > 0 { addAction("REPAIR  ·  $\(repair)", "car.repair",
                                          payload: ["slot": slot], enabled: near && cash >= repair) }
                let respray = (garage["resprayCost"] as? NSNumber)?.intValue ?? 0
                addAction("RESPRAY  ·  $\(respray)", "car.respray",
                          payload: ["slot": slot], enabled: near && cash >= respray)
            }
        }
        addText("WORKSHOP SUPPLIES", size: 20, bold: true)
        let supplies = ((state["catalog"] as? [String: Any])?["supplies"] as? [[String: Any]]) ?? []
        let inventory = state["supplies"] as? [String: Any] ?? [:]
        let dealer = state["dealer"] as? [String: Any] ?? [:]
        for supply in supplies {
            guard let id = supply["id"] as? String else { continue }
            let name = supply["name"] as? String ?? id
            let count = (inventory[id] as? NSNumber)?.intValue ?? 0
            let capacity = (supply["capacity"] as? NSNumber)?.intValue ?? 0
            let price = (supply["price"] as? NSNumber)?.intValue ?? 0
            addAction("BUY \(name.uppercased())  ·  \(count)/\(capacity)  ·  $\(price)",
                      "supply.buy", payload: ["item": id],
                      enabled: dealer["within"] as? Bool == true && state["onFoot"] as? Bool == true &&
                        cash >= price && count < capacity)
            if count > 0 {
                for (slot, car) in cars.enumerated() where slot < slots.count &&
                    slots[slot]["active"] as? Bool == true {
                    let near = state["onFoot"] as? Bool == true &&
                        ((slots[slot]["distance"] as? NSNumber)?.doubleValue ?? .infinity) <= 18
                    addAction("USE \(name.uppercased()) ON \((car["name"] as? String ?? "CAR").uppercased())",
                              "supply.use", payload: ["item": id, "slot": slot], enabled: near)
                }
            }
        }
    }

    private func renderCatalog() {
        let cars = ((state["catalog"] as? [String: Any])?["cars"] as? [[String: Any]]) ?? []
        addText("VEHICLE DEALERSHIP  ·  \(cars.count) MODELS", size: 20, bold: true)
        let cash = (state["cash"] as? NSNumber)?.intValue ?? 0
        let dealer = state["dealer"] as? [String: Any] ?? [:]
        let hangar = state["hangar"] as? [String: Any] ?? [:]
        for car in cars {
            guard let model = car["model"] as? NSNumber else { continue }
            guard let price = (car["price"] as? NSNumber)?.intValue else { continue }
            let name = (car["name"] as? String ?? "Vehicle").uppercased()
            let source = car["source"] as? String ?? "starter"
            let aircraft = ["plane", "helicopter"].contains(car["type"] as? String ?? "")
            let allowed: Bool
            if source == "starter" { allowed = true }
            else if aircraft {
                allowed = hangar["within"] as? Bool == true &&
                    (car["airports"] as? [String] ?? []).contains(hangar["id"] as? String ?? "")
            } else {
                allowed = dealer["within"] as? Bool == true &&
                    (car["dealers"] as? [String] ?? []).contains(dealer["id"] as? String ?? "")
            }
            addAction("\(name)  ·  $\(price)", "car.buy",
                      payload: ["model": model.intValue], enabled: cash >= price && allowed)
        }
    }

    private func renderWorld() {
        let connected = state["connected"] as? Bool == true
        let onFoot = state["onFoot"] as? Bool == true
        let cash = (state["cash"] as? NSNumber)?.intValue ?? 0
        addText("MULTIPLAYER RACE", size: 20, bold: true)
        if let race = state["race"] as? [String: Any],
           let stage = race["stage"] as? String, stage != "finished" {
            addText("\(race["host"] as? String ?? "LOCAL")  ·  \(stage.uppercased())")
            let joined = race["joined"] as? Bool == true
            if stage == "lobby" {
                let near = ((race["startDistance"] as? NSNumber)?.doubleValue ?? .infinity) <= 25
                if !joined { addAction("JOIN RACE", "race.join", enabled: connected && near && state["job"] is NSNull) }
                else {
                    let host = race["isHost"] as? Bool == true
                    let players = race["players"] as? [[String: Any]] ?? []
                    if host { addAction("START RACE", "race.start", enabled: near && players.count >= 2) }
                    addAction(host ? "CANCEL RACE" : "LEAVE RACE", "race.leave")
                }
            } else if joined {
                if let target = race["target"] as? [String: Any] {
                    addText("\(target["name"] as? String ?? "CHECKPOINT")  ·  \((race["remaining"] as? NSNumber)?.intValue ?? 0) M")
                    let index = (race["index"] as? NSNumber)?.intValue ?? 0
                    let total = (race["total"] as? NSNumber)?.intValue ?? 0
                    let near = ((race["remaining"] as? NSNumber)?.doubleValue ?? .infinity) <=
                        ((race["radius"] as? NSNumber)?.doubleValue ?? 0)
                    addAction(index == total ? "FINISH RACE" : "PASS CHECKPOINT",
                              index == total ? "race.finish" : "race.checkpoint", enabled: near)
                }
                addAction("LEAVE RACE", "race.leave")
            }
        } else { addAction("CREATE A THREE CHECKPOINT RACE", "race.create", enabled: connected &&
                           (state["job"] == nil || state["job"] is NSNull)) }

        addText("SAFETY & POLICE", size: 20, bold: true)
        let passive = state["passive"] as? Bool == true
        let police = state["policeDuty"] as? Bool == true
        let wanted = (state["wanted"] as? NSNumber)?.intValue ?? 0
        addAction(passive ? "TURN OFF PASSIVE MODE" : "TURN ON PASSIVE MODE",
                  "safety.passive", enabled: connected && (passive || (!police && wanted == 0)))
        addAction(police ? "END POLICE DUTY" : "START POLICE DUTY", "police.duty",
                  enabled: connected && (police || (!passive && wanted == 0)))
        if police {
            for suspect in state["nearbyWanted"] as? [[String: Any]] ?? [] {
                guard let number = suspect["number"] as? NSNumber else { continue }
                let near = ((suspect["distance"] as? NSNumber)?.doubleValue ?? .infinity) <= 4
                addAction("ARREST \((suspect["name"] as? String ?? "PLAYER").uppercased())",
                          "police.arrest", payload: ["number": number.intValue], enabled: near && onFoot)
            }
        }

        addText("CREWS & TERRITORY", size: 20, bold: true)
        let myGang = state["gang"] as? String
        let switchWait = (state["gangSwitchWait"] as? NSNumber)?.intValue ?? 0
        for gang in state["gangs"] as? [[String: Any]] ?? [] {
            guard let id = gang["id"] as? String else { continue }
            addAction("JOIN \((gang["name"] as? String ?? id).uppercased())", "gang.join",
                      payload: ["gang": id], enabled: myGang != id && switchWait == 0)
        }
        for turf in state["turfs"] as? [[String: Any]] ?? [] {
            guard let id = turf["id"] as? String else { continue }
            let ownCapture = turf["capturingYou"] as? Bool == true
            let near = ((turf["distance"] as? NSNumber)?.doubleValue ?? .infinity) <= 20
            addAction("\((turf["name"] as? String ?? id).uppercased())  ·  \((turf["distance"] as? NSNumber)?.intValue ?? 0) M",
                      ownCapture ? "turf.leave" : "turf.start",
                      payload: ownCapture ? [:] : ["turf": id],
                      enabled: ownCapture || (myGang != nil && onFoot && !passive && near &&
                        (state["job"] == nil || state["job"] is NSNull) &&
                        turf["capturing"] is NSNull))
        }

        addText("EXPLORATION", size: 20, bold: true)
        if let exploration = state["exploration"] as? [String: Any] {
            addText("\((exploration["found"] as? NSNumber)?.intValue ?? 0) / \((exploration["total"] as? NSNumber)?.intValue ?? 0) DISCOVERED")
            let tracked = (exploration["tracked"] as? [String: Any])?["id"] as? String
            for place in exploration["items"] as? [[String: Any]] ?? [] {
                guard let id = place["id"] as? String,
                      place["found"] as? Bool != true else { continue }
                let distance = (place["distance"] as? NSNumber)?.doubleValue ?? .infinity
                let claim = connected && onFoot && distance <= 12
                let label = (place["name"] as? String ?? id).uppercased()
                addAction("\(label)  ·  \(Int(distance.isFinite ? distance : 0)) M",
                          claim ? "explore.claim" : "explore.track",
                          payload: claim ? ["id": id] : ["id": tracked == id ? NSNull() : id])
            }
        }

        addText("HOMES", size: 20, bold: true)
        let owned = Set((state["homes"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        for home in ((state["catalog"] as? [String: Any])?["homes"] as? [[String: Any]]) ?? [] {
            guard let id = home["id"] as? String,
                  let price = (home["price"] as? NSNumber)?.intValue else { continue }
            let name = (home["name"] as? String ?? id).uppercased()
            addAction("\(name)  ·  \(owned.contains(id) ? "OWNED" : "$\(price)")",
                      owned.contains(id) ? "home.visit" : "home.buy",
                      payload: ["home": id], enabled: owned.contains(id) ? connected : cash >= price)
        }
    }

    private func renderSocial() {
        let party = state["party"] as? [String: Any] ?? [:]
        addText("PRIVATE GROUP", size: 20, bold: true)
        if let invite = party["invite"] as? [String: Any] {
            addText("\(invite["from"] as? String ?? "PLAYER") INVITED YOU")
            addAction("ACCEPT INVITE", "party.accept")
            addAction("DECLINE INVITE", "party.decline")
        }
        let group = party["group"] as? [String: Any]
        if let group {
            addText("\(group["leader"] as? String ?? "LOCAL")'S GROUP")
            let isLeader = group["isLeader"] as? Bool == true
            let you = (party["you"] as? NSNumber)?.intValue ?? -1
            for member in group["members"] as? [[String: Any]] ?? [] {
                guard let number = (member["number"] as? NSNumber)?.intValue else { continue }
                if isLeader && number != you {
                    addAction("REMOVE \((member["name"] as? String ?? "PLAYER").uppercased())",
                              "party.kick", payload: ["number": number])
                } else { addText(member["name"] as? String ?? "PLAYER") }
            }
            addInputAction("MESSAGE YOUR GROUP", "SEND", "party.chat", key: "text")
            addAction("LEAVE GROUP", "party.leave")
        } else { addAction("CREATE GROUP", "party.create") }
        if group == nil || group?["isLeader"] as? Bool == true {
            for candidate in party["candidates"] as? [[String: Any]] ?? [] {
                guard let number = (candidate["number"] as? NSNumber)?.intValue else { continue }
                addAction("INVITE \((candidate["name"] as? String ?? "PLAYER").uppercased())",
                          "party.invite", payload: ["number": number])
            }
        }

        addText("NEARBY PLAYERS", size: 20, bold: true)
        for other in state["nearbyPlayers"] as? [[String: Any]] ?? [] {
            guard let number = (other["number"] as? NSNumber)?.intValue else { continue }
            let distance = (other["distance"] as? NSNumber)?.doubleValue ?? .infinity
            addInputAction("GIVE CASH TO \((other["name"] as? String ?? "PLAYER").uppercased())  ·  \(Int(distance.isFinite ? distance : 0)) M",
                           "GIVE", "money.transfer", key: "amount", extra: ["number": number],
                           numeric: true, enabled: distance <= 8)
        }
        addText("LOCAL LEADERBOARD", size: 20, bold: true)
        for entry in state["leaderboard"] as? [[String: Any]] ?? [] {
            addText("#\((entry["place"] as? NSNumber)?.intValue ?? 0)  \(entry["name"] as? String ?? "PLAYER")  ·  \((entry["xp"] as? NSNumber)?.intValue ?? 0) XP")
        }
    }

    private func addInputAction(_ placeholder: String, _ title: String, _ action: String,
                                key: String, extra: [String: Any] = [:], numeric: Bool = false,
                                enabled: Bool = true) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        let input = UITextField()
        input.placeholder = placeholder
        input.attributedPlaceholder = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.6)])
        input.text = numeric ? "50" : ""
        input.textColor = .white
        input.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        input.font = .systemFont(ofSize: 15)
        input.keyboardType = numeric ? .numberPad : .default
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        row.addArrangedSubview(input)
        let button = makeButton(title, light: enabled)
        button.isEnabled = enabled
        button.widthAnchor.constraint(equalToConstant: 82).isActive = true
        button.addAction(UIAction { [weak self, weak input] _ in
            guard let self, let value = input?.text, !value.isEmpty else { return }
            var payload = extra
            if numeric {
                guard let amount = Int(value), amount > 0 else { return }
                payload[key] = amount
            }
            else { payload[key] = value }
            self.view.endEditing(true)
            self.onAction?(action, payload)
        }, for: .touchUpInside)
        row.addArrangedSubview(button)
        stack.addArrangedSubview(row)
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
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = light ? .black : .white
        configuration.background.backgroundColor = light ? .white : UIColor.white.withAlphaComponent(0.13)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 10)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 17, weight: .black, width: .condensed)
            return attributes
        }
        button.configuration = configuration
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 39).isActive = true
        return button
    }
}
