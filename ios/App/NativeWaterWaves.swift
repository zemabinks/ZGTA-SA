import Foundation
import simd

/// Direct translation of public modules 9527 and 45065. Coordinates are GTA
/// east/north/up. Water polygons/heights still come from NativeWorldWater.
final class NativeWaterWaves {
    struct Sample { let height: Float; let normal: SIMD3<Float> }
    struct RenderUniforms {
        let tint: SIMD4<Float>
        let alphas: SIMD2<Float>
        let shifts: SIMD4<Float>
        /// Three phases followed by the browser's 0.67 × roughness.
        let waves: SIMD4<Float>
    }
    private struct Document: Decodable {
        let regions: [[Double]]
        let xFactors: [Double]
        let yFactors: [Double]
        let wind: [Double]
        let components: [[Double]]
    }
    enum Error: Swift.Error { case invalidTable }
    private var table: Document?
    private var request: URLSessionDataTask?
    private var lastRegion: Int?
    private var phases = SIMD3<Double>.zero
    private var roughness: Double = 0
    private var eye = SIMD2<Double>.zero
    private let override: SIMD2<Double>?
    var isLoaded: Bool { table != nil }
    var rough: Float { Float(roughness) }
    var xFactors: [Float] { table?.xFactors.map(Float.init) ?? [] }
    var yFactors: [Float] { table?.yFactors.map(Float.init) ?? [] }

    init(amplitudes: SIMD2<Float>? = nil) {
        override = amplitudes.map { SIMD2(Double($0.x),Double($0.y)) }
    }
    convenience init(data: Data, amplitudes: SIMD2<Float>? = nil) throws {
        self.init(amplitudes: amplitudes); try install(data)
    }
    deinit { request?.cancel() }
    func load(server: ServerAddress, completion: (() -> Void)? = nil) {
        request?.cancel()
        request = URLSession.shared.dataTask(with: server.path("game/native/water-waves.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async {
                guard let self,(try? self.install(data)) != nil else { return }; completion?()
            }
        }
        request?.resume()
    }
    private func install(_ data: Data) throws {
        let value = try JSONDecoder().decode(Document.self,from: data)
        guard value.regions.allSatisfy({ $0.count == 12 && $0.allSatisfy(\.isFinite) && $0[0] < $0[2] && $0[1] < $0[3] }),
              value.xFactors.count == 8,value.yFactors.count == 8,value.wind.count == 23,
              (value.xFactors+value.yFactors+value.wind).allSatisfy(\.isFinite),
              value.components.count == 3,value.components.allSatisfy({ $0.count == 4 && $0[0] > 0 && $0.allSatisfy(\.isFinite) }) else { throw Error.invalidTable }
        table = value; lastRegion = nil
    }
    func weatherRoughness(from: Int,to: Int,blend: Float) -> Float {
        guard let table else { return 0 }
        let a = table.wind.indices.contains(from) ? table.wind[from] : 0
        let b = table.wind.indices.contains(to) ? table.wind[to] : 0
        return Float(min(1,min(1,a*(1-Double(blend))+b*Double(blend))+0.3))
    }
    func set(timeMilliseconds: Double,roughness: Float) {
        guard let table,timeMilliseconds.isFinite,roughness.isFinite else { return }
        self.roughness = Double(roughness)
        for i in 0..<3 { phases[i] = timeMilliseconds.truncatingRemainder(dividingBy: table.components[i][0])/table.components[i][0]*2*Double.pi }
    }
    func look(x: Float,y: Float) { eye = SIMD2(Double(x),Double(y)) }
    func heights(x: Float,y: Float) -> SIMD2<Float>? {
        amplitudes(Double(x),Double(y)).map { SIMD2(Float($0.x),Float($0.y)) }
    }
    private func amplitudes(_ inputX: Double,_ inputY: Double) -> SIMD2<Double>? {
        if let override { return override }
        guard let table,inputX.isFinite,inputY.isFinite else { return nil }
        let x = min(2999,max(-2999,inputX)),y = min(2999,max(-2999,inputY))
        func contains(_ row: [Double]) -> Bool { x >= row[0] && x <= row[2] && y >= row[1] && y <= row[3] }
        if lastRegion == nil || !contains(table.regions[lastRegion!]) {
            lastRegion = table.regions.firstIndex(where: contains)
        }
        guard let index = lastRegion else { return nil }
        let row = table.regions[index],u = (x-row[0])/(row[2]-row[0]),v = (y-row[1])/(row[3]-row[1])
        let first = (row[4]*(1-u)+row[5]*u)*(1-v)+(row[6]*(1-u)+row[7]*u)*v
        let second = (row[8]*(1-u)+row[9]*u)*(1-v)+(row[10]*(1-u)+row[11]*u)*v
        return SIMD2(first,second)
    }
    /// The public renderer's 265×265 half-metre replacement net. Sea values
    /// contain base height, the two amplitudes, and shoreline visibility. The
    /// one-metre samples and interpolation/edge treatment match its JS exactly.
    func nearGrid(origin: SIMD2<Float>,ground: (Float,Float) -> Float?) -> [SIMD4<Float>]? {
        guard let table else { return nil }
        let x = Double(origin.x),y = Double(origin.y)
        let overlap = x-66 < -2999 || y-66 < -2999 || x+66 > 2999 || y+66 > 2999 || table.regions.contains { x+66 >= $0[0] && x-66 <= $0[2] && y+66 >= $0[1] && y-66 <= $0[3] }
        guard overlap else { return nil }
        var values = [SIMD4<Float>](repeating: .zero,count: 265*265),any = false
        for row in stride(from: 0,through: 264,by: 2) {
            for col in stride(from: 0,through: 264,by: 2) {
                let px = origin.x+Float(col)*0.5-66,py = origin.y+Float(row)*0.5-66
                let height = ground(px,py),wave = heights(x: px,y: py)
                values[row*265+col] = SIMD4(height ?? 0,wave?.x ?? 0,wave?.y ?? 0,height != nil && wave != nil ? 1 : -1)
                if height != nil && wave != nil { any = true }
            }
        }
        guard any else { return nil }
        for row in stride(from: 0,through: 264,by: 2) {
            for col in stride(from: 0,through: 264,by: 2) {
                let n = row*265+col,left = col > 0 ? n-2 : n,right = col < 264 ? n+2 : n
                let top = row > 0 ? n-530 : n,bottom = row < 264 ? n+530 : n
                if values[n].w >= 0 {
                    if [left,right,top,bottom].contains(where: { values[$0].w < 0 }) { values[n].w = 0 }
                } else if let other = [left,right,top,bottom].first(where: { values[$0].w >= 0 }) { values[n].x = values[other].x }
            }
        }
        for row in stride(from: 0,through: 264,by: 2) {
            for col in stride(from: 1,through: 263,by: 2) {
                let n = row*265+col; values[n] = (values[n-1]+values[n+1])*0.5
            }
        }
        for row in stride(from: 1,through: 263,by: 2) {
            for col in 0..<265 { let n = row*265+col; values[n] = (values[n-265]+values[n+265])*0.5 }
        }
        return values
    }
    func isWavy(min: SIMD2<Float>,max: SIMD2<Float>) -> Bool {
        table?.regions.contains { $0[0] == Double(min.x) && $0[1] == Double(min.y) && $0[2] == Double(max.x) && $0[3] == Double(max.y) } ?? false
    }

