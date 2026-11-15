import Foundation
import simd

/// The archived browser weather manager's fixed 30 Hz visual simulation.
/// All positions use GTA axes; particles use the original splash/smoke/cloud
/// textures. Voice playback is left to NativeGameAudio, via thunder events.
final class NativeWeatherParticles {
    struct Line {
        let from: SIMD3<Float>
        let to: SIMD3<Float>
        let color: SIMD3<Float>
        let fromAlpha: Float
        let toAlpha: Float
    }
    struct Thunder { let durationTicks: Int; let serial: Int }
    struct Snapshot {
        let lines: [Line]
        let quads: [NativeAtmosphere.Quad]
        let clock: Float
        let rain: Float
        let sand: Float
        let wind: Float
        let windVector: SIMD3<Float>
        let fog: Float
        let fogIn: Float
        let hazeAlpha: Float
        let flash: Bool
        let bursting: Bool
        let bursts: Int
        let claps: Int
        let streaks: Int
    }
    private struct Document: Decodable { let wind: [Double]; let gusts: [Double]; let directions: [Double] }
    private struct Particle {
        var position = SIMD3<Float>.zero
        var velocity = SIMD3<Float>.zero
        var born: Float = 0
        var lifespan: Float = 0
        var start: Float = 0
        var end: Float = 0
        var angle: Float = 0
        var spin: Float = 0
        var tint = SIMD4<Float>.zero
    }
    enum Error: Swift.Error { case invalidTable }
    private var table: Document?
    private var request: URLSessionDataTask?
    private var clock: Double = 0, accumulator: Double = 0
    private var rain: Double = 0, sand: Double = 0, wind: Double = 0, fog: Double = 0
    private var fogIn: Double = 0, hazeAlpha: Double = 0
    private var way = SIMD3<Double>.zero
    private var bursting = false, flash = false
    private var burstStart: Double = 0, flashSince: Double = 0, thunderAt: Double = 0
    private var durationTicks = 0, bursts = 0, claps = 0, streakCount = 0
    private var lineSeeds = [SIMD3<Float>](repeating: .zero,count: 32) // Original Three axes.
    private var lineLife = [Float](repeating: 0,count: 32)
    private var lines: [Line] = []
    private var splash = [Particle](repeating: Particle(),count: 768)
    private var haze = [Particle](repeating: Particle(),count: 128)
    private var mist = [Particle](repeating: Particle(),count: 350)
    private var splashIndex = 0, hazeIndex = 0
    private var sampleGround = [SIMD3<Double>](repeating: SIMD3(0,Double.nan,0),count: 5) // Three axes.
    private var groundIndex = 0, hasMist = false
    private var mistStrength: Double = 0
    private var hazeShade: Double = 1
    private var fogShade = SIMD3<Double>(repeating: 1)
    var isLoaded: Bool { table != nil }
    var onThunder: ((Thunder) -> Void)?
    var audio: NativeWeatherAudio?

