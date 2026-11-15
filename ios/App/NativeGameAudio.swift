import AVFoundation
import Foundation
import UIKit

/// Plays the archived WAV banks directly from the owner's Mac. Routing and
/// loop points are extracted by prepare_native_audio.py into ignored data.
/// All public methods are called on the main thread with gameplay events.
final class NativeGameAudio: NSObject, AVAudioPlayerDelegate {
    // Pure explosion planning is kept separate from AVFoundation playback so
    // gains, pitch layers and distance curves can be checked against the JS.
    struct ExplosionSettings: Decodable {
        struct Base: Decodable { let sample: String; let offset: Float; let scale: Float }
        let layers: [Base]
        let stereoSample: String
        let pitches: [Float]
        let attenuation: [[Float]]
    }
    struct ExplosionLayer {
        let sample: String
        let rate: Float
        let gain: Float
        let pan: Float
        let fadeStart: Float
        let fadeEnd: Float
        let endGain: Float
    }
    private struct StreamSound: Decodable { let sample: String; let rate: Float; let gain: Float }
    private struct Footsteps: Decodable {
        struct Bank: Decodable { let bank: Int; let first: Int; let count: Int }
        let materials: [Int]
        let banks: [String: Bank]
        let water: Int
    }
    private struct Fade {
        let begins: Double; let ends: Double
        let from: Float; let to: Float
    }
    private struct Sample: Decodable { let rate: Int; let frames: Int; let loop: Int }
    private struct LoopVoice { let sample: String; let player: AVAudioPlayer }
    private let server: ServerAddress
    let weather = NativeWeatherAudio()
    private let rateAudio = NativeRateAudio()
    private var samples: [String: Sample] = [:]
    private var road: [String: [NSNumber]] = [:]
    private var aircraft: [String: [Any]] = [:]
    private var boats: [String: NSNumber] = [:]
    private var special: [String: [Any]] = [:]
    private var trains: [String: [NSNumber]] = [:]
    private var weapons: [String: [NSNumber]] = [:]
    private var reloads: [String: [NSNumber]] = [:]
    private var swings: [String: NSNumber] = [:]
    private var meleeHits: [String: [NSNumber]] = [:]
    private var explosionSettings: ExplosionSettings?
    private var streamSounds: [String: StreamSound] = [:]
    private var footstepSettings: Footsteps?
    private var explosionIndex = 0
    private var data: [String: Data] = [:]
    private var requests: [String: URLSessionDataTask] = [:]
    private var completions: [String: [(Data?) -> Void]] = [:]
    private var loops: [String: LoopVoice] = [:]
    private var oneShots: [ObjectIdentifier: AVAudioPlayer] = [:]
    private var fades: [ObjectIdentifier: Fade] = [:]
    private var fadeTimer: DispatchSourceTimer?
    private var notifications: [NSObjectProtocol] = []
    private var pendingManifest: URLSessionDataTask?
    private var suspended = false
    private var distanceSinceStep: Float = 0
    private var vehicleModel: Int?
    private var rotor: Float = 0
    private(set) var loadedSampleCount = 0
    private(set) var lastEvent = ""
    var volume: Float = 0.7 {
        didSet { volume = max(0, min(1, volume)) }
    }

