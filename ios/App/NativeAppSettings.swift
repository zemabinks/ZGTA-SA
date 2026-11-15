import Foundation
import CoreGraphics

/// Player preferences only. No simulation, server authority or control bindings
/// are changed by this store. The normalized audio defaults preserve Core82's
/// existing 0.7 effects gain and 0.6 radio gain.
final class NativeAppSettings {
    struct Snapshot: Codable, Equatable {
        var renderScale: Double = 1
        var frameRate: Int = 60
        var cameraSensitivity: Double = 1
        var invertY = false
        var footView: Int = 2
        var vehicleView: Int = 2
        var radarVisible = true
        var radarCircular = true
        var radarSpan: Double = 400
        var radarWorldMarkers = true
        var regionalWeather = false
        var reduceMenuMotion = false
        var masterVolume: Double = 1
        var effectsVolume: Double = 1
        var radioVolume: Double = 1

        var effectiveEffectsGain: Float {
            let value = validated()
            return Float(0.7 * value.masterVolume * value.effectsVolume)
        }
        var effectiveRadioGain: Float {
            let value = validated()
            return Float(0.6 * value.masterVolume * value.radioVolume)
        }

        func validated() -> Snapshot {
            var value = self
            func bounded(_ number: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
                number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback
            }
            value.renderScale = bounded(renderScale, 0.5...1, fallback: 1)
            value.frameRate = min(120, max(30, frameRate))
            value.cameraSensitivity = bounded(cameraSensitivity, 0.25...3, fallback: 1)
            value.footView = min(3, max(1, footView))
            value.vehicleView = min(6, max(1, vehicleView))
            value.radarSpan = bounded(radarSpan, 200...1200, fallback: 400)
            value.masterVolume = bounded(masterVolume, 0...1, fallback: 1)
            value.effectsVolume = bounded(effectsVolume, 0...1, fallback: 1)
            value.radioVolume = bounded(radioVolume, 0...1, fallback: 1)
            return value
        }

        /// A request is a cap, not a measured frame-rate promise. The OS may
        /// choose a lower cadence under thermal, power or display constraints.
        func effectiveFrameRate(maximum: Int) -> Int {
            min(max(1, maximum), validated().frameRate)
        }

        /// Pixel dimensions are recomputed from the unscaled viewport each
        /// time, so repeated application never compounds the resolution scale.
        func drawableSize(bounds: CGSize, displayScale: CGFloat) -> CGSize? {
            guard bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0,
                  displayScale.isFinite, displayScale > 0 else { return nil }
            let factor = displayScale * validated().renderScale
            let width = (bounds.width * factor).rounded()
            let height = (bounds.height * factor).rounded()
            guard width.isFinite, height.isFinite else { return nil }
            return CGSize(width: max(1, width), height: max(1, height))
        }

        init() {}
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case renderScale, frameRate, cameraSensitivity, invertY, footView, vehicleView
            case radarVisible, radarCircular, radarSpan, radarWorldMarkers, regionalWeather, reduceMenuMotion
            case masterVolume, effectsVolume, radioVolume
        }
        /// Partial or old preference documents retain valid independent fields.
        /// Wrong types are ignored rather than invalidating every preference.
        init(from decoder: Decoder) throws {
            self.init()
            let values = try decoder.container(keyedBy: CodingKeys.self)
            renderScale = (try? values.decode(Double.self, forKey: .renderScale)) ?? renderScale
            frameRate = (try? values.decode(Int.self, forKey: .frameRate)) ?? frameRate
            cameraSensitivity = (try? values.decode(Double.self, forKey: .cameraSensitivity)) ?? cameraSensitivity
            invertY = (try? values.decode(Bool.self, forKey: .invertY)) ?? invertY
            footView = (try? values.decode(Int.self, forKey: .footView)) ?? footView
            vehicleView = (try? values.decode(Int.self, forKey: .vehicleView)) ?? vehicleView
            radarVisible = (try? values.decode(Bool.self, forKey: .radarVisible)) ?? radarVisible
            radarCircular = (try? values.decode(Bool.self, forKey: .radarCircular)) ?? radarCircular
            radarSpan = (try? values.decode(Double.self, forKey: .radarSpan)) ?? radarSpan
            radarWorldMarkers = (try? values.decode(Bool.self, forKey: .radarWorldMarkers)) ?? radarWorldMarkers
            regionalWeather = (try? values.decode(Bool.self, forKey: .regionalWeather)) ?? regionalWeather
            reduceMenuMotion = (try? values.decode(Bool.self, forKey: .reduceMenuMotion)) ?? reduceMenuMotion
            masterVolume = (try? values.decode(Double.self, forKey: .masterVolume)) ?? masterVolume
            effectsVolume = (try? values.decode(Double.self, forKey: .effectsVolume)) ?? effectsVolume
            radioVolume = (try? values.decode(Double.self, forKey: .radioVolume)) ?? radioVolume
            self = validated()
        }
    }

    static let shared = NativeAppSettings()
    static let storageKey = "native.app.settings.v1"
    static let didChange = Notification.Name("NativeAppSettings.didChange")
    static var defaults: Snapshot { Snapshot() }
    private let storage: NativeAppSettingsStorage
    private let notifications: NotificationCenter
    private(set) var snapshot: Snapshot

    init(storage: NativeAppSettingsStorage = UserDefaults.standard,
         notifications: NotificationCenter = .default) {
        self.storage = storage; self.notifications = notifications
        if let bytes = storage.object(forKey: Self.storageKey) as? Data,
           let saved = try? JSONDecoder().decode(Snapshot.self, from: bytes) {
            snapshot = saved.validated()
        } else {
            var migrated = Self.defaults
            if let foot = storage.object(forKey: "world.view.foot") as? Int, (1...3).contains(foot) { migrated.footView = foot }
            if let car = storage.object(forKey: "world.view.car") as? Int, (1...6).contains(car) { migrated.vehicleView = car }
            if let weather = storage.object(forKey: "world.weather.auto") as? Bool { migrated.regionalWeather = weather }
            snapshot = migrated
        }
    }

    /// Notifications carry this store as object. Observers apply the complete
    /// snapshot, including values reset while a running game is behind Options.
    func update(_ change: (inout Snapshot) -> Void) {
        var next = snapshot
        change(&next)
        replace(next)
    }

    func replace(_ proposed: Snapshot) {
        let next = proposed.validated()
        guard next != snapshot else { return }
        snapshot = next
        persist()
        notifications.post(name: Self.didChange, object: self)
    }

    func reset() {
        // Persist even when already at defaults: this also replaces legacy
        // per-view preferences and prevents a later launch remigrating them.
        let changed = snapshot != Self.defaults
        snapshot = Self.defaults
        persist()
        if changed { notifications.post(name: Self.didChange, object: self) }
    }

    private func persist() {
        guard let bytes = try? JSONEncoder().encode(snapshot) else { return }
        storage.set(bytes, forKey: Self.storageKey)
        // Keep the existing camera/weather implementations compatible, without
        // making their old per-view defaults the new settings source of truth.
        storage.set(snapshot.footView, forKey: "world.view.foot")
        storage.set(snapshot.vehicleView, forKey: "world.view.car")
        storage.set(snapshot.regionalWeather, forKey: "world.weather.auto")
    }
}

/// Injection keeps persistence regressions out of the user's real preferences.
protocol NativeAppSettingsStorage {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}
extension UserDefaults: NativeAppSettingsStorage {}
