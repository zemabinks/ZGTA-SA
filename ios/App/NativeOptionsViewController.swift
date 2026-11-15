import UIKit

/// Every displayed option has a persisted value and a live native apply owner.
/// Keyboard/controller navigation uses the shared DE panel's focus handling.
final class NativeOptionsViewController: NativeDEPanelViewController {
    private let settings: NativeAppSettings
    private let column = UIStackView()
    private var refreshers: [() -> Void] = []
    private var settingsObserver: NSObjectProtocol?
    private var frameRateChoices: [Int] = []

    init(settings: NativeAppSettings = .shared) {
        self.settings = settings
        super.init(title: "OPTIONS")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = true
        contentView.addSubview(scroll)
        column.axis = .vertical; column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            column.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36)
        ])

        section("DISPLAY")
        slider("RESOLUTION SCALE", key: \.renderScale, range: 0.5...1, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
        let maximum = (view.window?.screen ?? UIScreen.main).maximumFramesPerSecond
        frameRateChoices = Array(Set([30, 60, 120, settings.snapshot.frameRate].map { min(max(1, maximum), $0) })).sorted()
        choice("FRAME RATE LIMIT", titles: frameRateChoices.map { "\($0) FPS" },
               selected: { [weak self] snapshot in
                   guard let self else { return 0 }
                   let cap = snapshot.effectiveFrameRate(maximum: maximum)
                   return self.frameRateChoices.firstIndex(of: cap) ?? self.frameRateChoices.indices.min(by: {
                       abs(self.frameRateChoices[$0] - cap) < abs(self.frameRateChoices[$1] - cap)
                   }) ?? 0
               }, change: { [weak self] index in
                   guard let self, self.frameRateChoices.indices.contains(index) else { return }
                   self.settings.update { $0.frameRate = self.frameRateChoices[index] }
               })

        section("CAMERA & CONTROLS")
        slider("CAMERA SENSITIVITY", key: \.cameraSensitivity, range: 0.25...3, step: 0.05) { String(format: "%.2f×", $0) }
        toggle("INVERT CAMERA Y", key: \.invertY)
        choice("ON-FOOT CAMERA", titles: ["NEAR", "MIDDLE", "FAR"],
               selected: { $0.footView - 1 }, change: { [weak self] index in self?.settings.update { $0.footView = index + 1 } })
        choice("VEHICLE CAMERA", titles: ["NEAR", "MID", "FAR", "EYE", "BUMPER", "CINEMA"],
               selected: { $0.vehicleView - 1 }, change: { [weak self] index in self?.settings.update { $0.vehicleView = index + 1 } })

        section("RADAR")
        toggle("SHOW RADAR", key: \.radarVisible)
        toggle("CIRCULAR RADAR", key: \.radarCircular)
        toggle("WORLD MARKERS", key: \.radarWorldMarkers)
        slider("RADAR RANGE", key: \.radarSpan, range: 200...1200, step: 50) { "\(Int($0.rounded())) M" }

        section("AUDIO")
        slider("MASTER VOLUME", key: \.masterVolume, range: 0...1, step: 0.05, format: Self.percent)
        slider("EFFECTS VOLUME", key: \.effectsVolume, range: 0...1, step: 0.05, format: Self.percent)
        slider("RADIO VOLUME", key: \.radioVolume, range: 0...1, step: 0.05, format: Self.percent)

        section("WORLD & ACCESSIBILITY")
        toggle("REGIONAL WEATHER", key: \.regionalWeather)
        toggle("REDUCE MENU MOTION", key: \.reduceMenuMotion)
        let motionNote = UILabel()
        motionNote.text = "Also respects iOS Reduce Motion."
        motionNote.font = bodyFont(size: 13); motionNote.textColor = UIColor.white.withAlphaComponent(0.75)
        motionNote.numberOfLines = 0; column.addArrangedSubview(motionNote)
        let reset = menuButton("RESTORE DEFAULTS") { [weak self] in self?.settings.reset() }
        reset.accessibilityHint = "Restore all options to the original native defaults"
        column.addArrangedSubview(reset)

        settingsObserver = NotificationCenter.default.addObserver(forName: NativeAppSettings.didChange,
            object: nil, queue: .main) { [weak self] note in
                guard let self, note.object as? NativeAppSettings === self.settings else { return }
                self.refreshValues()
            }
        refreshValues()
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func refreshValues() { refreshers.forEach { $0() } }

    private func section(_ title: String) {
        let label = UILabel()
        label.text = title; label.textColor = UIColor(red: 1, green: 0.84, blue: 0.22, alpha: 1)
        label.font = menuFont(size: 26)
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        column.addArrangedSubview(label)
    }

    private func caption(_ title: String, value: UILabel? = nil) -> UIStackView {
        let label = UILabel()
        label.text = title; label.textColor = .white; label.font = bodyFont(size: 17)
        label.numberOfLines = 0
        let line = UIStackView(arrangedSubviews: [label]); line.alignment = .center; line.spacing = 12
        if let value {
            value.font = bodyFont(size: 16); value.textColor = .white
            value.setContentHuggingPriority(.required, for: .horizontal)
            value.setContentCompressionResistancePriority(.required, for: .horizontal)
            line.addArrangedSubview(value)
        }
        return line
    }

    private func slider(_ title: String, key: WritableKeyPath<NativeAppSettings.Snapshot, Double>,
                        range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) {
        let value = UILabel(), control = UISlider()
        control.minimumValue = Float(range.lowerBound); control.maximumValue = Float(range.upperBound)
        control.minimumTrackTintColor = UIColor(red: 1, green: 0.84, blue: 0.22, alpha: 1)
        control.accessibilityLabel = title
        let row = UIStackView(arrangedSubviews: [caption(title, value: value), control])
        row.axis = .vertical; row.spacing = 1
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        column.addArrangedSubview(row)
        let commit: (Double) -> Void = { [weak self] proposed in
            let number = min(range.upperBound, max(range.lowerBound, (proposed / step).rounded() * step))
            self?.settings.update { $0[keyPath: key] = number }
        }
        control.addAction(UIAction { [weak control] _ in if let control { commit(Double(control.value)) } }, for: .valueChanged)
        registerMenuControl(control, adjust: { [weak self] direction in
            guard let self else { return }; commit(self.settings.snapshot[keyPath: key] + Double(direction) * step)
        })
        refreshers.append { [weak self, weak control, weak value] in
            guard let self, let control else { return }
            let current = self.settings.snapshot[keyPath: key]
            control.value = Float(current); value?.text = format(current)
            control.accessibilityValue = format(current)
        }
    }

    private func toggle(_ title: String, key: WritableKeyPath<NativeAppSettings.Snapshot, Bool>) {
        let control = UISwitch(), row = caption(title)
        control.accessibilityLabel = title
        control.onTintColor = UIColor(red: 0.64, green: 0.48, blue: 0.10, alpha: 1)
        row.addArrangedSubview(control); row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        column.addArrangedSubview(row)
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let control else { return }; self?.settings.update { $0[keyPath: key] = control.isOn }
        }, for: .valueChanged)
        registerMenuControl(control, adjust: { [weak self] direction in self?.settings.update { $0[keyPath: key] = direction > 0 } },
            activate: { [weak self] in self?.settings.update { $0[keyPath: key].toggle() } })
        refreshers.append { [weak self, weak control] in
            guard let self else { return }; control?.isOn = self.settings.snapshot[keyPath: key]
        }
    }

    private func choice(_ title: String, titles: [String], selected: @escaping (NativeAppSettings.Snapshot) -> Int,
                        change: @escaping (Int) -> Void) {
        let control = UISegmentedControl(items: titles)
        control.accessibilityLabel = title
        control.selectedSegmentTintColor = UIColor(red: 0.64, green: 0.48, blue: 0.10, alpha: 1)
        control.setTitleTextAttributes([.font: bodyFont(size: 13), .foregroundColor: UIColor.white], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let row = UIStackView(arrangedSubviews: [caption(title), control]); row.axis = .vertical; row.spacing = 6
        column.addArrangedSubview(row)
        control.addAction(UIAction { [weak control] _ in
            guard let control, control.selectedSegmentIndex >= 0 else { return }; change(control.selectedSegmentIndex)
        }, for: .valueChanged)
        registerMenuControl(control, adjust: { [weak control] direction in
            guard let control else { return }; change(min(titles.count - 1, max(0, control.selectedSegmentIndex + direction)))
        }, activate: { [weak control] in
            guard let control else { return }; change((control.selectedSegmentIndex + 1) % titles.count)
        })
        refreshers.append { [weak self, weak control] in
            guard let self, let control else { return }
            let index = min(titles.count - 1, max(0, selected(self.settings.snapshot)))
            control.selectedSegmentIndex = index; control.accessibilityValue = titles[index]
        }
    }
}
