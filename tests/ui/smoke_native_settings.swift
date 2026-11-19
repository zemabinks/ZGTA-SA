import Foundation
import CoreGraphics

final class SettingsMemory: NativeAppSettingsStorage {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
var settingsChecks = 0
func settingsCheck(_ condition: @autoclosure () -> Bool, _ message: String) {
    settingsChecks += 1
    precondition(condition(), message)
}
func settingsClose(_ value: Double, _ expected: Double, _ message: String) {
    settingsCheck(abs(value - expected) < 1e-6, message)
}

func verifySettingsStore() throws {
    let memory = SettingsMemory(), center = NotificationCenter()
    let store = NativeAppSettings(storage: memory, notifications: center)
    settingsCheck(store.snapshot == NativeAppSettings.defaults, "fresh installation defaults")
    settingsClose(Double(store.snapshot.effectiveEffectsGain), 0.7, "old effects default preserved")
    settingsClose(Double(store.snapshot.effectiveRadioGain), 0.6, "old radio default preserved")
    var changes = 0
    let token = center.addObserver(forName: NativeAppSettings.didChange, object: nil, queue: nil) { note in
        if note.object as? NativeAppSettings === store { changes += 1 }
    }
    defer { center.removeObserver(token) }
    store.update { _ in }
    settingsCheck(changes == 0, "no duplicate apply for unchanged preferences")
    store.update {
        $0.renderScale = 0.7; $0.frameRate = 120; $0.cameraSensitivity = 1.7; $0.invertY = true
        $0.footView = 3; $0.vehicleView = 6; $0.radarVisible = false; $0.radarCircular = false
        $0.radarSpan = 850; $0.radarWorldMarkers = false; $0.regionalWeather = true; $0.reduceMenuMotion = true
        $0.masterVolume = 0.5; $0.effectsVolume = 0.4; $0.radioVolume = 0.2
    }
    settingsCheck(changes == 1, "one complete snapshot notification")
    let reopened = NativeAppSettings(storage: memory, notifications: center)
    settingsCheck(reopened.snapshot == store.snapshot, "every setting survives new store construction")
    settingsClose(Double(store.snapshot.effectiveEffectsGain), 0.14, "master times effects")
    settingsClose(Double(store.snapshot.effectiveRadioGain), 0.06, "master times radio")
    settingsCheck(memory.values["world.view.foot"] as? Int == 3, "legacy foot preference synchronized")
    settingsCheck(memory.values["world.view.car"] as? Int == 6, "legacy vehicle preference synchronized")
    settingsCheck(memory.values["world.weather.auto"] as? Bool == true, "legacy weather preference synchronized")
    store.reset()
    settingsCheck(changes == 2, "reset notifies running game")
    settingsCheck(store.snapshot == NativeAppSettings.defaults, "reset applies actual defaults")
    settingsCheck(NativeAppSettings(storage: memory).snapshot == NativeAppSettings.defaults, "reset survives restart")
    store.reset()
    settingsCheck(changes == 2, "idempotent reset")

    let legacy = SettingsMemory()
    legacy.values = ["world.view.foot": 1, "world.view.car": 5, "world.weather.auto": true]
    let migrated = NativeAppSettings(storage: legacy)
    settingsCheck(migrated.snapshot.footView == 1 && migrated.snapshot.vehicleView == 5 && migrated.snapshot.regionalWeather,
                  "existing camera/weather preferences preserved")
    migrated.reset()
    settingsCheck(NativeAppSettings(storage: legacy).snapshot == NativeAppSettings.defaults, "reset prevents remigrating old views")

    let partial = SettingsMemory()
    partial.values[NativeAppSettings.storageKey] = Data("{\"frameRate\":120,\"invertY\":true,\"renderScale\":\"bad\",\"radioVolume\":0.3,\"unknownFutureField\":1}".utf8)
    let recovered = NativeAppSettings(storage: partial).snapshot
    settingsCheck(recovered.frameRate == 120 && recovered.invertY, "valid independent fields recovered")
    settingsCheck(recovered.renderScale == 1 && recovered.footView == 2, "wrong types and missing fields use defaults")
    settingsClose(recovered.radioVolume, 0.3, "partial audio document retained")
    partial.values[NativeAppSettings.storageKey] = Data("corrupted".utf8)
    settingsCheck(NativeAppSettings(storage: partial).snapshot == NativeAppSettings.defaults, "corrupt document safe fallback")

    for number in [-Double.infinity, Double.infinity, .nan, -100, 0, 0.4, 0.75, 1, 2, 100] {
        var value = NativeAppSettings.defaults
        value.renderScale = number; value.cameraSensitivity = number; value.radarSpan = number
        value.masterVolume = number; value.effectsVolume = number; value.radioVolume = number
        store.replace(value)
        let valid = store.snapshot
        settingsCheck(valid.renderScale.isFinite && (0.5...1).contains(valid.renderScale), "finite render scale")
        settingsCheck(valid.cameraSensitivity.isFinite && (0.25...3).contains(valid.cameraSensitivity), "finite sensitivity")
        settingsCheck(valid.radarSpan.isFinite && (200...1200).contains(valid.radarSpan), "bounded radar range")
        settingsCheck(valid.masterVolume.isFinite && (0...1).contains(valid.masterVolume), "bounded master")
        settingsCheck(valid.effectsVolume.isFinite && (0...1).contains(valid.effectsVolume), "bounded effects")
        settingsCheck(valid.radioVolume.isFinite && (0...1).contains(valid.radioVolume), "bounded radio")
        settingsCheck(NativeAppSettings(storage: memory).snapshot == valid, "validated values round-trip")
    }
    for integer in [Int.min, -1, 0, 1, 2, 3, 6, 30, 60, 120, Int.max] {
        var value = NativeAppSettings.defaults
        value.frameRate = integer; value.footView = integer; value.vehicleView = integer
        store.replace(value)
        settingsCheck((30...120).contains(store.snapshot.frameRate), "bounded requested FPS")
        settingsCheck((1...3).contains(store.snapshot.footView), "bounded foot view")
        settingsCheck((1...6).contains(store.snapshot.vehicleView), "bounded vehicle view")
    }
}

func verifySettingsSizingAndCamera() {
    for width in [320.0, 568, 844, 932, 1024, 1366] {
        for scale in [1.0, 2, 3] { for factor in [0.5, 0.75, 1] {
            var settings = NativeAppSettings.defaults; settings.renderScale = factor
            let size = settings.drawableSize(bounds: CGSize(width: width, height: 390), displayScale: scale)!
            settingsCheck(size.width == (width * scale * factor).rounded(), "real pixel width")
            settingsCheck(size.height == (390 * scale * factor).rounded(), "real pixel height")
            settingsCheck(settings.drawableSize(bounds: CGSize(width: width, height: 390), displayScale: scale) == size,
                          "repeated apply cannot compound resolution scale")
        } }
    }
    for invalid in [CGSize.zero, CGSize(width: -1, height: 390), CGSize(width: Double.nan, height: 390)] {
        settingsCheck(NativeAppSettings.defaults.drawableSize(bounds: invalid, displayScale: 3) == nil, "invalid viewport deferred")
    }
    for maximum in [0, 1, 24, 30, 60, 90, 120, 144, 240] {
        for requested in [30, 60, 90, 120] {
            var settings = NativeAppSettings.defaults; settings.frameRate = requested
            settingsCheck(settings.effectiveFrameRate(maximum: maximum) == min(max(1, maximum), requested), "hardware FPS cap")
        }
    }
    // Exercise the actual native camera, not a duplicate camera equation.
    for hz in [30, 60, 120] {
        for gain: Float in [0.25, 1, 2, 3] { for inverted in [false, true] {
            let camera = NativeGameCamera(persistViews: false)
            camera.setDirection(heading: 0, pitch: 0)
            for _ in 0..<hz { camera.lookAnalog(x: 0.1, y: 0.1, delta: 1 / Float(hz), sensitivity: gain, inverted: inverted) }
            let direction = inverted ? 1.0 : -1.0
            settingsCheck(camera.heading > 0, "sensitivity preserves horizontal direction")
            settingsCheck(Double(camera.pitch) * direction > 0, "invert Y reaches actual camera")
            let baseline = NativeGameCamera(persistViews: false)
            baseline.setDirection(heading: 0, pitch: 0)
            baseline.lookAnalog(x: 0.1, y: 0.1, delta: 1, sensitivity: gain, inverted: inverted)
            settingsClose(Double(camera.heading), Double(baseline.heading), "look remains frame-rate independent")
            settingsClose(Double(camera.pitch), Double(baseline.pitch), "vertical look remains frame-rate independent")
        } }
    }
}

@main enum NativeSettingsVerification {
    static func main() throws {
        try verifySettingsStore()
        verifySettingsSizingAndCamera()
        verifyNativeSettingsOwnerIntegration()
        print("native settings PASS: \(settingsChecks) checks")
    }
}
