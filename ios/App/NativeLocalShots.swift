// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Event-time bullet geometry. Results describe claims and presentation only;
/// neither resolving a pellet nor grouping its target can change health/ammo.
final class NativeLocalShots {
    typealias V = SIMD3<Double>
    static let weapons=Set(22...34).union([38])
    struct Ray {
        let origin:V,direction:V,range:Double,minimum:Double
        func point(_ distance:Double)->V {origin+direction*distance}
    }
    enum World {case clear,hit(Double),unavailable(Double)}
    /// An unresolved physical vehicle is cover, not an invented WORLD hit.
    /// Ready original mesh providers are excluded from this fallback query.
    static func cover(world:World,unresolved:World?)->World {
        let boundary:Double
        switch unresolved {
        case .some(.hit(let distance)),.some(.unavailable(let distance)):
            boundary=distance.isFinite ? max(0,distance):0
        case .some(.clear),.none:return world
        }
        switch world {
        case .clear:return .unavailable(boundary)
        case .hit(let distance),.unavailable(let distance):return boundary<distance ? .unavailable(boundary):world
        }
    }
    struct Person {
        let id:String,feet:V,heading:Double,crouched:Bool
    }
    struct Target:Equatable {
        let id:String,kind:Int
        var piece:Int? = nil
        var wheel:Int? = nil
    }
    struct Hit {let distance:Double,target:Target}
    struct Tyre {let index:Int,center:V,radius:Double}
    /// Tag a selected hull; this cannot bypass a nearer person or world hit.
    /// The source tags cached nominal tyre centres, not animated wheel meshes.
    static func tyre(ray:Ray,hullDistance:Double,tyres:[Tyre])->Int? {
        guard hullDistance.isFinite,hullDistance>=0 else{return nil}
        var nearest=Double.infinity,result:Int?
        for tyre in tyres {
            guard (0...3).contains(tyre.index),finite(tyre.center),tyre.radius.isFinite,tyre.radius>=0 else{continue}
            let offset=tyre.center-ray.origin,along=simd_dot(offset,ray.direction)
            guard along>=hullDistance-tyre.radius,along<=hullDistance+0.9,along<nearest,
                  simd_length(offset-ray.direction*along)<=tyre.radius else{continue}
            nearest=along;result=tyre.index
        }
        return result
    }
    /// Keep every original cached wheel, including duplicate multi-axle IDs.
    /// Physics struts are intentionally not the bullet-target list.
    static func carTyres(_ row:[String:Any])->[Tyre] {
        guard row["kind"]as?String=="car",let id=row["id"]as?Int,id != 432,
              let origin=row["origin"]as?Double,origin.isFinite,
              let wheels=row["wheels"]as?[[String:Any]],wheels.count<=32 else{return []}
        return wheels.compactMap { wheel in
            guard let p=wheel["centre"]as?[Double],p.count==3,p.allSatisfy(\.isFinite),
                  let radius=wheel["radius"]as?Double,radius.isFinite,radius>0,
                  let front=wheel["front"]as?Bool,let left=wheel["left"]as?Bool else{return nil}
            return Tyre(index:(left ? 0:2)+(front ? 0:1),center:V(p[0],-p[2],p[1]-origin),radius:radius)
        }
    }
    static func carTyreCatalog(_ rows:[String:[String:Any]])->[Int:[Tyre]] {
        guard rows.count<=1024 else{return [:]}
        var result:[Int:[Tyre]]=[:]
        for (key,row)in rows {
            guard let id=Int(key),String(id)==key,row["id"]as?Int==id else{continue}
            let tyres=carTyres(row)
            if !tyres.isEmpty{result[id]=tyres}
        }
        return result
    }
    struct BodySphere {let center:V,radius:Double,piece:Int,bone:Int}
    struct Occupant {let id:String,spheres:[BodySphere]}
    struct Hull {let distance:Double,transparent:Bool}
    static let bodySpheres:[(bone:Int,to:Int?,radius:Double,piece:Int)]=[
        (5,nil,0.16,9),(3,4,0.19,3),(3,nil,0.2,3),(1,nil,0.2,4),
        (32,33,0.09,5),(33,34,0.08,5),(22,23,0.09,6),(23,24,0.08,6),
        (41,42,0.13,7),(42,43,0.1,7),(51,52,0.13,8),(52,53,0.1,8)
    ]
    struct Pellet {
        let ray:Ray,visualOrigin:V,end:V,target:Target?,world:Bool
        var kind:Int {target?.kind ?? (world ? 4:0)}
        var event:NativeOrdinaryShot.Event {
            .init(weapon:weapon,origin:visualOrigin,end:end,
                  impact:target.map{$0.kind==1 ? .person:.car} ?? (world ? .world:nil),piece:target?.piece)
        }
        let weapon:Int
    }
    struct Claim {
        let origin:V,end:V,kind:Int
        var target:Target?
        var pellets:Int
    }
    struct Input {
        let weapon:Int,range:Double,pellets:Int,accuracy:Double,damage:Double
        let feet:V,heading:Double,crouched:Bool
        let camera:V,forward:V,up:V,verticalFov:Double,aspect:Double
        let muzzle:V?,hipOrigin:V?
        let scoped:Bool,hip:Bool
        let milliseconds:Double
        var crouchOffset=0.0
        /// Retain native body-to-barrel cover protection when the posed gun
        /// crosses geometry. This optional safety policy is not a browser claim.
        var coverOrigin:V?=nil
    }
    struct Frame {
        let pellets:[Pellet],claims:[Claim]
        /// Missing collision cells shorten all claims at the coverage boundary.
        /// They never become a fabricated WORLD impact or a through-wall hit.
        let collisionComplete:Bool
    }
    private(set) var recoil=0.0
    private let random:()->Double
    init(random:@escaping()->Double={Double.random(in:0..<1)}) {self.random=random}
    func clear(){recoil=0}
    func advance(seconds:Double,aimState:Bool) {
        guard seconds.isFinite,seconds>=0 else{return}
        if aimState {recoil *= pow(0.96,50*seconds)}else{recoil=0}
    }
    static func finite(_ p:V)->Bool {p.x.isFinite && p.y.isFinite && p.z.isFinite}
    private static func unit(_ v:V)->V? {
        let length=simd_length(v)
        guard finite(v),length.isFinite,length>0 else{return nil}
        return v/length
    }
    /// Capsule center segment and piece thresholds belong to the archived
    /// foot-target provider. These are deliberately separate from physics
    /// controller dimensions and from posed seated-body spheres.
    static func capsule(ray:Ray,person:Person)->Double? {
        let relative=ray.origin-person.feet-V(0,0,0.2)
        let height=(person.crouched ? 1.05:1.7)-0.2
        let projection=ray.direction.z*height,square=height*height
        let toward=simd_dot(ray.direction,relative),vertical=height*relative.z
        let denominator=square-projection*projection
        var share=denominator>1e-6 ? min(1,max(0,(vertical-projection*toward)/denominator)):0
        var distance=projection*share-toward
        if distance<0 {distance=0;share=min(1,max(0,vertical/square))}
        let separation=simd_length(relative+ray.direction*distance-V(0,0,height*share))
        guard separation<=0.36 else{return nil}
        return max(0,distance-sqrt(max(0,0.1296-separation*separation)))
    }
    static func piece(at point:V,person:Person)->Int {
        let offset=point-person.feet
        let height=offset.z/(person.crouched ? 0.6176470588235294:1)
        // Source(x,y,z) -> GTA(x,-z,y), preserving heading handedness.
        let lateral=offset.x*cos(person.heading)-offset.y*sin(person.heading)
        if height>=1.5{return 9}
        if height<0.85{return lateral<0 ? 7:8}
        if abs(lateral)>0.22{return lateral<0 ? 5:6}
        return 3
    }
    static func sphere(ray:Ray,center:V,radius:Double)->Double? {
        guard finite(center),radius.isFinite,radius>=0 else{return nil}
        let offset=center-ray.origin,along=simd_dot(offset,ray.direction)
        let perpendicular=simd_length_squared(offset)-along*along,square=radius*radius
        guard perpendicular<=square else{return nil}
        let half=sqrt(max(0,square-perpendicular))
        guard along+half>=0 else{return nil}
        return max(0,along-half)
    }
    /// The original hull bounds are admission geometry, not a substitute for
    /// original mesh triangles. Occupants can extend beyond those bounds.
    static func bounds(ray:Ray,body:simd_double4x4,low:V,high:V)->Double? {
        let inverse=body.inverse,p=inverse*SIMD4(ray.origin,1),d=inverse*SIMD4(ray.direction,0)
        let origin=V(p.x,p.y,p.z),direction=V(d.x,d.y,d.z)
        guard finite(origin),finite(direction),finite(low),finite(high)else{return nil}
        var near=0.0,far=Double.infinity
        for axis in 0..<3 {
            if abs(direction[axis])<1e-6 {if origin[axis]<low[axis] || origin[axis]>high[axis]{return nil};continue}
            let a=(low[axis]-origin[axis])/direction[axis],b=(high[axis]-origin[axis])/direction[axis]
            near=max(near,min(a,b));far=min(far,max(a,b));if near>far{return nil}
        }
        return near.isFinite ? near:nil
    }
    static func vehicle(ray:Ray,bounds:Double?,target:Target,occupants:[Occupant],hull:()->Hull?)->Hit? {
        var bodyHit:Hit?
        for occupant in occupants {for sphere in occupant.spheres {
            guard let at=Self.sphere(ray:ray,center:sphere.center,radius:sphere.radius),at<=ray.range,
                  bodyHit.map({at<$0.distance}) ?? true else{continue}
            bodyHit=Hit(distance:at,target:Target(id:occupant.id,kind:1,piece:sphere.piece))
        }}
        guard bounds.map({$0<=ray.range}) == true || bodyHit != nil else{return nil}
        let mesh=hull(),hullHit=bounds==nil ? nil:mesh
        var selected:Hit?
        if let bodyHit,mesh.map({$0.distance>=bodyHit.distance || $0.transparent}) ?? true {selected=bodyHit}
        if hullHit != nil {
            for occupant in occupants {
                guard let head=occupant.spheres.first(where:{$0.bone==5}),
                      let at=Self.sphere(ray:ray,center:head.center+V(0,0,0.1),radius:0.2),at<=ray.range,
                      selected.map({at<$0.distance}) ?? true else{continue}
                selected=Hit(distance:at,target:Target(id:occupant.id,kind:1,piece:9))
            }
        }
        return selected ?? hullHit.map{Hit(distance:$0.distance,target:target)}
    }
    func fire(_ input:Input,people:[Person],world:(Ray)->World,
              vehicles:(Ray)->[Hit] = {_ in []})->Frame? {
        guard Self.weapons.contains(input.weapon),input.range.isFinite,input.range>0,
              (1...100).contains(input.pellets),input.accuracy.isFinite,input.damage.isFinite,
              Self.finite(input.feet),Self.finite(input.camera),input.heading.isFinite,
              input.verticalFov.isFinite,input.verticalFov>=0,input.verticalFov<180,
              input.aspect.isFinite,input.aspect>0,input.milliseconds.isFinite,
              let cameraDirection=Self.unit(input.forward),let right=Self.unit(simd_cross(cameraDirection,input.up)),
              let up=Self.unit(simd_cross(right,cameraDirection)) else{return nil}
        let muzzle=input.muzzle.flatMap{Self.finite($0) ? $0:nil}
        var origin=input.camera,direction=cameraDirection
        if !input.scoped && !input.hip {
            let tangent=tan(input.verticalFov * .pi/360)
            guard let biased=Self.unit(direction+up*(0.2*tangent)+right*(input.aspect*0.06*tangent))else{return nil}
            direction=biased
        }
        var range=(input.weapon==34 && input.scoped ? 800:input.range)+simd_distance(origin,input.feet)
        if input.hip {
            origin=input.hipOrigin.flatMap{Self.finite($0) ? $0:nil} ?? input.feet+V(0,0,1.62-input.crouchOffset)
            let end=(muzzle ?? origin)+V(sin(input.heading),cos(input.heading),0)*input.range
            range=simd_distance(origin,end)
            guard let hipDirection=Self.unit(end-origin)else{return nil};direction=hipDirection
        }
        guard range.isFinite,range>0,let spreadRight=Self.unit(simd_cross(direction,input.up)),
              let spreadUp=Self.unit(simd_cross(spreadRight,direction))else{return nil}
        let angular:Double
        if input.pellets>1 {angular=0.05}
        else if !input.scoped && !input.hip {
            let accuracy=input.accuracy==0 ? 1:input.accuracy
            angular=1.25*recoil*min(1,15/input.range)/(accuracy*input.range)*(input.crouched ? 0.5:1)
        }else{angular=0}
        if input.pellets==1 && !input.scoped && !input.hip {recoil += 0.04*input.damage}
        var results:[Pellet]=[],complete=true
        for index in 0..<input.pellets {
            let radius=input.pellets>1 ? (index==0 ? 0:1.04*random()*angular):angular
            let turn=input.pellets>1 ? random()*2 * .pi:input.milliseconds.truncatingRemainder(dividingBy:1000)/1000*2 * .pi
            guard let way=Self.unit(direction+spreadRight*(cos(turn)*radius)+spreadUp*(sin(turn)*radius))else{return nil}
            let minimum=input.scoped || input.hip ? 0:min(range,max(0,simd_dot(input.feet+V(0,0,1.4)-origin,way)+0.2))
            let query=Ray(origin:origin+way*minimum,direction:way,range:max(0,range-minimum),minimum:0)
            var nearest=range,obstruction:Double?,worldSelected=false,selected:Target?
            if query.range>0 {
                switch world(query) {
                case .hit(let distance):
                    if distance.isFinite,distance>=0,distance<=query.range {nearest=minimum+distance;worldSelected=true}
                    else {nearest=minimum;complete=false}
                    obstruction=nearest
                case .unavailable(let distance):
                    nearest=minimum+min(query.range,max(0,distance.isFinite ? distance:0));complete=false
                    obstruction=nearest
                case .clear:break
                }
            }
            let ray=Ray(origin:origin,direction:way,range:range,minimum:minimum)
            for person in people where !person.id.isEmpty && Self.finite(person.feet) && person.heading.isFinite {
                guard let distance=Self.capsule(ray:ray,person:person),distance>=minimum,distance<=range,
                      obstruction.map({distance<$0}) ?? true else{continue}
                nearest=distance;obstruction=distance;worldSelected=false
                selected=Target(id:person.id,kind:1,piece:Self.piece(at:ray.point(distance),person:person))
            }
            for hit in vehicles(ray) where hit.distance.isFinite && hit.distance>=minimum && hit.distance<=range {
                guard obstruction.map({hit.distance<$0}) ?? true,
                      !hit.target.id.isEmpty,(1...3).contains(hit.target.kind)else{continue}
                nearest=hit.distance;obstruction=hit.distance;worldSelected=false;selected=hit.target
            }
            var end=ray.point(nearest)
            if let safe=input.coverOrigin,Self.finite(safe),let guardDirection=Self.unit(end-safe) {
                let length=simd_distance(safe,end),cover=Ray(origin:safe,direction:guardDirection,range:length,minimum:0)
                var limit=length,changed=false
                switch world(cover) {
                case .hit(let distance):
                    if distance.isFinite,distance>=0,distance<limit {limit=distance;selected=nil;worldSelected=true;changed=true}
                case .unavailable(let distance):
                    limit=min(length,max(0,distance.isFinite ? distance:0));selected=nil;worldSelected=false;changed=true;complete=false
                case .clear:break
                }
                for hit in vehicles(cover) where hit.distance.isFinite && hit.distance>=0 && hit.distance<limit {
                    guard !hit.target.id.isEmpty,(1...3).contains(hit.target.kind)else{continue}
                    limit=hit.distance;selected=hit.target;worldSelected=false;changed=true
                }
                if changed{end=cover.point(limit)}
            }
            let visual:V
            if input.scoped {let start=origin+way;visual=V(start.x,start.y,origin.z-0.12)}
            else{visual=muzzle ?? end}
            results.append(Pellet(ray:ray,visualOrigin:visual,end:end,target:selected,world:worldSelected,weapon:input.weapon))
        }
        var grouped:[Claim]=[]
        for pellet in results {
            guard let target=pellet.target else{continue}
            if let index=grouped.firstIndex(where:{$0.target?.id==target.id && $0.target?.kind==target.kind}) {
                grouped[index].pellets+=1
                if grouped[index].target?.wheel==nil {grouped[index].target?.wheel=target.wheel}
            }else{
                let origin=pellet.visualOrigin==pellet.end ? input.feet+V(0,0,1.4):pellet.visualOrigin
                grouped.append(Claim(origin:origin,end:pellet.end,kind:target.kind,target:target,pellets:1))
            }
        }
        if grouped.isEmpty,let first=results.first {
            grouped=[Claim(origin:first.visualOrigin==first.end ? input.feet+V(0,0,1.4):first.visualOrigin,
                           end:first.end,kind:first.kind,target:nil,pellets:1)]
        }
        return Frame(pellets:results,claims:grouped,collisionComplete:complete)
    }
}
