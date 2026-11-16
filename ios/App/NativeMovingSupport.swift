import Foundation
import simd

/// Pedestrian support/carry ownership, separate from vehicle rigid-body
/// collision. Scene queries retain their native world/streaming owner.
final class NativeMovingSupport {
    typealias V=SIMD3<Double>
    struct Body {
        let id:UInt64,position:V,rotation:simd_quatd,dynamic:Bool
        var velocity=V.zero,spin=V.zero
    }
    /// Scene owners update these objects in place while an entity lives. A
    /// ride keeps the same live presentation/driver reference between ticks.
    final class Entry {
        var handle:UInt64,id:String,vehicle:String?,position:V,rotation:simd_quatd
        var origin=0.0,kind="car",driver:String?,standing=false
        var velocity:V?,spin:V?
        init(handle:UInt64,id:String,vehicle:String?,position:V,rotation:simd_quatd){
            self.handle=handle;self.id=id;self.vehicle=vehicle;self.position=position;self.rotation=rotation
        }
    }
    struct Ray {let body:UInt64,distance:Double}
    protocol Scene:AnyObject {
        func body(_ id:UInt64)->Body?
        func ray(origin:V,distance:Double,groups:UInt32)->Ray?
        func nearbyTreads(at:V,radius:Double,limit:Int)->[UInt64]
        func treadRay(body:UInt64,origin:V,distance:Double)->Double?
        func belowStatic(origin:V,distance:Double)->Double?
        var entries:[Entry]{get}
    }
    struct Actor {
        let grounded:Bool,rising:Double
        let fits:(V,UInt64)->Bool
        let stand:()->Void
    }
    struct Motion {var move=V.zero,yaw=0.0,thrown:V?}
    struct Attachment {let id:String?,at:V}
    private final class Ride {
        var handle:UInt64,local=V.zero,turn:simd_quatd,speed:V?,under:V?,entry:Entry?,held=false,leant=0.0
        init(body:Body){handle=body.id;turn=body.rotation}
    }
    private let scene:any Scene
    private var ride:Ride?
    private var freeVelocity=V.zero,free=false,flatGround=false
    private var priorFeetY = -Double.infinity,snapped=false,snappedHead=V.zero
    init(scene:any Scene){self.scene=scene}
    var through:UInt64?{ride?.handle}
    var riding:Bool{ride != nil}
    var held:Bool{ride?.held ?? false}
    var afloat:Bool{ride?.entry?.kind=="boat"}
    var attachment:Attachment? {
        guard let ride,let entry=ride.entry else{return nil}
        return .init(id:entry.standing ? entry.id:entry.vehicle,at:V(ride.local.x,-ride.local.z,ride.local.y-entry.origin))
    }
    var drawnAt:V? {
        guard let ride,let entry=ride.entry else{return nil}
        return entry.rotation.act(ride.local)+entry.position
    }
    func drop(){ride=nil;free=false}
    private func release(_ velocity:V?) {
        ride=nil;free=velocity.map{simd_length_squared($0)>0.09} ?? false
        if let velocity,free{freeVelocity=velocity;freeVelocity.y=0}
    }
    private func findEntry(_ body:Body,_ entries:[Entry])->Entry? {
        if let exact=entries.first(where:{$0.handle==body.id}){return exact}
        var nearest:Entry?,distance=4.0
        for entry in entries {
            let gap=simd_distance(entry.position,body.position)
            if gap<distance && !(nearest?.velocity != nil && entry.velocity==nil && gap>0.01){nearest=entry;distance=gap}
        }
        return nearest
    }
    private func velocity(_ body:Body,entry:Entry?,feet:V,change:V,delta:Double)->V {
        var value:V
        if body.dynamic{value=body.velocity+simd_cross(body.spin,feet-body.position)}
        else if let entry,let velocity=entry.velocity{value=velocity+(entry.spin.map{simd_cross($0,feet-entry.position)} ?? .zero)}
        else{value=change/max(delta,1e-4)}
        value.y=0;return value
    }
    private func turn(_ ride:Ride,to rotation:simd_quatd)->Double {
        let first=ride.turn.act(V(0,0,-1)),last=rotation.act(V(0,0,-1))
        ride.turn=rotation
        let delta=atan2(-last.x,-last.z)-atan2(-first.x,-first.z)
        let value=(delta+Double.pi).truncatingRemainder(dividingBy:2*Double.pi)
        return (value<0 ? value+2*Double.pi:value)-Double.pi
    }
    func carry(delta:Double,actor:Actor,head:inout V,height:Double=1.7)->Motion {
        var result=Motion();guard delta.isFinite,delta>0 else{return result}
        priorFeetY=head.y-height;snapped=false
        guard let ride else {
            guard free else{return result}
            if actor.grounded && flatGround {
                if simd_length(freeVelocity)>7{result.thrown=freeVelocity;free=false;return result}
                freeVelocity *= pow(0.8,60*delta)
                if simd_length_squared(freeVelocity)<0.09{free=false}
            }
            result.move=freeVelocity*delta;return result
        }
        let entries=scene.entries
        var body=scene.body(ride.handle)
        if body==nil,ride.held,let previous=ride.entry {
            for entry in entries where entry.driver==previous.driver && entry.vehicle==previous.vehicle {
                if let replacement=scene.body(entry.handle){ride.handle=entry.handle;body=replacement;break}
            }
        }
        guard let body else{release(nil);return result}
        let feet=head-V(0,height,0),target=body.rotation.act(ride.local)+body.position,change=target-feet
        let upright=body.rotation.act(V(0,1,0)).y
        ride.entry=findEntry(body,entries) ?? (ride.held ? ride.entry:nil)
        if ride.entry?.driver != nil{ride.held=true}
        if ride.held {
            ride.leant=upright<0.5 ? ride.leant+delta:0
            if upright<0 || ride.leant>0.3 {
                let speed=ride.speed;release(speed)
                if let speed,simd_length(speed)>7{result.thrown=speed};return result
            }
        }else if simd_length(change)>4 || upright<0.5{release(nil);return result}
        let under=velocity(body,entry:ride.entry,feet:feet,change:change,delta:delta)
        if ride.under==nil{ride.under=under}
        ride.under! += (under-ride.under!)*(1-exp(-delta/0.15))
        let floorVelocity=ride.under!
        if ride.speed==nil{ride.speed=free ? freeVelocity:floorVelocity}
        free=false
        if ride.held {
            ride.speed=floorVelocity;result.yaw=turn(ride,to:body.rotation)
            head += change;snappedHead=head;snapped=true;return result
        }
        let difference=floorVelocity-ride.speed!,budget=28*delta
        if simd_length(difference)<=budget{ride.speed=floorVelocity}
        else{ride.speed! += simd_normalize(difference)*budget}
        let relative=ride.speed!-floorVelocity,speed=ride.speed!
        if simd_length(relative)>4.5{release(speed);result.thrown=speed;return result}
        result.move=relative*delta;result.yaw=turn(ride,to:body.rotation)
        if actor.fits(feet+change,body.id){head += change;snappedHead=head;snapped=true}
        else{if simd_length(speed)>7{result.thrown=speed};release(nil)}
        return result
    }
    func settle(actor:Actor,head:inout V,height:Double=1.7,jumping:Bool=false,moving:Bool=true) {
        var feet=head-V(0,height,0)
        if jumping{release(ride?.speed ?? (free ? freeVelocity:nil));return}
        var found:Body?,surface=0.0,landed=false
        func inspect(){
            found=nil;var offsetHit=false
            outer:for groups:UInt32 in [262146,262272] {
                for (x,z) in [(0.0,0.0),(1,0),(-1,0),(0,1),(0,-1)] {
                    let origin=feet+V(0.24*x,0.35,0.24*z)
                    if let hit=scene.ray(origin:origin,distance:0.8,groups:groups),let body=scene.body(hit.body){
                        found=body;surface=origin.y-hit.distance;offsetHit=x != 0 || z != 0;break outer
                    }
                }
            }
            let candidate=found ?? ride.flatMap{scene.body($0.handle)}
            if candidate==nil,actor.grounded {
                let origin=feet+V(0,0.5,0)
                for id in scene.nearbyTreads(at:feet,radius:5,limit:4) {
                    if let hit=scene.treadRay(body:id,origin:origin,distance:0.95),found==nil || origin.y-hit>surface {
                        found=scene.body(id);surface=origin.y-hit
                    }
                };return
            }
            guard let candidate else{return}
            let origin=feet+V(0,1,0)
            if let hit=scene.treadRay(body:candidate.id,origin:origin,distance:1.45),found==nil || offsetHit || origin.y-hit>surface{found=candidate;surface=origin.y-hit}
        }
        let fall=priorFeetY-feet.y
        if ride==nil,!actor.grounded,actor.rising<0,fall>0,fall<2 {
            let origin=V(feet.x,priorFeetY,feet.z)
            for id in scene.nearbyTreads(at:feet,radius:1.5,limit:4) {
                if let hit=scene.treadRay(body:id,origin:origin,distance:fall),found==nil || priorFeetY-hit>surface{found=scene.body(id);surface=priorFeetY-hit;landed=true}
            }
        }else if actor.grounded || ride != nil{inspect()}
        if let ride,snapped,found?.id==ride.handle,surface-feet.y>0.5 {
            head.x=snappedHead.x;head.z=snappedHead.z;feet=head-V(0,height,0);inspect()
            if found != nil && surface-feet.y>0.5{found=nil}
        }
        if found != nil && !landed && !actor.grounded && found?.id != ride?.handle{found=nil}
        if (found==nil || found?.id != ride?.handle),let ride,ride.held,!moving,let body=scene.body(ride.handle) {
            let at=body.rotation.act(ride.local)+body.position
            head=at+V(0,height,0);actor.stand();flatGround=false;return
        }
        guard let body=found else {
            if let ride{release(ride.speed)}
            flatGround=actor.grounded && scene.belowStatic(origin:feet+V(0,0.35,0),distance:0.8) != nil
            return
        }
        flatGround=false
        if ride?.handle != body.id{ride=Ride(body:body)}
        if feet.y-surface<0.3{head.y += surface+0.02-feet.y;feet.y=surface+0.02;actor.stand()}
        ride!.local=body.rotation.conjugate.act(feet-body.position)
    }
}
