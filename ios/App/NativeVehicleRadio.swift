import AVFoundation
import Foundation

/// Station tuning stays native. Music is streamed only from files supplied in
/// the Mac's ignored local-only/game/radio/custom directory.
final class NativeVehicleRadio {
    private struct Station {
        let name: String
        let file: String
    }

    private let server: ServerAddress
    private let stations: [Station] = [
        Station(name: "Playback FM", file: "CH"),
        Station(name: "K-Rose", file: "CO"),
        Station(name: "K-DST", file: "CR"),
        Station(name: "Bounce FM", file: "DS"),
        Station(name: "SF-UR", file: "HC"),
        Station(name: "Radio Los Santos", file: "MH"),
        Station(name: "Radio X", file: "MR"),
        Station(name: "CSR 103.9", file: "NJ"),
        Station(name: "K-Jah West", file: "RE"),
        Station(name: "Master Sounds 98.3", file: "RG"),
        Station(name: "WCTR", file: "TK"),
        Station(name: "User Track Player", file: "USER")
    ]
    private var player: AVPlayer?
    private var itemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var request: URLSessionDataTask?
    private var generation = 0
    private(set) var index = -1
    var onStatus: ((String) -> Void)?
    var stationName: String { index < 0 ? "RADIO OFF" : stations[index].name.uppercased() }

    init(server: ServerAddress) { self.server = server }

    func next() {
        index = index + 1 >= stations.count ? -1 : index + 1
        tune()
    }

    func stop() {
        generation += 1
        request?.cancel()
        request = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        itemObservation = nil
        player?.pause()
        player = nil
    }

    func resume() {
        if index >= 0 { tune() }
    }

    private func tune() {
        stop()
        guard index >= 0 else { onStatus?("RADIO OFF"); return }
        let station = stations[index]
        let token = generation
        onStatus?("TUNING \(station.name.uppercased())")
        // Each station can be an owner-provided MP3 or M4A. HEAD avoids pulling
        // an entire music file merely to check whether it exists.
        tryFormat(station: station, formats: ["mp3", "m4a", "wav"], token: token)
    }

    private func tryFormat(station: Station, formats: [String], token: Int) {
        guard token == generation else { return }
        guard let format = formats.first else {
            onStatus?("\(station.name.uppercased()): ADD LOCAL RADIO AUDIO ON YOUR MAC")
            return
        }
        let url = server.path("game/radio/custom/\(station.file).\(format)")
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        request = URLSession.shared.dataTask(with: head) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    let item = AVPlayerItem(url: url)
                    self.player = AVPlayer(playerItem: item)
                    self.onStatus?("LOADING \(station.name.uppercased())")
                    self.itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            guard let self, token == self.generation else { return }
                            switch item.status {
                            case .readyToPlay:
                                self.player?.play()
                                self.onStatus?("NOW PLAYING \(station.name.uppercased())")
                            case .failed:
                                self.onStatus?("\(station.name.uppercased()): AUDIO COULD NOT PLAY")
                            default: break
                            }
                        }
                    }
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                            self?.player?.seek(to: .zero)
                            self?.player?.play()
                        }
                } else {
                    self.tryFormat(station: station, formats: Array(formats.dropFirst()), token: token)
                }
            }
        }
        request?.resume()
    }
}
