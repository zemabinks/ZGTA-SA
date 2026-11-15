import AVFoundation
import Foundation
import UIKit

/// Original public station program with native PCM playback. Owner recordings
/// remain on the Mac and are decoded lazily by native_radio_server.js.
final class NativeVehicleRadio {
    private struct Station { let name: String; let file: String }
    private struct Track: Decodable { let id: Int; let url: String }
    private struct Song: Decodable { let name: String; let url: String }
    private struct Index: Decodable { let stations: [[Track]]; let adverts: [Track]; let songs: [Song] }
    private let server: ServerAddress
    private let stations: [Station] = [
        Station(name: "Playback FM", file: "CH"), Station(name: "K-Rose", file: "CO"),
        Station(name: "K-DST", file: "CR"), Station(name: "Bounce FM", file: "DS"),
        Station(name: "SF-UR", file: "HC"), Station(name: "Radio Los Santos", file: "MH"),
        Station(name: "Radio X", file: "MR"), Station(name: "CSR 103.9", file: "NJ"),
        Station(name: "K-Jah West", file: "RE"), Station(name: "Master Sounds 98.3", file: "RG"),
        Station(name: "WCTR", file: "TK"), Station(name: "User Track Player", file: "USER")
    ]
    private var program: NativeRadioProgram?
    private var tracks: [Int: URL] = [:]
    private var songs: [Song] = [], songOrder: [Int] = []
    private var songOffset = 0
    private var pcm: NativeRadioPlayback?
    private var player: AVPlayer?
    private var itemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var request: URLSessionDataTask?
    private var programRequest: URLSessionDataTask?
    private var indexRequest: URLSessionDataTask?
    private var generation = 0
    private var positions: [Int: Double] = [:]
    private var notifications: [NSObjectProtocol] = []
    private var wantsPlayback = false, interrupted = false
    private var loadedIndex: Int?
    private var dial: DispatchWorkItem?
    private var vehicleModel: Int?, specialStation: Int?
    private var vehicleType = 0
    private var following = false
    private var remembered: (station: Int, at: Double)?
    private var timeAnchor: (milliseconds: Double, uptime: Double)?
    private(set) var index = -1
    var onStatus: ((String) -> Void)?
    var stationID: Int { specialStation ?? (index < 0 ? 13 : index + 1) }
    var stationName: String { specialStation == 0 ? "RADIO" : index < 0 ? "RADIO OFF" : stations[index].name.uppercased() }
    var volume: Float = 0.6 {
        didSet { player?.volume = max(0, min(1, volume)); pcm?.volume = volume }
    }
    private var preferenceKey: String { "ZGTA.radio.\(server.path("").absoluteString)" }

