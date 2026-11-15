import Foundation
import simd

/// Original91584 rail samples retain its Float32 point/cumulative-distance
/// storage, while the train's control and pose calculations remain Double.
final class NativeTrainTracks {
    typealias V=SIMD3<Double>
    struct Line { let tram:Bool;let points:[V];let from:[Double];let total:Double }
    struct Nearest { let line:Int;let node:Int;let distance:Double;let away:Double;let way:V }
    let lines:[Line]
    init?(data:Data) {
        guard let document=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let rows=document["lines"] as? [[String:Any]] else { return nil }
        var lines:[Line]=[]
        for row in rows {
            guard let values=row["points"] as? [Double],values.count>=6,values.count%3==0,values.allSatisfy(\.isFinite) else { return nil }
            let points=stride(from:0,to:values.count,by:3).map { V(Double(Float(values[$0])),Double(Float(values[$0+2])),Double(Float(-values[$0+1]))) }
            var from=[Double](repeating:0,count:points.count+1)
            for index in points.indices {
                let difference=points[(index+1)%points.count]-points[index]
                from[index+1]=Double(Float(from[index]+Self.hypot3(difference)))
            }
            guard let total=from.last,total>0 else { return nil }
            lines.append(Line(tram:row["tram"] as? Bool ?? false,points:points,from:from,total:total))
        }
        guard !lines.isEmpty else { return nil };self.lines=lines
    }
    private static func hypot3(_ v:V)->Double {
        let scale=max(abs(v.x),max(abs(v.y),abs(v.z)));if scale==0 { return 0 }
        var sum=0.0,compensation=0.0
        for component in [v.x,v.y,v.z] {
            let fraction=abs(component)/scale,term=fraction*fraction-compensation,total=sum+term
            compensation=(total-sum)-term;sum=total
        }
        return sqrt(sum)*scale
    }
    func lineIndex(model:Int)->Int? { model==449 ? lines.firstIndex(where:{$0.tram}):0 }
    func sample(line:Int,distance:Double,node:inout Int?)->V {
        let track=lines[line],count=track.points.count
        let wrapped=((distance.truncatingRemainder(dividingBy:track.total))+track.total).truncatingRemainder(dividingBy:track.total)
        var at=node ?? min(count-1,Int(floor(wrapped/track.total*Double(count))))
        for _ in 0..<count {
            if track.from[at]<=wrapped && wrapped<=track.from[at+1] { break }
            at=(at+(wrapped<track.from[at] ? count-1:1))%count
        }
        node=at
        let share=(wrapped-track.from[at])/max(0.000001,track.from[at+1]-track.from[at])
        return track.points[at]+(track.points[(at+1)%count]-track.points[at])*share
    }
    func nearest(model:Int,position:V,node:inout Int?)->Nearest? {
        guard let line=lineIndex(model:model) else { return nil };let track=lines[line],count=track.points.count
        func search(start:Int,amount:Int)->Nearest? {
            var best:Nearest?
            for offset in 0..<amount {
                let at=(((start+offset)%count)+count)%count,next=(at+1)%count
                let a=track.points[at],difference=track.points[next]-a,length=simd_length(difference)
                if length<0.000001 { continue }
                let share=min(1,max(0,simd_dot(position-a,difference)/(length*length)))
                let point=a+difference*share,away=simd_length(point-position)
                if best==nil || away<best!.away { best=Nearest(line:line,node:at,distance:track.from[at]+share*length,away:away,way:difference*(1/length)) }
            }
            return best
        }
        var result:Nearest?
        if let node,node<count,count>25,let nearby=search(start:node-12,amount:25),nearby.away<=6 { result=nearby }
        if result==nil { result=search(start:0,amount:count) }
        if let result { node=result.node };return result
    }
}

