import Foundation
import simd

/// The water polygons in world/index.json use the game's native x/y/z axes.
struct NativeWorldWater {
    let polygons: [[SIMD3<Float>]]
    private struct Bounds { let minX: Float; let maxX: Float; let minY: Float; let maxY: Float; let shallow: Bool }
    private let bounds: [Bounds]
    private let grid: [Int:[Int]]
    private static func cell(_ coordinate: Float) -> Int { max(0,min(23,Int(floor((coordinate+3000)/250)))) }
    init(rows: [[Float]]) {
        let polygons: [[SIMD3<Float>]] = rows.compactMap { row in
            guard row.count == 9 || row.count == 12, row.allSatisfy(\.isFinite) else { return nil }
            return stride(from: 0, to: row.count, by: 3).map { SIMD3(row[$0], row[$0 + 1], row[$0 + 2]) }
        }
        self.polygons = polygons
        bounds = polygons.map { p in
            let minX = p.map(\.x).min()!,maxX = p.map(\.x).max()!,minY = p.map(\.y).min()!,maxY = p.map(\.y).max()!
            return Bounds(minX: minX,maxX: maxX,minY: minY,maxY: maxY,
                          shallow: p.map(\.z).min()! > 1 && maxX-minX <= 40 && maxY-minY <= 40)
        }
        var grid: [Int:[Int]] = [:]
        for (index,b) in bounds.enumerated() {
            for x in Self.cell(b.minX)...Self.cell(b.maxX) {
                for y in Self.cell(b.minY)...Self.cell(b.maxY) { grid[y*24+x,default: []].append(index) }
            }
        }
        self.grid = grid
    }
    func height(x: Float, y: Float, z: Float) -> Float? {
        guard x.isFinite,y.isFinite,z.isFinite else { return nil }
        if abs(x) > 3000 || abs(y) > 3000 { return 0 }
        var best: Double?
        for index in grid[Self.cell(y)*24+Self.cell(x)] ?? [] {
            let p = polygons[index],b = bounds[index]
            let minX = b.minX,maxX = b.maxX,minY = b.minY,maxY = b.maxY
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { continue }
            var surface: Double?
            if p.count == 4 {
                if p[0].z == p[1].z,p[0].z == p[2].z,p[0].z == p[3].z { surface = Double(p[0].z) }
                else {
                    let width = Double(p[1].x)-Double(p[0].x),height = Double(p[2].y)-Double(p[0].y)
                    let u = width == 0 ? 0 : min(1,max(0,(Double(x)-Double(p[0].x))/width))
                    let v = height == 0 ? 0 : min(1,max(0,(Double(y)-Double(p[0].y))/height))
                    surface = (Double(p[0].z)*(1-u)+Double(p[1].z)*u)*(1-v)+(Double(p[2].z)*(1-u)+Double(p[3].z)*u)*v
                }
            } else {
                let a = p[0],b = p[1],c = p[2]
                let ax = Double(a.x),ay = Double(a.y),bx = Double(b.x),by = Double(b.y),cx = Double(c.x),cy = Double(c.y)
                let d = (by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
                guard abs(d) >= 1e-9 else { continue }
                let u = ((by-cy)*(Double(x)-cx)+(cx-bx)*(Double(y)-cy))/d
                let v = ((cy-ay)*(Double(x)-cx)+(ax-cx)*(Double(y)-cy))/d
                let w = 1-u-v
                if u >= -1e-6,v >= -1e-6,w >= -1e-6 { surface = Double(a.z)*u+Double(b.z)*v+Double(c.z)*w }
            }
            if let surface, surface.isFinite, surface-Double(z) <= (b.shallow ? 6 : 200), surface > (best ?? -.infinity) { best = surface }
        }
        return best.map(Float.init)
    }
}