    func rise(x: Float,y: Float) -> Sample {
        guard let table,roughness > 0,let heights = amplitudes(Double(x),Double(y)) else {
            return Sample(height: 0,normal: SIMD3(0,0,1))
        }
        func factor(_ values: [Double],_ coordinate: Double) -> Double {
            let at = abs(coordinate)/2,whole = floor(at),share = at-whole
            let index = Int(whole.truncatingRemainder(dividingBy: 8))
            return values[index]*(1-share)+values[(index+1)%8]*share
        }
        let scale = factor(table.xFactors,Double(x))*factor(table.yFactors,Double(y))*roughness
        var height: Double = 0,dx: Double = 0,dy: Double = 0
        for i in 0..<3 {
            let component = table.components[i],amplitude = component[3]*heights[i == 0 ? 0 : 1]*scale
            if amplitude == 0 { continue }
            let phase = phases[i]+(abs(Double(x))*component[1]+abs(Double(y))*component[2])*2*Double.pi
            height += sin(phase)*amplitude
            let derivative = cos(phase)*amplitude*2*Double.pi
            dx += derivative*component[1]*(x == 0 ? 0 : x < 0 ? -1 : 1)
            dy += derivative*component[2]*(y == 0 ? 0 : y < 0 ? -1 : 1)
        }
        let normal = simd_normalize(SIMD3<Double>(-dx,-dy,1))
        return Sample(height: Float(height),normal: SIMD3(Float(normal.x),Float(normal.y),Float(normal.z)))
    }
    func shown(x: Float,y: Float) -> Float {
        let share = hypot(Double(x)-eye.x,Double(y)-eye.y)/48
        return share >= 1 ? 0 : rise(x: x,y: y).height*Float(min(1,(1-share)/0.25))
    }
    /// Exact water color/alpha/texture drift uniforms from module 45065.We.
    func renderUniforms(timeMilliseconds: Double,color: SIMD4<Float>) -> RenderUniforms {
        let level = floor(255*Double(color.w)*0.5)
        let alpha = SIMD2(Float(min(255,floor(256*level/(256-level)))/255),Float(level/255))
        let slow = timeMilliseconds.truncatingRemainder(dividingBy: 8192)/8192*2*Double.pi
        let fast = timeMilliseconds.truncatingRemainder(dividingBy: 4096)/4096*2*Double.pi
        return RenderUniforms(tint: color,alphas: alpha,
            shifts: SIMD4(0.5,Float(0.5+0.024*cos(slow)),Float(0.5+sin(fast)*roughness*0.08),Float(0.5+cos(fast)*roughness*0.08)),
            waves: SIMD4(Float(phases.x),Float(phases.y),Float(phases.z),Float(0.67*roughness)))
    }
}