/// Original91584 train motor: rail-constrained velocity kinematics, including
/// original acceleration/braking, reverse, chord pose and coupled carriages.
final class NativeTrainDynamics {
    typealias V=SIMD3<Double>
    struct Configuration { let model:Int;let origin:Double;let lower:Double;let minimum:V;let maximum:V;var carriages:[Int]=[] }
    struct Pose { let position:V;let rotation:simd_quatd }
    struct Output { let pose:Pose;let target:Pose;let linearVelocity:V;let angularVelocity:V }
    private final class PoseCache { var front:Int?;var rear:Int? }
    let configuration:Configuration
    let tracks:NativeTrainTracks
    let direction:Double
    let line:Int
    private let cache=PoseCache()
    private var carriageCaches:[PoseCache]=[]
    private var carriageNode:Int?
    private var distance:Double
    private var normalizedSpeed=0.0
    private let height:Double,back:Double,front:Double,weight:Double
    private(set) var initial=Pose(position:.zero,rotation:simd_quatd(ix:0,iy:0,iz:0,r:1))
    var speed:Double { 50*normalizedSpeed }
    init?(configuration:Configuration,tracks:NativeTrainTracks,position:V,heading:Double) {
        var node:Int?
        guard let nearest=tracks.nearest(model:configuration.model,position:position,node:&node) else { return nil }
        self.configuration=configuration;self.tracks=tracks;line=nearest.line
        back = -configuration.minimum.y;front=configuration.maximum.y
        direction = -nearest.way.x*sin(heading)-nearest.way.z*cos(heading)>=0 ? 1:-1
        distance=nearest.distance+direction*front
        height=configuration.lower-configuration.minimum.z-configuration.origin
        weight=3+Double(configuration.carriages.count)
        initial=pose(at:distance,configuration:configuration,cache:cache)
    }
    private static func normalized(_ v:V)->V { let length=simd_length(v);return length>0 ? v*(1/length):v }
    private static func rotation(right:V,up:V,back:V)->simd_quatd {
        let m11=right.x,m12=up.x,m13=back.x,m21=right.y,m22=up.y,m23=back.y,m31=right.z,m32=up.z,m33=back.z
        let trace=m11+m22+m33
        let x:Double,y:Double,z:Double,w:Double
        if trace>0 {
            let scale=0.5/sqrt(trace+1);w=0.25/scale;x=(m32-m23)*scale;y=(m13-m31)*scale;z=(m21-m12)*scale
        } else if m11>m22 && m11>m33 {
            let scale=2*sqrt(1+m11-m22-m33);w=(m32-m23)/scale;x=0.25*scale;y=(m12+m21)/scale;z=(m13+m31)/scale
        } else if m22>m33 {
            let scale=2*sqrt(1+m22-m11-m33);w=(m13-m31)/scale;x=(m12+m21)/scale;y=0.25*scale;z=(m23+m32)/scale
        } else {
            let scale=2*sqrt(1+m33-m11-m22);w=(m21-m12)/scale;x=(m13+m31)/scale;y=(m23+m32)/scale;z=0.25*scale
        }
        return simd_quatd(ix:x,iy:y,iz:z,r:w)
    }
    private func pose(at distance:Double,configuration:Configuration,cache:PoseCache,direction suppliedDirection:Double? = nil)->Pose {
        let direction=suppliedDirection ?? self.direction
        let rearExtent = -configuration.minimum.y,frontExtent=configuration.maximum.y
        let head=tracks.sample(line:line,distance:distance,node:&cache.front)
        if cache.rear==nil { cache.rear=cache.front }
        let tail=tracks.sample(line:line,distance:distance-direction*(rearExtent+frontExtent),node:&cache.rear)
        let backward=Self.normalized(tail-head),right=Self.normalized(simd_cross(V(0,1,0),backward)),up=simd_cross(backward,right)
        let height=configuration.lower-configuration.minimum.z-configuration.origin
        return Pose(position:tail+backward*(-rearExtent)+up*height,rotation:Self.rotation(right:right,up:up,back:backward))
    }
    /// Original91584.wY places every carriage from the locomotive's current
    /// Float32 Rapier pose, retaining its independent nearest-node cache.
    func carriages(body:Pose,configurations:[Configuration])->[Pose] {
        guard !configurations.isEmpty,
              let nearest=tracks.nearest(model:configuration.model,position:body.position,node:&carriageNode) else { return [] }
        while carriageCaches.count<configurations.count { carriageCaches.append(PoseCache()) }
        let direction=simd_dot(body.rotation.act(V(0,0,-1)),nearest.way)>=0 ? 1.0:-1.0
        var distance=nearest.distance+direction*configuration.maximum.y
        var length=configuration.maximum.y-configuration.minimum.y
        return configurations.enumerated().map { index,configuration in
            distance -= direction*(length+0.6)
            length=configuration.maximum.y-configuration.minimum.y
            return pose(at:distance,configuration:configuration,cache:carriageCaches[index],direction:direction)
        }
    }
    func step(delta:Double,throttle:Double,handbrake:Bool)->Output {
        let ticks=50*delta,input=min(1,max(-1,throttle)),accelerate=max(0,input),braking=max(0,-input)
        var drive=accelerate-braking,brake=0.0
        if abs(normalizedSpeed)>=0.001 {
            if normalizedSpeed>0 { drive=accelerate;brake=braking }
            else { drive = -braking;brake=accelerate }
        }
        if handbrake { drive=0;brake=1 }
        normalizedSpeed += drive*ticks*0.002/weight
        if brake != 0 {
            let change=brake*ticks*0.006/weight
            normalizedSpeed=abs(normalizedSpeed)>=change ? normalizedSpeed-(normalizedSpeed<0 ? -change:change):0
        }
        normalizedSpeed=min(1,max(-1,normalizedSpeed*pow(0.99975,ticks)))
        let current=pose(at:distance,configuration:configuration,cache:cache)
        distance += direction*normalizedSpeed*ticks
        let next=pose(at:distance,configuration:configuration,cache:cache)
        let linear=(next.position-current.position)*(1/delta),a=next.rotation,b=current.rotation.conjugate
        var difference=simd_quatd(ix:a.imag.x*b.real+a.real*b.imag.x+a.imag.y*b.imag.z-a.imag.z*b.imag.y,
            iy:a.imag.y*b.real+a.real*b.imag.y+a.imag.z*b.imag.x-a.imag.x*b.imag.z,
            iz:a.imag.z*b.real+a.real*b.imag.z+a.imag.x*b.imag.y-a.imag.y*b.imag.x,
            r:a.real*b.real-a.imag.x*b.imag.x-a.imag.y*b.imag.y-a.imag.z*b.imag.z)
        if difference.real<0 { difference=simd_quatd(vector:-difference.vector) }
        let angle=2*acos(min(1,difference.real)),sine=sqrt(max(0,1-difference.real*difference.real))
        let scale=sine>0.000001 ? angle/sine/delta:0
        return Output(pose:current,target:next,linearVelocity:linear,angularVelocity:difference.imag*scale)
    }
}
