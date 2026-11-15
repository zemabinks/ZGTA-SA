import simd

/// Shared mutable normalized-velocity context passed by original23895 to the
/// original aircraft89888 and buoyancy3104 solvers, in their original order.
final class NativeVehicleForces {
    typealias V = SIMD3<Double>
    var move: V
    var turn: V
    let right: V
    let forward: V
    let up: V
    let middle: V
    let place: V
    let quaternion: simd_quatd
    let mass: Double
    let turnMass: Double
    var wheels: Int
    init(move:V,turn:V,right:V,forward:V,up:V,middle:V,place:V,quaternion:simd_quatd,mass:Double,turnMass:Double,wheels:Int) {
        self.move=move;self.turn=turn;self.right=right;self.forward=forward;self.up=up;self.middle=middle
        self.place=place;self.quaternion=quaternion;self.mass=mass;self.turnMass=turnMass;self.wheels=wheels
    }
    func speed(at point:V)->V { move-simd_cross(point-middle,turn) }
    func pushTurn(_ force:V,at point:V) { turn += simd_cross(point-middle,force)/turnMass }
    func pushMove(_ force:V) { move += force/mass }
    func torque(_ axis:V,_ amount:Double,at arm:V) { turn += simd_cross(arm,axis*amount) }
    func axes(_ x:Double,_ forwardAmount:Double,_ vertical:Double)->V { right*x+forward*forwardAmount+up*vertical }
    static func clamp(_ value:Double,_ low:Double,_ high:Double)->Double { min(high,max(low,value)) }
}
