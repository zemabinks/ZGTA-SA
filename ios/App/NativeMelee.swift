import Foundation
import simd

/// Original data describes attack volumes and markers; it does not authorize
/// damage. Native/server health and inventory remain separate owners.
struct NativeMeleeDefinitions {
    struct Blow:Decodable {
        let hit:Double,chain:Double,radius:Float
        let level:String
        let damage:Double
        var valid:Bool {hit.isFinite && chain.isFinite && radius.isFinite && damage.isFinite &&
            hit>=0 && chain>0 && hit<=chain && radius>0 && radius<10 && damage>=0 &&
            ["H","L","G","B","N","HL","LL","GL"].contains(level)}
    }
    struct Combo:Decodable {let group:String;let attacks:[Blow];let flags:String}
    struct Definition:Decodable {
        let id:Int,range:Float,blocks:Bool,combo:Combo,moving:Blow?,ground:Blow?
        func blow(swing:Int,aside:String?)->Blow? {
            if aside=="run" {return moving};if aside=="ground" {return ground}
            return combo.attacks.indices.contains(swing) ? combo.attacks[swing]:nil
        }
        func compatible(_ profile:NativeFootWeaponAnimation,duration:(String)->Double?)->Bool {
            guard profile.id==id,profile.use=="melee",let swings=profile.swings,
                  let flags=UInt32(combo.flags.replacingOccurrences(of:"0x",with:""),radix:16) else{return false}
            // Original combo tables retain unused slots. OP includes only the
            // available attack flags (flowers have one playable strike).
            let count=1+(flags&1 != 0 ? 1:0)+(flags&2 != 0 ? 1:0)
            guard swings.count==count,combo.attacks.count>=count else{return false}
            for (animation,blow) in zip(swings,combo.attacks.prefix(count)) {
                guard let length=duration(animation.clip),length.isFinite,length>0 else{return false}
                guard abs(animation.loop.fire-blow.hit/30)<0.000001,
                      abs(animation.loop.interval-min(blow.chain/30,length))<0.000001 else{return false}
            }
            return true
        }
    }
    private let entries:[Int:Definition]
    init(data:Data)throws {
        struct Document:Decodable {let version:Int;let weapons:[Definition]}
        let doc=try JSONDecoder().decode(Document.self,from:data)
        guard doc.version==1 else{throw CocoaError(.fileReadCorruptFile)}
        var result:[Int:Definition]=[:]
        for entry in doc.weapons {
            guard (0...15).contains(entry.id),result[entry.id]==nil,entry.range.isFinite,entry.range>0,entry.range<10,
                  !entry.combo.group.isEmpty,(1...3).contains(entry.combo.attacks.count),entry.combo.attacks.allSatisfy(\.valid),
                  entry.moving?.valid ?? true,entry.ground?.valid ?? true else{throw CocoaError(.fileReadCorruptFile)}
            result[entry.id]=entry
        }
        guard result[0] != nil else{throw CocoaError(.fileReadCorruptFile)}
        entries=result
    }
    subscript(_ weapon:Int)->Definition? {entries[weapon]}
}

struct NativeMeleeProbe {
    let weapon:Int
    let feet:SIMD3<Float>
    let heading:Float
    let range:Float
    let radius:Float
}
struct NativeMeleeEvent {
    let weapon:Int
    /// Original controller: combo strikes1...3, running0, ground-1.
    let attack:Int
    let aside:String?
    let feet:SIMD3<Float>
    let heading:Float
    let range:Float
    let radius:Float
    let simulationTime:Double
    var probe:NativeMeleeProbe {.init(weapon:weapon,feet:feet,heading:heading,range:range,radius:radius)}
}

/// Browser60662.OY/9737.lt volumes, with explicit self-host LOS safety.
/// Pick the original geometric target first; a wall denies that target rather
/// than silently changing the chosen victim. Equal normal distances pick last.
enum NativeMeleeTargeting {
    typealias V=SIMD3<Float>
    struct Candidate {
        let id:String
        let feet:V
        var heading:Float=0
        var crouching=false
        var down=false
        var dead=false
    }
    struct Selection {let id:String;let point:V}
    static func select(event:NativeMeleeEvent,candidates:[Candidate],visible:(V,V)->Bool)->Selection? {
        if event.aside=="ground" {return groundTarget(probe:event.probe,candidates:candidates,visible:visible)}
        guard valid(event.probe) else{return nil}
        let origin=SIMD3<Double>(event.feet),heading=Double(event.heading),forward=SIMD2(sin(heading),cos(heading))
        var selected:Candidate?,nearest=Double(event.range+event.radius)
        for item in candidates where eligible(item) && !item.dead {
            let offset=SIMD3<Double>(item.feet)-origin,distance=hypot(offset.x,offset.y)
            guard distance<=nearest,abs(offset.z)<=1.5,
                  distance<=0.3 || simd_dot(SIMD2(offset.x,offset.y),forward)/distance>=0.5 else{continue}
            selected=item;nearest=distance
        }
        return selection(selected,probe:event.probe,ground:false,visible:visible)
    }
    static func groundTarget(probe:NativeMeleeProbe,candidates:[Candidate],visible:(V,V)->Bool)->Selection? {
        guard valid(probe) else{return nil}
        let position=SIMD3<Double>(probe.feet),heading=Double(probe.heading),forward=SIMD2(sin(heading),cos(heading))
        let extent=0.75+Double(probe.radius)
        var selected:Candidate?,best=Double.pi/3
        for item in candidates where eligible(item) && (item.down || item.dead) {
            let offset=SIMD3<Double>(item.feet)-position,h=Double(item.heading),s=sin(h),c=cos(h)
            guard abs(offset.z)<=1.5,abs(s*offset.x+c*offset.y)<extent+0.4,
                  abs(c*offset.x-s*offset.y)<extent+0.2 else{continue}
            let length=hypot(offset.x,offset.y),angle=length<0.05 ? 0:acos(min(1,max(-1,simd_dot(SIMD2(offset.x,offset.y),forward)/length)))
            guard angle<Double.pi/3 else{continue}
            if let old=selected,(!old.dead && item.dead || old.dead==item.dead && angle>=best){continue}
            selected=item;best=angle
        }
        return selection(selected,probe:probe,ground:true,visible:visible)
    }
    private static func selection(_ item:Candidate?,probe:NativeMeleeProbe,ground:Bool,visible:(V,V)->Bool)->Selection? {
        guard let item else{return nil}
        let point=item.feet+V(0,0,ground ? 0.25:item.crouching ? 0.8:1.2),origin=probe.feet+V(0,0,1)
        guard finite(point),finite(origin),visible(origin,point) else{return nil}
        return .init(id:item.id,point:point)
    }
    private static func valid(_ p:NativeMeleeProbe)->Bool {finite(p.feet) && p.heading.isFinite && p.range.isFinite && p.radius.isFinite && p.range>0 && p.radius>0}
    private static func eligible(_ c:Candidate)->Bool {!c.id.isEmpty && c.id.utf8.count<=64 && finite(c.feet) && c.heading.isFinite}
    private static func finite(_ v:V)->Bool {v.x.isFinite && v.y.isFinite && v.z.isFinite}
}
