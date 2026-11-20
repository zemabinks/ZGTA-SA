// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

private final class UIApplication {
    enum State {case active,inactive}
    static let shared=UIApplication()
    var applicationState:State = .active
}
private final class AuthoredView {var window:Bool?=true}
private final class Carrier {
    var now:Double=1
    private var lastRiderDraw:Double=0
    private var riderPoseClock=NativeRiderPoseClock()
    private var riderMonotonicNow:()->Double={0}
    private let view=AuthoredView()
    private let definition=NativeRiderDefinitions.Definition(model:"authored",astride:true,
        clips:["sit":"authored/sit","pedal":"authored/pedal"],seats:[],origin:0,bike:nil,afloat:nil,group:nil)
    private var ownRiderAnimation:NativeRiderAnimation?=NativeRiderAnimation(duration:{_ in 2})
    private let input=NativeRiderAnimation.Input(speed:10,pedal:1)
    init(){riderMonotonicNow = {[unowned self]in self.now}}
    func sample(_ time:Double,active:Bool=true,visible:Bool=true)->(Double,NativeRiderAnimation.Frame?) {
        now=time;UIApplication.shared.applicationState=active ? .active:.inactive;view.window=visible ? true:nil
// ACTUAL_CLOCK
        return (riderDelta,/* ACTUAL_FALLBACK */)
    }
}

private struct Failure:Error {let message:String}
private var checks=0
private func check(_ ok:Bool,_ label:String)throws{checks+=1;if !ok{throw Failure(message:label)}}
private func near(_ a:Double,_ b:Double,_ label:String)throws{try check(a.isFinite && abs(a-b)<1e-9,label+": \(a) != \(b)")}
private func phase(_ value:Double)->Double{value-floor(value)}
private func circular(_ a:Double,_ b:Double,_ label:String)throws{
    let d=abs(a-b);try check(a.isFinite && min(d,abs(1-d))<1e-9,label+": \(a) != \(b)")
}

