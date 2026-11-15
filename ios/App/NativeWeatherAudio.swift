import Foundation

/// Original fixed-30-Hz weather voice mixer, separated from audio devices so
/// its stereo loop changes, gains, pitches and fades can be replayed exactly.
final class NativeWeatherAudio {
    struct Event {
        var kind: String
        var id: String = ""
        var sample: String = ""
        var rate: Double = 1
        var gain: Double = 0
        var pan: Double = 0
        var rise: Double = 0
        var samples: [String] = []
    }
    private struct Band { var first = true;var swapAt: Double = 0;let pan: Double }
    private var bands = [Band(pan:-0.906),Band(pan:0.906)]
    private var warmed = false,stormWarmed = false,raining = false,blowing = false,storm = false
    private var rainDb: Double = -100,lastRainDb: Double = -100,windDb: Double = -100,lastWindDb: Double = -100
    private var gust = false,windRate: Double = 1,lastWindRate: Double = 1,stormDb: Double = -100
    private var nextRain = 2,stormUpdates = 0
    var onEvents: (([Event]) -> Void)?
    var active: Bool { raining || blowing || storm }
    private func approach(_ value: Double,_ target: Double,_ step: Double) -> Double {
        value < target ? min(target,value+step) : max(target,value-step)
    }
    static func gain(_ db: Double) -> Double { db <= -50 ? 0 : pow(10,(db-6)/20) }
    func stop() {
        var events: [Event] = []
        for index in bands.indices {
            if raining { for suffix in ["a","b"] { events.append(Event(kind:"drop",id:"weather:rain\(index)\(suffix)")) } }
            if blowing { events.append(Event(kind:"drop",id:"weather:wind\(index)")) }
        }
        if storm { events.append(Event(kind:"drop",id:"weather:storm")) }
        raining = false;blowing = false;storm = false
        rainDb = -100;lastRainDb = -100;windDb = -100;lastWindDb = -100;stormDb = -100
        if !events.isEmpty { onEvents?(events) }
    }
    func thunder(durationTicks: Int,serial: Int) {
        let gain = min(1,Self.gain(20*log10(0.0375*Double(durationTicks)+0.25)+4))
        let pitch = [1.15,1,0.85][max(0,serial)%3],rise: Double = durationTicks >= 20 ? 0.1 : 0.6
        var events: [Event] = []
        for (pan,rate) in zip([-0.906,0.906],[0.35636,0.4]) {
            events.append(Event(kind:"once",sample:"52_4",rate:pitch*rate,gain:gain,pan:pan,rise:rise))
            events.append(Event(kind:"once",sample:"52_1",rate:pitch*rate,gain:gain,pan:pan))
        }
        onEvents?(events)
    }
    func step(milliseconds: Double,outdoors: Bool,altitude: Double,rain: Double,wind: Double,sand: Double,
              random: () -> Double = { Double.random(in:0..<1) }) {
        var events: [Event] = []
        func hold(_ id: String,_ sample: String,_ db: Double,_ pan: Double,_ rate: Double = 1) {
            events.append(Event(kind:"hold",id:id,sample:sample,rate:rate,gain:Self.gain(db),pan:pan))
        }
        func drop(_ id: String) { events.append(Event(kind:"drop",id:id)) }
        if !warmed && (rain > 0 || wind > 0) {
            warmed = true
            events.append(Event(kind:"ready",samples:["105_1","105_0","59_29","59_30","52_4","52_1"]+(2...11).map { "105_\($0)" }))
        }
        let target = rain > 0.2 && outdoors ? -12+20*log10((rain-0.2)/0.8) : -100
        if target > -100 { rainDb = max(rainDb,-50) }
        rainDb = approach(rainDb,target,0.5)
        if target == -100 && rainDb <= -50 {
            if raining { for index in bands.indices { drop("weather:rain\(index)a");drop("weather:rain\(index)b") } }
            raining = false;rainDb = -100;lastRainDb = -100
        } else {
            let changed = abs(rainDb-lastRainDb) >= 0.5 || !raining
            for index in bands.indices {
                let swap = milliseconds > bands[index].swapAt
                if swap {
                    bands[index].first.toggle();bands[index].swapAt = milliseconds+65+random()*285
                    if raining {
                        nextRain = nextRain+1 > 11 ? 2 : nextRain+1
                        events.append(Event(kind:"once",sample:"105_\(nextRain)",gain:Self.gain(rainDb-15-6+random()*12),pan:bands[index].pan))
                    }
                }
                if swap || changed {
                    hold("weather:rain\(index)a","105_1",bands[index].first ? rainDb : -100,bands[index].pan)
                    hold("weather:rain\(index)b","105_0",bands[index].first ? -100 : rainDb,bands[index].pan)
                }
            }
            if changed { lastRainDb = rainDb };raining = true
        }
        let altitudeShare = min(1,max(0,altitude/500))
        let lower = altitudeShare < 0.3 ? altitudeShare/0.3*0.4 : 0.4+(altitudeShare-0.3)/0.7*0.1
        let upper = altitudeShare < 0.3 ? 0.5+altitudeShare/0.3*0.5 : 1
        let strength = lower+(upper-lower)*min(wind,1)
        if random() < 0.07 { gust.toggle() }
        if outdoors && strength > 0.15 {
            windDb = approach(max(windDb,-50),-33+(gust ? 21*strength : 0),0.6)
            windRate = approach(windRate,max(1,gust ? 1.2*strength : 0),0.1)
            if abs(windDb-lastWindDb) >= 0.6 || windRate != lastWindRate || !blowing {
                for index in bands.indices { hold("weather:wind\(index)",["59_29","59_30"][index],windDb,bands[index].pan,windRate) }
                lastWindDb = windDb;lastWindRate = windRate
            }
            blowing = true
        } else if blowing {
            for index in bands.indices { drop("weather:wind\(index)") }
            blowing = false;windDb = -100;lastWindDb = -100
        }
        if sand > 0 && !stormWarmed { stormWarmed = true;events.append(Event(kind:"ready",samples:["t167"])) }
        if sand > 0 && outdoors { stormDb = storm ? min(log10(sand),stormDb+1) : -34;storm = true }
        else if storm {
            stormDb -= 0.4
            if stormDb <= -40 { drop("weather:storm");storm = false;stormDb = -100 }
        }
        if storm {
            let update = stormDb < -0.5 || stormUpdates%10 == 0
            if stormDb >= -0.5 { stormUpdates += 1 }
            if update { hold("weather:storm","t167",stormDb,0) }
        }
        if !events.isEmpty { onEvents?(events) }
    }
}
