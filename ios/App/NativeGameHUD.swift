import UIKit
import simd

/// In-world information, drawn by UIKit over the Metal game view. The map image
/// is fetched from the self-hosted archive and never bundled into the app.
final class NativeGameHUD: UIView {
    let radar = NativeRadarView()
    let weaponIcon = UIImageView()
    let clock = NativeBitmapLabel()
    let cash = NativeBitmapLabel()
    let wanted = UILabel()
    let health = UIProgressView(progressViewStyle: .default)
    let armour = UIProgressView(progressViewStyle: .default)
    let weapon = NativeBitmapLabel()
    let vehicle = UILabel()
    private let radarCaption = UILabel()
    private let stats = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        radar.translatesAutoresizingMaskIntoConstraints = false
        radar.layer.borderWidth = 3
        radar.layer.borderColor = UIColor.black.cgColor
        radar.layer.cornerRadius = 61
        radar.clipsToBounds = true
        addSubview(radar)
        radarCaption.text = "N"
        radarCaption.font = .systemFont(ofSize: 13, weight: .black)
        radarCaption.textColor = .white
        radarCaption.layer.shadowColor = UIColor.black.cgColor
        radarCaption.layer.shadowOpacity = 1
        radarCaption.layer.shadowRadius = 2
        radarCaption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radarCaption)
        stats.backgroundColor = .clear
        stats.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stats)
        for item in [weaponIcon, clock, cash, wanted, health, armour, weapon, vehicle] {
            item.translatesAutoresizingMaskIntoConstraints = false
            stats.addSubview(item)
        }
        weaponIcon.contentMode = .scaleAspectFit
        weaponIcon.tintColor = .white
        clock.font = .monospacedDigitSystemFont(ofSize: 22, weight: .black)
        clock.textColor = .white
        clock.textAlignment = .right
        cash.font = .monospacedDigitSystemFont(ofSize: 20, weight: .black)
        cash.textColor = UIColor(red: 0.42, green: 0.82, blue: 0.34, alpha: 1)
        cash.textAlignment = .right
        wanted.font = .systemFont(ofSize: 15, weight: .black)
        wanted.textColor = UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1)
        wanted.textAlignment = .right
        wanted.layer.shadowColor = UIColor.black.cgColor
        wanted.layer.shadowOpacity = 1
        wanted.layer.shadowRadius = 2
        health.progressTintColor = UIColor(red: 0.9, green: 0.13, blue: 0.13, alpha: 1)
        health.trackTintColor = UIColor.black.withAlphaComponent(0.8)
        armour.progressTintColor = UIColor(red: 0.68, green: 0.83, blue: 0.95, alpha: 1)
        armour.trackTintColor = UIColor.black.withAlphaComponent(0.8)
        weapon.font = .systemFont(ofSize: 11, weight: .bold)
        weapon.textColor = .white
        weapon.textAlignment = .right
        vehicle.font = .systemFont(ofSize: 12, weight: .black)
        vehicle.textColor = .white
        vehicle.textAlignment = .right
        vehicle.isHidden = true
        NSLayoutConstraint.activate([
            radar.leadingAnchor.constraint(equalTo: leadingAnchor),
            radar.topAnchor.constraint(equalTo: topAnchor, constant: 68),
            radar.widthAnchor.constraint(equalToConstant: 122),
            radar.heightAnchor.constraint(equalTo: radar.widthAnchor),
            radarCaption.trailingAnchor.constraint(equalTo: radar.trailingAnchor, constant: -8),
            radarCaption.bottomAnchor.constraint(equalTo: radar.bottomAnchor, constant: -6),
            stats.trailingAnchor.constraint(equalTo: trailingAnchor),
            stats.topAnchor.constraint(equalTo: topAnchor),
            stats.widthAnchor.constraint(equalToConstant: 210),
            stats.heightAnchor.constraint(equalToConstant: 145),
            weaponIcon.leadingAnchor.constraint(equalTo: stats.leadingAnchor, constant: 7),
            weaponIcon.topAnchor.constraint(equalTo: stats.topAnchor, constant: 7),
            weaponIcon.widthAnchor.constraint(equalToConstant: 53),
            weaponIcon.heightAnchor.constraint(equalToConstant: 44),
            clock.trailingAnchor.constraint(equalTo: stats.trailingAnchor, constant: -8),
            clock.topAnchor.constraint(equalTo: stats.topAnchor, constant: 4),
            cash.trailingAnchor.constraint(equalTo: stats.trailingAnchor, constant: -8),
            cash.topAnchor.constraint(equalTo: clock.bottomAnchor, constant: 1),
            wanted.trailingAnchor.constraint(equalTo: stats.trailingAnchor, constant: -8),
            wanted.topAnchor.constraint(equalTo: cash.bottomAnchor),
            health.leadingAnchor.constraint(equalTo: stats.leadingAnchor, constant: 7),
            health.trailingAnchor.constraint(equalTo: stats.trailingAnchor, constant: -8),
            health.topAnchor.constraint(equalTo: wanted.bottomAnchor, constant: 4),
            armour.leadingAnchor.constraint(equalTo: health.leadingAnchor),
            armour.trailingAnchor.constraint(equalTo: health.trailingAnchor),
            armour.topAnchor.constraint(equalTo: health.bottomAnchor, constant: 5),
            weapon.trailingAnchor.constraint(equalTo: stats.trailingAnchor, constant: -8),
            weapon.topAnchor.constraint(equalTo: armour.bottomAnchor, constant: 4),
            vehicle.trailingAnchor.constraint(equalTo: stats.trailingAnchor, constant: -8),
            vehicle.topAnchor.constraint(equalTo: weapon.bottomAnchor)
        ])
        updateVitals(health: 100, armour: 0)
        updateCash(0)
        updateWanted(0)
        updateWeapon(pistol: false, magazine: 0, reserve: 0)
        updateClock()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func updateVitals(health life: Int, armour protection: Int) {
        health.progress = Float(max(0, min(100, life))) / 100
        armour.progress = Float(max(0, min(100, protection))) / 100
        self.armour.isHidden = protection == 0
        health.accessibilityLabel = "Health \(life)"
        armour.accessibilityLabel = "Armour \(protection)"
    }

    func updateCash(_ amount: Int) {
        cash.text = String(format: "$%08d", max(0, amount))
    }

    func updateWanted(_ level: Int) {
        wanted.isHidden = level == 0
        wanted.text = String(repeating: "★", count: max(0, min(6, level))) +
            String(repeating: "☆", count: max(0, 6 - min(6, level)))
    }

    func updateWeapon(pistol: Bool, magazine: Int, reserve: Int) {
        weapon.text = pistol ? "COLT .45  \(magazine) / \(reserve)" : "FISTS"
    }

    func updateVehicle(name: String?, speed: Float) {
        vehicle.isHidden = name == nil
        vehicle.text = name.map { "\($0.uppercased())  ·  \(Int(abs(speed) * 3.6)) KM/H" }
    }

    func updateClock() {
        let calendar = Calendar.current
        let now = Date()
        clock.text = String(format: "%02d:%02d", calendar.component(.hour, from: now),
                            calendar.component(.minute, from: now))
    }

    func loadWeaponIcon(server: ServerAddress, weapon id: Int) {
        URLSession.shared.dataTask(with: server.path("reference/weapons/\(id).png")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.weaponIcon.image = image }
        }.resume()
    }

    func loadFont(server: ServerAddress) {
        URLSession.shared.dataTask(with: server.path("game/native/hud/font-white.png")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.clock.atlas = image
                self?.weapon.atlas = image
            }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/hud/font-green.png")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.cash.atlas = image }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/hud/font-metrics.json")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let metrics = try? JSONSerialization.jsonObject(with: data) as? [String: [Int]] else { return }
            DispatchQueue.main.async {
                self?.clock.metrics = metrics
                self?.cash.metrics = metrics
                self?.weapon.metrics = metrics
            }
        }.resume()
    }
}

