import Foundation
import simd

/// Direct translation of the archived client's module7508 time/color
/// interpolation. The table is served from the Mac and stays outside GitHub.
final class NativeWorldEnvironment {
    struct Conditions {
        let skyTop: SIMD4<Float>
        let skyBottom: SIMD4<Float>
        let waterColor: SIMD4<Float>
        let farClip: Float
        let fogStart: Float
    }

    private struct Document: Decodable {
        let hours: [Float]
        let weatherNames: [String]
        let colors: [[[Float]]]
    }
    enum Error: Swift.Error { case invalidTable }
    private var hours: [Float] = []
    private var colors: [[[Float]]] = []
    private(set) var weatherNames: [String] = []
    private var request: NativeResourceTask?
    var isLoaded: Bool { !colors.isEmpty }

    init() {}

    convenience init(data: Data) throws {
        self.init()
        try install(data)
    }

    deinit { request?.cancel() }

    func load(server: ServerAddress, completion: (() -> Void)? = nil) {
        request?.cancel()
        request = NativeResourceTransport.dataTask(with: server.path("game/native/environment.json")) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async {
                guard let self, (try? self.install(data)) != nil else { return }
                completion?()
            }
        }
        request?.resume()
    }

    private func install(_ data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.hours.count == 8, document.hours.first == 0,
              zip(document.hours, document.hours.dropFirst()).allSatisfy({ $0 < $1 }),
              document.hours.allSatisfy({ $0.isFinite && $0 < 24 }),
              document.weatherNames.count == 23, document.colors.count == 23,
              document.colors.allSatisfy({ weather in
                  weather.count == 8 && weather.allSatisfy { row in
                      row.count == 12 && row.allSatisfy { $0.isFinite }
                  }
              }) else { throw Error.invalidTable }
        hours = document.hours + [24]
        colors = document.colors
        weatherNames = document.weatherNames
    }

    func sample(weatherFrom: Int, to weatherTo: Int, blend: Float,
                hour: Float, altitude: Float) -> Conditions {
        guard isLoaded else {
            return Conditions(skyTop: SIMD4(0.54, 0.70, 0.81, 1),
                              skyBottom: SIMD4(0.7, 0.8, 0.86, 1),
                              waterColor: SIMD4(0.2, 0.4, 0.5, 0.75),
                              farClip: 1000, fogStart: 700)
        }
        let time = hour.isFinite ? max(0, min(23.999, hour)) : 12
        let height = altitude.isFinite ? altitude : 0
        let weatherBlend = blend.isFinite ? max(0, min(1, blend)) : 1
        var bin = 0
        while bin < hours.count - 2 && time >= hours[bin + 1] { bin += 1 }
        let next = (bin + 1) % (hours.count - 1)
        let share = (time - hours[bin]) / (hours[bin + 1] - hours[bin])
        let from = weatherRow(weatherFrom, bin: bin, next: next, share: share, altitude: height)
        let to = weatherRow(weatherTo, bin: bin, next: next, share: share, altitude: height)
        let result = zip(from, to).map { $0 * (1 - weatherBlend) + $1 * weatherBlend }
        var far = result[6]
        if height > 200 && far > 1000 {
            far = height <= 500 ? far + (1000 - far) * ((height - 200) / 300) : 1000
        }
        return Conditions(skyTop: SIMD4(result[0] / 255, result[1] / 255, result[2] / 255, 1),
                          skyBottom: SIMD4(result[3] / 255, result[4] / 255, result[5] / 255, 1),
                          waterColor: SIMD4(result[8] / 255, result[9] / 255,
                                            result[10] / 255, result[11] / 255),
                          farClip: far, fogStart: result[7])
    }

    private func weatherRow(_ weather: Int, bin: Int, next: Int,
                            share: Float, altitude: Float) -> [Float] {
        let id = colors.indices.contains(weather) ? weather : 10
        var result = zip(colors[id][bin], colors[id][next]).map { $0 * (1 - share) + $1 * share }
        // Smog dissipates as the camera rises above the city, matching the
        // public client's altitude blend from weather2/3 to weather0/1.
        if weather == 2 || weather == 3 {
            let clear = weather == 2 ? 0 : 1
            let amount = max(0, min(1, (altitude - 20) / 200))
            let upper = zip(colors[clear][bin], colors[clear][next]).map { $0 * (1 - share) + $1 * share }
            result = zip(result, upper).map { $0 * (1 - amount) + $1 * amount }
        }
        return result
    }

    /// Browser game time advances one game minute per real second. The
    /// server can apply a millisecond shift or hold an explicit epoch value.
    static func gameHour(epochMilliseconds: Double = Date().timeIntervalSince1970 * 1000,
                         shiftMilliseconds: Double = 0, holdMilliseconds: Double? = nil) -> Float {
        let clock = holdMilliseconds ?? (epochMilliseconds + shiftMilliseconds)
        guard clock.isFinite else { return 12 }
        let minute = (clock / 1000).truncatingRemainder(dividingBy: 1440)
        return Float((minute + (minute < 0 ? 1440 : 0)) / 60)
    }

    static func nightShare(hour: Float) -> Float {
        let time = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        if time < 6 || time >= 21 { return 1 }
        if time < 7 { return 7 - time }
        return time < 20 ? 0 : time - 20
    }
}
