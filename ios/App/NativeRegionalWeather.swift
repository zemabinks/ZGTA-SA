import Foundation
import simd

/// Literal regional weather clock and override-release state from vE.at/pick
/// in the archived public client. Uses real/site epoch time, not the game day.
final class NativeRegionalWeather {
    struct State {
        let from: Int
        let to: Int
        let blend: Float
    }
    private struct Document: Decodable { let sequences: [String:[Int]] }
    enum Error: Swift.Error { case invalidSequences }
    private var sequences: [String:[Int]] = [:]
    private var request: URLSessionDataTask?
    private var from = 0,to = 0
    private var blend: Double = 0
    private var lastMinute: Double = -1
    private var lastAutomatic: Int?
    private var release: Double = 0
    var isLoaded: Bool { !sequences.isEmpty }
    init() {}
    convenience init(data: Data) throws { self.init();try install(data) }
    deinit { request?.cancel() }
    func load(server: ServerAddress,completion: (() -> Void)? = nil) {
        request?.cancel()
        request = URLSession.shared.dataTask(with: server.path("game/native/environment.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { guard let self,(try? self.install(data)) != nil else { return };completion?() }
        };request?.resume()
    }
    private func install(_ data: Data) throws {
        let document = try JSONDecoder().decode(Document.self,from: data)
        guard ["la","sf","lv","desert","country"].allSatisfy({ name in
            guard let sequence = document.sequences[name] else { return false }
            return !sequence.isEmpty && sequence.allSatisfy({ (0..<23).contains($0) })
        }) else { throw Error.invalidSequences }
        sequences = document.sequences
    }
    static func region(x: Float,y: Float) -> String {
        if x > 1000 && y > 910 { return "lv" }
        if x > -850 && x < 1000 && y > 1280 { return "desert" }
        if x < -1430 && y > -580 && y < 1430 { return "sf" }
        if x > 250 && x < 3000 && y > -3000 && y < -850 { return "la" }
        return "country"
    }
    private func automatic(epochMilliseconds: Double,x: Float,y: Float) {
        let minute = floor(epochMilliseconds/60000)
        let list = sequences[Self.region(x: x,y: y)]!
        if minute != lastMinute {
            from = minute == lastMinute+1 ? to : list[Int(minute.truncatingRemainder(dividingBy: Double(list.count)))]
            to = list[Int((minute+1).truncatingRemainder(dividingBy: Double(list.count)))]
            lastMinute = minute
        }
        blend = epochMilliseconds/60000-minute
    }
    /// Public vE.at counterpart, also used to select a destination when an
    /// explicit server override is released back to the regional clock.
    func at(epochMilliseconds: Double,position: SIMD2<Float>) -> State? {
        guard isLoaded,epochMilliseconds.isFinite,epochMilliseconds >= 0,position.x.isFinite,position.y.isFinite else { return nil }
        automatic(epochMilliseconds: epochMilliseconds,x: position.x,y: position.y)
        return State(from: from,to: to,blend: Float(blend))
    }
    /// Setting automatic false uses the manual controller's existing weather
    /// transition. Leaving a fully blended automatic state crossfades over 4 s;
    /// a manual transition already in progress supersedes that release.
    func pick(automatic enabled: Bool,epochMilliseconds: Double = Date().timeIntervalSince1970*1000,
              position: SIMD2<Float>,manualFrom: Int,manualTo: Int,manualBlend: Float,delta: Float) -> State {
        guard isLoaded,epochMilliseconds.isFinite,epochMilliseconds >= 0,
              position.x.isFinite,position.y.isFinite,delta.isFinite else {
            return State(from: manualFrom,to: manualTo,blend: manualBlend)
        }
        if enabled {
            automatic(epochMilliseconds: epochMilliseconds,x: position.x,y: position.y)
            lastAutomatic = to;release = 0
        } else {
            lastMinute = -1;from = manualFrom;to = manualTo;blend = Double(manualBlend)
            if let lastAutomatic {
                release += Double(delta)/4
                if release >= 1 || manualBlend < 1 { self.lastAutomatic = nil }
                else { from = lastAutomatic;blend = release }
            }
        }
        return State(from: from,to: to,blend: Float(blend))
    }
}
