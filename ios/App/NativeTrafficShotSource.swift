// SPDX-License-Identifier: AGPL-3.0-only
import simd

/// Immediate compact-traffic shot origins. The car group excludes the model
/// origin used by its mesh and riders. An unavailable selected muzzle uses
/// the car fallback; it never tries another occupant or waits for a model.
enum NativeTrafficShotSource {
    struct Car {
        let position:SIMD3<Double>
        let rotation:simd_quatd,distance:Double
        let visible:Bool,hasRearPassenger:Bool
    }
    struct Sample {
        let origin:SIMD3<Double>
        let side:Int,seat:Int
        let posed:Bool
    }
    static func sample(target:SIMD3<Double>,car:Car,
                       muzzle:(Int)->SIMD3<Double>?)->Sample? {
        guard car.visible,car.distance.isFinite,car.distance<=150,
              (0..<4).allSatisfy({car.rotation.vector[$0].isFinite}),
              abs(simd_length_squared(car.rotation.vector)-1)<1e-6,finite(car.position),finite(target) else{return nil}
        let rotation=car.rotation
        let local=rotation.inverse.act(target-car.position)
        let side=local.x>=0 ? 1:-1
        let seat=side>0 ? 1:car.hasRearPassenger ? 2:0
        if let origin=muzzle(seat),finite(origin) {
            return .init(origin:origin,side:side,seat:seat,posed:true)
        }
        // Browser local (side*.95, 1, .3) -> native GTA (x, -z, y).
        let origin=car.position+rotation.act(SIMD3(Double(side)*0.95,-0.3,1))
        return .init(origin:origin,side:side,seat:seat,posed:false)
    }
    private static func finite(_ value:SIMD3<Double>)->Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
