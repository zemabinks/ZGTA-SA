// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum ThermalGate {
    static var checks=0
    static func check(_ ok:Bool,_ why:String){guard ok else{fputs("FAIL \(why)\n",stderr);exit(42)};checks+=1}
    static func near(_ a:Double,_ b:Double,_ label:String){check(a.isFinite && abs(a-b)<1e-8,"\(label): \(a) / \(b)")}
    static func near(_ a:SIMD3<Double>,_ b:SIMD3<Double>,_ label:String){for i in 0..<3{near(a[i],b[i],label)}}
    static func vector(_ a:[Double])->SIMD3<Double>{SIMD3(a[0],a[1],a[2])}
    static func converted(_ a:[Double])->SIMD3<Double>{SIMD3(a[0],-a[2],a[1])}
    static func matrix(_ a:[Double])->simd_double4x4{.init(columns:(SIMD4(a[0],a[1],a[2],a[3]),SIMD4(a[4],a[5],a[6],a[7]),SIMD4(a[8],a[9],a[10],a[11]),SIMD4(a[12],a[13],a[14],a[15])))}
    static func rig(_ frames:Any?=nil)throws->Data {
        var row:[String:Any]=["version":1,"id":900,"kind":"car",
            "nodes":[["name":"body","parent":-1,"position":[0,0,0],"rotation":[0,0,0,1],"scale":[1,1,1],"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"matrixAutoUpdate":true,"visible":true,"wheel":false,"damaged":false,"lowDetail":false]],
            "draws":[],"joints":["damage":[],"wheels":[],"rotors":[],"gear":[],"nozzles":[],"rearSteerOnly":false]]
        if let frames{row["frames"]=frames}
        return try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys])
    }
    static func input()->NativeVehicleThermalEffects.Input {
        .init(model:900,kind:"car",health:249,burning:true,engine:SIMD3(2,3,4),transform:matrix_identity_double4x4,velocity:SIMD3(5,6,7),delta:1/60)
    }
    static func main()throws {
        let engine=SIMD3<Double>(2,3,4),frame:[String:Any]=["name":"engine","parent":"descriptive-parent","matrix":[1,0,0,0,0,1,0,0,0,0,1,0,2,3,4,1]]
        let old=NativeVehicleRig(data:try rig()),decoded=NativeVehicleRig(data:try rig([frame]))
        check(old != nil && old?.enginePosition == .zero,"Old catalogs retain zero-dummy fallback")
        check(decoded?.enginePosition==engine,"Engine frame translation without parent recomposition")
        var bad=frame;bad["matrix"]=[1,2,3]
        check(NativeVehicleRig(data:try rig([bad]))==nil,"Reject malformed optional frame")
        check(NativeVehicleRig(data:try rig([frame,frame]))==nil,"Reject ambiguous frame identity")
        for hz in [15,30,60,120] {
            var state=NativeVehicleThermalEffects.State(),row=input();row.kind="plane";row.delta=1/Double(hz)
            var fireDuration=0.0
            for _ in 0..<(3*hz) {
                let events=NativeVehicleThermalEffects.sample(row,state:&state,random:{0.37})
                if events.contains(where:{if case .fire=$0.kind{return true};return false}){fireDuration+=row.delta}
            }
            near(state.alight,3,"Equal aircraft burn duration at \(hz)Hz")
            check(abs(fireDuration-0.5)<=row.delta+1e-8,"Aircraft threshold within one frame at \(hz)Hz")
            row.burning=false;row.health=700
            check(NativeVehicleThermalEffects.sample(row,state:&state).isEmpty && state.alight==0,"Repair resets presentation clock")
            row.burning=true;row.health=249
            check(NativeVehicleThermalEffects.sample(row,state:&state,random:{0}).allSatisfy{if case .fire=$0.kind{return false};return true},"No immediate aircraft flames after repair")
            let held=state.alight
            _=NativeVehicleThermalEffects.sample(row,state:&state,effectsAvailable:false)
            near(state.alight,held,"Unavailable effects do not advance lifetime")
        }
        var state=NativeVehicleThermalEffects.State(),row=input()
        row.burning=false
        check(NativeVehicleThermalEffects.sample(row,state:&state).isEmpty,"Submerged owner can suppress burning without mutating health")
        check(row.health==249,"Presentation does not inflict or heal damage")
        row.burning=true;row.delta = .nan
        check(NativeVehicleThermalEffects.sample(row,state:&state).isEmpty,"Reject invalid frame duration")
        // Actual data-driven particle owner with invented sentinel systems.
        func system(_ rate:Double)->[String:Any]{["length":0,"emitters":[["texture":"sentinel","infos":["emrate":["rate":[[0,rate]]],"emlife":["life":[[0,1.0]]]]]]]}
        let definitions:[String:Any]=["systems":["fire_car":system(120),"fire_bike":system(120),"fire_large":system(120),"overheat_car":system(120),"overheat_car_electric":system(120),"prt_smoke_huge":system(120)]]
        let effects=try NativeParticleEffects(data:JSONSerialization.data(withJSONObject:definitions),textures:["sentinel"],random:{0.37})
        row=input();state = .init()
        let fire=NativeVehicleThermalEffects.sample(row,state:&state)
        NativeVehicleThermalEffects.render(fire,into:effects)
        check(effects.shown.count==2,"Vehicle fire reaches actual emitter owner")
        near(effects.shown[0].position,row.engine,"Fire emitter world origin")
        near(effects.shown[0].velocity,row.velocity,"Fire inherits actual GTA velocity")
        effects.clear();row.burning=false;row.health=500;row.electric=true
        NativeVehicleThermalEffects.render(NativeVehicleThermalEffects.sample(row,state:&state),into:effects)
        check(effects.shown.count==2,"Overheat reaches actual emitter owner")
        check(state.alight==0,"Overheat clears previous burning phase")
        effects.clear();row.kind="plane";row.health=249;row.burning=true;row.delta=0.1
        NativeVehicleThermalEffects.render(NativeVehicleThermalEffects.sample(row,state:&state,random:{0.37}),into:effects,random:{0.37})
        check(effects.shown.count==1,"Aircraft smoke uses actual particle pool")
        near(effects.shown[0].position,SIMD3(-0.52,0.52,0),"Aircraft jitter converted once")
        near(effects.shown[0].velocity,SIMD3(-0.39,0.39,0.37),"Aircraft smoke axes")
        near(effects.shown[0].life,0.3,"Aircraft particle lifetime")
        effects.clear();row.model=464;state = .init()
        NativeVehicleThermalEffects.render(NativeVehicleThermalEffects.sample(row,state:&state,random:{0.37}),into:effects,random:{0.37})
        check(effects.shown.count==1,"RC aircraft uses its own smoke profile")
        near(effects.shown[0].tint,SIMD3(0,0,pow((0.15+0.055)/1.055,2.4)),"RC smoke tint enters the linear particle color space")
        near(effects.shown[0].big,0.3,"RC smoke scale")
        effects.clear();check(effects.shown.isEmpty,"World clear removes thermal particles")
        if CommandLine.arguments.count>1 {
            let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
            let reference=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let adapters:[[String:Any]]?
            if CommandLine.arguments.count>2 {
                let other=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
                adapters=other["cases"] as? [[String:Any]]
            }else{adapters=nil}
            for (index,record) in (reference["cases"] as! [[String:Any]]).enumerated() {
                let raw=record["input"] as! [String:Any],kind=raw["kind"] as? String
                let transform=(record["modelTransformGTA"] as? [Double]).map(matrix) ?? matrix_identity_double4x4
                var row=NativeVehicleThermalEffects.Input(model:raw["model"] as! Int,kind:kind,electric:raw["electric"] as? Bool ?? false,
                    health:raw["health"] as! Double,burning:raw["burning"] as! Bool,engine:vector(record["engineGTA"] as! [Double]),
                    transform:transform,velocity:vector(record["velocityGTA"] as! [Double]),delta:raw["delta"] as! Double)
                var state=NativeVehicleThermalEffects.State(alight:raw["startAlight"] as? Double ?? 0),actual:[NativeVehicleThermalEffects.Emission]=[]
                if kind != nil {near(NativeVehicleThermalEffects.point(engine,transform:transform),row.engine,"Attachment \(index)")}
                for _ in 0..<(raw["frames"] as? Int ?? 1) {
                    actual+=NativeVehicleThermalEffects.sample(row,state:&state,effectsAvailable:raw["effects"] as? Bool ?? true,random:{0.37})
                }
                let expected=record["effects"] as! [[String:Any]]
                check(actual.count==expected.count,"Original callable emission count \(index)")
                if let alight=record["alight"] as? Double {near(state.alight,alight,"Original alight \(index)")}
                for (event,other) in zip(actual,expected) {
                    near(event.position,converted(other["at"] as! [Double]),"Original point \(index)")
                    switch event.kind {
                    case .smoke(let strength,let electric):
                        check(other["kind"] as? String=="smoke" && other["electric"] as? Bool==electric,"Original overheat kind")
                        near(strength,other["strength"] as! Double,"Original strength")
                    case .fire(let system):check(other["kind"] as? String=="fire" && other["system"] as? String==system,"Original fire family")
                    case .aircraftSmoke(let rc):check(other["kind"] as? String=="aircraftSmoke" && other["rc"] as? Bool==rc,"Original aircraft family")
                    }
                    if let speed=other["velocity"] as? [Double]{near(event.velocity,converted(speed),"Original velocity")}
                }
                if let adapters {
                    let names=["fire_car","fire_bike","fire_large","overheat_car","overheat_car_electric","prt_smoke_huge"]
                    var systems:[String:Any]=[:]
                    for name in names {
                        var definition=system(120)
                        var emitters=definition["emitters"] as! [[String:Any]]
                        emitters[0]["texture"]=name;definition["emitters"]=emitters;systems[name]=definition
                    }
                    let pool=try NativeParticleEffects(data:JSONSerialization.data(withJSONObject:["systems":systems]),textures:Set(names),random:{0.37})
                    NativeVehicleThermalEffects.render(actual,into:pool,random:{0.37})
                    var expected:[(name:String,at:SIMD3<Double>,speed:SIMD3<Double>,life:Double,size:Double,alpha:Double,tint:SIMD3<Double>,born:Double)]=[]
                    for call in adapters[index]["calls"] as! [[String:Any]] {
                        let spawn=call["kind"] as? String=="spawn"
                        let count=spawn ? call["count"] as! Int:Int(floor(120*(call["delta"] as! Double)*(call["scale"] as! Double)+0.37))
                        let mult=call["mult"] as? [String:Double] ?? [:]
                        for _ in 0..<count {
                            expected.append((call["name"] as! String,vector(call["at"] as! [Double]),vector(call["velocity"] as! [Double]),
                                mult["life"] ?? 1,mult["size"] ?? 1,mult["alpha"] ?? 1,
                                (call["tint"] as? [Double]).map(vector) ?? SIMD3(repeating:1),call["time"] as? Double ?? 0))
                        }
                    }
                    check(pool.shown.count==expected.count,"Original selected adapter particle count \(index)")
                    for (particle,other) in zip(pool.shown,expected) {
                        check(particle.emitter?.texture==other.name,"Original selected adapter system")
                        near(particle.position,other.at,"Original selected adapter point")
                        near(particle.velocity,other.speed,"Original selected adapter velocity")
                        near(particle.life,other.life,"Original selected adapter life")
                        near(particle.big,other.size,"Original selected adapter size")
                        near(particle.faint,other.alpha,"Original selected adapter alpha")
                        near(particle.tint,other.tint,"Original selected adapter tint")
                        near(particle.born,other.born,"Original selected adapter overheat curve")
                    }
                }
                row.health=1000 // Local value only; source records remain unchanged.
            }
            print("PASS unchanged shipped callable comparison: 212 authored cases")
        }
        print("PASS native thermal policy, attachment admission, frame transitions and actual particle owner: \(checks) checks")
    }
}