/// GTA:SA's archived font atlas has ASCII glyphs in a 16×16 grid. The bitmap
/// stays on the Mac; only the visible glyphs are drawn by native Core Graphics.
final class NativeBitmapLabel: UIView {
    var text: String? { didSet {
        guard text != oldValue else { return }
        accessibilityLabel = text
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    } }
    var textColor: UIColor = .white { didSet { setNeedsDisplay() } }
    var textAlignment: NSTextAlignment = .left { didSet { setNeedsDisplay() } }
    var font: UIFont = .systemFont(ofSize: 16) { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    var atlas: UIImage? { didSet { setNeedsDisplay() } }
    var metrics: [String: [Int]]? { didSet { setNeedsDisplay() } }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(text?.utf8.count ?? 0) * font.pointSize * 0.68,
               height: font.pointSize * 1.25)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let text, !text.isEmpty else { return }
        guard let cgImage = atlas?.cgImage, let metrics,
              cgImage.width >= 1024,
              cgImage.height >= 1024 else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = textAlignment
            (text as NSString).draw(in: rect, withAttributes: [
                .font: font, .foregroundColor: textColor, .paragraphStyle: paragraph
            ])
            return
        }
        let glyphScale = font.pointSize / 43
        let total = text.utf8.reduce(CGFloat(0)) { width, character in
            width + CGFloat(metrics[String(character)]?.last ?? 15) * glyphScale
        }
        let scale = min(1, rect.width / max(1, total))
        let usedWidth = total * scale
        let startX = textAlignment == .right ? rect.maxX - usedWidth :
            textAlignment == .center ? rect.midX - usedWidth / 2 : rect.minX
        let y = rect.midY - font.pointSize * scale / 2
        let current = UIGraphicsGetCurrentContext()
        current?.saveGState()
        current?.setShadow(offset: CGSize(width: 1.5, height: 1.5), blur: 1.5,
                           color: UIColor.black.cgColor)
        var cursor = startX
        for character in text.utf8 {
            guard character >= 32, character <= 127,
                  let dimensions = metrics[String(character)], dimensions.count == 5 else { continue }
            let glyph = Int(character - 32)
            defer { cursor += CGFloat(dimensions[4]) * glyphScale * scale }
            guard dimensions[2] > 0, dimensions[3] > 0 else { continue }
            let source = CGRect(x: glyph % 16 * 64 + dimensions[0],
                                y: glyph / 16 * 80 + dimensions[1],
                                width: dimensions[2], height: dimensions[3])
            guard let cropped = cgImage.cropping(to: source) else { continue }
            UIImage(cgImage: cropped).draw(in: CGRect(
                x: cursor, y: y + CGFloat(dimensions[1] - 18) * glyphScale * scale,
                width: CGFloat(dimensions[2]) * glyphScale * scale,
                height: CGFloat(dimensions[3]) * glyphScale * scale))
        }
        current?.restoreGState()
    }
}

