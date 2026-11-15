import Foundation

/// Public module1061's vehicle sound planning, independent of audio I/O.
/// Values stay Double until the native playback boundary, as in the browser.
enum NativeVehicleAudioDynamics {
    struct Layer {
        let name: String
        let sound: String
        let rate: Double
        let gain: Double
        var restart = false
        var startFraction = 0.0
    }
    struct Gear: Codable { var max = 0.0, up = 0.0, down = 0.0 }
    struct Box: Codable {
        var gears: [Gear]
        var count: Int
        var max: Double
        var reverse: Double?
        /// Original fallback used only when a vehicle has no handling sample.
        static func fallback(top: Double, count: Int = 5) -> Box {
            let maximum = top / 50, range = 0.5 * maximum / 5
            var gears = Array(repeating: Gear(), count: 6)
            for i in 1...count {
                gears[i].max = Double(i) * (maximum - range) / Double(count) + range
                let span = gears[i].max - gears[i-1].max
                if i >= count { gears[i].up = maximum }
                else { gears[i+1].down = 0.42 * span + gears[i-1].max; gears[i].up = 0.6667 * span + gears[i-1].max }
            }
            gears[1].down = -0.01
            return Box(gears: gears, count: count, max: maximum)
        }
    }
    struct RoadInput: Codable {
        var id = 420
        var speed = 0.0, climb = 0.0, accel = 0.0, brake = 0.0
        var handbrake = false
        var gear = 1
        var box = Box.fallback(top: 40)
        var grounded = 1.0, spin = 0.0, lean = 0.0
        var bike = false, nitro = false
    }
    struct RoadMix {
        var state = 0, gear = 0
        var idle = -Double.infinity, idleRate = 1.0
        var revs = -Double.infinity, revsRate = 1.0
        var runUp = -Double.infinity, runUpRate = 1.0, runUpFrom = -1.0
        var cruise = -Double.infinity, cruiseRate = 1.0
        var fall = -Double.infinity, fallRate = 1.0
    }
    private static let singleGear: Set<Int> = [448,457,462,485,530,539,571,572,574,583]
    private static let idleCurve = [[0.0,0],[0.075,0.7],[0.15,1.1],[0.25,1.25],[1,1.7]]
    static func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double { max(low, min(high, x)) }
    static func mix(_ a: Double, _ b: Double, _ share: Double) -> Double { a + (b-a)*share }
    static func curve(_ points: [[Double]], _ at: Double) -> Double {
        for i in 1..<points.count where at <= points[i][0] {
            return points[i-1][1] + (at-points[i-1][0])/(points[i][0]-points[i-1][0])*(points[i][1]-points[i-1][1])
        }
        return points.last![1]
    }
    static func decibels(_ value: Double) -> Double { pow(10, value/20) }
    struct Plan { let layers: [Layer]; var retain: Set<String> = [] }
    static func roadPlan(_ output: RoadMix, runUpBank: Int, idleBank: Int,
                         pitch: Double = 1, gainDB: Double = 0) -> Plan {
        var layers: [Layer] = []
        let gain = decibels(gainDB)
        for (name, sound, rate, level) in [
            ("idle","\(idleBank)_1",output.idleRate,output.idle),
            ("revs","\(idleBank)_0",output.revsRate,output.revs),
            ("runUp","\(runUpBank)_0",output.runUpRate,output.runUp),
            ("cruise","\(runUpBank)_1",output.cruiseRate,output.cruise),
            ("fall","\(runUpBank)_2",output.fallRate,output.fall)
        ] where level > -.infinity {
            var layer = Layer(name:name,sound:sound,rate:rate*pitch,gain:gain*decibels(level))
            layer.restart = name == "fall" || (name == "runUp" && output.runUpFrom >= 0)
            layer.startFraction = name == "runUp" ? max(0,output.runUpFrom):0
            layers.append(layer)
        }
        return Plan(layers:layers,retain:output.state == 6 && output.fall == -.infinity ? ["fall"]:[])
    }
    static func tyres(skid: Double, surface: Int, flat: Bool, speed: Double, top: Double) -> [Layer] {
        var layers: [Layer] = []
        let skidShare = skid/4
        if skidShare > 0.02 {
            let gravel = surface == 3 || surface == 4, water = surface == 5
            let sound = water ? "138_8":gravel ? "138_6":"138_24"
            let pitch = water || gravel ? 0.9:0.8
            let rate = pitch+(water || gravel ? 0.2:0.125)*skid
            let db: Double = water ? -12:gravel ? -9:0
            layers.append(Layer(name:"tyres",sound:sound,rate:rate,gain:min(1,skidShare)*decibels(db)*0.8))
        }
        let share = flat ? min(1,abs(speed)/(0.3*max(top,1))):0
        if share > 0.01 { layers.append(Layer(name:"flat",sound:"138_4",rate:1+0.4*share,gain:share*decibels(-9))) }
        return layers
    }
    static func sputter(model: Int, health: Double, speedShare: Double, roadEnabled: Bool) -> Layer? {
        guard health > 0, health < 390, roadEnabled,
              !Set([448,461,462,463,468,521,522,523,581,586]).contains(model) else { return nil }
        let share = clamp(abs(speedShare))
        return Layer(name:"sputter",sound:"138_2",rate:0.9+(1.2-0.9)*share,gain:decibels(-24+6*share))
    }
    final class Reverse {
        private var pedal = 0.0, grounded = 0.0
        func reset() { pedal = 0; grounded = 0 }
        func update(delta: Double, gas: Double, gear: Int, speed: Double, ground: Double, box: Box?) -> Layer? {
            let steps = min(5,delta/0.02), target = abs(gas)
            pedal = pedal < target ? min(target,pedal+0.09*steps) : max(target,pedal-0.07*steps)
            let old = grounded; grounded = ground
            guard gas < 0 || gear == 0, let reverse = box?.reverse, reverse != 0 else { return nil }
            if ground == 0 && old != 0 { pedal *= 0.4 }
            let share = abs(ground != 0 ? speed/50/reverse:pedal)
            return Layer(name:"reverse",sound:gas >= 0 ? "138_20":"138_19",rate:0.75+0.2*share,
                         gain:share > 0 ? decibels(-6+20*logarithm(share)):0)
        }
    }
    final class RemoteRoad {
        private var state = 0, fadeIn = 1.0, fadeOut = 1.0
        func reset() { state = 0; fadeIn = 1; fadeOut = 1 }
        func update(delta: Double, model: Int, share: Double, bank: Int,
                    pitch: Double = 1, gainDB: Double = 0) -> [Layer] {
            let steps = min(5,delta/0.02), value = clamp(abs(share))
            let idleShare = clamp(value/0.2), revShare = clamp((value-0.15)/0.85), before = state
            state = value < (before == 2 ? 0.15:0.2) ? 1:2
            let golf = model == 457
            var idleRate = golf ? 1:mix(0.85,1.2,idleShare), idle = golf ? -33:mix(-3,0,idleShare)
            var revsRate = mix(0.9,1.5,revShare), revs = mix(-4.5,0,revShare)
            if before == 0 { fadeIn = 1; fadeOut = 1; if state == 1 { revs = -.infinity } else { idle = -.infinity } }
            else if before != state {
                fadeIn = 0; fadeOut = 0
                if state == 1 { idle += 10*logarithm(0) } else { revs += 20*logarithm(0) }
            } else if state == 1 {
                fadeIn = min(1,fadeIn+0.1*steps); fadeOut = min(1,fadeOut+0.1*steps)
                if fadeIn <= 0.99 && !golf { idle += 10*logarithm(fadeIn) }
                if fadeOut < 0.99 { revs += 10*logarithm(1-fadeOut) } else { revs = -.infinity }
            } else {
                fadeIn = min(1,fadeIn+0.05*steps); fadeOut = min(1,fadeOut+0.05*steps)
                if fadeIn < 0.99 { revsRate *= curve([[0,1],[0.5,1],[0.7,1.2],[0.85,1],[1.0001,1]],fadeIn) }
                if fadeIn <= 0.99 { revs += 20*logarithm(curve([[0,0],[0.3,0],[0.5,0.707],[0.7,1],[1.0001,1]],fadeIn)) }
                if fadeOut < 0.99 {
                    if !golf {
                        idleRate *= curve([[0,1],[0.3,1],[0.5,0.85],[0.7,0.85],[1.0001,0.85]],fadeOut)
                        idle += 20*logarithm(curve([[0,1],[0.3,1],[0.5,1],[0.7,0.707],[1.0001,0]],fadeOut))
                    }
                } else { idle = -.infinity }
            }
            var layers: [Layer] = []
            if idle > -.infinity { layers.append(Layer(name:"idle",sound:"\(bank)_1",rate:idleRate*pitch,gain:decibels(gainDB)*decibels(idle))) }
            if revs > -.infinity { layers.append(Layer(name:"revs",sound:"\(bank)_0",rate:revsRate*pitch,gain:decibels(gainDB)*decibels(revs))) }
            return layers
        }
    }
    private static func logarithm(_ value: Double) -> Double { value >= 1e-5 ? log10(value) : -5 }
    private static func loudness(_ value: Double, _ level: Double = 8) -> Double { value > 1e-5 ? value*decibels(level-9) : 0 }
    private static let attenuation = [[4.5,0],[5,-0.38],[5.5,-2.21],[6,-3.91],[7,-7.01],[8,-9.78],[10,-14.57],[12,-18.65],[16,-25.37],[20,-30.82],[24,-35.43],[32,-43],[40,-49.1],[48,-54.25],[64,-62.65],[80,-69.41],[96,-75.08],[112,-79.98],[128,-84.29]]
    static func distanceDecibels(_ value: Double) -> Double { value <= 4.5 ? 0 : value > 128 ? -100 : curve(attenuation,value) }

