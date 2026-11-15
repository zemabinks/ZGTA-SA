import AVFoundation
import Foundation
import UIKit
import simd

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
    private let server: ServerAddress
    let weather = NativeWeatherAudio()
    private let rateAudio = NativeRateAudio()
    private let vehicleLoops=NativeVehicleLoopAudio()
    private let roadEngine=NativeVehicleAudioDynamics.RoadEngine()
    private let reverseEngine=NativeVehicleAudioDynamics.Reverse()
    private let boatEngine=NativeVehicleAudioDynamics.Boat()
    private let specialEngine=NativeVehicleAudioDynamics.Special()
    private var registeredVehicleSamples=Set<String>()
    private var aircraftPitch = -1.0
    private final class RemoteEngine {
        let model:Int
        let road=NativeVehicleAudioDynamics.RemoteRoad()
        let boat=NativeVehicleAudioDynamics.Boat()
        let special=NativeVehicleAudioDynamics.Special()
        var pitch = -1.0,time:Double
        init(model:Int,time:Double) {self.model=model;self.time=time}
    }
    private var remoteEngines:[String:RemoteEngine]=[:]
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
    private var sirens:[String:String]=[:]
    private var sirenModels=Set<Int>()
    private let hornController=NativeVehicleHornController()
    private var footstepSettings: Footsteps?
    private var footstepAudio: NativeFootstepAudio?
    private var contactAudio:NativeContactAudio?
    private var pendingContactManifest:URLSessionDataTask?
    private var flightPackIdle:[String:Double]=[:]
    private var explosionIndex = 0
    private var data: [String: Data] = [:]
    private var requests: [String: URLSessionDataTask] = [:]
    private var completions: [String: [(Data?) -> Void]] = [:]
    private var loops=Set<String>()
    private var oneShots: [ObjectIdentifier: AVAudioPlayer] = [:]
    private var fades: [ObjectIdentifier: Fade] = [:]
    private var fadeTimer: DispatchSourceTimer?
    private var notifications: [NSObjectProtocol] = []
    private var pendingManifest: URLSessionDataTask?
    private var suspended = false
    private var distanceSinceStep: Float = 0
    private var vehicleModel: Int?
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
        pendingContactManifest?.cancel()
        fadeTimer?.cancel()
        requests.values.forEach { $0.cancel() }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        vehicleLoops.stopAll(immediate:true)
        oneShots.values.forEach { $0.stop() }
    }

    func prepare() {
        configureSession()
        pendingContactManifest?.cancel()
        pendingContactManifest=URLSession.shared.dataTask(with:server.path("game/native/contact-audio.json")) { [weak self] bytes,response,_ in
            guard let bytes,(response as? HTTPURLResponse)?.statusCode==200,
                  let configuration=try? JSONDecoder().decode(NativeContactAudio.Configuration.self,from:bytes) else{return}
            DispatchQueue.main.async {
                self?.contactAudio=NativeContactAudio(configuration:configuration)
                self?.preload(configuration.samples.map{"39_\($0)"}+(0...4).map{"128_\($0)"})
            }
        }
        pendingContactManifest?.resume()
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
                self.sirens=document["sirens"] as? [String:String] ?? [:]
                self.sirenModels=Set(document["sirenModels"] as? [Int] ?? [])
                self.preload(Array(self.sirens.values))
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
                    if let configuration=try? JSONDecoder().decode(NativeFootstepAudio.Configuration.self,from:bytes) {
                        self.footstepAudio=NativeFootstepAudio(configuration:configuration)
                    }
                }
                self.preload(["0_0", "0_1", "0_2", "0_3", "0_4", "0_5", "0_6", "0_7", "0_8", "143_87", "143_39", "143_40"])
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
        weather.stop();rateAudio.stop();vehicleLoops.stopAll(immediate:true)
        remoteEngines.removeAll()
        _ = contactAudio?.quiet();flightPackIdle.removeAll()
        loops.removeAll()
        oneShots.values.forEach { $0.stop() }
        oneShots.removeAll()
        clearFades()
    }

    func resume() {
        configureSession()
        suspended = false

    }

    func stop() {
        suspended = true
        weather.stop();rateAudio.stop();vehicleLoops.stopAll(immediate:true)
        remoteEngines.removeAll()
        _ = contactAudio?.quiet();flightPackIdle.removeAll()
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

    /// The animation controller selects the exact original foot phase/profile.
    func footstep(_ kind:String,material:Int?,surface:Int?,wading:Bool) {
        guard !suspended,let footstepAudio else {return}
        let plan:NativeFootstepAudio.Plan?
        if kind == "fallLand" || kind == "collapse" {plan=footstepAudio.land(kind,water:wading)}
        else {plan=footstepAudio.step(kind,material:material,surface:surface,wading:wading)}
        guard let plan else {return}
        once(plan.sample,rate:Float(plan.rate),gain:Float(plan.gain),start:plan.start)
    }

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

    func vehicleContacts(_ collisions:[NativeVehicleDamageController.Collision],body:NativeVehicleDamage.Body) {
        guard !suspended,let contactAudio else{return}
        let slide=max(simd_length(body.move),simd_length(body.turn))
        for collision in collisions {
            let mine=contactAudio.carMaterial(other:collision.material,normal:collision.normal,up:body.up)
            let point=SwiftRapierWorld.rapierToGTA(SIMD3<Float>(collision.point))
            playContacts(contactAudio.crash(id:"world:\(collision.material)",impact:collision.impact,
                position:SIMD3<Double>(point),mine:mine,other:collision.material,slide:slide))
        }
    }

    func updateContacts(delta:Double) {
        guard !suspended,let contactAudio else{return}
        playContacts(contactAudio.update(delta:delta))
    }

    private func playContacts(_ events:[NativeContactAudio.Event]) {
        for event in events {
            let prefix="contact:"+event.id
            if event.kind=="drop" {vehicleLoops.apply(.init(layers:[]),prefix:prefix);continue}
            let point=SIMD3<Double>(SwiftRapierWorld.gtaToRapier(SIMD3<Float>(event.position)))
            let panner=NativeVehicleAudioSpatial.Panner(reference:event.near,maximum:event.reach,rolloff:1.6)
            var layer=NativeVehicleAudioDynamics.Layer(name:"sound",sound:event.sample,rate:event.rate,gain:event.gain)
            layer.startFraction=event.start
            if event.kind=="hold" {applyVehiclePlan(.init(layers:[layer]),prefix:prefix,position:point,panner:panner);continue}
            let received=ProcessInfo.processInfo.systemUptime
            let play={ [weak self] in
                guard let self,!self.suspended else{return}
                self.fetch(event.sample) { [weak self] bytes in
                    guard let self,!self.suspended,let bytes,
                          ProcessInfo.processInfo.systemUptime-received<event.delay+0.5 else{return}
                    if !self.registeredVehicleSamples.contains(event.sample) {
                        guard self.vehicleLoops.register(bytes,name:event.sample,loopStart:self.samples[event.sample]?.loop ?? -1) else{return}
                        self.registeredVehicleSamples.insert(event.sample)
                    }
                    self.applyVehiclePlan(.init(layers:[layer]),prefix:"contact-once:"+UUID().uuidString,position:point,panner:panner)
                }
            }
            if event.delay>0 {DispatchQueue.main.asyncAfter(deadline:.now()+event.delay,execute:play)}else{play()}
        }
    }

    func updateFlightPacks(_ voices:[NativeWorldRenderer.FlightAudioVoice],delta:Double) {
        guard !suspended else{return}
        let seen=Set(voices.map(\.id))
        for voice in voices {
            guard let sound=streamSounds[voice.sound] else{continue}
            flightPackIdle[voice.id]=0
            let layer=NativeVehicleAudioDynamics.Layer(name:"pack",sound:sound.sample,rate:Double(sound.rate),gain:Double(sound.gain))
            let position=SIMD3<Double>(SwiftRapierWorld.gtaToRapier(voice.position))
            applyVehiclePlan(.init(layers:[layer]),prefix:"flight:"+voice.id,position:position,
                             panner:.init(reference:5,maximum:80,rolloff:1.6))
        }
        for id in Array(flightPackIdle.keys) where !seen.contains(id) {
            let idle=flightPackIdle[id] ?? 0
            if idle+delta<0.2 {flightPackIdle[id]=idle+delta}
            else{flightPackIdle.removeValue(forKey:id);vehicleLoops.apply(.init(layers:[]),prefix:"flight:"+id)}
        }
    }

    func collision(severity: Float) {
        // Generic car body impact banks are present in the local archive.
        // Material-specific contact selection still needs collision materials.
        guard severity > 0 else { return }
        once(["39_20", "39_21", "39_22", "39_23", "39_24"].randomElement()!,
             rate: Float.random(in: 0.98...1.02), gain: min(0.8, 0.25 + severity / 100))
    }

    func vehicleHornInput(model:Int?,identity:String?,pressed:Bool,milliseconds:Double)->NativeVehicleHornController.Frame {
        hornController.update(pressed:pressed,milliseconds:milliseconds,identity:identity,emergency:model.map{sirenModels.contains($0)} ?? false)
    }

    func horn(model:Int?,active:Bool,siren:Bool=false) {
        let id = "effect:vehicleHorn"
        if !suspended,siren,let model,sirenModels.contains(model),let sample=sirens[active ? "yelp":"wail"] {
            stopLoop(id);loop("effect:vehicleSiren",sample:sample,rate:1,gain:0.7);return
        }
        stopLoop("effect:vehicleSiren")
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

    /// Module1061 receives the same normalized gearbox/force snapshot as the
    /// browser. Sample-clock playback retains the attack and archived loop tail.
    func updateVehicle(model:Int?,kind:String,speed:Float,throttle:Float,health:Int,delta:Float,
                       snapshot:NativeGroundVehicle.AudioSnapshot? = nil,
                       hull:NativeGroundVehicle.HullAudio? = nil,ear:SIMD3<Float> = .zero) {
        guard !suspended else {return}
        guard let model,health>0 else {if vehicleModel != nil {clearVehicle()};return}
        if model != vehicleModel {clearVehicle();vehicleModel=model;preloadVehicle(model)}
        typealias D=NativeVehicleAudioDynamics
        let time=Double(delta),velocity=snapshot?.speed ?? Double(speed),gas=snapshot?.gas ?? Double(throttle),key=String(model)
        var layers:[D.Layer]=[],retain=Set<String>()
        var up=1.0,nose=0.0,side=0.0,behind=0.5,distance=0.0
        if let body=snapshot?.body {
            let q=simd_quatd(ix:Double(body.rotation.imag.x),iy:Double(body.rotation.imag.y),iz:Double(body.rotation.imag.z),r:Double(body.rotation.real))
            let forward=q.act(SIMD3<Double>(0,0,-1)),right=q.act(SIMD3<Double>(1,0,0)),vertical=q.act(SIMD3<Double>(0,1,0))
            let difference=SIMD3<Double>(body.position)-SIMD3<Double>(SwiftRapierWorld.gtaToRapier(ear))
            distance=simd_length(difference);up=vertical.y;nose=forward.y;side=right.y
            if distance>0.001 {behind=(simd_dot(difference,forward)/distance+1)/2}
        }
        let top=snapshot?.top ?? 40
        if let row=aircraft[key],let type=row.first as? String {
            var input=D.AircraftInput()
            input.rotor=(snapshot?.rotorScalar ?? 0)/0.22;input.throttle=gas;input.health=Double(health)
            input.up=up;input.nose=nose;input.side=side;input.behind=behind;input.away=distance
            let output=D.aircraft(kind:type,bank:(row.count>1 ? row[1] as? NSNumber:nil)?.intValue ?? 0,
                                  input:input,previousPitch:aircraftPitch,delta:time,random:Double.random(in:0..<1))
            aircraftPitch=output.pitch;layers=output.layers
            layers += D.tyres(skid:snapshot?.skid ?? 0,surface:snapshot?.surface ?? 2,flat:false,speed:velocity,top:top)
        } else if let bank=boats[key] {
            layers=boatEngine.update(delta:time,throttle:hull?.gas ?? max(-0.3,gas),afloat:hull?.afloat ?? true,
                                     up:hull?.up ?? 1,distance:distance,speed:velocity,bank:bank.intValue)
            if let hull,let slam=boatEngine.slam(magnitude:hull.slam,time:ProcessInfo.processInfo.systemUptime,distance:distance) {
                once(slam.sound,rate:Float(slam.rate),gain:Float(slam.gain))
            }
        } else if let row=special[key],row.count>1,let type=row[0] as? String,let bank=row[1] as? NSNumber {
            var input=D.SpecialInput()
            input.share=abs(velocity)/max(top,1);input.speed=velocity;input.accel=max(0,gas);input.brake=max(0,-gas)
            input.up=up;input.nose=nose;input.side=side
            if ["rcHeli","rcPlane","hover"].contains(type) {input.rotor=snapshot?.rotorScalar}
            layers=specialEngine.update(delta:time,kind:type,bank:bank.intValue,input:input)
            if type == "golf" {layers += D.tyres(skid:snapshot?.skid ?? 0,surface:snapshot?.surface ?? 2,flat:false,speed:velocity,top:top)}
        } else if let row=trains[key],row.count>1 {
            var input=D.SpecialInput();input.speed=velocity;input.accel=max(0,gas);input.brake=max(0,-gas);input.nose=nose
            layers=specialEngine.train(delta:time,brakeBank:row[0].intValue,engineBank:row[1].intValue,input:input)
        } else if let row=road[key],row.count>=6 {
            var input=D.RoadInput();input.id=model;input.speed=velocity;input.accel=max(0,gas);input.brake=max(0,-gas)
            input.box=D.Box.fallback(top:max(top,1));input.gear=min(5,1+Int(floor(abs(velocity)/max(top,1)*5)))
            if let heard=snapshot?.heard {
                input.box=D.Box(gears:heard.box.gears.map{D.Gear(max:$0.max,up:$0.up,down:$0.down)},
                                count:heard.box.count,max:heard.box.max,reverse:heard.box.reverse)
                input.gear=max(0,min(heard.box.count,heard.gear));input.accel=heard.accel;input.brake=heard.brake
                input.handbrake=heard.handbrake;input.grounded=heard.grounded;input.spin=heard.spin;input.climb=heard.climb
                input.bike=heard.bike;input.lean=heard.lean
            }
            input.nitro=snapshot?.nitro ?? false
            let sample=samples["\(row[0].intValue)_0"]
            let rate=Double(sample?.rate ?? 1),duration=Double(sample?.frames ?? 1)/rate,loopStart=Double(max(0,sample?.loop ?? 0))/rate
            let output=roadEngine.update(delta:time,input:input,runUpDuration:duration,loopStart:loopStart)
            let plan=D.roadPlan(output,runUpBank:row[0].intValue,idleBank:row[1].intValue,
                                pitch:row[2].doubleValue == 0 ? 1:row[2].doubleValue,gainDB:row[3].doubleValue)
            layers=plan.layers;retain=plan.retain
            if let reverse=reverseEngine.update(delta:time,gas:gas,gear:input.gear,speed:velocity,ground:input.grounded,
                                                box:snapshot?.heard != nil && !input.bike ? input.box:nil) {layers.append(reverse)}
            if let sputter=D.sputter(model:model,health:Double(health),speedShare:abs(velocity)/max(top,1),roadEnabled:true) {layers.append(sputter)}
            layers += D.tyres(skid:snapshot?.skid ?? 0,surface:snapshot?.surface ?? 2,flat:snapshot?.flat ?? false,speed:velocity,top:top)
        }
        applyVehiclePlan(D.Plan(layers:layers.filter{$0.gain>0 && $0.rate>0.01},retain:retain))
    }

    private func preloadVehicle(_ model:Int) {
        let key=String(model)
        var names:[String]=[]
        if let row=road[key],row.count>=2 {
            names += (0...2).map{"\(row[0].intValue)_\($0)"}+(0...1).map{"\(row[1].intValue)_\($0)"}
        }
        if let row=aircraft[key],row.count>1,let bank=row[1] as? NSNumber {names += [0,1,3].map{"\(bank.intValue)_\($0)"}}
        if let bank=boats[key] {names.append("\(bank.intValue)_0")}
        if let row=special[key],row.count>1,let bank=row[1] as? NSNumber {names.append("\(bank.intValue)_0")}
        if let row=trains[key],row.count>1 {names += ["\(row[0].intValue)_0","\(row[0].intValue)_1","\(row[1].intValue)_0","\(row[1].intValue)_2"]}
        preload(names+["138_2","138_4","138_6","138_8","138_10","138_11","138_17","138_19","138_20","138_24","138_26","39_3","39_66"])
    }

    func updateRemoteVehicles(_ players:[RemotePlayer],ear:SIMD3<Float>,forward:SIMD3<Float>,top:(String)->Double?) {
        guard !suspended else{return}
        typealias D=NativeVehicleAudioDynamics
        typealias S=NativeVehicleAudioSpatial
        let listener=SIMD3<Double>(SwiftRapierWorld.gtaToRapier(ear))
        vehicleLoops.listener(position:listener,forward:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(forward)))
        let catalogue=S.Catalogue(road:Set(road.keys.compactMap(Int.init)),aircraft:Set(aircraft.keys.compactMap(Int.init)),
            boats:Set(boats.keys.compactMap(Int.init)),special:Set(special.keys.compactMap(Int.init)),trains:Set(trains.keys.compactMap(Int.init)))
        let driving=players.filter{!$0.code.hasPrefix("s")}
        let candidates=driving.compactMap { player -> S.Candidate? in
            guard let model=Int(player.code.split(separator:".").first ?? "") else{return nil}
            return .init(id:player.id,model:model,position:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(player.position)),speed:Double(player.speed))
        }
        let selected=S.select(candidates,listener:listener,catalogue:catalogue),ids=Set(selected.map{$0.candidate.id})
        for id in Array(remoteEngines.keys) where !ids.contains(id) {
            remoteEngines.removeValue(forKey:id)
            vehicleLoops.apply(.init(layers:[]),prefix:"remote:"+id)
            vehicleLoops.apply(.init(layers:[]),prefix:"far:"+id)
        }
        let now=ProcessInfo.processInfo.systemUptime
        for selected in selected {
            let candidate=selected.candidate,key=String(candidate.model),prefix="remote:"+candidate.id
            guard let player=driving.first(where:{$0.id==candidate.id}) else{continue}
            if remoteEngines[candidate.id]?.model != candidate.model {
                vehicleLoops.apply(.init(layers:[]),prefix:prefix);vehicleLoops.apply(.init(layers:[]),prefix:"far:"+candidate.id)
                remoteEngines[candidate.id]=RemoteEngine(model:candidate.model,time:now);preloadVehicle(candidate.model)
            }
            let state=remoteEngines[candidate.id]!,delta=max(0,now-state.time);state.time=now
            let y=simd_quatd(angle:-Double(player.heading),axis:SIMD3(0,1,0))
            let x=simd_quatd(angle:Double(player.pitch),axis:SIMD3(1,0,0))
            let z=simd_quatd(angle:-Double(player.roll),axis:SIMD3(0,0,1)),q=y*x*z
            let vertical=q.act(SIMD3<Double>(0,1,0)),ahead=q.act(SIMD3<Double>(0,0,-1)),right=q.act(SIMD3<Double>(1,0,0))
            let offset=candidate.position-listener,distance=selected.distance,speed=candidate.speed
            let behind=distance>0.001 ? (simd_dot(offset,ahead)/distance+1)/2:0.5
            let maximum=top(key) ?? 45,share=min(1,abs(speed)/maximum)
            var layers:[D.Layer]=[],specialKind:String?
            if let row=aircraft[key],let type=row.first as? String {
                var input=D.AircraftInput();input.rotor=type=="heli" ? 1:0.45+0.55*min(1,abs(speed)/40)
                input.up=vertical.y;input.nose=ahead.y;input.side=right.y;input.behind=behind;input.away=distance
                let output=D.aircraft(kind:type,bank:(row.count>1 ? row[1] as? NSNumber:nil)?.intValue ?? 0,input:input,
                                      previousPitch:state.pitch,delta:delta,remote:true,random:Double.random(in:0..<1))
                state.pitch=output.pitch;layers=output.layers.filter{$0.name != "far"}
                let far=output.layers.filter{$0.name=="far" && $0.gain>0 && $0.rate>0.01}
                applyVehiclePlan(.init(layers:far),prefix:"far:"+candidate.id,position:candidate.position,panner:S.panner(kind:.aircraft,far:true))
            } else if let row=special[key],row.count>1,let type=row[0] as? String,let bank=row[1] as? NSNumber {
                specialKind=type
                var input=D.SpecialInput();input.share=abs(speed)/max(maximum,1);input.up=vertical.y;input.nose=ahead.y;input.side=right.y
                layers=state.special.update(delta:delta,kind:type,bank:bank.intValue,input:input)
                if player.horn&1 != 0,row.count>3,let horn=row[2] as? NSNumber,horn.intValue>=0 {
                    let rate=(row[3] as? NSNumber)?.doubleValue ?? 1
                    layers.append(.init(name:"horn",sound:"74_\(horn.intValue)",rate:rate==0 ? 1:rate,gain:0.9))
                }
            } else if let row=trains[key],row.count>1 {
                var input=D.SpecialInput();input.speed=speed;input.mine=false;input.nose=ahead.y
                layers=state.special.train(delta:delta,brakeBank:row[0].intValue,engineBank:row[1].intValue,input:input)
            } else if let bank=boats[key] {
                let gas=state.boat.remoteThrottle(speed:speed,time:now)
                layers=state.boat.update(delta:delta,throttle:gas,afloat:true,up:vertical.y,distance:distance,speed:speed,bank:bank.intValue)
            } else if let row=road[key],row.count>=6 {
                layers=state.road.update(delta:delta,model:candidate.model,share:share,bank:row[1].intValue,
                    pitch:row[2].doubleValue==0 ? 1:row[2].doubleValue,gainDB:row[3].doubleValue)
                if let layer=D.sputter(model:candidate.model,health:Double(player.vehicleHealth),speedShare:share,roadEnabled:true) {layers.append(layer)}
                if player.horn&2 != 0,let sample=sirens[player.horn&1 != 0 ? "yelp":"wail"] {
                    layers.append(.init(name:"siren",sound:sample,rate:1,gain:0.9))
                } else if player.horn&1 != 0,row[4].intValue>=0 {
                    layers.append(.init(name:"horn",sound:"74_\(row[4].intValue)",rate:row[5].doubleValue==0 ? 1:row[5].doubleValue,gain:0.9))
                }
            }
            applyVehiclePlan(.init(layers:layers.filter{$0.gain>0 && $0.rate>0.01}),prefix:prefix,
                             position:candidate.position,panner:S.panner(kind:selected.kind,special:specialKind))
        }
    }

    private func applyVehiclePlan(_ plan:NativeVehicleAudioDynamics.Plan,prefix:String="mine",position:SIMD3<Double>?=nil,panner:NativeVehicleAudioSpatial.Panner?=nil) {
        for layer in plan.layers where !registeredVehicleSamples.contains(layer.sound) {
            guard let bytes=data[layer.sound] else {if requests[layer.sound]==nil {fetch(layer.sound){_ in}};continue}
            if vehicleLoops.register(bytes,name:layer.sound,loopStart:samples[layer.sound]?.loop ?? -1) {registeredVehicleSamples.insert(layer.sound)}
        }
        vehicleLoops.apply(plan,prefix:prefix,gain:Double(volume),spatialPosition:position,panner:panner)
    }

    private func clearVehicle() {
        vehicleLoops.apply(.init(layers:[]),prefix:"mine")
        vehicleModel=nil;aircraftPitch = -1
        roadEngine.reset();reverseEngine.reset();boatEngine.reset();specialEngine.reset()
    }

    private func stopLoop(_ id:String) {
        loops.remove(id);vehicleLoops.stop("held:"+id)
    }

    private func loop(_ id:String,sample name:String,rate:Float,gain:Float,pan:Float=0) {
        guard !suspended,samples[name] != nil,gain>0.001,rate>0 else {stopLoop(id);return}
        guard let bytes=data[name] else {
            if requests[name]==nil {fetch(name){_ in}}
            return
        }
        if !registeredVehicleSamples.contains(name) {
            guard vehicleLoops.register(bytes,name:name,loopStart:samples[name]?.loop ?? -1) else {return}
            registeredVehicleSamples.insert(name)
        }
        let layer=NativeVehicleAudioDynamics.Layer(name:id,sound:name,rate:Double(rate),gain:Double(gain*volume))
        if vehicleLoops.play(layer,id:"held:"+id,forceLoop:true,pan:Double(pan)) {loops.insert(id);vehicleLoops.start()}
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