final class NativeRadarView: UIView {
    var mapImage: UIImage? { didSet { setNeedsDisplay() } }
    var position = SIMD2<Float>(1480, -1738) { didSet { setNeedsDisplay() } }
    var playerPosition: SIMD2<Float>? { didSet { setNeedsDisplay() } }
    var heading: Float = 0 { didSet { setNeedsDisplay() } }
    var players: [SIMD2<Float>] = [] { didSet { setNeedsDisplay() } }
    var vehicles: [SIMD2<Float>] = [] { didSet { setNeedsDisplay() } }
    var target: SIMD2<Float>? { didSet { setNeedsDisplay() } }
    /// Width of the world represented by the radar viewport, in game units.
    var span: CGFloat = 400 { didSet { setNeedsDisplay() } }
    var circular = true { didSet { setNeedsDisplay() } }

    func loadMap(server: ServerAddress) {
        URLSession.shared.dataTask(with: server.path("tools/map/radar.webp")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.mapImage = image }
        }.resume()
    }

    private func screen(_ world: SIMD2<Float>, in rect: CGRect) -> CGPoint {
        let scale = rect.width / span
        return CGPoint(x: rect.midX + CGFloat(world.x - position.x) * scale,
                       y: rect.midY - CGFloat(world.y - position.y) * scale)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        (circular ? UIBezierPath(ovalIn: rect) : UIBezierPath(rect: rect)).addClip()
        UIColor(red: 0.17, green: 0.25, blue: 0.32, alpha: 1).setFill()
        context.fill(rect)
        if let mapImage {
            let side = rect.width * 6000 / span
            let left = rect.midX - CGFloat(position.x + 3000) / 6000 * side
            let top = rect.midY - CGFloat(3000 - position.y) / 6000 * side
            mapImage.draw(in: CGRect(x: left, y: top, width: side, height: side))
        }
        if let target, let playerPosition {
            let route = UIBezierPath()
            route.move(to: screen(playerPosition, in: rect))
            route.addLine(to: screen(target, in: rect))
            route.setLineDash([4, 3], count: 2, phase: 0)
            route.lineWidth = 2
            UIColor.yellow.withAlphaComponent(0.8).setStroke()
            route.stroke()
        }
        for point in vehicles { dot(screen(point, in: rect), color: .white, radius: 2.5) }
        for point in players { dot(screen(point, in: rect), color: .cyan, radius: 3.5) }
        if let target {
            let point = screen(target, in: rect)
            dot(point, color: .yellow, radius: 5)
        }
        context.restoreGState()
        let marker = UIBezierPath()
        marker.move(to: CGPoint(x: 0, y: -10))
        marker.addLine(to: CGPoint(x: -7, y: 7))
        marker.addLine(to: CGPoint(x: 0, y: 3))
        marker.addLine(to: CGPoint(x: 7, y: 7))
        marker.close()
        context.saveGState()
        let ownPoint = screen(playerPosition ?? position, in: rect)
        context.translateBy(x: ownPoint.x, y: ownPoint.y)
        context.rotate(by: CGFloat(heading))
        UIColor.black.setStroke()
        UIColor(red: 0.22, green: 0.53, blue: 1, alpha: 1).setFill()
        marker.lineWidth = 2
        marker.fill()
        marker.stroke()
        context.restoreGState()
    }

    private func dot(_ point: CGPoint, color: UIColor, radius: CGFloat) {
        let marker = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                 width: radius * 2, height: radius * 2))
        UIColor.black.setStroke()
        color.setFill()
        marker.lineWidth = 1.5
        marker.fill()
        marker.stroke()
    }
}