    struct AircraftInput: Codable {
        var rotor = 0.0, throttle = 0.0, health = 1_000.0
        var up = 1.0, nose = 0.0, side = 0.0, behind = 0.5, away = 0.0
    }
    static func aircraft(kind: String, bank: Int, input: AircraftInput, previousPitch: Double,
                         delta: Double, remote: Bool = false, random: Double = 0.5) -> (pitch: Double, layers: [Layer]) {
        let rotor = clamp(input.rotor), behind = clamp(input.behind)
        let gas = remote ? 0 : input.throttle > 0.05 ? 0.1 : input.throttle < -0.05 ? -0.05 : 0
        let far = remote && input.away > 48
        func ease(_ target: Double, _ speed: Double) -> Double {
            previousPitch < 0 ? target : previousPitch+clamp(target-previousPitch,-speed*delta,speed*delta)
        }
        if kind == "heli" {
            var target = ((1-input.up)*0.1+1)*curve([[0,0],[0.15,0],[0.38,0.6],[0.63,1],[1,1]],rotor)*(1+gas)
            if input.health < 390 { target *= 0.65+0.19999999999999996*random }
            let pitch = ease(target,rotor <= 0.63 ? 1.5:0.25)
            let gain = curve([[0,0],[0.15,0],[0.38,0.4],[0.63,0.7],[1,1]],rotor)
            var layers = [Layer(name:"front",sound:"\(bank)_0",rate:pitch,gain:loudness((1-0.67*behind)*gain)),
                          Layer(name:"rear",sound:"\(bank)_1",rate:pitch,gain:loudness((0.5*behind+0.5)*gain)),
                          Layer(name:"near",sound:"\(bank)_3",rate:1,gain:loudness(gain,2))]
            if remote { layers.append(Layer(name:"far",sound:"138_3",rate:1,gain:far ? loudness(gain):0)) }
            return (pitch,layers)
        }
        let damage = input.health >= 650 ? (0.0,1.0) : input.health >= 460 ? (-6,0.95) : input.health >= 390 ? (-9,0.9) : input.health >= 250 ? (-12,0.85) : (-18,0.8)
        let damageGain = decibels(damage.0)
        if kind == "prop" {
            let pitch = ease((1+0.1*abs(input.side)-0.15*input.nose+gas)*damage.1,50/187.5)
            let gain = curve([[0,0],[0.15,0.3],[1,1]],rotor)*damageGain
            var layers = [Layer(name:"front",sound:"\(bank)_0",rate:pitch,gain:loudness((1-0.67*behind)*gain)),
                          Layer(name:"rear",sound:"\(bank)_1",rate:pitch,gain:loudness((0.5*behind+0.5)*gain)),
                          Layer(name:"near",sound:"138_17",rate:1,gain:loudness(gain))]
            if remote { layers.append(Layer(name:"far",sound:"138_16",rate:1,gain:far ? loudness(gain):0)) }
            return (pitch,layers)
        }
        let share = max((clamp(rotor,0.2,1)-0.2)*1.25,0.2)
        let pitch = ease((0.8+0.4*share+0.1*abs(input.side)-0.15*input.nose+gas)*damage.1,50/187.5)
        let gain = (0.4+0.6*share)*damageGain
        var layers = [Layer(name:"front",sound:"138_10",rate:pitch,gain:loudness((1-0.67*behind)*gain)),
                      Layer(name:"rear",sound:"138_11",rate:pitch,gain:loudness((0.5*behind+0.5)*gain)),
                      Layer(name:"near",sound:"138_26",rate:1,gain:loudness(clamp(remote ? share-0.2:input.throttle)*share*damageGain))]
        if remote { layers.append(Layer(name:"far",sound:"138_14",rate:1,gain:far ? loudness(gain):0)) }
        return (pitch,layers)
    }

