import Foundation
import simd

@main enum VehicleBlastManagerSmoke {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),manager=NativeGroundVehicle()!
        _=manager.loadDefinitions(try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json")))
        let tracks=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/trains.json"))
        precondition(manager.loadTracks(tracks))
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/physics-fixtures/vehicle-blast-manager.json"))) as! [String:Any]
        func v(_ raw:Any)->SIMD3<Float>{let a=raw as! [Double];return SIMD3(Float(a[0]),Float(a[1]),Float(a[2]))}
        var maximumHealth=0.0,maximumAngular=0.0,failures=0
        let cases=document["cases"] as! [[String:Any]]
        for row in cases {
            let model=String(row["model"] as! Int)
            precondition(manager.enter(model:model,modelPosition:SIMD3(0,0,5),heading:0))
            let collider=manager.chassisColliders.first!,body=manager.world.colliderInfo(collider)!.body!
            let before=row["before"] as! [String:Any],q=before["rotation"] as! [Double]
            manager.world.setBodyState(.init(position:v(before["position"]!),rotation:simd_quatf(ix:Float(q[0]),iy:Float(q[1]),iz:Float(q[2]),r:Float(q[3])),
                linearVelocity:v(before["linearVelocity"]!),angularVelocity:v(before["angularVelocity"]!)),for:body)
            manager.applyBlast(centre:v(row["centreGTA"]!))
            let health=manager.damageController!.state.health,expectedHealth=(row["health"] as! NSNumber).doubleValue
            let angular=SIMD3<Double>(manager.world.bodyState(body)!.angularVelocity),reference=SIMD3<Double>(v(row["angularVelocity"]!))
            let healthError=abs(health-expectedHealth),angularError=simd_distance(angular,reference)
            maximumHealth=max(maximumHealth,healthError);maximumAngular=max(maximumAngular,angularError)
            if healthError>1e-8||angularError>1e-7 {if failures<8{print("FAIL \(model): health \(healthError), angular \(angularError)")};failures+=1}
            manager.exit()
        }
        let report:[String:Any]=["cases":cases.count,"maximumHealthError":maximumHealth,"maximumAngularVelocityError":maximumAngular,"failures":failures]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("local-only/native-physics/tests/vehicle-blast-manager.json"))
        print("\(failures==0 ? "PASS":"FAIL"): \(cases.count) actual62540 blast manager cases; health \(maximumHealth), angular \(maximumAngular)")
        if failures>0{exit(1)}
    }
}
