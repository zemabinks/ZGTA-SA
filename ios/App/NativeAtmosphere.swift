import Foundation
import simd

/// The public browser client's sky factory and cloud shaders in GTA coordinates
/// (x east, y north, z up). Extracted tables/textures are served by the Mac.
/// This helper produces geometry; the renderer owns texture sampling/blending.
final class NativeAtmosphere {
    enum Blend { case additive, alpha }
    enum Shading { case sky, cloud, particle }
    struct Quad {
        let texture: String
        let center: SIMD3<Float>
        /// Half extents, already oriented in world space. Vertex signs are ±1.
        let right: SIMD3<Float>
        let up: SIMD3<Float>
        let tint: SIMD4<Float>
        /// The flat cloud shader brightens its (-x,+y) corner only.
        let topLeftTint: SIMD4<Float>?
        let blend: Blend
        let depthTest: Bool
        let paintedOnSky: Bool
        let flipV: Bool
        let shading: Shading
    }
    struct Rainbow {
        let middle: SIMD3<Float>
        let across: SIMD3<Float>
        let over: SIMD3<Float>
        let colors: [SIMD3<Float>]
        let strength: Float
        /// Original sphere radius, band angle and width, in degrees.
        let distance: Float = 900
        let angle: Float = 42
        let width: Float = 2.6
    }
    struct Meteor {
        let head: SIMD3<Float>
        let tail: SIMD3<Float>
        let headAlpha: Float = 0.8824
    }
    struct Snapshot {
        let quads: [Quad]
        let belowColor: SIMD3<Float>
        let sunDirection: SIMD3<Float>
        let rainbow: Rainbow?
        let meteor: Meteor?
        let sheetDrift: Float
        let highFade: Float
    }
    private struct Sheet: Decodable { let spot: [Double]; let span: [Double] }
    private struct Volume: Decodable { let home: [Double]; let girth: [Double]; let density: Double }
    private struct Document: Decodable {
        let hours: [Double]
        let colors: [[[Double]]]
        let wind: [Double]
        let constants: [String: NumberArray]
        let sheets: [Sheet]
        let highClouds: [Volume]
    }
    /// The few original constants include both flat and nested numeric arrays.
    private struct NumberArray: Decodable {
        let flat: [Double]
        let nested: [[Double]]
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let rows = try? container.decode([[Double]].self) { flat = []; nested = rows }
            else { flat = try container.decode([Double].self); nested = [] }
        }
    }
    enum Error: Swift.Error { case invalidTable }
    private var table: Document?
    private var request: NativeResourceTask?
    private var starClock: Double = 1.0 / 30
    private var lastStarLight = -1
    private var starLight = [Double](repeating: 0, count: 12)
    private var sheetDrift: Double = 0
    private var highDrift = SIMD3<Double>.zero // Original Three axes, y up.
    private var highFade: Double = 255
    private var milliseconds: Double = 0
    var isLoaded: Bool { table != nil }

    init() {}
    convenience init(data: Data) throws { self.init(); try install(data) }
    deinit { request?.cancel() }

    func load(server: ServerAddress, completion: (() -> Void)? = nil) {
        request?.cancel()
        request = NativeResourceTransport.dataTask(with: server.path("game/native/atmosphere.json")) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async {
                guard let self, (try? self.install(data)) != nil else { return }
                completion?()
            }
        }
        request?.resume()
    }

    private func install(_ data: Data) throws {
        let value = try JSONDecoder().decode(Document.self, from: data)
        guard value.hours.count == 8, value.hours.first == 0, value.hours.allSatisfy({ $0.isFinite && $0 < 24 }),
              zip(value.hours, value.hours.dropFirst()).allSatisfy({ $0 < $1 }),
              value.colors.count == 23, value.colors.allSatisfy({ weather in
                  weather.count == 8 && weather.allSatisfy({ $0.count == 21 && $0.allSatisfy(\.isFinite) })
              }), value.wind.count == 23, value.wind.allSatisfy(\.isFinite),
              value.sheets.count == 58, value.sheets.allSatisfy({ $0.spot.count == 4 && $0.span.count == 3 && ($0.spot + $0.span).allSatisfy(\.isFinite) }),
              value.highClouds.count == 180, value.highClouds.allSatisfy({ $0.home.count == 3 && $0.girth.count == 3 && ($0.home + $0.girth + [$0.density]).allSatisfy(\.isFinite) }),
              ["yS", "y_", "yN", "yz", "yC", "yE", "yR", "w$", "wJ", "wQ"].allSatisfy({ !(value.constants[$0]?.flat.isEmpty ?? true) }),
              value.constants["yS"]?.flat.count == 8,
              ["yC", "yE", "yR"].allSatisfy({ value.constants[$0]?.flat.count == 9 }),
              value.constants["yO"]?.nested.count == 12, value.constants["yO"]!.nested.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }),
              value.constants["wY"]?.nested.count == 6, value.constants["wY"]!.nested.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else { throw Error.invalidTable }
        table = value
    }

    /// Preserve this object between frames: cloud fading/drift and star twinkle
    /// are stateful in the original. Supply the actual camera right/up vectors.
    /// `interiorColor == nil` is outside; zero is an interior without extra color.
    func update(delta: Float, hour: Float, weatherFrom: Int, weatherTo: Int, blend: Float,
                camera: SIMD3<Float>, cameraFar: Float, cameraRight: SIMD3<Float>, cameraUp: SIMD3<Float>,
                conditions: NativeWorldEnvironment.Conditions, air: Float = 1,
                interiorColor: Int? = nil, cloudQuality: Float = 1,
                random: () -> Double = { Double.random(in: 0..<1) }) -> Snapshot? {
        guard let data = table, camera.x.isFinite, camera.y.isFinite, camera.z.isFinite else { return nil }
        let dt = delta.isFinite ? max(0, Double(delta)) : 0
        let time = hour.isFinite ? max(0, min(23.999, Double(hour))) : 12
        let change = blend.isFinite ? max(0, min(1, Double(blend))) : 1
        let visibility = air.isFinite ? Double(air) : 1
        let eye = SIMD3<Double>(Double(camera.x), Double(camera.y), Double(camera.z))
        let right = SIMD3<Double>(Double(cameraRight.x), Double(cameraRight.y), Double(cameraRight.z))
        let up = SIMD3<Double>(Double(cameraUp.x), Double(cameraUp.y), Double(cameraUp.z))
        let hours = data.hours + [24]
        var bin = 0
        while bin < 7 && time >= hours[bin+1] { bin += 1 }
        let next = (bin+1)%8, share = (time-hours[bin])/(hours[bin+1]-hours[bin])
        func row(_ weather: Int) -> [Double] {
            let id = data.colors.indices.contains(weather) ? weather : 10
            var result = zip(data.colors[id][bin], data.colors[id][next]).map { $0*(1-share)+$1*share }
            if id == 2 || id == 3 {
                let clear = id == 2 ? 0 : 1, amount = Self.clamp((eye.z-20)/200)
                let upper = zip(data.colors[clear][bin], data.colors[clear][next]).map { $0*(1-share)+$1*share }
                result = zip(result, upper).map { $0*(1-amount)+$1*amount }
            }
            return result
        }
        var lighting = zip(row(weatherFrom), row(weatherTo)).map { $0*(1-change)+$1*change }
        if let color = interiorColor, color > 0 {
            let weather = 21+(color-1)/8, hour = (color-1)%8
            if data.colors.indices.contains(weather) { lighting = data.colors[weather][hour] }
        }
        func weatherShare(_ key: String) -> Double {
            let list = data.constants[key]!.flat
            return (list.contains(Double(weatherFrom)) ? 1-change : 0) + (list.contains(Double(weatherTo)) ? change : 0)
        }
        let fog = weatherShare("yz"), clear = weatherShare("y_")
        let cloudy = max(fog, 1-clear-weatherShare("yN"))
        let belowTable = data.constants["yS"]!.flat
        let below = (belowTable[bin]*(1-share)+belowTable[next]*share)/255
        let bottomBlend = max(fog, Self.clamp((eye.z-25)/80))
        let bottom = SIMD3<Double>(Double(conditions.skyBottom.x), Double(conditions.skyBottom.y), Double(conditions.skyBottom.z))
        let belowColor = SIMD3<Double>(repeating: below)+(bottom-SIMD3<Double>(repeating: below))*bottomBlend
        let angle = time * Double.pi/12, sx = 0.7+sin(angle), sz = 0.2-cos(angle)
        let sun = simd_normalize(SIMD3<Double>(sx, -0.7, sz))
        let projection = 2*tan(35*Double.pi/180)
        var quads: [Quad] = []
        func quad(_ texture: String, _ center: SIMD3<Double>, _ width: Double, _ height: Double,
                  _ tint: SIMD4<Double>, painted: Bool, depth: Bool) {
            quads.append(Quad(texture: texture, center: Self.float(center), right: Self.float(right*width),
                up: Self.float(up*height), tint: Self.float(tint), topLeftTint: nil,
                blend: .additive, depthTest: depth, paintedOnSky: painted, flipV: true, shading: .sky))
        }
        let outside = interiorColor == nil
        if outside && sun.z > -0.1 {
            let distance = 0.95 * Double(cameraFar)
            let size = lighting[12]*projection*distance/(0.95*Double(conditions.farClip))
            let stretch = 1+fog, position = eye+sun*distance
            quad("coronastar", position, 2.7335*size, 2.7335*size*0.75*stretch,
                 SIMD4(lighting[6]/255/stretch,lighting[7]/255/stretch,lighting[8]/255/stretch,1), painted: false, depth: true)
            let outer = sz > 0 ? 6*size : 0
            quad("coronastar", position, outer, 0.75*outer*stretch,
                 SIMD4(lighting[9]/255/stretch,lighting[10]/255/stretch,lighting[11]/255/stretch,1), painted: false, depth: true)
        }
        let moon = 220-abs(60*time-220).rounded(.towardZero)
        let moonLight = (max(0,moon)*(1-cloudy)).rounded(.towardZero)
        if outside && moonLight > 0 {
            quad("coronamoon", eye+SIMD3(0,-100,15), 10*projection, 7.5*projection,
                 SIMD4(moonLight/255,moonLight/255,(0.85*moon).rounded(.towardZero)/255,1), painted: true, depth: false)
        }
        let whole = floor(time), minute = floor((time-whole)*60)
        let intensity = whole > 22 || whole < 5 ? 255 : whole == 22 ? (255*minute/60).rounded(.towardZero) : whole == 5 ? ((60-minute)*255/60).rounded(.towardZero) : 0
        starClock += dt
        if outside && intensity > 0 {
            if starClock >= 1/30.0 || Int(intensity) != lastStarLight {
                starClock = 0; lastStarLight = Int(intensity)
                for i in 0..<11 { starLight[i] = (intensity*(1-0.015*floor(32*random()))).rounded(.towardZero)/255 }
                starLight[11] = (intensity*(0.5+0.0015625*floor(128*random()))).rounded(.towardZero)/255
            }
            let x = data.constants["yC"]!.flat, z = data.constants["yE"]!.flat, size = data.constants["yR"]!.flat
            for i in 0..<12 {
                let t = i%9, width = i == 11 ? 5*projection : 0.8*size[t]*projection
                let offset = i == 11 ? SIMD3<Double>(100,-90,10) : SIMD3<Double>(i >= 9 ? -100 : 100,-90*x[t],10+80*z[t])
                quad("coronastar", eye+offset, width, 0.75*width,
                     SIMD4(starLight[i],starLight[i],starLight[i],1), painted: true, depth: false)
            }
        }
        let horizonShare = (1-max(cloudy,clear))/255
        if outside && horizonShare > 0 && lighting[13]+lighting[14]+lighting[15] > 0 {
            let tint = SIMD4((lighting[13]*horizonShare*255).rounded(.towardZero)/255,
                            (lighting[14]*horizonShare*255).rounded(.towardZero)/255,
                            (lighting[15]*horizonShare*255).rounded(.towardZero)/255, 1)
            for spot in data.constants["yO"]!.nested {
                quad("cloud1", SIMD3(eye.x+800*spot[0],eye.y+800*spot[1],60*spot[2]+40),
                     320*projection, 30*projection, tint, painted: true, depth: false)
            }
        }
        let outdoors = outside && eye.z < 900 && visibility > 0
        let fromWind = data.wind.indices.contains(weatherFrom) ? data.wind[weatherFrom] : 0
        let toWind = data.wind.indices.contains(weatherTo) ? data.wind[weatherTo] : 0
        let wind = fromWind*(1-change)+toWind*change
        milliseconds += 1000*dt; sheetDrift += 12.5*dt*wind
        if outdoors && lighting[20] >= 1 && eye.z >= -90 {
            let alpha = lighting[20].rounded(.towardZero)/255*visibility
            let color = SIMD3(lighting[17]/255,lighting[18]/255,lighting[19]/255)
            let bright = SIMD3(min(255,2*lighting[17]+20)/255,min(255,1.5*lighting[18])/255,min(255,1.5*lighting[19])/255)
            for sheet in data.sheets {
                let puff = sheet.span[2] > 0.5, square: Double = puff ? 256 : 512
                let dx = Self.mod(sheet.spot[0]+sheet.spot[2]*sheetDrift-eye.x,square)-square*0.5
                let dy = Self.mod(sheet.spot[1]+sheet.spot[2]*sheetDrift-eye.y,square)-square*0.5
                let height = 160+max(0,(eye.z-200)*0.3)+30*sheet.spot[3]
                let edge = min(1,max(abs(dx),abs(dy))/(square*0.5))
                var opacity = alpha
                if puff { opacity *= 1-abs(eye.z-height)*0.004 }
                else {
                    if height > eye.z { opacity *= 1-(height-eye.z)*0.004 }
                    opacity *= Self.clamp(abs(eye.z-height)/10)
                }
                if edge > 0.75 { opacity *= 1-(edge-0.75)*4 }
                if puff { opacity *= Self.clamp((edge-0.05)*20) }
                guard opacity > 0 else { continue }
                quads.append(Quad(texture: "cloudmasked", center: Self.float(SIMD3(eye.x+dx,eye.y+dy,height)),
                    right: Self.float(puff ? right*sheet.span[0] : SIMD3(sheet.span[0],0,0)),
                    up: Self.float(puff ? up*(sheet.span[0]*0.75) : SIMD3(0,sheet.span[1],0)),
                    tint: Self.float(SIMD4(color,opacity)), topLeftTint: puff ? nil : Self.float(SIMD4(bright,opacity)),
                    blend: .alpha, depthTest: true, paintedOnSky: false, flipV: false, shading: .cloud))
            }
        }
        highFade = eye.z < 220 || !outdoors ? min(255,highFade+200*dt) : max(0,highFade-200*dt)
        highDrift.x = (highDrift.x+dt*2.1*wind).truncatingRemainder(dividingBy: 1400)
        highDrift.z = (highDrift.z-dt*2.1*wind).truncatingRemainder(dividingBy: 1400)
        if outdoors && highFade < 128 {
            let grey = min(1,(Double(conditions.skyTop.x+conditions.skyTop.y+conditions.skyTop.z)+Double(conditions.skyBottom.x+conditions.skyBottom.y+conditions.skyBottom.z))/6+64/255.0)
            let reach = min(Double(conditions.farClip),600), faded = highFade/255+(1-visibility)
            let quality = cloudQuality.isFinite ? Self.clamp(Double(cloudQuality)) : 1
            let count = min(180,5*Int((36*quality).rounded()))
            for volume in data.highClouds.prefix(count) {
                let offThree = SIMD3(Self.mod(volume.home[0]+highDrift.x-eye.x+700,1400)-700,
                                     Self.mod(volume.home[1]-eye.z+150,300)-150,
                                     Self.mod(volume.home[2]+highDrift.z+eye.y+700,1400)-700)
                let away = simd_length(offThree)
                var opacity = max(0,volume.density-faded)
                if away > reach-100 { opacity = min(opacity,(reach-away)*opacity/100) }
                opacity *= 1-Self.smoothstep(100,150,abs(offThree.y))
                let center = eye+SIMD3(offThree.x,-offThree.z,offThree.y)
                // Exactly the original three crossed planes, with ±0.5 vertices.
                let axes: [(SIMD3<Double>,SIMD3<Double>,Double)] = [
                    (SIMD3(volume.girth[0]*0.5,0,0),SIMD3(0,0,volume.girth[1]*0.5),offThree.z),
                    (SIMD3(volume.girth[0]*0.5,0,0),SIMD3(0,volume.girth[2]*0.5,0),offThree.y),
                    (SIMD3(0,volume.girth[2]*0.5,0),SIMD3(0,0,volume.girth[1]*0.5),offThree.x)]
                for (horizontal,vertical,facing) in axes {
                    let a = opacity*abs(facing/max(away,0.001))
                    guard a > 0 else { continue }
                    quads.append(Quad(texture: "cloudhigh",center: Self.float(center),right: Self.float(horizontal),up: Self.float(vertical),
                        tint: SIMD4(Float(grey),Float(grey),Float(grey),Float(a)),topLeftTint: nil,blend: .alpha,depthTest: true,paintedOnSky: false,flipV: true,shading: .cloud))
                }
            }
        }
        var rainbow: Rainbow?
        let rainbowShare = outdoors && data.constants["w$"]!.flat.contains(Double(weatherFrom)) && data.constants["wJ"]!.flat.contains(Double(weatherTo)) && change < 0.5 && whole > 6 && whole < 21 ? 1-4*abs(change-0.25) : 0
        if rainbowShare > 0 {
            let horizontal = hypot(sun.x,sun.y), distance = horizontal == 0 ? 1 : horizontal
            let turn = max(-Double.pi/6,-atan2(sun.z,distance))
            let middleFlat = SIMD3(-sun.x/distance,-sun.y/distance,0)
            let middle = middleFlat*cos(turn)+SIMD3(0,0,sin(turn))
            // Original Three cross/negation, transformed into GTA coordinates.
            let across = SIMD3(middleFlat.y,-middleFlat.x,0)
            let over = -simd_cross(across,middle)
            rainbow = Rainbow(middle: Self.float(middle),across: Self.float(across),over: Self.float(over),
                colors: data.constants["wY"]!.nested.map { SIMD3(Float($0[0]/255),Float($0[1]/255),Float($0[2]/255)) },strength: Float(1.5*rainbowShare*visibility))
        }
        var meteor: Meteor?
        let elapsed = milliseconds.truncatingRemainder(dividingBy: 8192), number = floor(milliseconds/8192).truncatingRemainder(dividingBy: 64)
        if outdoors && visibility >= 1 && whole < 5 && elapsed < 800 && data.constants["wQ"]!.flat.contains(Double(weatherFrom)) && data.constants["wQ"]!.flat.contains(Double(weatherTo)) {
            let along = simd_normalize(SIMD3((number.truncatingRemainder(dividingBy: 7)-3)*0.1,(floor(milliseconds/8192).truncatingRemainder(dividingBy: 8)-4)*0.1,1))
            let from = simd_normalize(SIMD3(number.truncatingRemainder(dividingBy: 9)-5,number.truncatingRemainder(dividingBy: 10)-5,0.1))*1000
            let gone = (400-elapsed)*2
            meteor = Meteor(head: Self.float(eye+from+along*gone),tail: Self.float(eye+from+along*(gone+50)))
        }
        return Snapshot(quads: quads, belowColor: Self.float(belowColor), sunDirection: Self.float(sun),rainbow: rainbow,meteor: meteor,sheetDrift: Float(sheetDrift),highFade: Float(highFade))
    }

    private static func clamp(_ value: Double) -> Double { max(0,min(1,value)) }
    private static func mod(_ x: Double, _ y: Double) -> Double { x-floor(x/y)*y }
    private static func smoothstep(_ a: Double,_ b: Double,_ x: Double) -> Double { let t = clamp((x-a)/(b-a)); return t*t*(3-2*t) }
    private static func float(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x),Float(v.y),Float(v.z)) }
    private static func float(_ v: SIMD4<Double>) -> SIMD4<Float> { SIMD4(Float(v.x),Float(v.y),Float(v.z),Float(v.w)) }
}