    final class Boat {
        private(set) var turning = 0.0, pitch = -1.0
        private var speed = 0.0, told = -1.0, trend = 0.0, splashed = -Double.infinity
        func reset() { turning = 0; pitch = -1; speed = 0; told = -1; trend = 0; splashed = -.infinity }
        func remoteThrottle(speed current: Double, time: Double) -> Double {
            if told < 0 { speed = current; told = time; trend = 0 }
            else if current != speed && time > told {
                let delta = time-told
                trend += ((current-speed)/delta-trend)*min(1,delta/0.6); speed = current; told = time
            }
            return current > 1.5 ? (trend > -0.2*current ? 1:0) : current < -1.5 && trend < -0.2*current ? -0.3:0
        }
        func update(delta: Double, throttle: Double, afloat: Bool, up: Double, distance: Double,
                    speed: Double, bank: Int) -> [Layer] {
            let target = throttle > 0 ? 0.18+0.16000000000000003*min(1,throttle) : throttle < 0 ? 0.18+0.13*max(-1,throttle) : 0
            turning += (target-turning)*(1-pow(1-(throttle != 0 ? 0.05:0.01),50*max(0,delta)))
            let share = clamp(3*turning), targetPitch = 0.6+0.1*min(1,1-up)+share*(afloat ? 0.4:0.7)
            pitch = pitch < 0 ? targetPitch : pitch+clamp(targetPitch-pitch,-delta,delta)
            let rawGain = -3+3*share+distanceDecibels(distance/3.5)
            let speedShare = min(37.5,abs(speed))/37.5
            let skimGain = 3+20*log10(speedShare)+distanceDecibels(distance/2.5)
            return [Layer(name:"engine",sound:"\(bank)_0",rate:pitch,gain:rawGain > -60 ? decibels(min(3,rawGain)):0),
                    Layer(name:"skim",sound:"39_3",rate:0.8+0.2*speedShare,
                          gain:afloat && speedShare >= 1e-5 && skimGain > -60 ? decibels(min(3,skimGain)):0)]
        }
        func slam(magnitude: Double, time: Double, distance: Double) -> Layer? {
            guard magnitude >= 450, time >= splashed+1.5 else { return nil }
            let db = 9.1+20*log10(min(1,magnitude/800))+distanceDecibels(distance)
            let gain = db > -60 ? decibels(min(3,db)):0
            guard gain > 0 else { return nil }; splashed = time
            return Layer(name:"slam",sound:"39_66",rate:1,gain:gain)
        }
    }

