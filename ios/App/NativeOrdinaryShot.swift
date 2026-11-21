// SPDX-License-Identifier: AGPL-3.0-only
import simd

/// Presentation observations only. No inventory, health, damage request,
/// projectile authority or destructible-object mutation belongs to this path.
enum NativeOrdinaryShot {
    enum Impact:Equatable {case person,car,world}
    struct Event {
        let weapon:Int
        let origin:SIMD3<Double>,end:SIMD3<Double>
        let impact:Impact?
        var piece:Int? = nil
    }
    typealias Along=(_ origin:SIMD3<Double>,_ direction:SIMD3<Double>,_ length:Double)->Double?
    static func traffic(_ shot:NativeAmbientTrafficProtocol.Shot,origin:SIMD3<Double>,along:Along?)->Event? {
        guard finite(origin),finite(shot.target) else{return nil}
        var end=shot.target,impact:Impact?
        switch shot.kind {
        case 1:impact = .person
        case 2:impact = .car
        case 0:
            let offset=end-origin,length=simd_length(offset)
            if length>0.5,let along,let distance=along(origin,offset/length,length),
               distance.isFinite,distance>=0,distance<=length {
                end=origin+offset*(distance/length);impact = .world
            }
        default:break
        }
        return .init(weapon:Int(shot.weapon),origin:origin,end:end,impact:impact)
    }
    static func finite(_ value:SIMD3<Double>)->Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
