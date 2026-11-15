import Foundation

/// SA PC defaults and console face buttons. Analog trigger aim/fire and
/// throttle are the explicitly retained native modern-controller adaptation.
enum NativeGameBindings {
    enum Mode: Equatable { case foot, climb, swim, jetpack, parachute, vehicle(String) }
    struct Context: Equatable {
        var mode: Mode = .foot
        var landingGear = false
        var nozzle = false
        var melee = false
        var guarding = false
        var driving: Bool { if case .vehicle = mode { return true };return false }
        var aircraft: Bool { if case .vehicle(let kind)=mode { return kind=="plane" || kind=="helicopter" };return false }
    }
    enum Action: Equatable { case jump, crouch, dive, enter, meleeAlternate, weaponPrevious, weaponNext, reload, action, jobs, chat, map, animations, camera, lights, gear, radioPrevious, radioNext, pause, attack }
    // USB HID usages, shared by UIKit and physical keyboards. No UIKit
    // dependency is needed to verify the complete mapping on a host machine.
    enum Key: Int, CaseIterable {
        case a=4,c=6,d=7,e=8,f=9,g=10,h=11,j=13,l=15,m=16,q=20,r=21,s=22,t=23,v=25,w=26
        case two=31,four=33,enter=40,escape=41,tab=43,space=44,caps=57,insert=73,home=74,delete=76
        case right=79,left=80,down=81,up=82,keypadPlus=87,keypadOne=89,keypadTwo=90,keypadFour=92,keypadSix=94,keypadEight=96,keypadZero=98
        case control=224,shift=225,alt=226,rightControl=228
    }
    struct Frame {
        var forward: Float=0,sideways:Float=0,steering:Float=0,pitch:Float=0
        var moving=false,steeringKeys=false,pitchKeys=false
        var sprint=false,walk=false,jump=false,attack=false,aim=false,handbrake=false,horn=false,flightBrake=false,hop=false
        var look:String?,nozzle:Float=0
    }
    static func keyAction(_ raw:Int,context c:Context)->Action? {
        guard let k=Key(rawValue:raw) else{return nil}
        switch k {
        case .escape:return .pause
        case .f,.enter:return c.melee && c.guarding ? .meleeAlternate:.enter
        case .v,.home:return .camera
        case .j:return .jobs // Native server extension; F remains enter/exit.
        case .t:return .chat
        case .m:return .map
        case .g:return .animations // No unimplemented gang command is claimed.
        case .l:return c.driving ? .lights:nil
        case .two:return c.landingGear ? .gear:nil
        case .insert,.four:return c.driving ? .radioNext:nil
        case .r:return c.driving ? .radioPrevious:.reload
        case .delete:return c.driving ? .radioPrevious:nil
        case .tab:return c.driving ? nil:.action
        case .q:return c.driving ? nil:.weaponPrevious
        case .e:return c.driving ? nil:.weaponNext
        case .shift,.rightControl:
            return c.driving || c.mode == .jetpack || c.mode == .parachute || (c.melee && c.guarding) ? nil:.jump
        case .c:return c.driving || c.mode == .climb || c.mode == .jetpack || c.mode == .parachute ? nil:(c.mode == .swim ? .dive:.crouch)
        case .control,.keypadZero:return c.mode == .swim ? .dive:nil
        default:return nil
        }
    }
    static func keyboard(_ raw:Set<Int>,context c:Context)->Frame {
        func held(_ keys:Key...)->Bool {keys.contains{raw.contains($0.rawValue)}}
        func axis(_ positive:Bool,_ negative:Bool)->Float {(positive ? 1:0)-(negative ? 1:0)}
        var f=Frame()
        f.sprint = !c.driving && held(.space)
        f.walk = c.mode == .foot && held(.alt)
        f.jump = !c.driving && held(.shift,.rightControl)
        f.attack = !c.driving && c.mode != .climb && c.mode != .swim && held(.control,.keypadZero)
        f.aim = !c.driving && c.mode != .climb && c.mode != .swim && c.mode != .parachute && held(.delete,.caps)
        f.handbrake = c.driving && held(.space,.rightControl)
        f.horn = c.driving && held(.h,.caps)
        f.flightBrake = c.mode == .jetpack && held(.c)
        if c.driving {
            // Original INTRO1 tutorial names VEHICLE_FIREWEAPON_ALT: the
            // PC manual's secondary-fire keys, not jump or handbrake.
            f.hop = c.mode == .vehicle("bicycle") && held(.control,.keypadZero)
            f.forward=axis(held(.w),held(.s));f.moving=held(.w,.s)
            f.sideways=c.aircraft ? axis(held(.d),held(.a)):0
            f.steering=axis(held(.right) || (!c.aircraft && held(.d)),held(.left) || (!c.aircraft && held(.a)))
            f.steeringKeys=c.aircraft ? held(.left,.right):held(.a,.d,.left,.right)
            f.pitch=axis(held(.up),held(.down));f.pitchKeys=held(.up,.down)
            let left=held(.q),right=held(.e)
            f.look=left && right ? "behind":left ? "left":right ? "right":nil
            f.nozzle=c.nozzle ? axis(held(.keypadEight),held(.keypadTwo)):0
        } else {
            f.forward=axis(held(.w,.up),held(.s,.down))
            f.sideways=axis(held(.d,.right),held(.a,.left))
            f.moving=held(.w,.a,.s,.d,.up,.down,.left,.right)
            f.look=held(.keypadOne) ? "behind":nil
        }
        return f
    }
    /// Hardware aim takes ownership on a hardware edge. A neutral keyboard or
    /// controller must not clear the independently toggled touch gun aim.
    static func cameraAimUpdate(held:Bool,previousHeld:Bool,melee:Bool,current:Bool)->Bool? {
        if melee {return current ? false:nil}
        return held != previousHeld ? held:nil
    }
    static func shouldRequestAttack(held:Bool,wasHeld:Bool,nativeGun:Bool,nativeMelee:Bool)->Bool {
        held && ((!nativeGun && !nativeMelee) || !wasHeld)
    }
    struct Pad {
        var a=false,b=false,x=false,y=false,lb=false,rb=false,leftClick=false,rightClick=false,menu=false,options=false
        var up=false,down=false,left=false,right=false
    }
    static func padLook(_ pad:Pad,context c:Context)->String? {
        if pad.rightClick {return "behind"}
        // Aircraft shoulders are rudder controls, not a simultaneous fixed
        // camera peek. Car/bike shoulder look keeps its documented meaning.
        guard c.driving,!c.aircraft else{return nil}
        return pad.lb && pad.rb ? "behind":pad.lb ? "left":pad.rb ? "right":nil
    }
    static func padActions(_ now:Pad,previous old:Pad,context c:Context)->[Action] {
        if now.menu && !old.menu{return [.pause]}
        var out:[Action]=[]
        if now.options && !old.options {out.append(.camera)}
        if now.y && !old.y {out.append(c.melee && c.guarding ? .meleeAlternate:.enter)}
        guard !c.driving else {
            if c.landingGear && now.leftClick && !old.leftClick {out.append(.gear)}
            if now.up && !old.up {out.append(.radioNext)}
            if now.down && !old.down {out.append(.radioPrevious)}
            return out
        }
        if now.x && !old.x && c.mode != .jetpack && c.mode != .parachute && !(c.melee && c.guarding) {out.append(.jump)}
        if now.b && !old.b && c.mode == .swim {out.append(.dive)}
        if now.b && !old.b && c.mode == .climb {out.append(.enter)}
        if c.mode != .climb && c.mode != .swim && c.mode != .parachute {
            if now.lb && !old.lb {out.append(.weaponPrevious)}
            if now.rb && !old.rb {out.append(.weaponNext)}
            if now.up && !old.up {out.append(.reload)} // Explicit native extension.
            if now.leftClick && !old.leftClick && c.mode != .jetpack {out.append(.crouch)}
        }
        return out
    }
    static func weaponOrder(_ rows:[[String:Any]],owned:[Int])->[Int] {
        let allowed=Set(owned)
        let ordered=rows.compactMap { row -> (Int,Int)? in
            guard let id=row["id"] as? Int,let slot=row["slot"] as? Int,allowed.contains(id) else{return nil}
            return (id,slot)
        }.sorted {$0.1 == $1.1 ? $0.0 < $1.0:$0.1 < $1.1}.map(\.0)
        var seen=Set<Int>()
        return (ordered+owned).filter{seen.insert($0).inserted}
    }
    static func legend(_ c:Context)->String {
        switch c.mode {
        case .climb:return "SHIFT / PAD X: PULL UP\nF / RETURN / PAD Y OR B: LET GO\nESC / MENU: PAUSE"
        case .swim:return "WASD / STICK: SWIM - SPACE / PAD A: FAST\nCTRL / PAD B: DIVE - SHIFT / PAD X: JUMP\nF / PAD Y: ENTER - ESC / MENU: PAUSE"
        case .jetpack:return "SPACE / PAD A: RISE - SHIFT / PAD X: DESCEND\nC: BRAKE - CTRL / PAD B OR RT: FIRE\nF / PAD Y: REMOVE WHEN GROUNDED - MENU: PAUSE"
        case .parachute:return "WASD / STICK: STEER\nCTRL / PAD B OR RT: OPEN CANOPY\nESC / MENU: PAUSE"
        case .vehicle(let kind):
            if kind=="bicycle" {return "W/S OR RT/LT: PEDAL / REVERSE - X: BRAKE\nHOLD / RELEASE CTRL, KEYPAD 0 OR PAD A: BUNNY HOP\nF / RETURN / PAD Y: EXIT - ESC / MENU: PAUSE"}
            if c.aircraft {return "ARROWS / LEFT STICK: PITCH / ROLL\nA/D OR LB/RB: RUDDER - W/S OR RT/LT: THRUST\nF / PAD Y: EXIT - ESC / MENU: PAUSE"}
            return "W/S OR RT/LT: GAS / BRAKE - ARROWS: STEER\nSPACE / PAD X: HANDBRAKE - Q/E OR LB/RB: LOOK\nF / RETURN / PAD Y: EXIT - ESC / MENU: PAUSE"
        case .foot:
            if c.melee {return "CTRL / PAD B OR RT: STRIKE - AIM: GUARD\nHOLD AIM + SHIFT / PAD X: BLOCK\nQ/E OR LB/RB: WEAPON - ESC / MENU: PAUSE"}
            return "WASD / ARROWS: MOVE - SPACE / PAD A: RUN\nSHIFT / PAD X: JUMP - F / PAD Y: ENTER\nQ/E OR LB/RB: WEAPON - ALT: WALK - B/RT: ATTACK"
        }
    }
}