    struct SpecialInput: Codable {
        var share = 0.0, speed = 0.0, accel = 0.0, brake = 0.0
        var rotor: Double?
        var up = 1.0, nose = 0.0, side = 0.0
        var mine = true
    }
    final class Special {
        private(set) var pitch = -1.0, twin = 0, turned = 0.0
        func reset() { pitch = -1; twin = 0; turned = 0 }
        func update(delta: Double, kind: String, bank: Int, input: SpecialInput) -> [Layer] {
            let share = clamp(input.share)
            if kind == "golf" { return [Layer(name:"engine",sound:"\(bank)_0",rate:mix(0.85,1.2,share),
                gain:share >= 0.05 ? decibels(20*logarithm(curve([[0,0],[0.05,0],[0.1,0.5],[1,1]],share))-3):0)] }
            if kind == "rcCar" { return [Layer(name:"engine",sound:"\(bank)_0",rate:curve([[0,0.7],[0.05,0.7],[0.2,0.9],[1,1.15]],share),
                gain:decibels(curve([[0,-100],[0.05,-24],[0.2,0],[1,0]],share)))] }
            if kind == "rcPlane" || kind == "rcHeli" {
                let value = input.rotor.map { max(0,$0)/(kind == "rcHeli" ? 0.22:0.34) } ?? 1
                let clamped = min(1,value), rotor = clamped > 0.2 ? max(0.2,1.25*(clamped-0.2)):0.2
                let gas = input.brake > 0 ? -0.05 : input.accel > 0 ? 0.1:0
                let target = kind == "rcHeli" ? 0.8+0.2*rotor+0.2*min(1,(1-input.up)*0.5/0.07)+gas : 0.1*abs(input.side)-input.nose*0.15+gas+1
                let step = (1/187.5)*delta/0.02
                pitch = pitch < 0 ? target : pitch+clamp(target-pitch,-step,step)
                return [Layer(name:"engine",sound:"\(bank)_0",rate:pitch,gain:decibels((kind == "rcHeli" ? -6:0)+20*logarithm(rotor)))]
            }
            if kind == "hover" {
                let rotor = input.rotor.map { clamp(max(0,$0)/0.34) } ?? (0.45+0.55*share)
                let target = 0.8+0.35*rotor+(input.brake > 0 ? -0.05 : input.accel > 0 ? 0.1:0)
                let step = (1/187.5)*delta/0.02
                pitch = pitch < 0 ? target : pitch+clamp(target-pitch,-step,step)
                return [Layer(name:"engine",sound:"\(bank)_0",rate:pitch,gain:decibels(mix(-12,-6,rotor)))]
            }
            return []
        }
        func train(delta: Double, brakeBank: Int, engineBank: Int, input: SpecialInput) -> [Layer] {
            let tram = engineBank == 133, speed = input.speed/50, share = clamp(abs(speed))
            let gas = input.mine ? abs(speed) >= 0.001 ? (speed < 0 ? -input.brake:input.accel) : input.accel-input.brake : 0
            let slope = clamp(input.nose,-0.3,0.3)*(tram ? -0.35:-0.6)
            let engineDB = (tram ? 11+20*logarithm(share):0)+gas*3
            let trackDB = share >= 1e-5 ? (tram ? 10:6)+20*logarithm(share)+1.5-9 : -.infinity
            let braking = abs(speed) < 0.001 ? 0 : speed > 0 ? input.brake:input.accel
            let brakeShare = input.mine ? braking*curve([[0,0],[0.001,0],[0.1,1],[1,1]],share):0
            if brakeShare > 0 { turned += delta; if turned >= 3 { turned = 0; twin = 1-twin } }
            else { turned = 0 }
            let brakeDB = brakeShare > 0 ? 9+20*logarithm(brakeShare)+1.5-9 : -.infinity
            return [Layer(name:"engine",sound:"\(engineBank)_0",rate:mix(tram ? 0.9:0.8,tram ? 1.1:1.2,share)*(1+slope),gain:decibels(engineDB+1.5-9)),
                    Layer(name:"track",sound:"\(engineBank)_2",rate:mix(0.8,1.2,share)*0.96,gain:decibels(trackDB)),
                    Layer(name:"brakes",sound:"\(brakeBank)_\(twin)",rate:mix(0.68,1,share),gain:decibels(brakeDB))]
        }
    }

