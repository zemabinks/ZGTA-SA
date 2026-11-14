import UIKit
import simd

/// A local-only full city map using the same archived radar raster as the browser.
final class NativeCityMapViewController: UIViewController {
    private let map = NativeRadarView()
    private let location: SIMD2<Float>
    private let target: SIMD2<Float>?

    init(image: UIImage?, position: SIMD2<Float>, players: [SIMD2<Float>],
         vehicles: [SIMD2<Float>], target: SIMD2<Float>?) {
        location = position
        self.target = target
        super.init(nibName: nil, bundle: nil)
        map.mapImage = image
        map.position = .zero
        map.playerPosition = position
        map.players = players
        map.vehicles = vehicles
        map.target = target
        map.span = 6000
        map.circular = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.93)
        map.translatesAutoresizingMaskIntoConstraints = false
        map.layer.borderWidth = 3
        map.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        view.addSubview(map)
        let title = UILabel()
        title.text = "SAN ANDREAS"
        title.textColor = .white
        title.font = .systemFont(ofSize: 23, weight: .black, width: .condensed)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        let legend = UILabel()
        legend.text = target == nil ? "BLUE  YOU    ·    CYAN  PLAYERS    ·    WHITE  CARS" :
            "BLUE  YOU    ·    YELLOW  OBJECTIVE    ·    CYAN  PLAYERS"
        legend.textColor = .white
        legend.font = .systemFont(ofSize: 12, weight: .bold)
        legend.numberOfLines = 2
        legend.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(legend)
        let coordinates = UILabel()
        coordinates.text = String(format: "X %.0f   Y %.0f", location.x, location.y)
        coordinates.textColor = .lightGray
        coordinates.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        coordinates.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coordinates)
        let close = UIButton(type: .system)
        close.setTitle("CLOSE MAP", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .black)
        close.addTarget(self, action: #selector(closeMap), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            map.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            map.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            map.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, constant: -34),
            map.widthAnchor.constraint(equalTo: map.heightAnchor),
            title.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            legend.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            legend.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 13),
            legend.trailingAnchor.constraint(lessThanOrEqualTo: map.leadingAnchor, constant: -8),
            coordinates.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            coordinates.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 13),
            close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
    }

    @objc private func closeMap() { dismiss(animated: true) }
}
