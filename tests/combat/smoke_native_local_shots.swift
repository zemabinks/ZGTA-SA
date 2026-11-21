// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main struct LocalShotGate {
    static func main() {
        var checks=0
        func check(_ value:Bool,_ reason:String){checks+=1;if !value{print("FAIL \(reason)");exit(1)}}
        func near(_ a:Double,_ b:Double,_ reason:String){check(abs(a-b)<1e-10,"\(reason): actual \(a), expected \(b)")}
        typealias S=NativeLocalShots
        let standing=S.Person(id:"one",feet:.zero,heading:0,crouched:false)
        let crouched=S.Person(id:"low",feet:.zero,heading:0,crouched:true)
        let side=S.Ray(origin:SIMD3(-1,0,1.65),direction:SIMD3(1,0,0),range:20,minimum:0)
        near(S.capsule(ray:side,person:standing) ?? -1,0.64,"standing ray capsule")
        check(S.capsule(ray:side,person:crouched)==nil,"standing head ray passes above crouched body")
        let away=S.Ray(origin:SIMD3(-1,0,1),direction:SIMD3(-1,0,0),range:20,minimum:0)
        check(S.capsule(ray:away,person:standing)==nil,"body behind ray is not selected")
        let inside=S.Ray(origin:SIMD3(0,0,1),direction:SIMD3(1,0,0),range:20,minimum:0)
        near(S.capsule(ray:inside,person:standing) ?? -1,0,"ray starting in capsule")
        for (point,piece) in [(SIMD3<Double>(0,0,1.5),9),(SIMD3(-0.3,0,0.84),7),(SIMD3(0.3,0,0.84),8),(SIMD3(-0.3,0,0.85),5),(SIMD3(0.3,0,0.85),6),(SIMD3(0.22,0,1),3),(SIMD3(-0.22,0,1),3)] {
            check(S.piece(at:point,person:standing)==piece,"body piece threshold \(point)")
        }
        check(S.piece(at:SIMD3(0,0,1),person:crouched)==9,"crouched height normalization")
        near(S.sphere(ray:side,center:SIMD3(3,0,1.65),radius:0.16) ?? -1,3.84,"posed body sphere distance")
        check(S.sphere(ray:away,center:SIMD3(3,0,1),radius:0.2)==nil,"sphere behind ray")
        func input(_ weapon:Int=31,pellets:Int=1,hip:Bool=true,scope:Bool=false)->S.Input {
            .init(weapon:weapon,range:35,pellets:pellets,accuracy:1,damage:30,feet:.zero,heading:0,crouched:false,
                  camera:SIMD3(0,-3,1.6),forward:SIMD3(0,1,0),up:SIMD3(0,0,1),verticalFov:55,aspect:2,
                  muzzle:SIMD3(0,0,1.6),hipOrigin:SIMD3(0,0,1.6),scoped:scope,hip:hip,milliseconds:500)
        }
        let person=S.Person(id:"p7",feet:SIMD3(0,8,0),heading:0,crouched:false)
        let gun=S(random:{0.5})
        let hit=gun.fire(input(),people:[person],world:{_ in .clear})!
        check(hit.claims.count==1 && hit.claims[0].kind==1 && hit.claims[0].target?.id=="p7","typed NPC head claim")
        check(hit.claims[0].target?.piece==9,"actual capsule endpoint head piece")
        let wall=gun.fire(input(),people:[person],world:{_ in .hit(4)})!
        check(wall.claims[0].kind==4 && wall.claims[0].target==nil,"nearer world blocks body")
        near(wall.claims[0].end.y,4,"world endpoint retained")
        let equal=gun.fire(input(),people:[person],world:{_ in .hit(7.64)})!
        check(equal.claims[0].kind==4,"world wins exact body-distance tie")
        let missing=gun.fire(input(),people:[person],world:{_ in .unavailable(3)})!
        check(!missing.collisionComplete && missing.claims[0].target==nil && missing.claims[0].kind==0,"unloaded collision cannot authorize through-world target or fake impact")
        near(missing.claims[0].end.y,3,"unknown boundary endpoint")
        if case .unavailable(let at)=S.cover(world:.clear,unresolved:.hit(3)){near(at,3,"unknown vehicle cover")}
        else{check(false,"unknown cover must not become WORLD damage/effects")}
        if case .hit(let at)=S.cover(world:.hit(2),unresolved:.hit(3)){near(at,2,"nearer static world keeps ownership")}
        else{check(false,"nearer static surface lost")}
        if case .hit(let at)=S.cover(world:.hit(3),unresolved:.hit(3)){near(at,3,"exact world/unknown tie retains world")}
        else{check(false,"static tie lost")}
        if case .unavailable(let at)=S.cover(world:.hit(4),unresolved:.hit(3)){near(at,3,"unknown vehicle blocks farther static hit")}
        else{check(false,"unresolved vehicle cover ignored")}
        if case .clear=S.cover(world:.clear,unresolved:nil){check(true,"ready geometry skips cover fallback")}
        else{check(false,"ready geometry occluded by fallback")}
        let alternate=S.Person(id:"other",feet:person.feet,heading:0,crouched:false)
        let tie=gun.fire(input(),people:[person,alternate],world:{_ in .clear})!
        check(tie.claims[0].target?.id==person.id,"provider order breaks equal person ties")
        let car=S.Hit(distance:2,target:.init(id:"t4",kind:3))
        let hull=gun.fire(input(),people:[person],world:{_ in .clear},vehicles:{_ in [car]})!
        check(hull.claims[0].kind==3 && hull.claims[0].target?.id=="t4","standing traffic hull keeps typed ID")
        let occluded=gun.fire(input(),people:[],world:{_ in .hit(1)},vehicles:{_ in [car]})!
        check(occluded.claims[0].kind==4,"car cannot override nearer world")
        let shotgun=gun.fire(input(25,pellets:15),people:[person],world:{_ in .clear})!
        check(shotgun.pellets.count==15,"trace all shotgun pellets")
        check(shotgun.claims.count==1 && shotgun.claims[0].pellets==15,"same target pellets grouped once")
        let miss=gun.fire(input(25,pellets:15),people:[],world:{_ in .clear})!
        check(miss.claims.count==1 && miss.claims[0].pellets==1 && miss.claims[0].kind==0,"all-miss shotgun reports first representative")
        near(gun.recoil,0,"hip/multipellet do not add aimed recoil")
        let scoped=gun.fire(input(34,hip:false,scope:true),people:[],world:{_ in .clear})!
        near(scoped.pellets[0].ray.range,800+sqrt(11.56),"scoped sniper range plus camera distance")
        near(scoped.pellets[0].visualOrigin.z,1.48,"scope visual starts below camera")
        for fps in [15,30,60,120,240] {
            let owner=S();_=owner.fire(input(31,hip:false),people:[],world:{_ in .clear})
            near(owner.recoil,1.2,"one aim marker adds recoil")
            for _ in 0..<(fps*2){owner.advance(seconds:1/Double(fps),aimState:true)}
            near(owner.recoil,1.2*pow(0.96,100),"recoil clock \(fps)FPS")
            owner.advance(seconds:0,aimState:false);near(owner.recoil,0,"leaving gun aim resets recoil")
        }
        let plane:[SIMD3<Float>]=[SIMD3(-2,4,0),SIMD3(2,4,0),SIMD3(0,4,3)]
        let surface=NativeLocalShotMesh.Surface(node:0,start:0,count:3,side:2,transparent:false,opacity:1,additive:false)
        let mesh=NativeLocalShotMesh(positions:plane,indices:[0,1,2],surfaces:[surface])!
        let through=S.Ray(origin:SIMD3(0,0,1),direction:SIMD3(0,1,0),range:30,minimum:0)
        let identity=matrix_identity_double4x4
        near(mesh.hit(ray:through,body:identity,matrices:[identity],visible:[true])?.distance ?? -1,4,"original triangle intersection")
        check(mesh.hit(ray:through,body:identity,matrices:[identity],visible:[false])==nil,"hidden node rejected")
        var scaled=identity;scaled.columns.1.y=2;scaled.columns.3.y=3
        near(mesh.hit(ray:through,body:scaled,matrices:[identity],visible:[true])?.distance ?? -1,11,"scaled inverse ray preserves world units")
        var displaced=identity;displaced.columns.3.x=8
        check(mesh.hit(ray:through,body:identity,matrices:[displaced],visible:[true])==nil,"current rigid node transform moves target")
        let additive=NativeLocalShotMesh.Surface(node:0,start:0,count:3,side:2,transparent:false,opacity:1,additive:true)
        let skipped=NativeLocalShotMesh(positions:plane,indices:[0,1,2],surfaces:[surface,additive])!
        check(skipped.hit(ray:through,body:identity,matrices:[identity],visible:[true])==nil,"one additive material excludes whole mesh")
        let a=SIMD3<Double>(0,0,0),b=SIMD3<Double>(1,0,0),c=SIMD3<Double>(0,1,0)
        let above=SIMD3<Double>(0.2,0.2,1),below=SIMD3<Double>(0.2,0.2,-1)
        near(NativeLocalShotMesh.triangle(origin:above,direction:SIMD3(0,0,-1),a:a,b:b,c:c,side:0) ?? -1,1,"front material face")
        check(NativeLocalShotMesh.triangle(origin:below,direction:SIMD3(0,0,1),a:a,b:b,c:c,side:0)==nil,"front material rejects back face")
        near(NativeLocalShotMesh.triangle(origin:below,direction:SIMD3(0,0,1),a:a,b:b,c:c,side:1) ?? -1,1,"back material face")
        near(NativeLocalShotMesh.triangle(origin:below,direction:SIMD3(0,0,1),a:a,b:b,c:c,side:2) ?? -1,1,"double-sided original material")
        let torso=S.Occupant(id:"c42.1",spheres:[.init(center:SIMD3(0,6,1),radius:0.2,piece:3,bone:3)])
        let carTarget=S.Target(id:"t42",kind:3)
        let opaque=S.vehicle(ray:through,bounds:3,target:carTarget,occupants:[torso],hull:{.init(distance:3,transparent:false)})!
        check(opaque.target==carTarget,"opaque car protects torso")
        let glass=S.vehicle(ray:through,bounds:3,target:carTarget,occupants:[torso],hull:{.init(distance:3,transparent:true)})!
        check(glass.target.kind==1 && glass.target.id=="c42.1","translucent material exposes loaded occupant torso")
        near(glass.distance,5.8,"posed torso sphere distance")
        let headRay=S.Ray(origin:SIMD3(0,0,1.6),direction:SIMD3(0,1,0),range:30,minimum:0)
        let head=S.Occupant(id:"passenger",spheres:[.init(center:SIMD3(0,6,1.5),radius:0.16,piece:9,bone:5)])
        let override=S.vehicle(ray:headRay,bounds:3,target:carTarget,occupants:[head],hull:{.init(distance:3,transparent:false)})!
        check(override.target.id=="passenger" && override.target.piece==9,"source extra head sphere override")
        near(override.distance,5.8,"source raised/radius head sphere")
        let wide=S.vehicle(ray:through,bounds:nil,target:carTarget,occupants:[torso],hull:{nil})!
        check(wide.target.id=="c42.1","occupant outside body bounds remains hittable")
        var coverInput=input();coverInput.coverOrigin=SIMD3(0,0,1.6)
        var coverQueries=0
        let guarded=gun.fire(coverInput,people:[person],world:{_ in coverQueries+=1;return coverQueries==1 ? .clear:.hit(0.1)})!
        check(guarded.claims[0].kind==4 && guarded.claims[0].target==nil,"body-to-barrel cover cannot be skipped by camera trace minimum")
        near(guarded.claims[0].end.y,0.1,"body-to-barrel cover endpoint")
        let wheelRows:[[String:Any]]=[
            ["centre":[1.0,2.0,-3.0],"radius":0.4,"front":false,"left":true],
            ["centre":[1.0,2.0,-4.0],"radius":0.5,"front":false,"left":true]]
        let tyreMetadata:[String:Any]=["id":420,"kind":"car","origin":0.7,"wheels":wheelRows,"struts":[wheelRows[1]]]
        let nominal=S.carTyres(tyreMetadata)
        check(nominal.count==2 && nominal.map(\.index)==[1,1],"all original wheel candidates survive reduced physics struts")
        check(nominal[0].center==SIMD3(1,3,1.3) && nominal[0].radius==0.4,"nominal model-local conversion removes body origin without radius inflation")
        var tank=tyreMetadata;tank["id"]=432
        check(S.carTyres(tank).isEmpty,"tank track wheels are not tyres")
        var unsupported=tyreMetadata;unsupported["kind"]="boat"
        check(S.carTyres(unsupported).isEmpty,"unsupported vehicle kind cannot invent tyre tags")
        let tyreCatalog=S.carTyreCatalog(["420":tyreMetadata,"0420":tyreMetadata,"421":tyreMetadata])
        check(tyreCatalog.count==1 && tyreCatalog[420]?.count==2,"canonical model identity prevents duplicate-key crashes and mismatched metadata")
        let excessive=Dictionary(uniqueKeysWithValues:(0..<1025).map{(String($0),tyreMetadata)})
        check(S.carTyreCatalog(excessive).isEmpty,"tyre catalog obeys the bounded model metadata budget")
        let tyreRay=S.Ray(origin:.zero,direction:SIMD3(0,1,0),range:20,minimum:0)
        let tyre=S.Tyre(index:0,center:SIMD3(0,5,0),radius:0.5)
        check(S.tyre(ray:tyreRay,hullDistance:5.5,tyres:[tyre])==0,"tyre near window includes exact lower bound and wheel zero")
        check(S.tyre(ray:tyreRay,hullDistance:4.1,tyres:[tyre])==0,"tyre near window includes exact upper bound")
        check(S.tyre(ray:tyreRay,hullDistance:5.5001,tyres:[tyre])==nil,"tyre outside near hull window")
        check(S.tyre(ray:tyreRay,hullDistance:4.0999,tyres:[tyre])==nil,"tyre outside far hull window")
        check(S.tyre(ray:tyreRay,hullDistance:5,tyres:[.init(index:1,center:SIMD3(0.5,5,0),radius:0.5)])==1,"exact perpendicular radius is included")
        check(S.tyre(ray:tyreRay,hullDistance:5,tyres:[.init(index:1,center:SIMD3(0.5001,5,0),radius:0.5)])==nil,"outside perpendicular radius is excluded")
        check(S.tyre(ray:tyreRay,hullDistance:5,tyres:[.init(index:3,center:SIMD3(0,5,0),radius:0.5),tyre])==3,"equal projected tyre distance retains source order")
        check(S.tyre(ray:tyreRay,hullDistance:5,tyres:[.init(index:3,center:SIMD3(0,5.1,0),radius:0.5),tyre])==0,"nearest projected tyre centre wins")
        check(S.tyre(ray:tyreRay,hullDistance:5,tyres:[.init(index:0,center:SIMD3(.nan,5,0),radius:0.5),.init(index:1,center:SIMD3(0,5,0),radius:.infinity)])==nil,"invalid tyre metadata never tags a claim")
        let wheelClaim=S.Claim(origin:SIMD3(-0.005,0.005,1),end:SIMD3(0,4,1),kind:3,target:.init(id:"t42",kind:3,wheel:0),pellets:15)
        let packet=NativeLocalShotPackets.original(weapon:25,claims:[wheelClaim])![0]
        check(packet["wh"]as?Int==0 && packet["n"]as?Int==15,"wire wheel zero and grouped pellets retained")
        pointPacket: do {
            let origin=packet["o"]as! [Double]
            near(origin[0],0,"wire negative half rounds toward positive infinity");near(origin[1],0.01,"wire positive half")
        }
        check(NativeLocalShotPackets.original(weapon:31,claims:[])==nil,"empty firing batch rejected")
        let broken=S.Claim(origin:SIMD3(.nan,0,0),end:.zero,kind:0,target:nil,pellets:1)
        check(NativeLocalShotPackets.original(weapon:31,claims:[wheelClaim,broken])==nil,"entire malformed batch rejected before transport")
        var referenceCases=0
        if CommandLine.arguments.count>1 {
            let data=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
            let document=try! JSONSerialization.jsonObject(with:data) as! [String:Any]
            func vector(_ value:Any?)->SIMD3<Double>? {
                guard let a=value as? [Double],a.count==3 else{return nil};return SIMD3(a[0],a[1],a[2])
            }
            func point(_ actual:SIMD3<Double>,_ expected:Any?,_ label:String) {
                guard let expected=vector(expected)else{check(false,"missing reference vector \(label)");return}
                check(simd_distance(actual,expected)<1e-9,label)
            }
            for row in document["tyreCases"]as?[[String:Any]] ?? [] {
                let tyres=(row["tyres"]as![[String:Any]]).map{item in S.Tyre(index:item["index"]as!Int,center:vector(item["center"])!,radius:item["radius"]as!Double)}
                let ray=S.Ray(origin:vector(row["origin"])!,direction:vector(row["direction"])!,range:1000,minimum:0)
                let actual=S.tyre(ray:ray,hullDistance:row["hullDistance"]as!Double,tyres:tyres)
                check(actual==row["expected"]as?Int,"original tyre \(row["name"]as!String): actual \(String(describing:actual)), expected \(row["expected"]!)")
                referenceCases+=1
            }
            for row in document["capsuleCases"] as! [[String:Any]] {
                let person=S.Person(id:"reference",feet:vector(row["positionGTA"])!,heading:0,crouched:row["crouch"] as! Bool)
                let ray=S.Ray(origin:vector(row["originGTA"])!,direction:simd_normalize(vector(row["directionGTA"])!),range:1000,minimum:0)
                let actual=S.capsule(ray:ray,person:person)
                if let expected=row["expectedDistance"]as?Double {near(actual ?? -1,expected,row["name"]as!String)}
                else{check(actual==nil,row["name"]as!String)}
                referenceCases+=1
            }
            for row in document["pieceCases"] as! [[String:Any]] {
                let person=S.Person(id:"reference",feet:vector(row["positionGTA"])!,heading:row["nativeHeading"]as!Double,crouched:row["crouch"]as!Bool)
                check(S.piece(at:vector(row["pointGTA"])!,person:person)==row["expectedPiece"]as!Int,row["name"]as!String)
                referenceCases+=1
            }
            let weapons=document["weapons"]as! [String:[String:Any]]
            for row in document["kernelCases"]as! [[String:Any]] {
                let name=row["name"]as!String,input=row["input"]as! [String:Any],expected=row["expected"]as! [String:Any]
                // The resolver has no authority over the controller's marker,
                // stun or inventory gate; the corresponding capture is excluded.
                guard input["marker"]as?Bool != false,input["ready"]as?Bool != false,input["stunned"]as?Bool != true else{continue}
                let weapon=input["weapon"]as!Int,metadata=weapons[String(weapon)]!,mode=input["mode"]as!String
                var randomCalls=0
                let owner=S(random:{randomCalls+=1;return input["random"]as!Double})
                let initial=input["initialRecoil"]as!Double
                if initial != 0 {
                    let seed=S.Input(weapon:weapon,range:1,pellets:1,accuracy:1,damage:initial/0.04,feet:.zero,heading:0,crouched:false,
                        camera:SIMD3(0,-1,1),forward:SIMD3(0,1,0),up:SIMD3(0,0,1),verticalFov:50,aspect:1,muzzle:.zero,hipOrigin:nil,scoped:false,hip:false,milliseconds:0)
                    _=owner.fire(seed,people:[],world:{_ in .clear});randomCalls=0
                }
                let feet=vector(input["pedPositionGTA"])!,hand=vector(input["handPointGTA"])
                let offset=(metadata["offset"]as! [Double])[2]
                let origin=vector(input["aimOriginGTA"]) ?? vector(input["cameraPositionGTA"])!
                let verticalFov=(input["aimFov"]as?Double).map{2*atan(0.75*tan($0 * .pi/360))*180 / .pi} ?? input["fov"]as!Double
                var config=S.Input(weapon:weapon,range:metadata["range"]as!Double,pellets:metadata["pellets"]as?Int ?? 1,
                    accuracy:metadata["accuracy"]as?Double ?? 1,damage:metadata["damage"]as!Double,feet:feet,
                    heading:input["nativeHeading"]as!Double,crouched:input["crouching"]as!Bool,
                    camera:origin,forward:vector(input["cameraDirectionGTA"])!,up:vector(input["cameraUpGTA"])!,
                    verticalFov:verticalFov,aspect:input["aspect"]as!Double,
                    muzzle:vector(input["muzzleGTA"]),hipOrigin:hand.map{$0+SIMD3(0,0,offset+0.15)},scoped:mode=="scope",hip:mode=="hip",milliseconds:input["now"]as!Double)
                config.crouchOffset=input["crouchOffset"]as!Double
                let people=(input["people"]as! [[String:Any]]).map{S.Person(id:$0["id"]as!String,feet:vector($0["positionGTA"])!,heading:$0["nativeHeading"]as!Double,crouched:$0["crouch"]as!Bool)}
                var queries:[S.Ray]=[]
                let frame=owner.fire(config,people:people,world:{ ray in
                    let index=queries.count;queries.append(ray)
                    if let sequence=input["worldRelativeSequence"]as? [Any],sequence.indices.contains(index),let distance=sequence[index]as?Double{return .hit(distance)}
                    return (input["worldRelative"]as?Double).map{.hit($0)} ?? .clear
                },vehicles:{_ in
                    let index=max(0,queries.count-1)
                    return (input["cars"]as! [[String:Any]]).compactMap{ car in
                        let distance:Double?
                        if let sequence=car["atSequence"]as? [Any],sequence.indices.contains(index){distance=sequence[index]as?Double}
                        else{distance=car["at"]as?Double}
                        guard let distance else{return nil}
                        if let occupant=car["occupant"]as? [String:Any] {
                            return S.Hit(distance:distance,target:.init(id:occupant["id"]as!String,kind:1,piece:occupant["piece"]as?Int))
                        }
                        return S.Hit(distance:distance,target:.init(id:car["id"]as!String,kind:car["standing"]as?Bool==true ? 3:2,wheel:car["tyre"]as?Int))
                    }
                })!
                let expectedQueries=expected["worldQueries"]as! [[String:Any]]
                check(queries.count==expectedQueries.count,"\(name) query count")
                for (query,want)in zip(queries,expectedQueries) {
                    point(query.origin,want["originGTA"],"\(name) world origin");point(query.direction,want["directionGTA"],"\(name) world direction")
                    near(query.range,want["maximum"]as!Double,"\(name) world reach")
                }
                let claims=expected["claims"]as! [[String:Any]],packets=expected["packets"]as! [[String:Any]]
                check(frame.claims.count==claims.count,"\(name) grouped claim count")
                let actualPackets=NativeLocalShotPackets.original(weapon:weapon,claims:frame.claims)!
                check(NSDictionary(dictionary:["packets":actualPackets]).isEqual(to:["packets":packets]),"\(name) exact original packet serialization")
                for (index,pair)in zip(frame.claims,claims).enumerated() {
                    let (claim,want)=pair
                    check(claim.kind==packets[index]["ht"]as!Int,"\(name) typed hit kind")
                    check(claim.target?.id==(want["person"]as?String ?? (want["car"]as? [String:Any])?["id"]as?String),"\(name) target namespace")
                    check(claim.target?.piece==want["piece"]as?Int,"\(name) piece")
                    check(claim.target?.wheel==want["wheel"]as?Int,"\(name) wheel")
                    check(claim.pellets==want["pellets"]as!Int,"\(name) grouped pellet count")
                    point(claim.origin,want["fromGTA"],"\(name) claim origin");point(claim.end,want["toGTA"],"\(name) claim endpoint")
                }
                near(owner.recoil,expected["recoil"]as!Double,"\(name) recoil accumulation")
                check(randomCalls==expected["randomCalls"]as!Int,"\(name) RNG consumption")
                referenceCases+=1
            }
        }
        print("PASS \(checks) actual local shot/BVH/packet checks; \(referenceCases) archived calculation cases. No full controller, FX/audio, original asset mesh, socket or retail claim")
    }
}
