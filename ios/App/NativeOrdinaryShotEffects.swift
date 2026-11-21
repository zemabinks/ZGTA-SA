// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Shared ordinary bullet presentation. All inputs are already observed
/// world-space events; these queries and particles cannot apply damage.
final class NativeOrdinaryShotEffects {
    typealias V=SIMD3<Double>
    struct Contact {
        let normal:V,material:Int,surface:Int
        var unseen=false
    }
    enum Style:Equatable {case sparks,sand,wood,dust}
    let tracers:NativeShotTracers
    weak var particles:NativeParticleEffects?
    var eye:V?
    var waterLevel:((V)->Double?)?
    var struck:((V,V,Double)->Contact?)?
    var shellFloor:((V,Double)->Double?)?
    private var minigunShell=false
    private let random:()->Double
    init(random:@escaping()->Double={Double.random(in:0..<1)}) {
        self.random=random;tracers=NativeShotTracers(random:random)
    }
    static func style(material:Int,surface:Int)->Style {
        if material<0{return surface==4 ? .sand:surface==3 ? .dust:.sparks}
        if sand.contains(material){return .sand}
        if dust.contains(material){return .dust}
        return wood.contains(material) ? .wood:.sparks
    }
    private static let sand:Set<Int>=[9,10,11,12,13,14,15,16,17,19,20,21,22,24,25,26,27,28,29,30,31,32,33,38,39,40,41,74,75,76,77,78,79,96,97,98,99,100,133,145]
    private static let dust:Set<Int>=[71,80,81,82,83,84,85,86,87,88,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,146,147,148,149,150,151,152,153,166,169,176]
    private static let wood:Set<Int>=[23,42,43,44,61,70,72,73,95,158,163,172,173,174]
    static func linear(_ color:V)->V {
        func channel(_ value:Double)->Double{value<=0.04045 ? value/12.92:pow((value+0.055)/1.055,2.4)}
        return V(channel(color.x),channel(color.y),channel(color.z))
    }
    func clear(){tracers.clear()}
    func blood(at position:V,direction:V,count:Int=8) {
        guard count>0,let particles,particles.has("prt_blood")else{return}
        for _ in 0..<count {
            let size=0.7+0.3*random()
            particles.spawn("prt_blood",at:position,velocity:direction*1.5,
                options:.init(jitter:1,tint:Self.linear(V(0.5,0,0)),mult:.init(size:size,life:0.8)))
        }
    }
    func casing(weapon:Int,at muzzle:V,direction:V) {
        let back:Double,size:Double
        switch weapon {
        case 22,23,24,34:back=0.2;size=0.25
        case 25,26,27:back=0.3;size=0.45
        case 28,29,32:back=0.2;size=0.3
        case 30,31,38:back=0.65;size=0.25
        default:return
        }
        if weapon==38 {minigunShell.toggle();if minigunShell{return}}
        let horizontal=hypot(direction.x,direction.y)
        var velocity=horizontal>0 ? V(direction.y/horizontal,-direction.x/horizontal,0):.zero
        velocity.z=0.4+1.2*random()
        let position=muzzle-direction*back
        guard let particles,particles.has("prt_gunshell"),
              eye.map({simd_distance_squared($0,position)<=100}) ?? true else{return}
        let tint=Self.linear(weapon==25 || weapon==27 ? V(0.6,0.1,0.1):V(repeating:0.5))
        particles.spawn("prt_gunshell",at:position,velocity:velocity,
            options:.init(tint:tint,mult:.init(size:size),floor:shellFloor?(position,4)))
    }
    func shot(_ event:NativeOrdinaryShot.Event,gunsmoke:Bool=true) {
        tracers.shot(from:event.origin,to:event.end)
        let offset=event.end-event.origin,length=simd_length(offset)
        let direction=length>0 ? offset/length:.zero
        if event.origin.z>event.end.z,let level=waterLevel?(event.end),level.isFinite,
           event.end.z<level,event.origin.z>level {
            let crossing=event.origin+offset*((event.origin.z-level)/(event.origin.z-event.end.z))
            if eye.map({simd_distance_squared($0,crossing)<625}) ?? true {particles?.play("water_splash",at:crossing)}
        }
        switch event.impact {
        case .some(.person):
            blood(at:event.end,direction:-direction,count:event.piece == 9 ? 16:8)
        case .some(.car),.some(.world):
            let distance=eye.map{simd_distance_squared($0,event.end)} ?? 0
            if distance<=22500 {
                var contact:Contact?
                if event.impact == .world,length>0 {
                    let reach=min(length,0.3)
                    contact=struck?(event.end-direction*reach,direction,reach+0.2)
                }
                if contact?.unseen != true {
                    let style=contact.map{Self.style(material:$0.material,surface:$0.surface)} ?? .sparks
                    if style != .wood || distance<=625 {hit(at:event.end,normal:contact?.normal ?? -direction,style:style)}
                }
            }
        case .none:break
        }
        if gunsmoke {particles?.play("gunsmoke",at:event.origin)}
    }
    private func hit(at position:V,normal:V,style:Style) {
        // The original generic-FX path is available only with its definitions.
        // Its separate procedural fallback sprites are not reproduced here.
        guard let particles,particles.has("prt_spark")else{return}
        switch style {
        case .sand,.dust:
            let tint=Self.linear(style == .sand ? V(0.81,0.67,0.57):V(repeating:0.6))
            particles.spawn("prt_sand",at:position,velocity:normal*0.3,count:2,
                options:.init(tint:tint,mult:.init(size:0.4,life:0.3,alpha:0.3)))
        case .wood:
            for _ in 0..<4 {
                let size=0.7+0.3*random()
                let tint=Self.linear(V(0.13+0.12*random(),0.12+0.03*random(),0.04+0.03*random()))
                particles.spawn("prt_blood",at:position,velocity:normal*4,
                    options:.init(jitter:2,tint:tint,mult:.init(size:size)))
            }
        case .sparks:
            particles.spawn("prt_spark",at:position,velocity:normal*3,count:8,
                options:.init(jitter:1.2,mult:.init(life:0.8)))
            particles.spawn("prt_smokeii_3_expand",at:position,velocity:normal,
                options:.init(mult:.init(size:0.4,life:0.075,alpha:0.3)))
        }
    }
}