    init(server: ServerAddress) {
        self.server = server
        super.init()
        weather.onEvents = { [weak self] events in self?.playWeather(events) }
        let center = NotificationCenter.default
        notifications = [
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began { self?.suspend() } else { self?.resume() }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.suspend() },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.resume() }
        ]
    }

    deinit {
        pendingManifest?.cancel()
        fadeTimer?.cancel()
        requests.values.forEach { $0.cancel() }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        loops.values.forEach { $0.player.stop() }
        oneShots.values.forEach { $0.stop() }
    }

    func prepare() {
        configureSession()
        pendingManifest?.cancel()
        pendingManifest = URLSession.shared.dataTask(with: server.path("game/native/audio.json")) { [weak self] bytes, response, _ in
            guard let bytes, (response as? HTTPURLResponse)?.statusCode == 200,
                  let document = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let sampleDocument = document["samples"],
                  let sampleBytes = try? JSONSerialization.data(withJSONObject: sampleDocument),
                  let metadata = try? JSONDecoder().decode([String: Sample].self, from: sampleBytes) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.samples = metadata
                self.road = document["road"] as? [String: [NSNumber]] ?? [:]
                self.aircraft = document["aircraft"] as? [String: [Any]] ?? [:]
                self.boats = document["boats"] as? [String: NSNumber] ?? [:]
                self.special = document["special"] as? [String: [Any]] ?? [:]
                self.trains = document["trains"] as? [String: [NSNumber]] ?? [:]
                self.weapons = document["weapons"] as? [String: [NSNumber]] ?? [:]
                self.reloads = document["reloads"] as? [String: [NSNumber]] ?? [:]
                self.swings = document["swings"] as? [String: NSNumber] ?? [:]
                self.meleeHits = document["meleeHits"] as? [String: [NSNumber]] ?? [:]
                if let config = document["explosion"],
                   let bytes = try? JSONSerialization.data(withJSONObject: config) {
                    self.explosionSettings = try? JSONDecoder().decode(ExplosionSettings.self, from: bytes)
                }
                if let config = document["streams"],
                   let bytes = try? JSONSerialization.data(withJSONObject: config) {
                    self.streamSounds = (try? JSONDecoder().decode([String: StreamSound].self, from: bytes)) ?? [:]
                }
                if let config = document["footsteps"],
                   let bytes = try? JSONSerialization.data(withJSONObject: config) {
                    self.footstepSettings = try? JSONDecoder().decode(Footsteps.self, from: bytes)
                }
                self.preload(["0_1", "0_2", "0_3", "0_4", "0_5", "0_6", "143_87", "143_39", "143_40"])
                if let config = self.explosionSettings {
                    self.preload(config.layers.map(\.sample) + [config.stereoSample])
                }
                self.preload(self.streamSounds.values.map(\.sample))
                if let footsteps = self.footstepSettings {
                    self.preload(footsteps.banks.values.flatMap { bank in
                        (bank.first..<(bank.first + bank.count)).map { "\(bank.bank)_\($0)" }
                    })
                }
                self.preloadWeapon(22)
            }
        }
        pendingManifest?.resume()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func suspend() {
        suspended = true
        weather.stop();rateAudio.stop()
        loops.values.forEach { $0.player.pause() }
        oneShots.values.forEach { $0.stop() }
        oneShots.removeAll()
        clearFades()
    }

    func resume() {
        configureSession()
        suspended = false
        loops.values.forEach { $0.player.play() }
    }

    func stop() {
        suspended = true
        weather.stop();rateAudio.stop()
        loops.values.forEach { $0.player.stop() }
        loops.removeAll()
        oneShots.values.forEach { $0.stop() }
        oneShots.removeAll()
        clearFades()
        vehicleModel = nil
        distanceSinceStep = 0
    }

    private func preload(_ names: [String]) { names.forEach { fetch($0) { _ in } } }

    private func fetch(_ name: String, completion: @escaping (Data?) -> Void) {
        guard samples[name] != nil else { completion(nil); return }
        if let bytes = data[name] { completion(bytes); return }
        completions[name, default: []].append(completion)
        guard requests[name] == nil else { return }
        let request = URLSession.shared.dataTask(with: server.path("game/sound/b\(name).wav")) { [weak self] bytes, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let valid = (response as? HTTPURLResponse)?.statusCode == 200 ? bytes : nil
                if let valid { self.data[name] = valid; self.loadedSampleCount = self.data.count }
                self.requests.removeValue(forKey: name)
                let callbacks = self.completions.removeValue(forKey: name) ?? []
                callbacks.forEach { $0(valid) }
            }
        }
        requests[name] = request
        request.resume()
    }

    private func once(_ name: String, rate: Float = 1, gain: Float = 1, pan: Float = 0,
                      start: Double = 0, fade: Fade? = nil,rise: Double = 0) {
        guard !suspended, gain > 0, volume > 0 else { return }
        let requested = Date()
        fetch(name) { [weak self] bytes in
            guard let self, !self.suspended, requested.timeIntervalSinceNow > -0.5,
                  let bytes else { return }
            if rate < 0.5 || rate > 2 {
                if self.rateAudio.play(bytes,name:name,rate:rate,gain:gain*self.volume,pan:pan,rise:rise) { self.lastEvent = name }
                return
            }
            guard let voice = try? AVAudioPlayer(data: bytes) else { return }
            voice.enableRate = true
            voice.rate = max(0.5, min(2, rate))
            voice.pan = max(-1, min(1, pan))
            let targetVolume = max(0,min(1,gain*self.volume))
            voice.volume = rise > 0 ? 0 : targetVolume
            voice.currentTime = max(0, min(0.99, start)) * voice.duration
            voice.delegate = self
            self.oneShots[ObjectIdentifier(voice)] = voice
            voice.play()
            if rise > 0 { voice.setVolume(targetVolume,fadeDuration:rise) }
            if let fade, fade.ends > fade.begins, fade.to < gain {
                let now = ProcessInfo.processInfo.systemUptime
                self.fades[ObjectIdentifier(voice)] = Fade(begins: now + fade.begins,
                    ends: now + fade.ends, from: gain, to: max(0.0001, fade.to))
                self.startFadeTimer()
            }
            self.lastEvent = name
            if self.oneShots.count > 24, let oldest = self.oneShots.first {
                oldest.value.stop()
                self.oneShots.removeValue(forKey: oldest.key)
                self.fades.removeValue(forKey: oldest.key)
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        oneShots.removeValue(forKey: ObjectIdentifier(player))
        fades.removeValue(forKey: ObjectIdentifier(player))
    }

    private func clearFades() {
        fades.removeAll()
        fadeTimer?.cancel()
        fadeTimer = nil
    }

    private func startFadeTimer() {
        guard fadeTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for (id, fade) in self.fades {
                guard let voice = self.oneShots[id] else { self.fades.removeValue(forKey: id); continue }
                guard now >= fade.begins else { continue }
                let share = Float(max(0, min(1, (now - fade.begins) / (fade.ends - fade.begins))))
                voice.volume = min(1, max(0, fade.from * pow(fade.to / max(fade.from, 0.0001), share) * self.volume))
                if share >= 1 { self.fades.removeValue(forKey: id) }
            }
            if self.fades.isEmpty { self.clearFades() }
        }
        fadeTimer = timer
        timer.resume()
    }

    /// Exact layering from archived module99488: three impact layers and a
    /// stereo pair, cycling three base pitches, with distance attenuation.
    static func explosionPlan(_ config: ExplosionSettings, weapon: Int, distance: Float,
                              serial: Int, random: () -> Float = { Float.random(in: 0..<1) }) -> [ExplosionLayer] {
        guard !config.pitches.isEmpty, config.attenuation.count > 1,
              distance.isFinite, distance >= 0 else { return [] }
        let pitch = config.pitches[max(0, serial) % config.pitches.count]
        let level: Float = 20 + (weapon == 18 ? -36 : 0)
        let quiet = min(0, level), fadeEnd = max(0, level) / 30
        func attenuation(_ distance: Float) -> Float {
            guard let first = config.attenuation.first, first.count >= 2, distance > first[0] else { return 0 }
            for index in 1..<config.attenuation.count {
                let a = config.attenuation[index - 1], b = config.attenuation[index]
                guard a.count >= 2, b.count >= 2 else { return -100 }
                if distance <= b[0] { return a[1] + (distance - a[0]) / (b[0] - a[0]) * (b[1] - a[1]) }
            }
            return -100
        }
        func jitter() -> Float { 1 + (2 * random() - 1) * 0.06 }
        var result: [ExplosionLayer] = []
        func add(_ sample: String, _ rate: Float, _ offset: Float, _ pan: Float) {
            let decibels = min(0, level + offset), endDecibels = min(0, quiet + offset)
            guard decibels >= -60 else { return }
            let from = max(0, min(1, (level + offset) / 30 / (fadeEnd > 0 ? fadeEnd : 1))) * fadeEnd
            result.append(ExplosionLayer(sample: sample, rate: rate, gain: pow(10, (decibels - 2) / 20),
                pan: pan, fadeStart: from, fadeEnd: fadeEnd, endGain: pow(10, (endDecibels - 2) / 20)))
        }
        for base in config.layers where base.scale > 0 {
            add(base.sample, pitch * jitter(), attenuation(distance / base.scale) - base.offset, 0)
        }
        let leftHigh = random() < 0.5
        let stereo = attenuation(distance / 12) - 3 - 1.38
        add(config.stereoSample, pitch * (leftHigh ? 1.189207115002721 : 1) * jitter(), stereo, -1)
        add(config.stereoSample, pitch * (leftHigh ? 1 : 1.189207115002721) * jitter(), stereo, 1)
        return result
    }

    func explosion(weapon: Int, distance: Float = 0) {
        guard !suspended, let config = explosionSettings else { return }
        let layers = Self.explosionPlan(config, weapon: weapon, distance: distance, serial: explosionIndex)
        explosionIndex = (explosionIndex + 1) % max(1, config.pitches.count)
        for layer in layers {
            let fade = layer.fadeEnd > layer.fadeStart && layer.endGain < layer.gain ?
                Fade(begins: Double(layer.fadeStart), ends: Double(layer.fadeEnd), from: layer.gain, to: layer.endGain) : nil
            once(layer.sample, rate: layer.rate, gain: layer.gain, pan: layer.pan, fade: fade)
        }
    }

    func stream(weapon: Int, active: Bool) {
        let name = [37: "flame", 38: "minigun", 41: "spray", 42: "foam"][weapon]
        guard active, let name, let sound = streamSounds[name] else { stopLoop("effect:stream"); return }
        loop("effect:stream", sample: sound.sample, rate: sound.rate, gain: sound.gain)
    }

    func fire(active: Bool) {
        guard active, let sound = streamSounds["fire"] else { stopLoop("effect:fire"); return }
        loop("effect:fire", sample: sound.sample, rate: sound.rate, gain: sound.gain)
    }

    private func playWeather(_ events: [NativeWeatherAudio.Event]) {
        for event in events {
            let id = "effect:weather:"+event.id
            switch event.kind {
            case "ready": preload(event.samples)
            case "drop": stopLoop(id)
            case "hold":
                if !suspended { loop(id,sample:event.sample,rate:Float(event.rate),gain:Float(event.gain),pan:Float(event.pan)) }
            case "once": once(event.sample,rate:Float(event.rate),gain:Float(event.gain),pan:Float(event.pan),rise:event.rise)
            default: break
            }
        }
    }

    /// Use travelled distance rather than touch pressure so blocked walking
    /// does not make steps. Default plain-ground banks match the browser.
    func footsteps(distance: Float, running: Bool, crouching: Bool = false,
                   swimming: Bool = false, grounded: Bool = true, material: Int? = nil) {
        guard !suspended, grounded, distance > 0, distance < 2 else {
            if !grounded { distanceSinceStep = 0 }
            return
        }
        distanceSinceStep += distance
        let stride: Float = crouching ? 0.45 : running ? 1.05 : 0.65
        guard distanceSinceStep >= stride else { return }
        distanceSinceStep.formTruncatingRemainder(dividingBy: stride)
        let mapped = material.flatMap { index -> Int? in
            guard let settings = footstepSettings, settings.materials.indices.contains(index) else { return nil }
            return settings.materials[index]
        } ?? 0
        let step = swimming ? footstepSettings?.water ?? 7 : mapped
        let bank = footstepSettings?.banks[String(step)]
        let first = bank?.first ?? 1, count = max(1, bank?.count ?? 5)
        let sample = "\(bank?.bank ?? 0)_\(Int.random(in: first..<(first + count)))"
        let decibels: Float = crouching ? -18 : running ? -6 : -12
        let pitch: Float = crouching ? 0.8 : running ? 1.1 : 0.9
        once(sample, rate: pitch * Float.random(in: 0.9412...1.0588),
             gain: 0.9 * pow(10, decibels / 20), start: step == (footstepSettings?.water ?? 7) ? 0.5 : 0)
    }

    func land(water: Bool = false, collapse: Bool = false) {
        once(water ? "128_\(Int.random(in: 0...4))" : collapse ? "0_0" : "0_6",
             rate: Float.random(in: 0.9412...1.0588), gain: 0.8, start: water ? 0.5 : 0)
    }

    func preloadWeapon(_ id: Int) {
        let shot = (weapons[String(id)] ?? []).prefix(5).filter { $0.intValue >= 0 }
        let reload = reloads[String(id)] ?? []
        preload((Array(shot) + reload).map { "143_\($0.intValue)" })
    }

    /// These layer IDs and rates come from the archived client's kk map.
    func shot(weapon id: Int) {
        guard let row = weapons[String(id)], row.count >= 8 else { return }
        let pitch = row[5].floatValue
        let level = pow(10, row[6].floatValue / 20)
        once("143_\(row[0].intValue)", rate: pitch, gain: 0.45 * level)
        once("143_\(row[1].intValue)", rate: pitch, gain: 0.8 * level)
        let spread = pitch * Float.random(in: 0.98...1.02)
        once("143_\(row[2].intValue)", rate: spread, gain: 0.75 * level, pan: -0.6)
        once("143_\(row[3].intValue)", rate: spread, gain: 0.75 * level, pan: 0.6)
        if row[4].intValue >= 0 {
            once("143_\(row[4].intValue)", rate: row[7].floatValue * (Bool.random() ? 1 : 1.18921),
                 gain: 0.3 * level)
        }
    }

    func reload(weapon id: Int) {
        guard let row = reloads[String(id)], row.count >= 2 else { return }
        once("143_\(row[0].intValue)", gain: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.once("143_\(row[1].intValue)", gain: 0.5)
        }
    }

    func swing(weapon id: Int = 0) {
        once("143_\(swings[String(id)]?.intValue ?? 86)",
             rate: Float.random(in: 0.95...1.05), gain: 0.5)
    }

    func meleeHit(weapon id: Int = 0) {
        guard let value = meleeHits[String(id)]?.randomElement() else { return }
        once("143_\(value.intValue)", rate: Float.random(in: 0.95...1.05), gain: 0.8)
    }

    func collision(severity: Float) {
        // Generic car body impact banks are present in the local archive.
        // Material-specific contact selection still needs collision materials.
        guard severity > 0 else { return }
        once(["39_20", "39_21", "39_22", "39_23", "39_24"].randomElement()!,
             rate: Float.random(in: 0.98...1.02), gain: min(0.8, 0.25 + severity / 100))
    }

    func horn(model:Int?,active:Bool) {
        let id = "effect:vehicleHorn"
        guard !suspended,active,let model else {stopLoop(id);return}
        let bank:Int,rate:Float
        if let row=road[String(model)],row.count >= 6 {
            bank=row[4].intValue;rate=row[5].floatValue == 0 ? 1:row[5].floatValue
        } else if let row=special[String(model)],row.count >= 4,let value=row[2] as? NSNumber {
            bank=value.intValue;rate=(row[3] as? NSNumber)?.floatValue ?? 1
        } else {stopLoop(id);return}
        guard bank >= 0 else {stopLoop(id);return}
        loop(id,sample:"74_\(bank)",rate:rate,gain:0.8)
    }

    /// The archived bank mapping is exact; road engine crossfades use the
    /// native client's approximate speed and throttle until its full gearbox
    /// state machine is ported. Missing bank files remain silent.
    func updateVehicle(model: Int?, kind: String, speed: Float, throttle: Float,
                       health: Int, delta: Float) {
        guard !suspended else { return }
        guard let model, health > 0 else { clearVehicle(); return }
        if model != vehicleModel { clearVehicle(); vehicleModel = model }
        let key = String(model)
        let share = min(1, abs(speed) / 45)
        var wanted: Set<String> = []
        func layer(_ id: String, _ sample: String, _ rate: Float, _ gain: Float) {
            wanted.insert(id)
            loop(id, sample: sample, rate: rate, gain: gain)
        }
        if let row = aircraft[key], let type = row.first as? String {
            rotor += ((max(0, throttle) > 0.05 ? 1 : 0.4) - rotor) * min(1, delta * 0.5)
            if type == "jet" {
                let pitch = 0.8 + rotor * 0.4
                layer("front", "138_10", pitch, 0.25 + 0.3 * rotor)
                layer("rear", "138_11", pitch, 0.25 + 0.3 * rotor)
                layer("near", "138_26", 1, rotor * 0.2)
            } else if row.count > 1, let bank = row[1] as? NSNumber {
                let pitch: Float = type == "heli" ? 0.3 + rotor * 0.7 : 0.8 + rotor * 0.3
                layer("front", "\(bank)_0", pitch, 0.25 + 0.3 * rotor)
                layer("rear", "\(bank)_1", pitch, 0.25 + 0.3 * rotor)
                if type == "heli" { layer("near", "\(bank)_3", 1, 0.2 * rotor) }
            }
        } else if let bank = boats[key] {
            layer("engine", "\(bank)_0", 0.6 + max(0, throttle) * 0.4, 0.6)
            if share > 0.05 { layer("water", "39_3", 0.8 + share * 0.2, share * 0.4) }
        } else if let row = special[key], row.count > 1, let bank = row[1] as? NSNumber {
            layer("engine", "\(bank)_0", 0.85 + share * 0.35, share > 0.05 ? 0.5 : 0.15)
        } else if let row = trains[key], row.count > 1 {
            layer("engine", "\(row[1])_0", 0.8 + share * 0.4, 0.45)
            if share > 0.05 { layer("track", "\(row[0])_0", 0.8 + share * 0.4, share * 0.4) }
        } else if let row = road[key], row.count >= 6 {
            let multiplier = row[2].floatValue
            let idle = row[1].intValue
            let idlePitch = (0.85 + share * 0.65) * multiplier
            let rev = min(1, share * 1.4 + max(0, throttle) * 0.3)
            layer("idle", "\(idle)_1", idlePitch, 0.55 * (1 - rev * 0.55))
            layer("revs", "\(idle)_0", (0.9 + rev * 0.6) * multiplier, rev * 0.5)
            if speed < -0.2 { layer("reverse", "138_19", 0.75 + share * 0.2, share * 0.3) }
        }
        for id in Array(loops.keys) where !id.hasPrefix("effect:") && !wanted.contains(id) { stopLoop(id) }
    }

    private func clearVehicle() {
        Array(loops.keys).filter { !$0.hasPrefix("effect:") }.forEach { stopLoop($0) }
        vehicleModel = nil
        rotor = 0
    }

    private func stopLoop(_ id: String) {
        loops.removeValue(forKey: id)?.player.stop()
    }

    private func loop(_ id: String, sample name: String, rate: Float, gain: Float,pan: Float = 0) {
        guard samples[name] != nil, gain > 0.001 else { stopLoop(id); return }
        if let voice = loops[id], voice.sample == name {
            voice.player.rate = max(0.5, min(2, rate))
            voice.player.volume = max(0, min(1, gain * volume))
            voice.player.pan = max(-1,min(1,pan))
            if !voice.player.isPlaying { voice.player.play() }
            return
        }
        // Start on a later update after prefetch; keep one pending request per
        // sample rather than creating an ever-growing callback list per frame.
        guard let bytes = data[name] else {
            if requests[name] == nil { fetch(name) { _ in } }
            return
        }
        stopLoop(id)
        let trimmed = Self.loopData(bytes, startFrame: samples[name]?.loop ?? -1) ?? bytes
        guard let player = try? AVAudioPlayer(data: trimmed) else { return }
        player.enableRate = true
        player.rate = max(0.5, min(2, rate))
        player.volume = max(0, min(1, gain * volume))
        player.pan = max(-1,min(1,pan))
        player.numberOfLoops = -1
        loops[id] = LoopVoice(sample: name, player: player)
        player.play()
    }

    /// Preserve the archived loop start in PCM frames, including WAV files
    /// with ancillary chunks. Repeating only the loop tail avoids replaying
    /// an engine's recorded attack on each iteration.
    static func loopData(_ bytes: Data, startFrame: Int) -> Data? {
        guard startFrame > 0, bytes.count >= 44 else { return nil }
        let raw = [UInt8](bytes)
        func u32(_ n: Int) -> Int {
            Int(raw[n]) | Int(raw[n+1]) << 8 | Int(raw[n+2]) << 16 | Int(raw[n+3]) << 24
        }
        guard Array(raw[0..<4]) == Array("RIFF".utf8),
              Array(raw[8..<12]) == Array("WAVE".utf8) else { return nil }
        var format: Data?
        var pcm: Data?
        var align = 0
        var offset = 12
        while offset + 8 <= raw.count {
            let size = u32(offset + 4), begin = offset + 8
            guard size >= 0, begin + size <= raw.count else { return nil }
            let id = String(bytes: raw[offset..<offset+4], encoding: .ascii)
            if id == "fmt ", size >= 16 {
                guard raw[begin] == 1, raw[begin+1] == 0 else { return nil }
                align = Int(raw[begin+12]) | Int(raw[begin+13]) << 8
                format = bytes.subdata(in: begin..<begin+size)
            } else if id == "data" { pcm = bytes.subdata(in: begin..<begin+size) }
            offset = begin + size + (size % 2)
        }
        guard let format, let pcm, align > 0, startFrame * align < pcm.count else { return nil }
        let tail = pcm.dropFirst(startFrame * align)
        func little(_ value: Int) -> Data {
            var result = UInt32(value).littleEndian
            return withUnsafeBytes(of: &result) { Data($0) }
        }
        var result = Data("RIFF".utf8)
        result.append(little(4 + 8 + format.count + format.count % 2 + 8 + tail.count + tail.count % 2))
        result.append(Data("WAVEfmt ".utf8)); result.append(little(format.count)); result.append(format)
        if format.count % 2 != 0 { result.append(0) }
        result.append(Data("data".utf8)); result.append(little(tail.count)); result.append(contentsOf: tail)
        if tail.count % 2 != 0 { result.append(0) }
        return result
    }
}
