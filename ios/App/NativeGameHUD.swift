import UIKit
import simd

/// Browser-derived font advances and HUD textures are fetched from the Mac.
/// No extracted game image or font table is bundled in the native executable.
struct NativeHUDFontTable: Decodable {
    let widths: [Int]
    let fixed: Int
    let space: Int
}

final class NativeHUDResources {
    static let shared = NativeHUDResources()
    static let changed = Notification.Name("NativeHUDResourcesChanged")
    private(set) var font1: UIImage?
    private(set) var font2: UIImage?
    private(set) var table1: NativeHUDFontTable?
    private(set) var table2: NativeHUDFontTable?
    private(set) var sprites: [String: UIImage] = [:]
    private(set) var places: [NativeRadarMarker] = []
    private var loadedServer: String?
    private var glyphs: [String: UIImage] = [:]

    func load(server: ServerAddress) {
        guard loadedServer != server.display else { return }
        loadedServer = server.display
        font1 = nil; font2 = nil; table1 = nil; table2 = nil
        sprites.removeAll(); glyphs.removeAll(); places.removeAll()
        let group = DispatchGroup(), lock = NSLock()
        var files: [String: Data] = [:]
        for name in ["font1-white.png", "font2-white.png", "font-layout.json", "sprites.png", "sprites.json", "places.json"] {
            group.enter()
            URLSession.shared.dataTask(with: server.path("game/native/hud/\(name)")) { data, response, _ in
                if (response as? HTTPURLResponse)?.statusCode == 200, let data {
                    lock.lock(); files[name] = data; lock.unlock()
                }
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.loadedServer == server.display else { return }
            self.font1 = files["font1-white.png"].flatMap { UIImage(data: $0) }
            self.font2 = files["font2-white.png"].flatMap { UIImage(data: $0) }
            if let data = files["font-layout.json"],
               let document = try? JSONDecoder().decode(FontDocument.self, from: data) {
                self.table1 = document.font1; self.table2 = document.font2
            }
            if let data = files["sprites.json"],
               let document = try? JSONDecoder().decode(SpriteDocument.self, from: data),
               let image = files["sprites.png"].flatMap({ UIImage(data: $0) })?.cgImage {
                for (name, box) in document.rectangles where box.count == 4 {
                    if let crop = image.cropping(to: CGRect(x: box[0], y: box[1], width: box[2], height: box[3])) {
                        self.sprites[name] = UIImage(cgImage: crop)
                    }
                }
            }
            if let data = files["places.json"],
               let document = try? JSONDecoder().decode(PlaceDocument.self, from: data) {
                self.places = document.places.map { NativeRadarMarker(id: $0.id, name: $0.name,
                    position: SIMD2($0.x, $0.y), icon: $0.icon) }
            }
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }

    func glyph(_ index: Int, menu: Bool) -> UIImage? {
        let key = "\(menu ? 2 : 1)-\(index)"
        if let image = glyphs[key] { return image }
        guard let image = (menu ? font2 : font1)?.cgImage else { return nil }
        // The client's 32×40 logical cells are doubled in the 1024px atlas.
        let unit = CGFloat(image.width) / (16 * 32)
        let box = CGRect(x: CGFloat(index % 16 * 32) * unit,
                         y: CGFloat(index / 16 * 40 + 1) * unit,
                         width: 32 * unit, height: 38 * unit)
        guard box.maxY <= CGFloat(image.height), let crop = image.cropping(to: box) else { return nil }
        let glyph = UIImage(cgImage: crop)
        glyphs[key] = glyph
        return glyph
    }

    private struct FontDocument: Decodable {
        let font1: NativeHUDFontTable
        let font2: NativeHUDFontTable
    }
    private struct SpriteDocument: Decodable { let rectangles: [String: [Int]] }
    private struct PlaceDocument: Decodable { let places: [Place] }
    private struct Place: Decodable { let id: String; let name: String; let x: Float; let y: Float; let icon: String }
}

/// Draws with the archived browser's advance widths and alternate bold glyphs.
/// The old alpha-bounds approximation changed the shapes and spacing of digits.
final class NativeBitmapLabel: UIView {
    var text: String? { didSet {
        guard text != oldValue else { return }
        accessibilityLabel = text
        invalidateIntrinsicContentSize(); setNeedsDisplay()
    } }
    var textColor: UIColor = .white { didSet { setNeedsDisplay() } }
    var textAlignment: NSTextAlignment = .left { didSet { setNeedsDisplay() } }
    var font: UIFont = .systemFont(ofSize: 16) { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    var menuFont = false { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    var heavy = true { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    var fixed = false { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    var outline: CGFloat = 1.5 { didSet { setNeedsDisplay() } }
    // Kept for source compatibility with older callers; current builds load
    // the full layout through NativeHUDResources rather than guessed bounds.
    var atlas: UIImage? { didSet { setNeedsDisplay() } }
    var metrics: [String: [Int]]? { didSet { setNeedsDisplay() } }
    private var observer: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear
        isAccessibilityElement = true
        observer = NotificationCenter.default.addObserver(forName: NativeHUDResources.changed,
            object: nil, queue: .main) { [weak self] _ in
            self?.invalidateIntrinsicContentSize(); self?.setNeedsDisplay()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override var intrinsicContentSize: CGSize {
        let table = menuFont ? NativeHUDResources.shared.table2 : NativeHUDResources.shared.table1
        let width = Self.width(text ?? "", pointSize: font.pointSize, table: table,
                               heavy: heavy, fixed: fixed, menu: menuFont)
        return CGSize(width: ceil(width + outline * 2), height: ceil(font.pointSize + outline * 2))
    }

    override func draw(_ rect: CGRect) {
        Self.draw(text ?? "", in: rect, font: font, colour: textColor,
                  alignment: textAlignment, menu: menuFont, heavy: heavy,
                  fixed: fixed, outline: outline)
    }

    private static func glyphIndex(_ character: UInt32, heavy: Bool, menu: Bool) -> Int {
        let index = Int(character) - 32
        guard heavy else { return max(0, index) }
        if !menu && index == 4 { return 93 }
        if !menu && index == 26 { return 154 }
        if (16...25).contains(index) { return index + 128 }
        if (33...58).contains(index) { return index + 122 }
        if (65...90).contains(index) { return index + 90 }
        return max(0, index)
    }

    private static func ascii(_ text: String) -> String {
        text.replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "’", with: "'")
    }

    static func width(_ text: String, pointSize: CGFloat, table: NativeHUDFontTable?,
                      heavy: Bool, fixed: Bool, menu: Bool) -> CGFloat {
        guard let table else { return CGFloat(text.count) * pointSize * 0.55 }
        return ascii(text).unicodeScalars.reduce(CGFloat(0)) { result, character in
            let index = glyphIndex(character.value, heavy: heavy, menu: menu)
            guard table.widths.indices.contains(index) else { return result + pointSize * 0.65 }
            let advance = fixed ? table.fixed : table.widths[index]
            return result + CGFloat(advance) * pointSize / 40
        }
    }

    static func draw(_ text: String, in rect: CGRect, font: UIFont, colour: UIColor,
                     alignment: NSTextAlignment = .left, menu: Bool = false,
                     heavy: Bool = true, fixed: Bool = false, outline: CGFloat = 1.5) {
        let resources = NativeHUDResources.shared
        let table = menu ? resources.table2 : resources.table1
        guard let table, (menu ? resources.font2 : resources.font1) != nil else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
            (text as NSString).draw(in: rect, withAttributes: [.font: font,
                .foregroundColor: colour, .paragraphStyle: paragraph])
            return
        }
        let text = ascii(text)
        let total = width(text, pointSize: font.pointSize, table: table,
                          heavy: heavy, fixed: fixed, menu: menu)
        let fit = min(1, max(0, rect.width - 2 * outline) / max(1, total))
        let sx = font.pointSize / 40 * fit, sy = font.pointSize / 20 * fit
        let used = total * fit
        let x = alignment == .right ? rect.maxX - used - outline :
            alignment == .center ? rect.midX - used / 2 : rect.minX + outline
        let y = rect.midY - font.pointSize * fit / 2
        var cursor = x
        var painted: [(UIImage, CGRect)] = []
        var fallback: [(String, CGRect)] = []
        for character in text.unicodeScalars {
            let index = glyphIndex(character.value, heavy: heavy, menu: menu)
            guard table.widths.indices.contains(index) else {
                fallback.append((String(character), CGRect(x: cursor, y: y,
                    width: font.pointSize * 0.65 * fit, height: font.pointSize * 1.2 * fit)))
                cursor += font.pointSize * 0.65 * fit
                continue
            }
            let advance = fixed ? table.fixed : table.widths[index]
            let shift = fixed ? CGFloat(table.fixed - table.widths[index]) / 2 : 0
            defer { cursor += CGFloat(advance) * sx }
            guard character.value != 32, let glyph = resources.glyph(index, menu: menu) else { continue }
            painted.append((glyph, CGRect(x: cursor + shift * sx, y: y, width: 32 * sx, height: 20 * sy)))
        }
        // The browser outlines the composed word. Painting each glyph's black
        // edge immediately before its fill lets the next glyph's edge cover
        // the previous digit. Draw every edge first, then every foreground.
        if outline > 0 {
            for (glyph, box) in painted {
                let black = glyph.withTintColor(.black, renderingMode: .alwaysOriginal)
                for step in 0..<8 {
                    let angle = CGFloat(step) * .pi / 4
                    black.draw(in: box.offsetBy(dx: cos(angle) * outline, dy: sin(angle) * outline))
                }
            }
        }
        for (glyph, box) in painted {
            glyph.withTintColor(colour, renderingMode: .alwaysOriginal).draw(in: box)
        }
        for (character, box) in fallback {
            (character as NSString).draw(in: box, withAttributes: [
                .font: font.withSize(font.pointSize * fit), .foregroundColor: colour])
        }
    }
}

/// UILabel-compatible bitmap lettering for gameplay status and objective text.
/// Existing line wrapping, accessibility, and UIKit layout remain available.
class NativeHUDTextLabel: UILabel {
    var menuFont = false { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    var heavy = false { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    private var observer: NSObjectProtocol?
    private var lastWidth: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        observer = NotificationCenter.default.addObserver(forName: NativeHUDResources.changed,
            object: nil, queue: .main) { [weak self] _ in
            self?.invalidateIntrinsicContentSize(); self?.setNeedsDisplay()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func lines(width: CGFloat) -> [String] {
        guard let text else { return [] }
        let table = menuFont ? NativeHUDResources.shared.table2 : NativeHUDResources.shared.table1
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var line = ""
            for word in paragraph.components(separatedBy: " ") {
                let candidate = line.isEmpty ? word : line + " " + word
                if !line.isEmpty && NativeBitmapLabel.width(candidate, pointSize: font.pointSize,
                    table: table, heavy: heavy, fixed: false, menu: menuFont) > width - 4 {
                    result.append(line); line = word
                } else { line = candidate }
            }
            result.append(line)
        }
        return Array(result.prefix(numberOfLines == 0 ? Int.max : numberOfLines))
    }
    override var intrinsicContentSize: CGSize {
        guard NativeHUDResources.shared.table1 != nil else { return super.intrinsicContentSize }
        let table = menuFont ? NativeHUDResources.shared.table2 : NativeHUDResources.shared.table1
        let fullWidth = (text ?? "").components(separatedBy: "\n").map {
            NativeBitmapLabel.width($0, pointSize: font.pointSize, table: table,
                heavy: heavy, fixed: false, menu: menuFont) + 4
        }.max() ?? 0
        let available = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width > 0 ? bounds.width : fullWidth
        let count = lines(width: available).count
        return CGSize(width: ceil(fullWidth), height: ceil(CGFloat(count) * font.pointSize * 1.2) + 2)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width-lastWidth) > 0.5 {
            lastWidth = bounds.width; invalidateIntrinsicContentSize()
        }
    }
    override func drawText(in rect: CGRect) {
        guard NativeHUDResources.shared.table1 != nil else { super.drawText(in: rect); return }
        let visible = lines(width: rect.width), lineHeight = font.pointSize * 1.2
        let top = rect.midY - CGFloat(visible.count) * lineHeight / 2
        for (index, line) in visible.enumerated() {
            NativeBitmapLabel.draw(line, in: CGRect(x: rect.minX, y: top + CGFloat(index) * lineHeight,
                width: rect.width, height: lineHeight), font: font, colour: textColor,
                alignment: textAlignment, menu: menuFont, heavy: heavy, outline: 1)
        }
    }
}

/// Keeps UIButton actions, focus, and accessibility while its visible title
/// uses the same menu glyphs as the browser's native-style panels.
final class NativeHUDButton: UIButton {
    private let lettering = NativeHUDTextLabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        lettering.menuFont = true; lettering.heavy = true
        lettering.font = .systemFont(ofSize: 17)
        lettering.isUserInteractionEnabled = false
        lettering.isAccessibilityElement = false
        lettering.numberOfLines = 1
        addSubview(lettering)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel?.alpha = 0
        lettering.text = configuration?.title ?? currentTitle
        lettering.textColor = configuration?.baseForegroundColor ?? currentTitleColor
        lettering.alpha = isEnabled ? (isHighlighted ? 0.65 : 1) : 0.4
        lettering.textAlignment = contentHorizontalAlignment == .left ? .left : .center
        let insets = configuration?.contentInsets ?? NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        lettering.frame = bounds.inset(by: UIEdgeInsets(top: insets.top, left: insets.leading,
                                                       bottom: insets.bottom, right: insets.trailing))
        bringSubviewToFront(lettering)
    }
}

final class NativeHUDBar: UIView {
    var progress: Float = 1 { didSet { setNeedsDisplay() } }
    var colour: UIColor = .red { didSet { setNeedsDisplay() } }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ rect: CGRect) {
        UIColor.black.setFill(); UIRectFill(rect)
        let inner = rect.insetBy(dx: 2, dy: 2)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        UIColor(red: r / 2, green: g / 2, blue: b / 2, alpha: 1).setFill(); UIRectFill(inner)
        colour.setFill()
        UIRectFill(CGRect(x: inner.minX, y: inner.minY,
            width: inner.width * CGFloat(max(0, min(1, progress))), height: inner.height))
    }
}

/// The archived wanted routine draws six font2 `]` stars with an 18-unit
/// pitch, black inactive stars, and a two-second flash after a level change.
final class NativeWantedHUDView: UIView {
    var fontSize: CGFloat = 24 { didSet { setNeedsDisplay() } }
    var pitch: CGFloat = 18 { didSet { setNeedsDisplay() } }
    private(set) var level = 0
    private var changedAt = Date.distantPast
    private var flashTimer: Timer?
    private var observer: NSObjectProtocol?
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        observer = NotificationCenter.default.addObserver(forName: NativeHUDResources.changed,
            object: nil, queue: .main) { [weak self] _ in self?.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit { flashTimer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    func setLevel(_ value: Int) {
        let value = max(0, min(6, value))
        guard value != level else { return }
        level = value; changedAt = Date(); isHidden = value == 0
        accessibilityLabel = "Wanted level \(value)"
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.133, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.setNeedsDisplay()
            if Date().timeIntervalSince(self.changedAt) >= 2 { timer.invalidate() }
        }
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        let lit = Date().timeIntervalSince(changedAt) >= 2 || Int(Date().timeIntervalSince1970 / 0.133) % 2 == 0
        for index in 0..<6 {
            let active = index < level
            if active && !lit { continue }
            let box = CGRect(x: rect.maxX-CGFloat(index+1)*pitch, y: 0, width: pitch+3, height: rect.height)
            NativeBitmapLabel.draw("]", in: box, font: .systemFont(ofSize: fontSize),
                colour: active ? UIColor(red: 144/255, green: 98/255, blue: 16/255, alpha: 1) : .black,
                alignment: .right, menu: true, heavy: false, outline: active ? 1 : 0)
        }
    }
}

/// SA HUD layout and colours follow the archived MM/tz routines. Touch menu
/// controls remain outside this view and do not affect the HUD's lettering.
final class NativeGameHUD: UIView {
    let radar = NativeRadarView()
    let weaponIcon = UIImageView()
    let clock = NativeBitmapLabel()
    let cash = NativeBitmapLabel()
    let wanted = NativeWantedHUDView()
    let health = NativeHUDBar()
    let armour = NativeHUDBar()
    let breath = NativeHUDBar()
    let weapon = NativeBitmapLabel()
    let vehicle = NativeBitmapLabel()
    private let stats = UIView()
    private let aim = NativeAimHUDView()
    private var weaponRequestID = 0
    private var wantedLevel = 0
    private var currentCash: Int?
    private let cashChange = NativeBitmapLabel()
    private var cashChangeTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; backgroundColor = .clear
        radar.clipsToBounds = false
        addSubview(radar); addSubview(stats); addSubview(aim)
        for item in [weaponIcon, clock, cash, wanted, health, armour, breath, weapon, vehicle, cashChange] {
            stats.addSubview(item)
        }
        weaponIcon.contentMode = .scaleAspectFit
        clock.textColor = UIColor(white: 225 / 255, alpha: 1)
        clock.textAlignment = .right; clock.fixed = true
        cash.textColor = UIColor(red: 54 / 255, green: 104 / 255, blue: 44 / 255, alpha: 1)
        cash.textAlignment = .right; cash.fixed = true
        health.colour = UIColor(red: 180 / 255, green: 25 / 255, blue: 29 / 255, alpha: 1)
        armour.colour = UIColor(white: 225 / 255, alpha: 1)
        breath.colour = UIColor(red: 172 / 255, green: 203 / 255, blue: 241 / 255, alpha: 1)
        weapon.heavy = false; weapon.textAlignment = .center
        weapon.textColor = breath.colour
        vehicle.menuFont = true; vehicle.heavy = true; vehicle.textAlignment = .right
        vehicle.textColor = UIColor(red: 172 / 255, green: 203 / 255, blue: 241 / 255, alpha: 1)
        cashChange.textAlignment = .right; cashChange.isHidden = true
        aim.isHidden = true
        updateVitals(health: 100, armour: 0)
        updateBreath(nil)
        updateCash(0); updateWanted(0); updateWeapon(pistol: false, magazine: 0, reserve: 0); updateClock()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let windowSize = window?.bounds.size ?? UIScreen.main.bounds.size
        let x = max(0.8, min(windowSize.width / 640, windowSize.height / 480 * 4 / 3))
        let y = 480 * max(0.8, min(x, windowSize.height / 480)) / 448
        stats.frame = CGRect(x: bounds.maxX - 160 * x, y: 0, width: 160 * x, height: 164 * y)
        func box(_ x0: CGFloat, _ y0: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x0 * x, y: y0 * y, width: w * x, height: h * y)
        }
        weaponIcon.frame = box(17, 8, 47, 58)
        weapon.frame = box(10, 51, 62, 18); weapon.font = .systemFont(ofSize: 14 * y)
        clock.frame = box(58, 10, 72, 25); clock.font = .systemFont(ofSize: 22 * y)
        armour.frame = box(66, 36, 62, 9)
        breath.frame = box(66, 50, 62, 9)
        health.frame = box(19, 65, 109, 9)
        cash.frame = box(0, 77, 130, 26); cash.font = .systemFont(ofSize: 22 * y)
        cashChange.frame = box(0, 101, 130, 20); cashChange.font = .systemFont(ofSize: 18 * y)
        wanted.frame = box(12, 106, 118, 28); wanted.fontSize = 24 * y; wanted.pitch = 18 * x
        vehicle.frame = box(-35, 137, 165, 20); vehicle.font = .systemFont(ofSize: 18 * y)
        let radarSize: CGFloat = windowSize.height < 350 ? 96 : 122
        radar.frame = CGRect(x: 0, y: max(8, bounds.height - 196 - radarSize), width: radarSize, height: radarSize)
        // The parent HUD excludes its top controls. Centre the sight on the
        // actual game window, rather than the shortened HUD coordinate space.
        aim.frame = bounds
        if let window { aim.aimPoint = convert(CGPoint(x: window.bounds.midX, y: window.bounds.midY), from: window) }
    }

    func updateVitals(health life: Int, armour protection: Int) {
        health.progress = Float(max(0, min(100, life))) / 100
        armour.progress = Float(max(0, min(100, protection))) / 100
        armour.isHidden = protection <= 1
        health.accessibilityLabel = "Health \(life)"
        armour.accessibilityLabel = "Armour \(protection)"
    }
    func updateBreath(_ value: Int?) {
        breath.isHidden = value == nil || value! >= 100
        breath.progress = Float(max(0, min(100, value ?? 100))) / 100
        breath.accessibilityLabel = "Breath \(value ?? 100)"
    }
    func updateCash(_ amount: Int) {
        cash.text = amount < 0 ? String(format: "-$%07d", min(9_999_999, abs(amount))) :
            String(format: "$%08d", min(99_999_999, amount))
        if let previous = currentCash, previous != amount {
            let change = amount - previous
            cashChange.text = "\(change < 0 ? "-" : "+")$\(abs(change))"
            cashChange.textColor = change > 0 ? UIColor(red: 11 / 255, green: 191 / 255, blue: 8 / 255, alpha: 1) :
                UIColor(red: 191 / 255, green: 8 / 255, blue: 44 / 255, alpha: 1)
            cashChange.isHidden = false
            cashChangeTimer?.invalidate()
            cashChangeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.cashChange.isHidden = true }
        }
        currentCash = amount
    }
    func updateWanted(_ level: Int) {
        wantedLevel = max(0, min(6, level)); wanted.isHidden = wantedLevel == 0
        wanted.setLevel(wantedLevel)
    }
    func updateWeapon(pistol: Bool, magazine: Int, reserve: Int) {
        updateWeapon(id: pistol ? 22 : 0, name: pistol ? "COLT .45" : "FISTS", magazine: magazine, reserve: reserve)
    }
    func updateWeapon(id: Int, name: String, magazine: Int, reserve: Int) {
        weapon.isHidden = id < 22
        weapon.text = id < 22 ? nil : "\(reserve)-\(magazine)"
        weapon.accessibilityLabel = id < 22 ? name : "\(name), \(magazine) loaded, \(reserve) reserve"
    }
    func updateVehicle(name: String?, speed: Float) {
        vehicle.isHidden = name == nil
        vehicle.text = name.map { "\($0.uppercased())  \(Int(abs(speed) * 3.6)) KM/H" }
    }
    func updateClock(hour: Float = NativeWorldEnvironment.gameHour()) {
        let minutes = Int(hour * 60) % 1440
        clock.text = String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
    func loadWeaponIcon(server: ServerAddress, weapon id: Int) {
        weaponRequestID = id
        URLSession.shared.dataTask(with: server.path("reference/weapons/\(id).png")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { if self?.weaponRequestID == id { self?.weaponIcon.image = image } }
        }.resume()
    }
    func loadFont(server: ServerAddress) { NativeHUDResources.shared.load(server: server) }
    func setAiming(_ on: Bool, scoped: Bool = false) {
        aim.isHidden = !on; aim.scoped = scoped; aim.setNeedsDisplay()
    }
    func updateWorld(state: [String: Any]) {
        radar.updateWorld(state: state)
        if let breath = (state["breath"] as? NSNumber)?.intValue { updateBreath(breath) }
    }
}

private final class NativeAimHUDView: UIView {
    var scoped = false
    var aimPoint: CGPoint?
    private var observer: NSObjectProtocol?
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        observer = NotificationCenter.default.addObserver(forName: NativeHUDResources.changed,
            object: nil, queue: .main) { [weak self] _ in self?.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func draw(_ rect: CGRect) {
        let centre = aimPoint ?? CGPoint(x: rect.midX, y: rect.midY)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if scoped {
            let radius = min(rect.width, rect.height) * 0.47
            let hole = CGRect(x: centre.x-radius, y: centre.y-radius, width: radius*2, height: radius*2)
            let mask = UIBezierPath(rect: rect); mask.append(UIBezierPath(ovalIn: hole)); mask.usesEvenOddFillRule = true
            UIColor.black.setFill(); mask.fill()
            UIColor.black.setStroke()
            let cross = UIBezierPath(); cross.move(to: CGPoint(x: hole.minX, y: centre.y)); cross.addLine(to: CGPoint(x: hole.maxX, y: centre.y))
            cross.move(to: CGPoint(x: centre.x, y: hole.minY)); cross.addLine(to: CGPoint(x: centre.x, y: hole.maxY)); cross.lineWidth = 1; cross.stroke()
        }
        if let quarter = NativeHUDResources.shared.sprites["sitem16"] {
            let size: CGFloat = scoped ? 17 : 10
            for (sx, sy) in [(1 as CGFloat, 1 as CGFloat), (-1, 1), (1, -1), (-1, -1)] {
                context.saveGState(); context.translateBy(x: centre.x, y: centre.y); context.scaleBy(x: sx, y: sy)
                quarter.draw(in: CGRect(x: 0, y: 0, width: size, height: size)); context.restoreGState()
            }
        } else {
            let dot = UIBezierPath(ovalIn: CGRect(x: centre.x-2, y: centre.y-2, width: 4, height: 4))
            UIColor.white.setFill(); UIColor.black.setStroke(); dot.lineWidth = 1; dot.fill(); dot.stroke()
        }
    }
}

struct NativeRadarMarker {
    let id: String
    let name: String
    let position: SIMD2<Float>
    let icon: String
    var colour: UIColor = .white
}

final class NativeRadarView: UIView {
    var mapImage: UIImage? { didSet { setNeedsDisplay() } }
    var position = SIMD2<Float>(1480, -1738) { didSet { setNeedsDisplay() } }
    var playerPosition: SIMD2<Float>? { didSet { setNeedsDisplay() } }
    var heading: Float = 0 { didSet { setNeedsDisplay() } }
    var players: [SIMD2<Float>] = [] { didSet { setNeedsDisplay() } }
    var vehicles: [SIMD2<Float>] = [] { didSet { setNeedsDisplay() } }
    var target: SIMD2<Float>? { didSet { setNeedsDisplay() } }
    var waypoint: SIMD2<Float>? { didSet { setNeedsDisplay() } }
    var markers: [NativeRadarMarker] = [] { didSet { setNeedsDisplay() } }
    var span: CGFloat = 400 { didSet { setNeedsDisplay() } }
    var circular = true { didSet { setNeedsDisplay() } }
    var showWorldMarkers = true { didSet { setNeedsDisplay() } }
    private var observer: NSObjectProtocol?
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        observer = NotificationCenter.default.addObserver(forName: NativeHUDResources.changed,
            object: nil, queue: .main) { [weak self] _ in self?.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func loadMap(server: ServerAddress) {
        URLSession.shared.dataTask(with: server.path("tools/map/radar.webp")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.mapImage = image }
        }.resume()
    }
    func updateWorld(state: [String: Any]) {
        var result: [NativeRadarMarker] = NativeHUDResources.shared.places
        func add(_ item: [String: Any], id: String, icon: String, colour: UIColor = .white) {
            let point = (item["out"] as? [NSNumber]).flatMap { $0.count >= 2 ? SIMD2($0[0].floatValue, $0[1].floatValue) : nil } ?? {
                guard let x = (item["x"] as? NSNumber)?.floatValue, let y = (item["y"] as? NSNumber)?.floatValue else { return nil }
                return SIMD2(x, y)
            }()
            guard let point else { return }
            result.removeAll { $0.id == id }
            result.append(NativeRadarMarker(id: id, name: item["name"] as? String ?? id,
                position: point, icon: icon, colour: colour))
        }
        for item in state["homes"] as? [[String: Any]] ?? [] { add(item, id: "home-\(item["id"] ?? "")", icon: "radar_propertyowned", colour: .systemBlue) }
        if let item = state["dealer"] as? [String: Any] { add(item, id: "dealer", icon: "radar_modgarage") }
        if let item = state["hangar"] as? [String: Any] { add(item, id: "hangar", icon: "radar_airyard") }
        if let exploration = state["exploration"] as? [String: Any] {
            for item in exploration["items"] as? [[String: Any]] ?? [] where item["found"] as? Bool != true {
                add(item, id: "explore-\(item["id"] ?? "")", icon: "radar_qmark")
            }
        }
        let gangs = state["gangs"] as? [[String: Any]] ?? []
        for item in state["turfs"] as? [[String: Any]] ?? [] {
            let owner = item["owner"] as? String
            let gang = gangs.first { $0["id"] as? String == owner }
            let colour = (gang?["color"] as? String).flatMap(Self.colour(hex:)) ?? .white
            let icon = owner == "violet" ? "radar_gangp" : owner == "gold" ? "radar_gangy" : "radar_gangg"
            add(item, id: "turf-\(item["id"] ?? "")", icon: icon, colour: colour)
        }
        markers = result
    }
    private static func colour(hex: String) -> UIColor? {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat(value >> 16 & 255)/255, green: CGFloat(value >> 8 & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1)
    }
    func screen(_ world: SIMD2<Float>, in rect: CGRect) -> CGPoint {
        let scale = rect.width / span
        return CGPoint(x: rect.midX + CGFloat(world.x - position.x) * scale,
                       y: rect.midY - CGFloat(world.y - position.y) * scale)
    }
    func world(at point: CGPoint) -> SIMD2<Float> {
        let scale = max(0.0001, bounds.width / span)
        return SIMD2(position.x + Float((point.x - bounds.midX) / scale),
                     position.y - Float((point.y - bounds.midY) / scale))
    }
    private func clamped(_ point: CGPoint, in rect: CGRect, padding: CGFloat) -> CGPoint {
        guard circular else { return point }
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        let length = hypot(dx, dy), radius = min(rect.width, rect.height)/2 - padding
        guard length > radius else { return point }
        return CGPoint(x: rect.midX + dx / length * radius, y: rect.midY + dy / length * radius)
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let sprites = NativeHUDResources.shared.sprites
        let inner = circular ? rect.insetBy(dx: 4, dy: 4) : rect
        context.saveGState()
        (circular ? UIBezierPath(ovalIn: inner) : UIBezierPath(rect: inner)).addClip()
        UIColor(red: 0.43, green: 0.54, blue: 0.67, alpha: 1).setFill(); context.fill(inner)
        if let mapImage {
            let side = rect.width * 6000 / span
            let left = rect.midX - CGFloat(position.x + 3000) / 6000 * side
            let top = rect.midY - CGFloat(3000 - position.y) / 6000 * side
            mapImage.draw(in: CGRect(x: left, y: top, width: side, height: side))
        }
        if showWorldMarkers {
            for marker in markers {
                let point = screen(marker.position, in: rect)
                guard !circular || hypot(point.x-rect.midX, point.y-rect.midY) < rect.width/2-8 else { continue }
                if let icon = sprites[marker.icon] {
                    let size: CGFloat = circular ? 12 : 16
                    icon.draw(in: CGRect(x: point.x-size/2, y: point.y-size/2, width: size, height: size))
                } else { dot(point, color: marker.colour, radius: 3) }
            }
        }
        for point in vehicles { dot(screen(point, in: rect), color: .white, radius: circular ? 2 : 2.5) }
        for point in players { dot(screen(point, in: rect), color: .cyan, radius: circular ? 2.5 : 3.5) }
        if let target {
            let point = clamped(screen(target, in: rect), in: inner, padding: 7)
            if let icon = sprites["radar_flag"] {
                icon.draw(in: CGRect(x: point.x-7, y: point.y-7, width: 14, height: 14))
            } else { dot(point, color: .yellow, radius: 5) }
        }
        if let waypoint {
            let point = clamped(screen(waypoint, in: rect), in: inner, padding: 8)
            if let icon = sprites["radar_waypoint"] { icon.draw(in: CGRect(x: point.x-8, y: point.y-8, width: 16, height: 16)) }
            else { dot(point, color: .red, radius: 5) }
        }
        let own = screen(playerPosition ?? position, in: rect)
        context.saveGState(); context.translateBy(x: own.x, y: own.y); context.rotate(by: CGFloat(heading))
        if let image = sprites["radar_centre"] {
            image.draw(in: CGRect(x: -8, y: -8, width: 16, height: 16))
        } else {
            let marker = UIBezierPath(); marker.move(to: CGPoint(x: 0, y: -8)); marker.addLine(to: CGPoint(x: -6, y: 6)); marker.addLine(to: CGPoint(x: 6, y: 6)); marker.close()
            UIColor.white.setFill(); UIColor.black.setStroke(); marker.lineWidth = 1.5; marker.fill(); marker.stroke()
        }
        context.restoreGState(); context.restoreGState()
        if circular {
            if let rim = sprites["radar_rim"] { rim.draw(in: rect) }
            else { let rim = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)); UIColor.black.setStroke(); rim.lineWidth=4; rim.stroke() }
            if let north = sprites["radar_north"] { north.draw(in: CGRect(x: rect.midX-7, y: rect.minY-3, width: 14, height: 14)) }
        }
    }
    private func dot(_ point: CGPoint, color: UIColor, radius: CGFloat) {
        let marker = UIBezierPath(ovalIn: CGRect(x: point.x-radius, y: point.y-radius, width: radius*2, height: radius*2))
        UIColor.black.setStroke(); color.setFill(); marker.lineWidth=1; marker.fill(); marker.stroke()
    }
}