/// Serialize selection requests so fast Q/E or shoulder taps advance from the
/// requested cursor, not an earlier authoritative HTTP/WS snapshot.
final class NativeWeaponCycleQueue {
    struct Request {let id:UUID;let weapon:Int}
    private var targets:[Int]=[]
    private var cursor:Int?
    private var current:Request?
    private var cancelled=false
    var busy:Bool {current != nil}
    func request(direction:Int,owned:[Int],selected:Int)->Request? {
        guard !(cancelled && busy) else{return nil}
        var seen=Set<Int>()
        let choices=owned.filter{seen.insert($0).inserted}
        guard choices.count>1, direction != 0 else{return nil}
        let index=choices.firstIndex(of:cursor ?? selected) ?? 0
        let target=choices[(index+(direction>0 ? 1:choices.count-1)) % choices.count]
        cursor=target;targets.append(target)
        return next()
    }
    func complete(_ id:UUID,succeeded:Bool?)->Request? {
        guard current?.id==id else{return nil}
        current=nil
        guard succeeded==true,!cancelled else {targets=[];cursor=nil;cancelled=false;return nil}
        return next()
    }
    func cancel() {targets=[];cursor=nil;cancelled=busy}
    /// A fresh connection invalidates the old HTTP nonce on the server.
    func disconnected() {targets=[];cursor=nil;current=nil;cancelled=false}
    private func next()->Request? {
        guard current==nil,!targets.isEmpty else {if current==nil {cursor=nil};return nil}
        let result=Request(id:UUID(),weapon:targets.removeFirst());current=result;return result
    }
}

