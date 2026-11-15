import Foundation
import simd

/// Archived-browser ledge query adapter. Controlled native/WASM scene fixtures
/// cover query construction, filtering and clearance; retail GTA is unverified.
final class NativeRapierClimbQueries {
    typealias V=SIMD3<Double>
    let world:SwiftRapierWorld
    var excluded:Set<UInt64>
    init(world:SwiftRapierWorld,excluded:Set<UInt64>) {
        self.world=world;self.excluded=excluded
    }
    private func f(_ v:V)->SIMD3<Float>{SIMD3(Float(v.x),Float(v.y),Float(v.z))}
    private func collider(_ value:SwiftRapierWorld.ColliderInfo)->NativeClimbProbe.Collider {
        guard let body=value.body else{return .init(fixed:true,speed:0,material:value.material)}
        guard let kind=world.bodyKind(body),let state=world.bodyState(body) else {
            // Unknown parent cannot become a static handhold or be ignored
            // by body-clearance tests. Keep the nearest-hit query boundary.
            return .init(fixed:false,speed:.infinity,material:value.material,known:false)
        }
        return .init(fixed:kind == .fixed,speed:simd_length(V(state.linearVelocity)),material:value.material)
    }
    func find(feet:V,heading:Double,extended:Bool=true)->NativeClimbController.Ledge? {
        let probe=NativeClimbProbe(ray:{[unowned self] origin,direction,distance,groups in
            var ignored=excluded
            // The original predicate removes PED before choosing a closest
            // hit. Rejecting the returned nearest PED would incorrectly hide
            // a real climbable wall behind it.
            while let hit=world.queryRay(origin:f(origin),direction:f(direction),distance:Float(distance),groups:groups,excludingColliders:ignored) {
                if hit.collider.material==62 {ignored.insert(hit.collider.id);continue}
                return .init(distance:Double(hit.distance),normal:V(hit.normal),collider:collider(hit.collider))
            }
            return nil
        },overlaps:{[unowned self] origin,radius,groups in
            // Native zero-height capsule matched original Ball clearance in
            // the controlled native/WASM fixtures; general grazing is untested.
            world.intersections(center:f(origin),halfHeight:0,radius:Float(radius),groups:groups,excludingColliders:excluded)
                .filter{$0.material != 62}.map(collider)
        })
        return probe.find(feet:feet,heading:heading,extended:extended)
    }
}