    final class RoadEngine {
        private(set) var output = RoadMix()
        private var state = 0, gear = 0
        private var cruised = 0.0, before = 0.0, heard = 0.0, owed = 0.0, clock = 60_000.0, at = -1.0
        private var sinceLoop = 0, stoppedAt = 0.0, stoppedShare = 0.0, mayRunUp = 0.0, mayCruise = 0.0
        private var fresh = true
        private var speed = 0.0, share = 0.0, pitch = 1.0, spinPitch = 0.0
        func reset() {
            output = RoadMix(); state = 0; gear = 0; cruised = 0; before = 0; heard = 0; owed = 0
            clock = 60_000; at = -1; sinceLoop = 0; stoppedAt = 0; stoppedShare = 0
            mayRunUp = 0; mayCruise = 0; fresh = true
        }
        @discardableResult func update(delta: Double, input: RoadInput, runUpDuration: Double, loopStart: Double) -> RoadMix {
            output.runUpFrom = -1; output.fall = -.infinity
            let single = singleGear.contains(input.id), box = input.box, count = single ? 1 : box.count
            let targetSpeed = input.speed/50
            if fresh { fresh = false; heard = targetSpeed; before = targetSpeed }
            owed = min(owed + delta, 0.1)
            let steps = Int(floor(owed/0.02 + 1e-6))
            owed -= 0.02 * Double(steps)
            func healthPitch() -> Double {
                let value = abs(speed)
                share = clamp(value/box.max)
                let slope = speed != 0 ? input.climb/50/speed : 0
                var tilt = (slope <= 0 ? -(max(-0.2,slope)/0.2) : -min(0.2,slope)/0.2)*0.15
                if speed < -0.001 { tilt = -tilt }
                let lowShare = min(1, value/box.gears[1].up)
                let lean = input.bike ? 0.12*abs(sin(input.lean))*lowShare : 0
                pitch = (lowShare*tilt+1)*(lean+1)*(input.nitro ? 1.12:1)
                spinPitch = input.spin/5*0.25
                return slope
            }
            func idle() {
                output.idle = (input.id == 457 ? -33 : mix(-3,-1.5,share)) + (input.nitro ? 3:0)
                output.idleRate = input.id == 457 ? 1 : mix(0.85,1.5,curve(idleCurve,share))*pitch
            }
            func revs() {
                let selected = single ? (input.gear != 0 ? 1:0) : input.gear
                let item = box.gears[input.gear]
                let value = selected != 0 && item.max != item.down ? clamp((abs(speed)-item.down)/(item.max-item.down)) : 0
                output.revs = mix(-4,0,value) + (input.nitro ? 3:0)
                output.revsRate = (input.spin <= 5 ? 1+input.spin/5*0.2 : 1+mix(0.2,0.4,(input.spin-5)/5))*pitch
            }
            func runUp() {
                output.runUp = (single ? -2 : mix(-2,0,Double(gear)/5)) + (input.nitro ? 3:0)
                output.runUpRate = (spinPitch+(single ? 1 : [0.4,0.22,0.13,0.075,0,-0.075][gear]+1))*pitch
            }
            func cruise() {
                output.cruise = (single ? -2 : mix(0,2,cruised/150)) + (input.nitro ? 3:0)
                output.cruiseRate = (spinPitch+0.32499999999999996*cruised/150+(single ? 1:0.925))*pitch
            }
            func endRunUp() {
                if at >= 0 {
                    stoppedShare = clamp(at/runUpDuration); stoppedAt = clock; at = -1
                    output.runUp = -.infinity; output.runUpFrom = -1
                }
            }
            func startIdle(_ falling: Bool) {
                endRunUp(); output.revs = -.infinity; output.cruise = -.infinity; cruised = 0
                if falling { output.fall = mix(-3,-1.5,share)+(input.nitro ? 3:0); output.fallRate = mix(0.75,1.25,share)*pitch }
                idle(); state = 6
            }
            func startRevs() { endRunUp(); output.idle = -.infinity; output.cruise = -.infinity; cruised = 0; revs(); state = 4 }
            func startCruise() { endRunUp(); output.idle = -.infinity; output.revs = -.infinity; cruise(); state = 5 }
            func startRunUp(_ resume: Bool) {
                if resume { gear = single ? 1 : min(max(1,input.gear),gear,box.count-1) }
                output.idle = -.infinity; output.revs = -.infinity; output.cruise = -.infinity; cruised = 0
                let elapsed = clock-stoppedAt
                var position = 0.0
                sinceLoop = 0
                if elapsed <= 1_000 { position = clamp(stoppedShare*(1-elapsed/1_000),0,0.8) }
                if position > 0.1 { sinceLoop = 11 }
                at = position*runUpDuration; output.runUpFrom = position; runUp(); state = 3
            }
            if steps > 0 { for i in 1...steps {
                speed = heard+(targetSpeed-heard)*Double(i)/Double(steps); clock += 20
                let slope = healthPitch(), reverse = speed < -0.001, pedal = input.accel > 150.0/255, released = !(input.accel > 0)
                let blocked = input.brake > 0 || input.handbrake || input.spin > 5 || input.grounded == 0
                let slow = !single && speed < 0.1, selected = single ? (input.gear != 0 ? 1:0) : input.gear
                let hill = selected < count && before+0.001 > speed && slope > 0.2
                switch state {
                case 3:
                    if reverse || blocked { if pedal { startRevs() } else { startIdle(true) } }
                    else if released || slow || !pedal { startIdle(true) }
                    else if hill && mayCruise >= clock { startCruise(); mayRunUp = clock+2_000 }
                    else {
                        at += 0.02*output.runUpRate
                        var transition = false
                        if sinceLoop < 10 { sinceLoop += 1 }
                        else if at+0.12 > runUpDuration { sinceLoop = 0; transition = true }
                        if at >= runUpDuration { at = loopStart+(at-runUpDuration) }
                        if transition {
                            let oldGear = gear; gear = min(5,oldGear+1)
                            if oldGear+2 <= count || selected < count { runUp() } else { startCruise() }
                        } else { runUp() }
                    }
                case 4:
                    if reverse { if pedal { revs() } else { startIdle(true) } }
                    else if released { startIdle(true) }
                    else if (blocked || slow) && pedal { revs() }
                    else if blocked || slow || !pedal { startIdle(true) }
                    else { output.revs = -.infinity; if hill { startCruise() } else { startRunUp(true) } }
                case 5:
                    if reverse || (!released && (blocked || slow)) { if pedal { startRevs() } else { startIdle(true) } }
                    else if released || !pedal { startIdle(true) }
                    else if selected < count && before+0.0015 <= speed && mayRunUp >= clock {
                        mayCruise = clock+2_000; startRunUp(true)
                    } else { cruised = speed <= before-0.05 ? max(0,cruised-0.25) : min(cruised+1,150); cruise() }
                case 6:
                    if reverse { if pedal { startRevs() } else { idle() } }
                    else if released { idle() }
                    else if blocked || slow { if pedal { startRevs() } else { idle() } }
                    else if pedal { if hill { startCruise() } else { startRunUp(true) } }
                    else { idle() }
                default:
                    if !reverse && released { startIdle(false) }
                    else if reverse || blocked || slow { if pedal { startRevs() } else { startIdle(false) } }
                    else if pedal { if hill { startCruise() } else { startRunUp(false) } }
                    else { startIdle(false) }
                }
                before = speed
            } }
            heard = targetSpeed; output.state = state; output.gear = gear
            return output
        }
    }
}