/// A modal opened by a held button must observe its release before that same
/// button is allowed to close it. Polls/auto-repeat are not fresh edges.
struct NativeReleaseEdge {
    private var down:Bool
    init(pressed:Bool) {down=pressed}
    mutating func update(pressed:Bool)->Bool {
        let edge=pressed && !down;down=pressed;return edge
    }
}

/// One state object spans the presenting responder and a modal responder.
/// A key-up delivered during presentation cannot be overwritten by a late
/// viewDidAppear seed copied from the opening key-down.
final class NativeModalKeyHandoff {
    private var edge:NativeReleaseEdge
    init(pressed:Bool=false) {edge=NativeReleaseEdge(pressed:pressed)}
    func press()->Bool {edge.update(pressed:true)}
    func release() {_=edge.update(pressed:false)}
}

/// Raw-HID ownership crosses UIKit menu/game responders. A release delivered
/// to the game must clear the same latch that suppressed menu auto-repeat.
enum NativeMenuKeyLatch {
    private static var held: Set<Int> = []
    static func press(_ key: Int) -> Bool { held.insert(key).inserted }
    static func isHeld(_ key: Int) -> Bool { held.contains(key) }
    static func release(_ key: Int) { held.remove(key) }
    static func reset() { held.removeAll() }
}
