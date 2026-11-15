import Foundation
import simd

/// Data-driven public fx.json particle core: original emission curves, rings,
/// life/size/colour clocks, force/friction, water and floor behavior. Values
/// are GTA Z-up; a caller supplies the original texture names and render order.
final class NativeParticleEffects {
    typealias V=SIMD3<Double>
    final class Anchor {var position:V;init(_ position:V){self.position=position}}
    struct Multiplier {var size:Double=1;var life:Double=1;var alpha:Double=1}
    struct Options {
        var time:Double=0
        var velocity:V = .zero
        var scale:Double=1
        var tint:V=V(repeating:1)
        var clock:Double?
        var turn:simd_quatd?
        var only:Int = -1
        var anchor:Anchor?
        var water:Double?
        var mult:Multiplier?
    }
    struct DirectOptions {
        var jitter:Double=0
        var tint:V=V(repeating:1)
        var mult:Multiplier?
        var floor:Double?
        var angle:Double?
        var anchor:Anchor?
        var water:Double?
    }
    struct Info {
        var curves:[String:[[Double]]]
        var timeMode:Int?
        func value(_ name:String,_ time:Double)->Double {
            guard let rows=curves[name],let first=rows.first,first.count>=2 else{return 0}
            if time<=first[0]{return first[1]}
            for index in 1..<rows.count {
                let right=rows[index],left=rows[index-1]
                if time>right[0]{continue}
                return right[0]>left[0] ? left[1]+(right[1]-left[1])*(time-left[0])/(right[0]-left[0]):right[1]
            }
            return rows.last![1]
        }
    }
    struct Emitter {
        var texture:String
        var infos:[String:Info]
        var adds:Bool
        var order:Int
        var span:Double
        var rect:SIMD4<Double> // wide/tall/across/up
        var seen:Double
        var rank:Int
        var available:Bool
        var flat:Bool{infos["flat"] != nil}
        func value(_ info:String,_ field:String,_ time:Double)->Double{infos[info]?.value(field,time) ?? 0}
    }
    struct System {var length:Double;var emitters:[Emitter]}
    struct Particle {
        var on=false
        var flat:Bool
        var position=V.zero,velocity=V.zero,tint=V(repeating:1),home=V.zero
        var anchor:Anchor?
        var emitter:Emitter?
        var life:Double=0,age:Double=0,born:Double=0,rest:Double = -.infinity
        var level:Double?
        var big:Double=1,faint:Double=1,widely:Double=0,tally:Double=0
        var floor:Double?
        var trail:Double=0,spin:Double=0,wide:Double=1,tall:Double=1,turned:Double=0
        var across:Double,up:Double
        var color=V(repeating:1)
        var shows:Double=0
        var adds=false
        var rank=0
    }
    private struct Extra {var anchor:Anchor?;var water:Double?;var angle:Double?;var mult:Multiplier?;var floor:Double?}
    private struct Playing {var system:System;var position:V;var time:Double=0;var extra:Extra?}
    private var systems:[String:System]=[:]
    private let random:()->Double
    var water:((V)->Double?)?
    private(set) var particles:[Particle]
    private var ordinary=0,flat=0
    private var playing:[Playing]=[]
    var shown:[Particle]{particles.filter(\.on)}
    init(data:Data,textures:Set<String>,random:@escaping()->Double={Double.random(in:0..<1)})throws {
        self.random=random
        particles=(0..<1120).map{let flat=$0>=1024;return Particle(flat:flat,across:flat ? 0:0.5,up:flat ? 0:0.5)}
        let document=try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:],rows=document["systems"] as? [String:[String:Any]] ?? [:]
        for(name,row)in rows {
            let length=(row["length"] as? NSNumber)?.doubleValue ?? 0,span=length==0 ? 1:length
            let emitters=(row["emitters"] as? [[String:Any]] ?? []).enumerated().map{index,row->Emitter in
                var infos:[String:Info]=[:]
                for(name,raw)in row["infos"] as? [String:[String:Any]] ?? [:] {
                    var curves:[String:[[Double]]]=[:]
                    for(key,value)in raw {if let rows=value as? [[NSNumber]]{curves[key]=rows.map{$0.map(\.doubleValue)}}}
                    infos[name]=Info(curves:curves,timeMode:(raw["timemode"] as? NSNumber)?.intValue)
                }
                let rect=infos["spriterect"],top=rect?.value("top",0) ?? 0.5,bottom=rect?.value("bottom",0) ?? -0.5,left=rect?.value("left",0) ?? 0.5,right=rect?.value("right",0) ?? -0.5
                let wide=abs(left-right),tall=abs(top-bottom),color=infos["colour"] ?? infos["colourbright"],alpha=color?.curves["alpha"]
                let seen:Double
                if let alpha,alpha.count>1,color?.timeMode != 0,alpha.last![1]==0 {seen=min(1,alpha.last![0])}else{seen=1}
                let texture=row["texture"] as? String ?? "",blend=(row["blend"] as? [NSNumber])?.map(\.intValue) ?? []
                let flat=infos["flat"] != nil,rank=flat ? (index==0 ? 0:128+min(index,100)):1+min(index,100)
                return Emitter(texture:texture,infos:infos,adds:blend.count>1 && blend[1]==1,order:index,span:span,rect:SIMD4(wide==0 ? 1:wide,tall==0 ? 1:tall,(left+right)/2,(top+bottom)/2),seen:seen,rank:rank,available:textures.contains(texture))
            }
            systems[name]=System(length:length,emitters:emitters)
        }
    }
    func has(_ name:String)->Bool{systems[name] != nil}
    func burst(_ name:String,at position:V,delta:Double,options:Options=Options()) {
        guard let system=systems[name] else{return}
        let extra=options.anchor != nil || options.water != nil || options.mult != nil ? Extra(anchor:options.anchor,water:options.water,angle:nil,mult:options.mult,floor:nil):nil
        for emitter in system.emitters where options.only<0 || emitter.order==options.only {
            emit(emitter,at:position,time:options.clock ?? options.time*(system.length==0 ? 1:system.length),delta:delta,velocity:options.velocity,scale:options.scale,tint:options.tint,turn:options.turn,extra:extra)
        }
    }
    func play(_ name:String,at position:V,water:Double?=nil) {
        guard let system=systems[name] else{return}
        playing.append(Playing(system:system,position:position,extra:water.map{Extra(anchor:nil,water:$0,angle:nil,mult:nil,floor:nil)}))
    }
    func spawn(_ name:String,at position:V,velocity:V,count:Int=1,options:DirectOptions=DirectOptions()) {
        guard let emitter=systems[name]?.emitters.first else{return}
        let extra=options.anchor != nil || options.water != nil || options.angle != nil || options.floor != nil ? Extra(anchor:options.anchor,water:options.water,angle:options.angle,mult:nil,floor:options.floor):nil
        guard count>0 else{return}
        for _ in 0..<count {
            var speed=velocity
            if options.jitter != 0 {let x=bias(options.jitter),z=bias(options.jitter),y = -bias(options.jitter);speed += V(x,y,z)}
            add(emitter,position:position,velocity:speed,time:0,tint:options.tint,mult:options.mult,extra:extra)
        }
    }
    func update(delta dt:Double,brightness:Double=1) {
        for index in playing.indices.reversed() {
            let current=playing[index]
            for emitter in current.system.emitters {emit(emitter,at:current.position,time:current.time,delta:dt,velocity:.zero,scale:1,tint:V(repeating:1),turn:nil,extra:current.extra)}
            playing[index].time+=dt
            if playing[index].time>=current.system.length{playing.remove(at:index)}
        }
        for index in particles.indices where particles[index].on {
            var p=particles[index]
            guard let emitter=p.emitter else{continue}
            let info=emitter.infos
            p.age+=dt;let age=p.age/p.life
            if age>=emitter.seen || age>=1 {particles[index].on=false;continue}
            if let force=info["force"]{p.velocity += V(force.value("forcex",age),force.value("forcey",age),force.value("forcez",age))*dt}
            if let friction=info["friction"]{p.velocity *= pow(friction.value("friction",age),50*dt)}
            p.position+=p.velocity*dt
            if let anchor=p.anchor{p.position+=anchor.position-p.home;p.home=anchor.position}
            if p.position.z<p.rest{p.position.z=p.rest;p.velocity.z=0}
            if let floor=p.floor,p.position.z<floor+(p.flat ? 1:p.tall)/2 {
                let info=info["groundcollide"],error=(random()<0.5 ? -5.0:5.0)*(info?.value("bounceerror",age) ?? 0)*dt/sqrt(3)
                p.position.z=floor+(p.flat ? 1:p.tall)/2
                p.velocity=normalized(V(p.velocity.x+error,p.velocity.y+error,p.velocity.z-2*(info?.value("bounce",age) ?? 0)+error))*(info?.value("speedmult",age) ?? 0)
            }
            if let level=p.level,p.position.z>level{particles[index].on=false;continue}
            p.turned+=p.spin*dt
            func size(_ y:Bool)->Double{
                guard let size=info["size"] else{return 1}
                let time=size.timeMode==0 ? min(1,(p.born+p.age)/emitter.span):age
                return max(0.01,(size.value(y ? "sizey":"sizex",time)+size.value(y ? "sizeybias":"sizexbias",time)*(y ? p.tally:p.widely))*p.big)
            }
            if p.flat {
                let width=size(false),height=size(true);p.wide=width*emitter.rect.x;p.tall=height*emitter.rect.y;p.across=width*emitter.rect.z;p.up = -height*emitter.rect.w
            } else if info["size"] != nil {p.wide=size(false)*emitter.rect.x;p.tall=size(true)*emitter.rect.y}
            if let color=info["colour"] ?? info["colourbright"] {
                let light=info["selflit"] != nil ? 1.0/255:brightness/255
                let source=V(color.value("red",age),color.value("green",age),color.value("blue",age))*light
                p.color=V(linear(source.x),linear(source.y),linear(source.z))*p.tint
                p.shows=min(1,color.value("alpha",age)/255)*p.faint
            } else {p.shows=1}
            particles[index]=p
        }
    }
    private func emit(_ emitter:Emitter,at position:V,time:Double,delta:Double,velocity:V,scale:Double,tint:V,turn:simd_quatd?,extra:Extra?) {
        let infos=emitter.infos,count=Int(floor(emitter.value("emrate","rate",time)*scale*delta+random()))
        guard count>0 else{return}
        for _ in 0..<count {
            var at=position
            let size=infos["emsize"]
            if let size {let x=lerp(size.value("sizeminx",time),size.value("sizemaxx",time),random()),z=lerp(size.value("sizeminz",time),size.value("sizemaxz",time),random()),y=lerp(size.value("sizeminy",time),size.value("sizemaxy",time),random());at+=V(x,y,z)}
            if let place=infos["empos"]{at+=V(place.value("x",time),place.value("y",time),place.value("z",time))}
            let dir=infos["emdir"]
            var direction=dir.map{V($0.value("dirx",time),$0.value("diry",time),$0.value("dirz",time))} ?? V(0,0,1)
            if simd_length_squared(direction)<0.000001{direction=V(0,0,1)}
            direction=normalized(direction)
            let angle=infos["emangle"].map{lerp($0.value("min",time),$0.value("max",time),random())*Double.pi/180} ?? 0
            if angle>0 {
                var across=abs(direction.x)>0.9 ? V(0,-1,0):V(1,0,0)
                across=normalized(simd_cross(across,direction));let over=simd_cross(direction,across),around=random()*Double.pi*2
                direction=direction*cos(angle)+across*(sin(angle)*cos(around))+over*(sin(angle)*sin(around))
            }
            let radius=size?.value("radius",time) ?? 0
            if radius>0 && infos["emangle"]==nil{let x=2*random()-1,z=2*random()-1,y = -(2*random()-1);direction=normalized(V(x,y,z))}
            if let turn{direction=turn.act(direction)}
            if radius>0{at+=direction*(radius*random())}
            let speed=max(0,emitter.value("emspeed","speed",time)+bias(emitter.value("emspeed","bias",time)))
            add(emitter,position:at,velocity:direction*speed+velocity,time:time,tint:tint,mult:extra?.mult,extra:extra)
        }
    }
    private func add(_ emitter:Emitter,position:V,velocity:V,time:Double,tint:V,mult:Multiplier?,extra:Extra?) {
        guard emitter.available,emitter.infos["heathaze"]==nil else{return}
        let infos=emitter.infos,isFlat=emitter.flat
        let level=(infos["underwater"] != nil || infos["float"] != nil) ? extra?.water ?? water?(position):nil
        if infos["underwater"] != nil && !(level != nil && position.z<=level!){return}
        let life=(emitter.value("emlife","life",time)+bias(emitter.value("emlife","bias",time)))*(mult?.life ?? 1)
        guard life>0 else{return}
        let index:Int
        if isFlat{index=1024+flat;flat=(flat+1)%96}else{index=ordinary;ordinary=(ordinary+1)%1024}
        var p=particles[index]
        p.position=position;if isFlat{p.position.z+=0.04};p.velocity=velocity;p.emitter=emitter;p.life=life;p.age=0;p.born=time;p.anchor=extra?.anchor
        if let anchor=p.anchor{p.home=anchor.position}
        p.rest=infos["float"] != nil && level != nil ? level!+(isFlat ? 0.04:0):-.infinity
        p.level=infos["underwater"] != nil ? level:nil;p.tint=tint;p.big=mult?.size ?? 1;p.faint=mult?.alpha ?? 1
        p.widely=random()-0.5;p.tally=random()-0.5;p.floor=infos["groundcollide"] != nil ? extra?.floor:nil
        p.trail=infos["trail"].map{$0.value("screenspace",0) != 0 ? -1:$0.value("trailtime",0)/100} ?? 0
        if let rotation=infos["rotspeed"] {
            let clockwise=random()<0.5
            p.spin=(clockwise ? lerp(rotation.value("mincw",0),rotation.value("maxcw",0),random()):-lerp(rotation.value("minccw",0),rotation.value("maxccw",0),random()))*Double.pi/180
        } else{p.spin=0}
        p.adds=emitter.adds
        p.turned=extra?.angle ?? infos["emrotation"].map{lerp($0.value("anglemin",time),$0.value("anglemax",time),random())*Double.pi/180} ?? 0
        if !isFlat{p.across=0.5-emitter.rect.z/emitter.rect.x;p.up=0.5-emitter.rect.w/emitter.rect.y}
        p.shows=0;p.rank=emitter.rank;p.on=true;particles[index]=p
    }
    private func linear(_ value:Double)->Double{value<0.04045 ? value*0.0773993808:pow(value*0.9478672986+0.0521327014,2.4)}
    private func normalized(_ value:V)->V{let length=simd_length(value);return length==0 ? value:value/length}
    private func bias(_ value:Double)->Double{(2*random()-1)*value}
    private func lerp(_ a:Double,_ b:Double,_ t:Double)->Double{a+(b-a)*t}
}
