import Foundation
import simd

/// SCL2 is the archive's collision mesh for each detailed city cell.
/// Queries use the same triangles as the browser world's solid geometry.
final class WorldCollision {
    private struct Triangle {
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        let normal: SIMD3<Float>
        let surface: Int
        let material: Int
    }
    private let triangles: [Triangle]
    private let cells: [Int: [Int]]
    private let minX: Float
    private let minY: Float
    private let width: Int
    private let large: [Int]
    private let cellSize: Float = 10

    enum Error: Swift.Error { case invalidHeader, invalidLength, invalidIndex }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 |
                UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func f32(_ at: Int) -> Float { Float(bitPattern: u32(at)) }
        guard bytes.count >= 16, u32(0) == 0x324c4353 else { throw Error.invalidHeader }
        let vertexCount = Int(u32(4)), triangleCount = Int(u32(8))
        guard vertexCount < 1_000_000, triangleCount < 1_000_000,
              (vertexCount > 0 && triangleCount > 0) || (vertexCount == 0 && triangleCount == 0) else { throw Error.invalidHeader }
        let indexStart = 16 + vertexCount * 12
        let surfaceStart = indexStart + triangleCount * 12
        let padded = ((triangleCount+3)/4)*4
        let materialStart = surfaceStart+padded
        let hasMaterials = u32(12)&1 != 0 && materialStart+triangleCount <= bytes.count
        guard indexStart + triangleCount * 12 <= bytes.count else { throw Error.invalidLength }
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(vertexCount)
        for n in 0..<vertexCount {
            let at = 16 + n * 12
            let point = SIMD3(f32(at), f32(at + 4), f32(at + 8))
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { throw Error.invalidHeader }
            points.append(point)
        }
        minX = floor((points.map(\.x).min() ?? -3000) / cellSize) * cellSize
        minY = floor((points.map(\.y).min() ?? -3000) / cellSize) * cellSize
        width = max(1, Int(ceil(((points.map(\.x).max() ?? minX + 375) - minX) / cellSize)) + 1)
        var built: [Triangle] = []
        var lookup: [Int: [Int]] = [:]
        var oversized: [Int] = []
        built.reserveCapacity(triangleCount)
        for n in 0..<triangleCount {
            let at = indexStart + n * 12
            let ia = Int(u32(at)), ib = Int(u32(at + 4)), ic = Int(u32(at + 8))
            guard ia < points.count, ib < points.count, ic < points.count else { throw Error.invalidIndex }
            let a = points[ia], b = points[ib], c = points[ic]
            let normal = simd_cross(b - a, c - a)
            guard simd_length_squared(normal) > 0.00001 else { continue }
            let loX = Int(floor((min(a.x, b.x, c.x) - minX) / cellSize))
            let hiX = Int(floor((max(a.x, b.x, c.x) - minX) / cellSize))
            let loY = Int(floor((min(a.y, b.y, c.y) - minY) / cellSize))
            let hiY = Int(floor((max(a.y, b.y, c.y) - minY) / cellSize))
            // Airport aprons and long road surfaces use triangles wider than
            // 150 m. Dropping them left aircraft with no floor to land on.
            let number = built.count
            built.append(Triangle(a: a, b: b, c: c, normal: normal,
                surface: surfaceStart+n < bytes.count ? Int(bytes[surfaceStart+n]) : 0,
                material: hasMaterials ? Int(bytes[materialStart+n]) : 0))
            if hiX-loX > 64 || hiY-loY > 64 || (hiX-loX+1)*(hiY-loY+1)>4096 {
                oversized.append(number); continue
            }
            for y in loY...hiY { for x in loX...hiX { lookup[y * width + x, default: []].append(number) } }
        }
        triangles = built
        cells = lookup
        large = oversized
    }

    private func candidates(_ x: Float, _ y: Float) -> [Int] {
        let gx = Int(floor((x - minX) / cellSize))
        let gy = Int(floor((y - minY) / cellSize))
        return (cells[gy * width + gx] ?? []) + large
    }

    func height(x: Float, y: Float, near previous: Float, maxDrop: Float = 0.8) -> Float? {
        ground(x:x,y:y,near:previous,maxDrop:maxDrop)?.height
    }
    struct Ground { let height: Float; let surface: Int; let material: Int }
    func ground(x: Float, y: Float, near previous: Float, maxDrop: Float = 0.8) -> Ground? {
        var best: Ground?
        for index in candidates(x, y) {
            let t = triangles[index]
            guard abs(t.normal.z) > 0.35 * simd_length(t.normal) else { continue }
            let denominator = (t.b.y - t.c.y) * (t.a.x - t.c.x) +
                (t.c.x - t.b.x) * (t.a.y - t.c.y)
            if abs(denominator) < 0.0001 { continue }
            let u = ((t.b.y - t.c.y) * (x - t.c.x) +
                     (t.c.x - t.b.x) * (y - t.c.y)) / denominator
            let v = ((t.c.y - t.a.y) * (x - t.c.x) +
                     (t.a.x - t.c.x) * (y - t.c.y)) / denominator
            let w = 1 - u - v
            if u < -0.002 || v < -0.002 || w < -0.002 { continue }
            let z = u * t.a.z + v * t.b.z + w * t.c.z
            // Keep the player on the upper street when a basement or tunnel
            // surface overlaps it. A single frame cannot drop several metres.
            if z <= previous + 1.5 && z >= previous - maxDrop &&
                z > (best?.height ?? -.infinity) {
                best = Ground(height:z,surface:t.surface,material:t.material)
            }
        }
        return best
    }

    func canMove(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float,
                 bodyHeight: Float) -> Bool {
        let vector = SIMD2(to.x - from.x, to.y - from.y)
        let distance = simd_length(vector)
        if distance < 0.0001 { return true }
        let lateral = SIMD2(-vector.y, vector.x) / distance * radius
        let ids = Set(candidates(from.x, from.y) + candidates(to.x, to.y))
        for id in ids {
            let triangle = triangles[id]
            guard abs(triangle.normal.z) < 0.65 * simd_length(triangle.normal) else { continue }
            for amount in [-1 as Float, 0, 1] {
                let offset = lateral * amount
                for elevation in [bodyHeight * 0.35, bodyHeight * 0.8] {
                    let start = from + SIMD3(offset.x, offset.y, elevation)
                    let finish = to + SIMD3(offset.x, offset.y, elevation)
                    if Self.intersects(start: start, finish: finish, triangle: triangle) { return false }
                }
            }
        }
        return true
    }

    func lineOfSight(from start: SIMD3<Float>, to finish: SIMD3<Float>) -> Bool {
        let distance = simd_distance(start, finish)
        let steps = max(1, Int(ceil(distance / 5)))
        var ids: Set<Int> = []
        for step in 0...steps {
            let point = start + (finish - start) * (Float(step) / Float(steps))
            ids.formUnion(candidates(point.x, point.y))
        }
        for id in ids where Self.intersects(start: start, finish: finish,
                                             triangle: triangles[id]) { return false }
        return true
    }

    struct Contact { let distance: Float; let normal: SIMD3<Float> }
    func raycast(from start: SIMD3<Float>, direction: SIMD3<Float>, distance: Float) -> Contact? {
        guard distance > 0, simd_length_squared(direction) > 0.0001 else { return nil }
        let unit = simd_normalize(direction), finish = start + unit * distance
        let steps = max(1, Int(ceil(distance / 5)))
        var ids: Set<Int> = []
        for n in 0...steps {
            let point = start + (finish-start) * (Float(n)/Float(steps))
            ids.formUnion(candidates(point.x, point.y))
        }
        var nearest: Contact?
        for id in ids {
            let t = triangles[id]
            guard let fraction = Self.intersectionFraction(start: start, finish: finish, triangle: t) else { continue }
            let at = fraction * distance
            if at < (nearest?.distance ?? .infinity) {
                var normal = simd_normalize(t.normal)
                if simd_dot(normal,unit) > 0 { normal = -normal }
                nearest = Contact(distance: at, normal: normal)
            }
        }
        return nearest
    }

    private static func intersects(start: SIMD3<Float>, finish: SIMD3<Float>,
                                   triangle: Triangle) -> Bool {
        intersectionFraction(start: start, finish: finish, triangle: triangle) != nil
    }
    private static func intersectionFraction(start: SIMD3<Float>, finish: SIMD3<Float>,
                                             triangle: Triangle) -> Float? {
        let direction = finish - start
        let edge1 = triangle.b - triangle.a
        let edge2 = triangle.c - triangle.a
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)
        if abs(determinant) < 0.000001 { return nil }
        let inverse = 1 / determinant
        let delta = start - triangle.a
        let u = simd_dot(delta, p) * inverse
        if u < 0 || u > 1 { return nil }
        let q = simd_cross(delta, edge1)
        let v = simd_dot(direction, q) * inverse
        if v < 0 || u + v > 1 { return nil }
        let t = simd_dot(edge2, q) * inverse
        return t >= 0 && t <= 1 ? t : nil
    }
}
