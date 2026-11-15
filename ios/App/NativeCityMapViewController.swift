import UIKit
import simd

/// Native map navigation uses the archived radar raster and HUD sprites.
/// Waypoints are local navigation markers and do not replace mission targets.
final class NativeCityMapViewController: UIViewController {
    private let map = NativeRadarView()
    private let location: SIMD2<Float>
    private let target: SIMD2<Float>?
    private let titleLabel = NativeHUDTextLabel()
    private let legend = NativeHUDTextLabel()
    private let coordinates = NativeHUDTextLabel()
    private let selection = NativeHUDTextLabel()
    private let close = UIButton(type: .system)
    private let clear = UIButton(type: .system)
    private let centre = UIButton(type: .system)
    private let zoomIn = UIButton(type: .system)
    private let zoomOut = UIButton(type: .system)
    private var panStart = SIMD2<Float>.zero
    private var pinchStart: CGFloat = 6000
    private let onWaypoint: ((SIMD2<Float>?) -> Void)?

    init(image: UIImage?, position: SIMD2<Float>, players: [SIMD2<Float>],
         vehicles: [SIMD2<Float>], target: SIMD2<Float>?,
         markers: [NativeRadarMarker] = [], heading: Float = 0,
         waypoint: SIMD2<Float>? = nil, onWaypoint: ((SIMD2<Float>?) -> Void)? = nil) {
        location = position
        self.target = target
        self.onWaypoint = onWaypoint
        super.init(nibName: nil, bundle: nil)
        map.mapImage = image
        map.position = .zero
        map.playerPosition = position
        map.players = players; map.vehicles = vehicles; map.target = target
        map.markers = markers; map.heading = heading; map.waypoint = waypoint
        map.span = 6000; map.circular = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.96)
        map.layer.borderWidth = 2; map.layer.borderColor = UIColor.black.cgColor
        map.isUserInteractionEnabled = true
        view.addSubview(map)
        titleLabel.text = "SAN ANDREAS"
        titleLabel.menuFont = true; titleLabel.heavy = true
        titleLabel.textColor = UIColor(white: 225/255, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 24)
        titleLabel.numberOfLines = 2
        view.addSubview(titleLabel)
        legend.text = "DRAG TO MOVE\nPINCH TO ZOOM\nTAP FOR WAYPOINT"
        legend.textColor = .white; legend.font = .systemFont(ofSize: 12)
        legend.numberOfLines = 0
        view.addSubview(legend)
        coordinates.text = String(format: "X %.0f\nY %.0f", location.x, location.y)
        coordinates.textColor = .lightGray; coordinates.font = .systemFont(ofSize: 13)
        coordinates.numberOfLines = 2
        view.addSubview(coordinates)
        selection.font = .systemFont(ofSize: 13); selection.textColor = .white
        selection.numberOfLines = 4
        selection.text = target == nil ? "WHITE - YOU\nCYAN - PLAYERS" : "FLAG - OBJECTIVE\nWHITE - YOU"
        view.addSubview(selection)
        configure(close, title: "CLOSE MAP", action: #selector(closeMap))
        configure(clear, title: "CLEAR WAYPOINT", action: #selector(clearWaypoint))
        configure(centre, title: "FIND PLAYER", action: #selector(findPlayer))
        configure(zoomIn, title: "+", action: #selector(increaseZoom))
        configure(zoomOut, title: "-", action: #selector(decreaseZoom))
        close.accessibilityLabel = "Close city map"
        zoomIn.accessibilityLabel = "Zoom map in"; zoomOut.accessibilityLabel = "Zoom map out"
        map.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panMap(_:))))
        map.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchMap(_:))))
        map.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapMap(_:))))
        map.accessibilityLabel = "San Andreas city map"
        map.accessibilityHint = "Drag to move, pinch to zoom, tap to place a waypoint"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        let side = max(100, min(safe.height - 20, safe.width - 190))
        map.frame = CGRect(x: safe.midX - side/2 + 30, y: safe.midY-side/2, width: side, height: side)
        let left = safe.minX + 10
        let width = max(90, min(150, map.frame.minX-left-10))
        titleLabel.frame = CGRect(x: left, y: safe.minY+10, width: width, height: 55)
        legend.frame = CGRect(x: left, y: titleLabel.frame.maxY+8, width: width, height: 55)
        coordinates.frame = CGRect(x: left, y: legend.frame.maxY+8, width: width, height: 35)
        selection.frame = CGRect(x: left, y: coordinates.frame.maxY+10, width: width, height: 70)
        close.frame = CGRect(x: safe.maxX-130, y: safe.minY+6, width: 125, height: 35)
        let controlsX = min(safe.maxX-130, map.frame.maxX+12)
        centre.frame = CGRect(x: controlsX, y: safe.midY-28, width: 125, height: 36)
        clear.frame = CGRect(x: controlsX, y: safe.midY+12, width: 125, height: 36)
        zoomIn.frame = CGRect(x: controlsX, y: safe.maxY-52, width: 48, height: 42)
        zoomOut.frame = CGRect(x: controlsX+55, y: safe.maxY-52, width: 48, height: 42)
    }

    private func configure(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal); button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 26 : 12, weight: .bold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        button.layer.cornerRadius = 6
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)
    }
    private func clampCentre() {
        let half = Float(map.span/2)
        map.position = SIMD2(max(-3000+half, min(3000-half, map.position.x)),
                             max(-3000+half, min(3000-half, map.position.y)))
    }
    @objc private func panMap(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { panStart = map.position }
        let shift = gesture.translation(in: map), scale = Float(map.span / max(1, map.bounds.width))
        map.position = panStart + SIMD2(-Float(shift.x)*scale, Float(shift.y)*scale)
        clampCentre()
    }
    @objc private func pinchMap(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { pinchStart = map.span }
        map.span = max(250, min(6000, pinchStart/max(0.01, gesture.scale)))
        clampCentre()
    }
    @objc private func tapMap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: map)
        var world = map.world(at: point)
        world = SIMD2(max(-3000, min(3000, world.x)), max(-3000, min(3000, world.y)))
        let nearest = map.markers.min { lhs, rhs in
            let a = map.screen(lhs.position, in: map.bounds), b = map.screen(rhs.position, in: map.bounds)
            return hypot(a.x-point.x, a.y-point.y) < hypot(b.x-point.x, b.y-point.y)
        }
        if let nearest {
            let marker = map.screen(nearest.position, in: map.bounds)
            if hypot(marker.x-point.x, marker.y-point.y) <= 18 {
                world = nearest.position; selection.text = nearest.name.uppercased()
            } else { selection.text = "WAYPOINT" }
        } else { selection.text = "WAYPOINT" }
        map.waypoint = world; onWaypoint?(world)
        coordinates.text = String(format: "X %.0f\nY %.0f", world.x, world.y)
    }
    @objc private func clearWaypoint() {
        map.waypoint = nil; onWaypoint?(nil); selection.text = "WAYPOINT CLEARED"
    }
    @objc private func findPlayer() {
        map.span = 1200; map.position = location; clampCentre()
    }
    @objc private func increaseZoom() { map.span = max(250, map.span/1.5); clampCentre() }
    @objc private func decreaseZoom() { map.span = min(6000, map.span*1.5); clampCentre() }
    @objc private func closeMap() { dismiss(animated: true) }
}