@main private struct Main {
    static func schedule(_ steps:[Double])throws {
        let owner=Carrier(),bike=NativeRemoteBikeAnimation()
        let packet=NativeRemoteBikeAnimation.Sample(serial:1,time:1,speed:10,yawRate:0,kit:[0,0,1,0,0])
        let initial=owner.sample(1);try near(initial.0,0,"first display has no inherited time")
        _=bike.update(model:"authored",maxLean:nil,now:1,presentationDelta:initial.0,sample:packet,previous:nil)
        var now=1.0,elapsed=0.0
        for dt in steps {
            now+=dt;elapsed+=dt
            let row=owner.sample(now)
            try near(row.0,dt,"valid rider interval retained")
            let frame=bike.update(model:"authored",maxLean:nil,now:now,presentationDelta:row.0,sample:packet,previous:nil)
            try circular(frame.crank!,phase(elapsed*1.1),"remote pedal consumes complete interval")
            let pedal=row.1?.mixes.first{$0.clip=="authored/pedal"}
            try check(pedal != nil,"actual local fallback sampled pedal")
            try circular(pedal!.time/2,phase(elapsed*1.1),"fallback pedal consumes complete interval")
        }
    }
    static func pauseAndInvalid()throws {
        for visible in [false,true] {
            let owner=Carrier();_=owner.sample(1)
            try near(owner.sample(1.2,active:visible,visible:!visible).0,0,"inactive/windowless owner holds")
            try near(owner.sample(5).0,0,"foreground primes without debt")
            try near(owner.sample(5.03).0,0.03,"foreground next display resumes")
        }
        for invalid in [Double.nan,Double.infinity,-Double.infinity,0.5,1.6] {
            let owner=Carrier();_=owner.sample(1)
            try near(owner.sample(invalid).0,0,"invalid/backward/suspended interval holds")
            let next=invalid.isFinite ? invalid+0.03:10
            let prime=owner.sample(next).0
            try near(prime,invalid.isFinite ? 0.03:0,"rejected elapsed is not deferred")
            try near(owner.sample(next+0.02).0,0.02,"clean clock after rejection")
        }
        let animator=NativeRiderAnimation(duration:{_ in 2})
        let config=NativeRiderAnimation.Configuration(astride:true,clips:["pedal":"authored/pedal"])
        let input=NativeRiderAnimation.Input(speed:10,pedal:1)
        let rejected=NativeRiderPoseClock.Interval(start:1,end:1.5,rejection:0.5)
        let held=animator.update(interval:rejected,configuration:config,input:input)
        try check(held.mixes.isEmpty,"rejected fallback interval cannot advance blend or phase")
        let frame=animator.update(interval:.init(start:2,end:2.2,rejection:nil),configuration:config,input:input)
        let manual=NativeRiderAnimation(duration:{_ in 2})
        _=manual.update(delta:0.1,configuration:config,input:input)
        let expected=manual.update(delta:0.1,configuration:config,input:input)
        try near(frame.mixes[0].time,expected.mixes[0].time,"fallback preserves bounded direct-delta phases")
        try near(frame.mixes[0].weight,expected.mixes[0].weight,"fallback preserves bounded direct-delta response")
        let fresh=NativeRiderAnimation(duration:{_ in 2})
        let first=fresh.update(interval:.init(start:10,end:10.2,rejection:nil),configuration:config,input:input)
        try check(first.mixes.isEmpty,"new fallback owner cannot consume precreation time")
        let next=fresh.update(interval:.init(start:10.2,end:10.4,rejection:nil),configuration:config,input:input)
        try near(next.mixes[0].time,0.44,"fallback next admitted interval owns full time")
        let duplicate=fresh.update(interval:.init(start:10.2,end:10.4,rejection:nil),configuration:config,input:input)
        try near(duplicate.mixes[0].time,next.mixes[0].time,"duplicate presentation interval cannot replay elapsed")
        try near(duplicate.mixes[0].weight,next.mixes[0].weight,"duplicate interval cannot replay easing")
        let visible=fresh.update(interval:.init(start:20,end:20.1,rejection:nil),configuration:config,input:input)
        try near(visible.mixes[0].time,0.66,"missing draws do not accrue fallback pose debt")
        let bike=NativeRemoteBikeAnimation()
        let packet=NativeRemoteBikeAnimation.Sample(serial:1,time:30.2,speed:10,yawRate:0,kit:[0,0,1,0.2,0])
        let freshBike=bike.update(model:"authored",maxLean:nil,now:30.2,presentationDelta:0.2,sample:packet,previous:nil)
        try near(freshBike.crank!,0.2,"new bike cannot consume precreation time")
        let nextBike=bike.update(model:"authored",maxLean:nil,now:30.4,presentationDelta:0.2,sample:packet,previous:nil)
        try near(nextBike.crank!,0.42,"bike next admitted interval owns full time")
        let duplicateBike=bike.update(model:"authored",maxLean:nil,now:30.4,presentationDelta:0.2,sample:packet,previous:nil)
        try near(duplicateBike.crank!,nextBike.crank!,"duplicate bike presentation cannot replay time")
        let visibleBike=bike.update(model:"authored",maxLean:nil,now:40,presentationDelta:0.1,sample:packet,previous:nil)
        try near(visibleBike.crank!,0.53,"missing bike draws cannot accrue presentation debt")
        for invalid in [Double.nan,Double.infinity,-Double.infinity] {
            let heldBike=bike.update(model:"authored",maxLean:nil,now:invalid,presentationDelta:0,sample:packet,previous:nil)
            try near(heldBike.crank!,visibleBike.crank!,"nonfinite bike clock holds last valid pose")
        }
        let resumed=bike.update(model:"authored",maxLean:nil,now:50,presentationDelta:0.03,sample:packet,previous:nil)
        try near(resumed.crank!,0.53,"bike primes cleanly after invalid time")
        let again=bike.update(model:"authored",maxLean:nil,now:50.03,presentationDelta:0.03,sample:packet,previous:nil)
        try near(again.crank!,0.563,"bike resumes without deferred invalid time")
    }
    static func main(){
        do {
            // Run the hitch first so a historical negative fails at its intended
            // production-clock assertion, rather than at an unrelated boundary.
            try schedule([0.2])
            for rate in [15,30,60,120,144]{try schedule(Array(repeating:1/Double(rate),count:rate*2))}
            for delta in [0.125,0.2,0.35,0.5]{try schedule([delta,0.03,0.04])}
            try schedule([0.2,0.125,0.03,0.1,0.005,0.24,0.3])
            try pauseAndInvalid()
            print("{\"status\":\"PASS\",\"checks\":\(checks),\"scope\":\"authored time/UI/packet/clip-duration boundaries and actual native consumers\"}")
        }catch{
            let message=(error as? Failure)?.message ?? String(describing:error)
            let result:[String:Any]=["status":"FAIL","checks":checks,"failure":message]
            let data=try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]);print(String(decoding:data,as:UTF8.self));exit(1)
        }
    }
}