    init(server: ServerAddress) {
        self.server = server
        if let saved = UserDefaults.standard.object(forKey: preferenceKey) as? Int,
           saved >= -1, saved < stations.count { index = saved }
        installNotifications()
        loadProgram()
    }
    deinit {
        request?.cancel(); programRequest?.cancel(); indexRequest?.cancel(); dial?.cancel()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        player?.pause()
    }
    private func installNotifications() {
        let center = NotificationCenter.default
        notifications = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                self.interrupted = type == .began
                if self.interrupted { self.player?.pause(); self.pcm?.stop() }
                else if self.wantsPlayback { self.tune() }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.interrupted = true; self?.player?.pause(); self?.pcm?.stop()
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }; self.interrupted = false
                if self.wantsPlayback { self.tune() }
            }
        ]
    }
    func next() {
        guard vehicleType == 0 || vehicleType == 2 else { return }
        let choices = following ? Array(1...11) + [13] : tracks.isEmpty && !songs.isEmpty ? [12, 13] : Array(1...13)
        let selected = choices[((choices.firstIndex(of: stationID) ?? 0) + 1) % choices.count]
        specialStation = nil
        index = selected == 13 ? -1 : selected - 1
        UserDefaults.standard.set(index, forKey: preferenceKey)
        wantsPlayback = index >= 0
        dial?.cancel(); releasePlayback()
        onStatus?(index < 0 ? "RADIO OFF" : "TUNING \(stationName)")
        let work = DispatchWorkItem { [weak self] in self?.tune() }
        dial = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
    func stop() {
        if vehicleType == 0 || vehicleType == 2 { remembered = (stationID, ProcessInfo.processInfo.systemUptime) }
        vehicleModel = nil; following = false; dial?.cancel(); dial = nil; wantsPlayback = false
        releasePlayback()
    }
    func resume() {
        vehicleType = 0; wantsPlayback = index >= 0
        if index >= 0 { tune() }
    }
    /// The original model classification includes ordinary, off-only and
    /// emergency vehicles. Known models should use this instead of resume().
    func enter(model: Int, followedStation: Int? = nil) {
        vehicleModel = model
        following = followedStation != nil
        guard let program else { resume(); return }
        let defaults = program.defaultStation(model: model)
        vehicleType = defaults.type
        var selected = defaults.station
        if vehicleType == 3 { selected = 0 }
        else if vehicleType != 0 && vehicleType != 2 { selected = 13 }
        else if let followedStation, (1...11).contains(followedStation) || followedStation == 13 { selected = followedStation }
        else if vehicleType == 0, let remembered, ProcessInfo.processInfo.systemUptime - remembered.at < 60,
                remembered.station != defaults.station { selected = remembered.station }
        if tracks.isEmpty && !songs.isEmpty && (1...11).contains(selected) { selected = 12 }
        specialStation = selected == 0 ? 0 : nil
        index = (1...12).contains(selected) ? selected - 1 : -1
        wantsPlayback = selected != 13
        tune()
    }
    func synchronize(milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        timeAnchor = (milliseconds, ProcessInfo.processInfo.systemUptime)
    }
    private func now() -> Double {
        if let anchor = timeAnchor { return anchor.milliseconds + (ProcessInfo.processInfo.systemUptime - anchor.uptime) * 1_000 }
        return Date().timeIntervalSince1970 * 1_000
    }
    private func releasePlayback() {
        generation += 1; pcm?.stop(); pcm = nil; request?.cancel(); request = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
        itemObservation = nil
        if let loadedIndex, let seconds = player?.currentTime().seconds,
           seconds.isFinite, seconds >= 0 { positions[loadedIndex] = seconds }
        player?.pause(); player = nil; loadedIndex = nil
    }
    private func loadProgram() {
        programRequest = URLSession.shared.dataTask(with: server.path("game/native/radio.program.json")) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let value = try? NativeRadioProgram(data: data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }; self.program = value
                if let model = self.vehicleModel { self.enter(model: model) }
                else if self.wantsPlayback { self.tune() }
            }
        }
        indexRequest = URLSession.shared.dataTask(with: server.path("game/radio/native/index")) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let value = try? JSONDecoder().decode(Index.self, from: data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }; self.tracks.removeAll()
                for track in value.stations.flatMap({ $0 }) + value.adverts {
                    if let url = self.audioURL(track.url) { self.tracks[track.id] = url }
                }
                self.songs = value.songs.filter { self.audioURL($0.url) != nil }
                self.songOrder = Array(self.songs.indices).shuffled()
                if let model = self.vehicleModel { self.enter(model: model) }
                else if self.wantsPlayback { self.tune() }
            }
        }
        programRequest?.resume(); indexRequest?.resume()
    }
    private func audioURL(_ relative: String) -> URL? {
        guard let url = URL(string: relative, relativeTo: server.url)?.absoluteURL,
              url.scheme == server.url.scheme, url.host == server.url.host, url.port == server.url.port,
              url.path.hasPrefix("/game/radio/"), url.user == nil, url.password == nil else { return nil }
        return url
    }
    private func tune() {
        releasePlayback()
        guard stationID != 13 else { onStatus?("RADIO OFF"); return }
        guard !interrupted, wantsPlayback else { return }
        if stationID <= 11, let program, !tracks.isEmpty {
            let playback = NativeRadioPlayback(program: program, tracks: tracks, clock: { [weak self] in
                self?.now() ?? Date().timeIntervalSince1970 * 1_000
            })
            playback.volume = volume
            playback.onFailure = { [weak self] in self?.onStatus?("RADIO: OWNER AUDIO COULD NOT PLAY") }
            do { try playback.start(station: stationID); pcm = playback; onStatus?("NOW PLAYING \(stationName)") }
            catch { onStatus?("RADIO AUDIO COULD NOT START") }
            return
        }
        if stationID == 12 && !songs.isEmpty { playUserSong(token: generation); return }
        let station = specialStation == 0 ? Station(name: "RADIO", file: "AA") : stations[index]
        onStatus?("TUNING \(station.name.uppercased())")
        tryFormat(station: station, formats: ["mp3", "m4a", "wav"], token: generation)
    }
    private func playUserSong(token: Int) {
        guard !songOrder.isEmpty else { return }
        let song = songs[songOrder[songOffset % songOrder.count]]
        guard let url = audioURL(song.url) else { return }
        play(url: url, token: token, tuningIndex: index, title: song.name.uppercased(), userSong: true)
    }
    private func play(url: URL, token: Int, tuningIndex: Int, title: String, userSong: Bool = false) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item); player?.volume = max(0, min(1, volume)); loadedIndex = tuningIndex
        onStatus?("LOADING \(title)")
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                switch item.status {
                case .readyToPlay:
                    if let seconds = self.positions[tuningIndex], seconds > 0 {
                        let duration = item.duration.seconds
                        let target = duration.isFinite && duration > 0 ? seconds.truncatingRemainder(dividingBy: duration) : seconds
                        self.player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                    }
                    if self.wantsPlayback && !self.interrupted { self.player?.play() }
                    self.onStatus?("NOW PLAYING \(title)")
                case .failed: self.onStatus?("\(title): AUDIO COULD NOT PLAY")
                default: break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self, token == self.generation else { return }
            self.positions[tuningIndex] = 0
            if userSong {
                self.songOffset += 1; self.releasePlayback(); self.positions[tuningIndex] = 0
                if self.wantsPlayback { self.playUserSong(token: self.generation) }
            } else {
                self.player?.seek(to: .zero)
                if self.wantsPlayback && !self.interrupted { self.player?.play() }
            }
        }
    }
    private func tryFormat(station: Station, formats: [String], token: Int) {
        guard token == generation else { return }
        guard let format = formats.first else {
            onStatus?("\(station.name.uppercased()): ADD LOCAL RADIO AUDIO ON YOUR MAC"); return
        }
        let url = server.path("game/radio/custom/\(station.file).\(format)"), tuningIndex = index
        var head = URLRequest(url: url); head.httpMethod = "HEAD"
        request = URLSession.shared.dataTask(with: head) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    self.play(url: url, token: token, tuningIndex: tuningIndex, title: station.name.uppercased())
                } else { self.tryFormat(station: station, formats: Array(formats.dropFirst()), token: token) }
            }
        }
        request?.resume()
    }
}
