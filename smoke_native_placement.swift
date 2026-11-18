// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation
// PLACEMENT_SESSION
// SEAT_SESSION

@main struct PlacementChecks {
    static var checks=0
    static func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
    static let nonce="placement-session-A000000"
    static func hello(_ nonce:String=nonce)->[String:Any]{[
        "positionAck":1,"placement":["connection":nonce,"revision":0],"spot":[100.125,200.5,20.75,0.75],
        "healthAck":["connection":nonce,"processed":0,"revision":0,"respawned":0],"life":[73,11]]}
    static func transaction(_ value:NativePlacementSession.Hello)->NativePlacementSession.Transaction {
        guard case .place(let item)=value else{preconditionFailure("Valid placement rejected")};return item
    }
    static func tp(_ revision:Int,_ nonce:String=nonce)->[String:Any]{[
        "t":"tp","x":300.125,"y":400.5,"z":20.75,"h":90.0,
        "placement":["connection":nonce,"revision":revision]]}
    static func main(){
        var legacy=NativePlacementSession()
        if case .legacy=legacy.hello([:],connection:nonce,fresh:true){}else{preconditionFailure("Legacy handshake changed")}
        check(!legacy.negotiated && legacy.permitsPosition,"Legacy mode incorrectly gated")
        check(legacy.stamping(["t":"me"])?["placement"]==nil,"Legacy packet was tagged")
        var state=NativePlacementSession()
        let initial=transaction(state.hello(hello(),connection:nonce,fresh:true))
        check(state.negotiated && state.isPlacing && !state.permitsPosition && state.applied==nil,"Fresh barrier absent")
        check(initial.position==SIMD3(100.125,200.5,20.75) && initial.heading == -0.75,"Hello unit/precision boundary changed")
        check(state.stamping(["t":"me"])==nil,"Pending hello leaked position")
        check(state.stamping(["t":"board"])?["t"]as?String=="board","Non-position helper changed packet")
        check(state.commit(initial) && !state.isPlacing && state.permitsPosition,"Applied hello did not unlock")
        check(!state.commit(initial),"Transaction committed twice")
        check((state.stamping(["t":"me","placement":["revision":999]])?["placement"]as?[String:Any])?["revision"]as?Int==0,"Central stamp trusted forged producer envelope")
        let next=state.teleport(tp(1),connection:nonce)!
        check(state.isPlacing && state.applied?.revision==0 && !state.permitsPosition,"TP published pending revision early")
        check(state.stamping(["t":"me"])==nil,"TP cleanup leaked old/current pose")
        check(abs(next.heading + .pi/2)<1e-6,"TP degrees converted incorrectly")
        check(state.commit(next) && state.applied?.revision==1,"TP commit failed")
        for duplicate:[String:Any] in [[:],hello(),["positionAck":true,"placement":false,"spot":[0,0,0,0]]]{
            if case .duplicate=state.hello(duplicate,connection:nonce,fresh:false){}else{preconditionFailure("Duplicate hello reprocessed")}
            check(state.negotiated && state.applied?.revision==1 && !state.isPlacing,"Duplicate hello rewound or downgraded")
        }
        let malformed:[Any]=[true,false,NSNull(),"1",[],[:],-1,0.5,Double.nan,Double.infinity,-Double.infinity,9_007_199_254_740_992.0]
        for bad in malformed {
            var packet=tp(2);packet["placement"]=["connection":nonce,"revision":bad]
            check(state.teleport(packet,connection:nonce)==nil,"Invalid revision admitted: \(bad)")
            for key in ["x","y","z","h"] {
                if let n=bad as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,
                   abs(n.doubleValue)<=1_000_000{continue}
                var packet=tp(2);packet[key]=bad
                check(state.teleport(packet,connection:nonce)==nil,"Invalid pose scalar admitted: \(key)")
            }
            check(state.applied?.revision==1 && !state.isPlacing,"Invalid TP changed state")
        }
        for bad in [NSNull(),true,[],[:],["connection":"old-session-0000000","revision":2],
                    ["connection":nonce,"revision":0],["connection":nonce,"revision":1]]as[Any]{
            var packet=tp(2);packet["placement"]=bad
            check(state.teleport(packet,connection:nonce)==nil,"Missing/old envelope admitted")
        }
        for value in [1_000_000.1,-1_000_000.1,Double.greatestFiniteMagnitude]{
            var packet=tp(2);packet["x"]=value
            check(state.teleport(packet,connection:nonce)==nil,"Out-of-domain coordinate admitted")
        }
        let badValues:[Any]=[true,false,NSNull(),"1",[],[:],-1,0.5,Double.nan,Double.infinity]
        for field in ["positionAck","placement","spot","healthAck","life"] {
            for bad in badValues {
                var message=hello();message[field]=bad;var candidate=NativePlacementSession()
                if case .invalid=candidate.hello(message,connection:nonce,fresh:true){}else{preconditionFailure("Invalid hello field admitted: \(field)")}
                check(!candidate.negotiated && !candidate.isPlacing && candidate.applied==nil,"Rejected hello partially applied")
            }
        }
        for key in ["processed","revision","respawned"] {
            for bad in badValues {
                var message=hello(),ack=message["healthAck"]as![String:Any];ack[key]=bad;message["healthAck"]=ack
                var candidate=NativePlacementSession()
                if case .invalid=candidate.hello(message,connection:nonce,fresh:true){}else{preconditionFailure("Invalid health prerequisite admitted")}
                check(candidate.applied==nil,"Malformed health prerequisite placed")
            }
        }
        for bad in ["","short","bad nonce with spaces","n"+String(repeating:"x",count:80),"wrong-session-0000000"] {
            var candidate=NativePlacementSession();let message=hello(bad=="wrong-session-0000000" ? nonce:bad)
            if case .invalid=candidate.hello(message,connection:bad,fresh:true){}else{preconditionFailure("Invalid/mismatched nonce admitted")}
            check(candidate.applied==nil,"Bad nonce applied")
        }
        var invalidInitial=hello();invalidInitial["placement"]=["connection":nonce,"revision":1]
        var candidate=NativePlacementSession()
        if case .invalid=candidate.hello(invalidInitial,connection:nonce,fresh:true){}else{preconditionFailure("Nonzero fresh revision admitted")}
        for degrees in [-720.0,-180,-90,-40,-0.001,0,0.001,39.5340878640268,90,180,270,720] {
            let revision=state.applied!.revision+1
            var packet=tp(revision);packet["h"]=degrees
            let transaction=state.teleport(packet,connection:nonce)!
            check(abs(Double(transaction.heading)+degrees * .pi/180)<2e-6,"TP angle changed")
            check(state.commit(transaction),"Angle transaction commit failed")
        }
        // A replacement transaction or reset must never accept an old callback.
        let old=state.teleport(tp(state.applied!.revision+1),connection:nonce)!
        let newer=state.teleport(tp(old.envelope.revision+1),connection:nonce)!
        check(!state.commit(old) && state.isPlacing,"Older callback committed over newer pending transaction")
        check(state.commit(newer) && !state.commit(old),"Older callback undid newer commit")
        let pending=state.teleport(tp(state.applied!.revision+1),connection:nonce)!
        state.reset();check(!state.commit(pending) && !state.negotiated && state.applied==nil && !state.isPlacing,"Disconnect retained pending transaction")
        let replacement=transaction(state.hello(hello(),connection:nonce,fresh:true))
        check(!state.commit(pending) && state.commit(replacement),"Old callback matched a replacement session")
        var frame=state.stamping(["t":"me"])!
        check((frame["placement"]as![String:Any])["connection"]as?String==nonce,"Wrong connection stamped")
        let maximum=state.teleport(tp(9_007_199_254_740_991),connection:nonce)!
        check(state.commit(maximum),"Largest safe revision rejected")
        check(state.teleport(tp(9_007_199_254_740_991),connection:nonce)==nil,"Equal max revision repeated")
        frame=state.stamping(["t":"me"])!
        check((frame["placement"]as![String:Any])["revision"]as?Int==9_007_199_254_740_991,"Safe integer rounded")
        var seats=NativeVehicleSeatSession()
        let beforeTP=seats.request(vehicle:"authored-cab",seat:1)!
        seats.clearOccupancy()
        let afterTP=seats.request(vehicle:"authored-cab",seat:1)!
        check(afterTP.request>beforeTP.request,"TP reused entry correlation")
        check(seats.receive(vehicle:"authored-cab",seat:1,accepted:true,request:beforeTP.request)==nil,"Old ACK granted new seat")
        check(seats.pending==afterTP && seats.passenger==nil,"Old ACK canceled new entry")
        check(seats.receive(vehicle:"authored-cab",seat:1,accepted:true,request:afterTP.request) != nil && seats.passenger != nil,"Current entry ACK rejected")
        seats.clearOccupancy();check(seats.pending==nil && seats.passenger==nil,"Placement retained occupancy")
        seats.reset();check(seats.request(vehicle:"authored-cab",seat:1)?.request==1,"Fresh connection failed to reset namespace")
        // Historical misuse control: full reset on the SAME peer aliases ACKs.
        var oldReset=NativeVehicleSeatSession()
        let prior=oldReset.request(vehicle:"authored-cab",seat:1)!
        oldReset.reset();let reused=oldReset.request(vehicle:"authored-cab",seat:1)!
        check(prior.request==reused.request,"Old same-peer-reset alias control absent")
        check(oldReset.receive(vehicle:"authored-cab",seat:1,accepted:true,request:prior.request) != nil,"Old reset ambiguity no longer reproduced")
        print("DRAFT_SAME_PEER_RESET_ALIAS prior=1 replacement=1 delayedOldAccepted=true")
        print("PASS placement session: \(checks) checks")
    }
}
