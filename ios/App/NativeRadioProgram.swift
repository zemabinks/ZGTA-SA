import Foundation

/// Sample-clock translation of public module19737.mY. Program data is served
/// by the owner's Mac; no station recordings are included in this source.
final class NativeRadioProgram {
    struct Piece: Equatable, Codable {
        let id: Int
        let kind: String
        let song: Int
        let at: Int
        let plays: Int
    }
    struct Cursor: Equatable, Codable {
        let station: Int
        let day: Int
        let index: Int
        let piece: Piece
        let into: Int
    }
    struct Song: Decodable {
        let middle: Int
        let intro: [Int]
        let outro: [Int]
        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            middle = try values.decode(Int.self)
            intro = try values.decode([Int].self)
            outro = try values.decode([Int].self)
        }
    }
    struct Station: Decodable {
        let songs: [Song]
        let idents: [Int]?
        let talk: [String: [Int]?]
        let noAdverts: [Int]
    }
    struct Name: Decodable { let pack: String?; let name: String? }
    struct Document: Decodable {
        let rate: Int
        let samples: [Int]
        let stations: [Station]
        let adverts: [Int]
        let vehicleDefaults: [String: [Int]]
        let stationNames: [Name]
        let rain: [Int]
        let sun: [Int]
        let fog: [Int]
        let stationRegions: [String: String]
        let talkShowGroups: [[Int]]
        let weather: [String: [Int]]
    }
    enum Failure: Error { case invalidProgram }
    let document: Document
    var rate: Int { document.rate }
    private var cache: [String: [Piece]] = [:]

    init(data: Data) throws {
        document = try JSONDecoder().decode(Document.self, from: data)
        let d = document
        func validRange(_ range: [Int]) -> Bool {
            range.count == 2 && range[0] >= 0 && range[0] <= range[1] && range[1] < d.samples.count
        }
        guard (8_000...192_000).contains(d.rate), d.samples.allSatisfy({ $0 >= 0 }),
              d.stations.count == 12, d.stationNames.count == 13,
              validRange(d.adverts), d.weather["la"]?.isEmpty == false,
              d.weather["sf"]?.isEmpty == false, d.weather["desert"]?.isEmpty == false,
              d.stations.allSatisfy({ station in
                  !station.songs.isEmpty && station.songs.allSatisfy {
                      d.samples.indices.contains($0.middle) && validRange($0.intro) && validRange($0.outro)
                          && d.samples[$0.middle] > 0
                  } && (station.idents.map(validRange) ?? true)
                    && station.talk.values.allSatisfy { $0.map(validRange) ?? true }
                    && (d.adverts[0]...d.adverts[1]).contains(where: { !station.noAdverts.contains($0) })
              }), !d.talkShowGroups.isEmpty,
              d.talkShowGroups.allSatisfy({ !$0.isEmpty && $0.allSatisfy { d.stations[11].songs.indices.contains($0) } })
        else { throw Failure.invalidProgram }
    }

    func defaultStation(model: Int) -> (station: Int, type: Int) {
        let values = document.vehicleDefaults[String(model)] ?? [13, -1]
        guard values.count == 2 else { return (13, -1) }
        return (values[1] == 2 ? 13 : values[0], values[1])
    }

    func day(station: Int, day: Int) -> [Piece] {
        guard document.stations.indices.contains(station), day >= 0 else { return [] }
        let key = "\(station):\(day)"
        if let result = cache[key] { return result }
        if cache.count > 30 { cache.removeAll() }
        let result = Builder(document: document, station: station, day: day).build()
        cache[key] = result
        return result
    }

    func at(station: Int, milliseconds: Double) -> Cursor? {
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 8.64e15 else { return nil }
        let dayNumber = Int(floor(milliseconds / 86_400_000))
        let pieces = day(station: station, day: dayNumber)
        guard !pieces.isEmpty else { return nil }
        let sample = max(0, min(86_400 * rate - 1,
            Int(floor((milliseconds - Double(dayNumber) * 86_400_000) * (Double(rate) / 1_000)))))
        var low = 0, high = pieces.count - 1
        while low < high {
            let middle = (low + high + 1) >> 1
            if pieces[middle].at <= sample { low = middle } else { high = middle - 1 }
        }
        return Cursor(station: station, day: dayNumber, index: low, piece: pieces[low], into: sample - pieces[low].at)
    }

    func after(_ cursor: Cursor) -> Cursor? {
        let pieces = day(station: cursor.station, day: cursor.day)
        if pieces.indices.contains(cursor.index + 1) {
            return Cursor(station: cursor.station, day: cursor.day, index: cursor.index + 1,
                          piece: pieces[cursor.index + 1], into: 0)
        }
        guard let first = day(station: cursor.station, day: cursor.day + 1).first else { return nil }
        return Cursor(station: cursor.station, day: cursor.day + 1, index: 0, piece: first, into: 0)
    }

    private final class Builder {
        let document: Document
        let stationID: Int
        let station: Station
        let dayStart: Double
        let total: Int
        var randomState: UInt32
        var pieces: [Piece] = []
        var sample = 0
        var songsSinceTalk = 0
        var recentSongs: [Int] = [], recentIdents: [Int] = [], recentTalk: [Int] = [], recentAdverts: [Int] = []
        var showChoices: [Int]?

        init(document: Document, station: Int, day: Int) {
            self.document = document
            stationID = station
            self.station = document.stations[station]
            dayStart = Double(day) * 86_400_000
            total = 86_400 * document.rate
            randomState = UInt32(truncatingIfNeeded: station + 1) &* 0x9e3779b1
                ^ UInt32(truncatingIfNeeded: day) &* 0x85ebca6b
            if station == 11 {
                showChoices = document.talkShowGroups.map { $0[integer(0, $0.count - 1)] }
            }
        }
        func random() -> Double {
            randomState &+= 0x6d2b79f5
            var value = (randomState ^ (randomState >> 15)) &* (1 | randomState)
            value = (value &+ ((value ^ (value >> 7)) &* (61 | value))) ^ value
            return Double(value ^ (value >> 14)) / 4_294_967_296
        }
        func chance(_ probability: Double) -> Bool { random() < probability }
        func integer(_ low: Int, _ high: Int) -> Int { low + Int(floor(random() * Double(high - low + 1))) }
        func append(_ id: Int, _ kind: String, song: Int = -1) {
            if sample < total { pieces.append(Piece(id: id, kind: kind, song: song, at: sample,
                                                   plays: min(document.samples[id], total - sample))) }
            sample += document.samples[id]
        }
        @discardableResult func remember(_ list: inout [Int], _ id: Int, _ count: Int) -> Bool {
            guard list.first != id else { return false }
            list.insert(id, at: 0)
            if list.count > count { list.removeLast(list.count - count) }
            return true
        }
        func eligible(_ list: [Int], _ id: Int, _ recent: Int, _ count: Int) -> Bool {
            !list.prefix(max(0, min(recent, count - 2))).contains(id)
        }
        func song() {
            var index: Int
            repeat {
                if let choices = showChoices { index = choices[integer(0, choices.count - 1)] }
                else { index = integer(0, station.songs.count - 1) }
            } while showChoices != nil
                ? recentSongs.prefix(showChoices!.count - 1).contains(index)
                : !eligible(recentSongs, index, 20, station.songs.count)
            let value = station.songs[index]
            append(integer(value.intro[0], value.intro[1]), "intro", song: index)
            append(value.middle, "middle", song: index)
            append(integer(value.outro[0], value.outro[1]), "outro", song: index)
            if remember(&recentSongs, index, 20) { songsSinceTalk += 1 }
        }
        func ident() {
            guard let range = station.idents else { return }
            var id: Int
            repeat { id = integer(range[0], range[1]) }
            while (stationID == 6 && id == 1100) || !eligible(recentIdents, id, 8, range[1] - range[0] + 1)
            append(id, "ident")
            remember(&recentIdents, id, 8)
        }
        func selectTalk(_ range: [Int]?) -> Int {
            guard let range else { return -1 }
            let count = range[1] - range[0] + 1, offset = integer(0, count - 1)
            let general = station.talk["general"] ?? nil
            for i in 0..<count {
                let id = range[0] + (i + offset) % count
                if eligible(recentTalk, id, 15, general.map { $0[1] - $0[0] + 1 } ?? 0) { return id }
            }
            return -1
        }
        func maybeTalk(_ kind: String, _ probability: Double) -> Int {
            chance(probability) ? selectTalk(station.talk[kind] ?? nil) : -1
        }
        func talkOrAdvert() {
            var id = -1
            if stationID == 0 { id = selectTalk(station.talk["general"] ?? nil) }
            else if chance(0.6) {
                let now = dayStart + Double(sample) / (Double(document.rate) / 1_000)
                let hour = Int(floor((now / 1_000).truncatingRemainder(dividingBy: 1_440) / 60))
                let weather = document.weather[document.stationRegions[String(stationID)] ?? "la"]!
                let minute = Int(floor(now / 60_000))
                let upcoming = (0..<4).map { weather[(minute + 1 + $0) % weather.count] }
                if document.rain.contains(where: upcoming.contains) { id = maybeTalk("rain", 0.5) }
                else if hour >= 8 && hour < 18 && document.sun.contains(where: upcoming.contains) { id = maybeTalk("sun", 0.5) }
                else if document.fog.contains(where: upcoming.contains) { id = maybeTalk("fog", 0.5) }
                if id == -1 {
                    if hour >= 6 && hour <= 8 { id = maybeTalk("morning", 0.3) }
                    else if hour >= 18 && hour <= 20 { id = maybeTalk("evening", 0.3) }
                    else if hour >= 22 || hour <= 2 { id = maybeTalk("night", 0.3) }
                    if id == -1 { id = selectTalk(station.talk["general"] ?? nil) }
                }
            }
            if id >= 0 {
                append(id, "talk")
                remember(&recentTalk, id, 15)
            } else {
                repeat { id = integer(document.adverts[0], document.adverts[1]) }
                while station.noAdverts.contains(id) || recentAdverts.contains(id)
                append(id, "advert")
                remember(&recentAdverts, id, 40)
            }
            songsSinceTalk = 0
        }
        func build() -> [Piece] {
            song()
            while sample < total {
                if stationID == 0 { talkOrAdvert() }
                else if songsSinceTalk < 2 && chance(0.5) { if chance(0.5) { ident() } }
                else { if chance(0.5) { ident() }; talkOrAdvert() }
                song()
            }
            return pieces
        }
    }
}
