import Foundation
import simd
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let massRows=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("mass-reference.json"))) as! [[String:Any]]
let world=SwiftRapierWorld(gravity:.zero)!
func mass(_ value:Float)->SwiftRapierWorld.Mass {.init(value:value,centre:SIMD3(0.2,0,0),turnMass:value)}
let body=world.addBody(position:.zero,mass:mass(100))!
world.addSphere(radius:0.3,body:body)
var stage=0
func check(){
    let row=massRows[stage],expected=row["velocity"] as! [Double],state=world.bodyState(body)!
    precondition(Double(world.mass(of:body)!)==row["mass"] as! Double,"Effective mass timing at \(row["label"]!)")
    for i in 0..<3 {precondition(Double(state.linearVelocity[i])==expected[i])}
    stage += 1
}
func push(){world.applyImpulse(SIMD3(100,0,0),to:body)}
check();push();check();world.step();check();push();check();world.setMass(mass(200),for:body);check();push();check()
world.step();check();push();check();world.setMass(mass(400),for:body);check();world.recomputeMassProperties(body);check();push();check()
precondition(stage==11)
let frictionRows=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("friction-reference.json"))) as! [[String:Any]]
var maximum:Float=0,frames=0
for row in frictionRows {
    let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
    let floor=world.addTriangleMesh(.init(vertices:[SIMD3(-100,0,-100),SIMD3(100,0,-100),SIMD3(100,0,100),SIMD3(-100,0,100)],indices:[0,2,1,0,3,2]))!
    if row["floorRule"] as! String == "Min" {precondition(world.setColliderFrictionCombine(floor,.min))}
    let body=world.addBody(position:SIMD3(0,0.3,0),mass:.init(value:100,turnMass:10000),gravityScale:1)!
    world.setVelocities(body,linear:SIMD3(6,0,0),angular:.zero)
    let shape=world.addSphere(radius:0.3,body:body,friction:1)!
    precondition(world.setColliderFrictionCombine(shape,row["bodyRule"] as! String == "Average" ? .average:.min))
    for expected in row["frames"] as! [[String:Any]] {
        precondition(world.step());let actual=world.bodyState(body)!
        let fields:[(String,[Float])]=[("position",[actual.position.x,actual.position.y,actual.position.z]),
            ("rotation",Array([actual.rotation.imag.x,actual.rotation.imag.y,actual.rotation.imag.z,actual.rotation.real])),
            ("velocity",[actual.linearVelocity.x,actual.linearVelocity.y,actual.linearVelocity.z]),
            ("angular",[actual.angularVelocity.x,actual.angularVelocity.y,actual.angularVelocity.z])]
        for (name,values) in fields {for (actual,expected) in zip(values,expected[name] as! [Double]) {maximum=max(maximum,abs(actual-Float(expected)))}}
        frames += 1
    }
}
precondition(maximum<1e-5,"Friction combine/core path differs from original")
print("PASS: all11 original JS mass/impulse stages exact;\(frames) Average/Min contact frames maximum \(maximum)")