    init() {}
    convenience init(data: Data) throws { self.init(); try install(data) }
    deinit { request?.cancel() }
    func load(server: ServerAddress,completion: (() -> Void)? = nil) {
        request?.cancel()
        request = URLSession.shared.dataTask(with: server.path("game/native/atmosphere.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { guard let self,(try? self.install(data)) != nil else { return }; completion?() }
        }
        request?.resume()
    }
    private func install(_ data: Data) throws {
        let value = try JSONDecoder().decode(Document.self,from: data)
        guard value.wind.count == 23,value.gusts.count == 16,value.directions.count == 16,
              (value.wind+value.gusts+value.directions).allSatisfy(\.isFinite) else { throw Error.invalidTable }
        table = value
    }
    /// Ground returns an absolute native z, queried from camera.z+40 down 80 m.
    /// Missing geometry returns nil and suppresses that sample's splash sprites.
    func update(delta: Float,camera: SIMD3<Float>,forward: SIMD3<Float>,cameraRight: SIMD3<Float>,cameraUp: SIMD3<Float>,
                weatherFrom: Int,weatherTo: Int,blend: Float,skyTop: SIMD3<Float>,outdoors: Bool,
                textured: Bool = true,ground: ((Float,Float,Float,Float) -> Float?)? = nil,
                random: () -> Double = { Double.random(in: 0..<1) }) -> Snapshot? {
        guard let table,delta.isFinite,camera.x.isFinite,camera.y.isFinite,camera.z.isFinite else { return nil }
        let change = blend.isFinite ? max(0,min(1,Double(blend))) : 1
        // A completed blend uses the destination as both source and target.
        let from = change >= 1 ? weatherTo : weatherFrom
        let fromWind = table.wind.indices.contains(from) ? table.wind[from] : 0
        let toWind = table.wind.indices.contains(weatherTo) ? table.wind[weatherTo] : 0
        let quiet = fromWind == 0 && toWind == 0 && ![8,16,9].contains(from) && ![8,16,9].contains(weatherTo)
        let activeSprites = splash.contains { clock-Double($0.born) < Double($0.lifespan) } || haze.contains { clock-Double($0.born) < Double($0.lifespan) }
        let resting = quiet && rain == 0 && sand == 0 && fogIn == 0 && hazeAlpha == 0 && streakCount == 0 && thunderAt == 0 && !activeSprites
        if !resting || audio?.active == true {
            let dt = max(0,Double(delta)),step = 1/30.0
            clock += dt; accumulator = min(accumulator+dt,3*step)
            while accumulator >= step {
                accumulator -= step
                tick(camera: camera,forward: forward,from: from,to: weatherTo,blend: change,
                     skyTop: skyTop,outdoors: outdoors && camera.z < 900,textured: textured,ground: ground,random: random)
            }
        } else { bursting = false; flash = false }
        let quads = particles(camera: camera,right: cameraRight,up: cameraUp)
        return Snapshot(lines: lines,quads: quads,clock: Float(clock),rain: Float(rain),sand: Float(sand),wind: Float(wind),
            windVector: Self.native(way),fog: Float(fog),fogIn: Float(fogIn),hazeAlpha: Float(hazeAlpha),
            flash: flash,bursting: bursting,bursts: bursts,claps: claps,streaks: streakCount)
    }

    private func tick(camera: SIMD3<Float>,forward: SIMD3<Float>,from: Int,to: Int,blend: Double,
                      skyTop: SIMD3<Float>,outdoors: Bool,textured: Bool,
                      ground: ((Float,Float,Float,Float) -> Float?)?,random: () -> Double) {
        guard let table else { return }
        func between(_ lo: Double,_ hi: Double) -> Double { lo+random()*(hi-lo) }
        func weather(_ values: [Int]) -> Double { (values.contains(from) ? 1-blend : 0)+(values.contains(to) ? blend : 0) }
        let ms = 1000*clock,level = floor(ms/8192).truncatingRemainder(dividingBy: 4)*0.1+0.7
        rain = Self.approach(rain,level*weather([8,16]),1/30.0*50*0.005)
        sand = Self.approach(sand,level*weather([19]),1/30.0*50*0.005)
        fog = weather([9])
        let a = table.wind.indices.contains(from) ? table.wind[from] : 0,b = table.wind.indices.contains(to) ? table.wind[to] : 0
        wind = a+(b-a)*blend
        func gust(_ index: Double,_ blend: Double) -> Double {
            let i = Int(index.truncatingRemainder(dividingBy: 16)),next = (i+1)%16
            return table.gusts[i]+(table.gusts[next]-table.gusts[i])*blend
        }
        let strength = min(wind,1),bin = floor(ms/1024),ease = 0.5-0.5*cos(ms.truncatingRemainder(dividingBy: 1024)/1024*Double.pi)
        var x = gust(bin,ease)*strength*0.4+0.7*strength
        var z = gust(bin+3,ease)*strength*0.4+0.7*strength
        var y = gust(bin+6,ease)*strength*0.2
        let extra = (strength-0.5)*0.4
        if extra > 0 {
            let bin = floor(ms/256),share = ms.truncatingRemainder(dividingBy: 256)/256
            x += gust(bin,share)*extra; z += gust(bin+3,share)*extra; y += gust(bin+6,share)*extra
        }
        let turnBin = Int(floor(ms/2048).truncatingRemainder(dividingBy: 16))
        let turnShare = 0.5-0.5*cos(ms.truncatingRemainder(dividingBy: 2048)/2048*Double.pi)
        let direction = table.directions[turnBin]+(table.directions[(turnBin+1)%16]-table.directions[turnBin])*turnShare
        way = SIMD3(x*direction,y*direction,-z*direction)
        let eye = SIMD3<Double>(Double(camera.x),Double(camera.z),-Double(camera.y))
        let aim = SIMD3<Double>(Double(forward.x),Double(forward.z),-Double(forward.y))
        if outdoors && [8,16].contains(from) && [8,16].contains(to) {
            if bursting {
                if random() < 24/256.0 {
                    bursting = false; flash = false
                    durationTicks = min(20,Int(((clock-burstStart)/(1/30.0)).rounded()))
                    thunderAt = ms+Double(20-durationTicks)*150
                } else if ms-flashSince > 50 {
                    let old = flash; flash = random() < 0.5
                    if old != flash { flashSince = ms }
                }
            } else if random() < 200/32768.0 {
                bursting = true; flash = true; burstStart = clock; flashSince = ms; bursts += 1
            } else { flash = false }
        } else { bursting = false; flash = false }
        if thunderAt != 0 && ms > thunderAt {
            thunderAt = 0; claps += 1; onThunder?(Thunder(durationTicks: durationTicks,serial: claps))
            if outdoors { audio?.thunder(durationTicks:durationTicks,serial:claps-1) }
        }
        let wanted = outdoors ? Int(floor(110*rain)) : 0
        if streakCount < wanted { streakCount += 1 } else if streakCount > 0 && streakCount > wanted { streakCount -= 1 }
        lines.removeAll(keepingCapacity: true)
        if streakCount > 0 {
            for i in 0..<32 {
                let oldSeed = lineSeeds[i]
                let distance = simd_length(SIMD3(Double(oldSeed.x),Double(oldSeed.y),Double(oldSeed.z))-eye)
                if !(lineLife[i] >= 1) || distance > 8 {
                    lineSeeds[i] = SIMD3(Float((5*random()+6*aim.x+eye.x-2.5).rounded(.towardZero)),
                                         Float((5*random()+6*aim.y+eye.y-2.5).rounded(.towardZero)),
                                         Float((5*random()+6*aim.z+eye.z-2.5).rounded(.towardZero)))
                    lineLife[i] = Float(floor(0.6*Double(streakCount)))
                }
                let seed = lineSeeds[i]
                let position = SIMD3(Double(seed.x)+between(-0.2,0.2),Double(seed.y)+between(-0.1,0.1),Double(seed.z)+between(-0.2,0.2))
                let length = (i%2 != 0 ? wind : wind*rain)*0.1
                let tip = SIMD3(position.x-way.x*length,position.y-way.y*length+between(0.1,0.5),position.z-way.z*length)
                lines.append(Line(from: Self.native(position),to: Self.native(tip),color: SIMD3(210/255.0,210/255.0,230/255.0),
                    fromAlpha: lineLife[i]/255,toAlpha: Float(floor(Double(lineLife[i])/2)/255)))
                lineLife[i] = max(0,lineLife[i]-Float(2+floor(3*random())))
            }
        }
        func particle(_ position: SIMD3<Double>,_ velocity: SIMD3<Double>,_ life: Double,_ start: Double,_ end: Double,_ angle: Double,_ spin: Double,_ tint: SIMD4<Double>) -> Particle {
            Particle(position: SIMD3(Float(position.x),Float(position.y),Float(position.z)),velocity: SIMD3(Float(velocity.x),Float(velocity.y),Float(velocity.z)),born: Float(clock),lifespan: Float(life),start: Float(start),end: Float(end),angle: Float(angle),spin: Float(spin),tint: SIMD4(Float(tint.x),Float(tint.y),Float(tint.z),Float(tint.w)))
        }
        func putHaze(_ velocity: Double,_ color: SIMD3<Double>,_ alpha: Double) {
            let size = 15+between(-7,7)
            let position = SIMD3(eye.x+10*aim.x+between(-20,20),eye.y+between(-2,5),eye.z+10*aim.z+between(-20,20))
            let angle = between(0,2*Double.pi),spin = between(20,50)*Double.pi/180*(random() < 0.5 ? -1 : 1)
            haze[hazeIndex] = particle(position,way*velocity,1,size,size,angle,spin,SIMD4(color,alpha))
            hazeIndex = (hazeIndex+1)%haze.count
        }
        let effects = outdoors && textured
        if effects && wind > 1.01 { putHaze(25,SIMD3(pow(0.67,2.2),pow(0.65,2.2),pow(0.55,2.2)),0.25) }
        if effects && (rain > 0.1 || hazeAlpha > 0) {
            let count = Int(floor(5*rain)),drops = 15+Int(floor(2*rain))
            if count > 0 {
                let angle = random() < 0.5 ? between(0,2*Double.pi) : atan2(aim.x,aim.z)+between(-0.8,0.8)
                let distance = between(0,20),x = eye.x+sin(angle)*distance,z = eye.z+cos(angle)*distance
                let height = ground?(Float(x),Float(-z),Float(eye.y+40),80)
                sampleGround[groundIndex] = SIMD3(Double(Float(x)),height.map { Double(Float($0+0.1)) } ?? Double.nan,Double(Float(z)))
                groundIndex = (groundIndex+1)%5
            }
            if count > 0 {
                for i in 0..<min(count,5) {
                    let sample = sampleGround[i]
                    if !sample.y.isNaN {
                        for _ in 0..<drops {
                            let position = SIMD3(sample.x+between(-15,15),sample.y,sample.z+between(-15,15))
                            let life = 0.105+between(-0.09,0.09)
                            splash[splashIndex] = particle(position,.zero,life,0.1,0.4,0,0,SIMD4(1,1,1,0.6))
                            splashIndex = (splashIndex+1)%splash.count
                        }
                    }
                }
            }
            hazeAlpha = Self.approach(hazeAlpha,0.2*rain,0.0025)
            putHaze(15,SIMD3(pow(0.9,2.2),pow(0.9,2.2),1),hazeAlpha)
        } else if !outdoors { hazeAlpha = 0 }
        hazeShade = min(1,0.25+Double(skyTop.x+skyTop.y+skyTop.z)*0.9)
        fogIn = fog > 0 && outdoors ? min(1,fogIn+1/180.0) : max(0,fogIn-1/180.0)
        mistStrength = textured ? fog*fogIn : 0
        if mistStrength > 0 {
            for i in 0..<mist.count {
                let p = mist[i],age = clock-Double(p.born)
                let dx = Double(p.position.x)+Double(p.velocity.x)*age-eye.x
                let dy = Double(p.position.y)-eye.y
                let dz = Double(p.position.z)+Double(p.velocity.z)*age-eye.z
                let distance = sqrt(dx*dx+dy*dy+dz*dz)
                if hasMist && distance <= 60 { continue }
                let speed = between(0.5,1.2)*1.8,size = between(4,10)
                let position = SIMD3(eye.x+between(-58,58),eye.y+between(-5,5),eye.z+between(-58,58))
                let alpha = between(8,20)/255
                mist[i] = particle(position,SIMD3(speed,0,-speed),1e9,size,size,0,0,SIMD4(1,1,1,alpha))
            }
            hasMist = true
            fogShade = SIMD3(Self.linear(min(1,Double(skyTop.x)+132/255.0)),Self.linear(min(1,Double(skyTop.y)+132/255.0)),Self.linear(min(1,Double(skyTop.z)+132/255.0)))
        } else { hasMist = false }
        audio?.step(milliseconds:ms,outdoors:outdoors,altitude:Double(camera.z),rain:rain,wind:wind,sand:sand,random:random)
    }

    private func particles(camera: SIMD3<Float>,right: SIMD3<Float>,up: SIMD3<Float>) -> [NativeAtmosphere.Quad] {
        var quads: [NativeAtmosphere.Quad] = []
        func put(_ buffer: [Particle],kind: Int) {
            if kind == 2 && mistStrength <= 0 { return }
            for p in buffer {
                let age = clock-Double(p.born),share = age/max(Double(p.lifespan),0.0001)
                if age < 0 || share >= 1 { continue }
                let sourcePosition = SIMD3(Double(p.position.x),Double(p.position.y),Double(p.position.z))+SIMD3(Double(p.velocity.x),Double(p.velocity.y),Double(p.velocity.z))*age
                let center = Self.native(sourcePosition),distance = Double(simd_length(center-camera))
                let near: Double = kind == 2 ? 42 : 30,far: Double = kind == 2 ? 60 : 50
                let distanceFade = max(0,min(1,(far-distance)/(far-near)))
                let fade = kind == 0 ? 1-share : kind == 1 ? min(share/0.1,(1-share)/0.9) : min(age/0.3,1)
                let alpha = Double(p.tint.w)*fade*distanceFade*(kind == 2 ? mistStrength : 1)
                if alpha <= 0 { continue }
                let size = Double(p.start)+(Double(p.end)-Double(p.start))*share
                let angle = Double(p.angle)+Double(p.spin)*age,c = Float(cos(angle)),s = Float(sin(angle))
                let horizontal = (right*c+up*s)*Float(size*0.5),vertical = (up*c-right*s)*Float(size*0.5)
                let shade = kind == 1 ? SIMD3<Double>(repeating: hazeShade) : kind == 2 ? fogShade : SIMD3<Double>(repeating: 1)
                let tint = SIMD4(Float(Double(p.tint.x)*shade.x),Float(Double(p.tint.y)*shade.y),Float(Double(p.tint.z)*shade.z),Float(alpha))
                quads.append(NativeAtmosphere.Quad(texture: kind == 0 ? (share < 0.25 ? "splash_up1" : "splash_up2") : kind == 1 ? "bullethitsmoke" : "cloudmasked",
                    center: center,right: horizontal,up: vertical,tint: tint,topLeftTint: nil,
                    blend: kind == 0 ? .additive : .alpha,depthTest: true,paintedOnSky: false,flipV: false,shading: .particle))
            }
        }
        put(splash,kind: 0); put(haze,kind: 1); put(mist,kind: 2)
        return quads
    }
    private static func approach(_ value: Double,_ target: Double,_ step: Double) -> Double { value < target ? min(target,value+step) : max(target,value-step) }
    private static func native(_ value: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(value.x),Float(-value.z),Float(value.y)) }
    private static func linear(_ value: Double) -> Double { value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055,2.4) }
}
