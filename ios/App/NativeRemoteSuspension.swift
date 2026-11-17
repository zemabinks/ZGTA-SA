// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation
import simd

/// Visual wheel travel at an already-authoritative draw pose. This never moves
/// a body, creates a collider, or applies forces. Coordinates are GTA Z-up.
enum NativeRemoteSuspension {
    typealias V = SIMD3<Double>
    struct Wheel { let index: Int; let centre: V; let radius: Double }
    struct Configuration {
        let model: Int
        let origin: Double
        let upper: Double
        let lower: Double
        let wheels: [Wheel]

        /// Aircraft, rail, watercraft and astride rigs have separate suspension
        /// and gear/lean controls. Hydraulic travel must keep its existing owner.
        init?(_ row: [String: Any]) {
            func number(_ raw: Any?) -> Double? {
                guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
                return n.doubleValue
            }
            guard let id = number(row["id"]).flatMap(Int.init(exactly:)), (400...611).contains(id),
                  let kind = row["kind"] as? String, ["car", "trailer"].contains(kind),
                  let origin = number(row["origin"]), abs(origin) < 100,
                  let table = row["table"] as? [String: Any], let upper = number(table["upper"]),
                  let lower = number(table["lower"]), lower < upper, upper <= 5, lower >= -5,
                  let flags = number(table["flags"]).flatMap(Int.init(exactly:)), flags & 131072 == 0,
                  row["hydraulics"] as? Bool != true,
                  let rows = (row["struts"] ?? row["wheels"]) as? [[String: Any]], (1...16).contains(rows.count) else { return nil }
            var selected = [Int: Wheel]()
            for row in rows {
                guard let p = row["centre"] as? [Double], p.count == 3,
                      p.allSatisfy({ $0.isFinite && abs($0) < 100 }),
                      let radius = number(row["radius"]), radius > 0, radius <= 5,
                      radius + upper - lower <= 10,
                      let front = row["front"] as? Bool, let left = row["left"] as? Bool else { return nil }
                let index = (left ? 0 : 2) + (front ? 0 : 1)
                // Metadata's wheel centres include the origin in Rapier axes.
                // Convert to authored-model GTA coordinates once, here.
                let wheel = Wheel(index: index, centre: V(p[0], -p[2], p[1] - origin), radius: radius)
                if let previous = selected[index] {
                    if front ? wheel.centre.y > previous.centre.y : wheel.centre.y < previous.centre.y { selected[index] = wheel }
                } else { selected[index] = wheel }
            }
            self.model = id; self.origin = origin; self.upper = upper; self.lower = lower
            wheels = selected.keys.sorted().map { selected[$0]! }
        }
    }
    struct Ray { let origin: V; let direction: V; let distance: Double }
    enum Contact { case unavailable, clear, hit(distance: Double, normal: V) }
    struct Frame { let offsets: [Double]; let contacts: [Bool] }

    /// No time integration or easing: equal draw poses and collision coverage
    /// produce equal travel at 15/30/60/120/144 Hz. Missing coverage returns nil
    /// rather than manufacturing a ground plane. Known airborne travel droops.
    static func sample(_ configuration: Configuration, model: simd_float4x4,
                       tyres: [Int] = [], query: (Ray) -> Contact) -> Frame? {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { model[column][$0].isFinite } }),
              abs(model[3].w - 1) < 0.001 else { return nil }
        func vector(_ column: SIMD4<Float>) -> V { V(Double(column.x), Double(column.y), Double(column.z)) }
        let right = vector(model[0]), forward = vector(model[1])
        let up = vector(model[2]), place = vector(model[3])
        guard [right, forward, up].allSatisfy({ abs(simd_length_squared($0) - 1) < 0.003 }),
              abs(simd_dot(right, forward)) < 0.003, abs(simd_dot(right, up)) < 0.003,
              abs(simd_dot(forward, up)) < 0.003, up.z > 0.15,
              abs(simd_determinant(simd_double3x3(columns: (right, forward, up))) - 1) < 0.003 else { return nil }
        var offsets = [Double](repeating: 0, count: 4), contacts = [Bool](repeating: false, count: 4)
        for wheel in configuration.wheels {
            offsets[wheel.index] = configuration.lower
            let start = wheel.centre + V(0, 0, configuration.upper)
            let origin = place + right * start.x + forward * start.y + up * start.z
            let length = configuration.upper - configuration.lower + wheel.radius
            switch query(Ray(origin: origin, direction: -up, distance: length)) {
            case .unavailable: return nil
            case .clear: break
            case let .hit(distance, normal):
                guard distance.isFinite, distance >= 0, distance <= length + 0.00001,
                      normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
                      simd_length_squared(normal) > 0.000001 else { return nil }
                guard simd_dot(simd_normalize(normal), up) > 0.05 else { continue }
                let tyre = tyres.indices.contains(wheel.index) ? tyres[wheel.index] : 0
                guard tyre < 2 else { continue }
                let radius = wheel.radius * (tyre == 1 ? 0.75 : 1)
                offsets[wheel.index] = max(configuration.lower, min(configuration.upper, configuration.upper + radius - distance))
                contacts[wheel.index] = true
            }
        }
        return Frame(offsets: offsets, contacts: contacts)
    }
}
