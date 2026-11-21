// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficAudioTests {
    typealias S=NativeVehicleAudioSpatial
    static var checks=0
    static func check(_ v:Bool,_ message:String)throws{checks+=1;if !v{throw NSError(domain:message,code:1)}}
    static func car(_ id:UInt16,_ distance:Float,flags:UInt8=0,built:Bool=true,shown:Bool=true)->S.Traffic {
        .init(id:id,model:400,gtaPosition:SIMD3(distance,0,0),heading:0,pitch:0,speed:2,flags:flags,built:built,shown:shown)
    }
    static func main(){do{try run()}catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        let unsorted=[car(30,30),car(40,10),car(50,20),car(60,10),car(70,5),car(80,8),car(99,80,flags:10),car(3,50,flags:2),car(1,60,flags:2)]
        let choices=S.trafficSources(unsorted,listener:.zero)
        try check(choices.map(\.identity)==[.traffic(70),.traffic(80),.traffic(40),.traffic(60),.traffic(99),.traffic(3)],"Near distance/tie budget or far insertion order")
        try check(choices.suffix(2).allSatisfy{$0.siren && !$0.horn && $0.health==1000},"Far allowance changed horn/health contract")
        let edges=S.trafficSources([car(0,0,flags:8),car(1,45,flags:2),car(2,150,flags:2),car(3,44.99),car(4,149.99,flags:2),car(5,2,built:false),car(6,3,shown:false),car(7,.nan)],listener:.zero)
        try check(edges.map(\.identity)==[.traffic(0),.traffic(3),.traffic(1),.traffic(4)],"Strict45/150, build/shown or finite position boundary")
        try check(edges[0].horn && !edges[0].siren,"Near horn bit mapping")
        try check(S.trafficSources(unsorted,listener:SIMD3(.infinity,0,0)).isEmpty,"Invalid listener admitted compact sources")
        try check(S.SourceIdentity.player("traffic:1:1").token != S.SourceIdentity.traffic(1).token,"Human ID collided with compact source")
        let routedAudio=Audio(),routedRenderer=Renderer(),routedNetwork=Network()
        routedRenderer.presentedAmbientTraffic=[.init(identity:.init(id:18,model:400,first:0,second:0),generation:5,
            body:.init(position:SIMD3(4,5,6),heading:0,pitch:0,steering:0,spin:0,wheelPhase:0),
            speed:2,health:0,flags:10,crewCount:0,deadSeats:0,plate:nil)]
        productionHandoff(routedAudio,network:routedNetwork,renderer:routedRenderer)
        try check(routedAudio.remoteEngines["traffic:18"] != nil,"Actual GVC call omitted compact traffic sources")
        try check(routedAudio.positions["remote:traffic:18"]==SIMD3(4,6,-5),"Actual renderer-to-GVC-to-audio position composition")
        try check(routedNetwork.orderedPlayers.isEmpty,"Compact audio created a human player")
        try check(routedAudio.plans["remote:traffic:18"]!.layers.contains{$0.sound=="authored-yelp"},"Actual composed flags did not reach the voice plan")
        let audio=Audio()
        for flags:UInt8 in [0,8,2,10] {
            let sources=S.trafficSources([car(7,10,flags:flags)],listener:.zero)
            audio.updateRemoteVehicles([],traffic:sources,ear:.zero,forward:SIMD3(0,1,0),top:{_ in 45})
            let layers=audio.plans["remote:traffic:7"]!.layers
            try check(layers.contains{$0.name=="idle" || $0.name=="revs"},"Actual consumer omitted compact engine")
            let expected=flags&2 != 0 ? (flags&8 != 0 ? "authored-yelp":"authored-wail"):flags&8 != 0 ? "74_3":nil
            try check(layers.filter{$0.name=="siren" || $0.name=="horn"}.map(\.sound)==(expected.map{[$0]} ?? []),"Actual consumer horn/siren state")
            try check(audio.positions["remote:traffic:7"]==SIMD3(10,0,0),"Compact position bypassed spatial axis boundary")
            AudioClock.processInfo.systemUptime+=0.02
        }
        var human=RemotePlayer(id:"traffic:7",code:"400.1.0");human.position=SIMD3(0,2,3);human.horn=1
        audio.updateRemoteVehicles([human],traffic:S.trafficSources([car(7,10)],listener:.zero),ear:.zero,forward:SIMD3(0,1,0),top:{_ in nil})
        try check(Set(audio.remoteEngines.keys)==["player:traffic:7","traffic:7"],"Typed traffic replaced an unrelated human vehicle")
        try check(audio.positions["remote:player:traffic:7"]==SIMD3(0,3,-2),"Human vehicle coordinate mapping changed")
        let existing=audio.remoteEngines["traffic:7"]!
        audio.updateRemoteVehicles([],traffic:S.trafficSources([car(7,10)],listener:.zero),ear:.zero,forward:SIMD3(0,1,0),top:{_ in nil})
        try check(audio.remoteEngines["traffic:7"]===existing,"Unchanged compact model restarted its voice state")
        try check(audio.vehicleLoops.cleared.contains("remote:player:traffic:7"),"Removed human source retained voices")
        audio.road["401"]=[10,20,1,0,3,1]
        let replacement=S.Source(identity:.traffic(7),model:401,gtaPosition:SIMD3(10,0,0),heading:0,pitch:0,roll:0,speed:2,health:1000,horn:false,siren:false)
        audio.updateRemoteVehicles([],traffic:[replacement],ear:.zero,forward:SIMD3(0,1,0),top:{_ in nil})
        try check(audio.remoteEngines["traffic:7"] !== existing && audio.remoteEngines["traffic:7"]?.model==401,"Actual compact model replacement retained its previous sound state")
        let before=audio.vehicleLoops.listenerCalls;audio.suspended=true
        audio.updateRemoteVehicles([],ear:.zero,forward:SIMD3(0,1,0),top:{_ in nil})
        try check(audio.vehicleLoops.listenerCalls==before,"Suspended consumer advanced listener")
        audio.suspended=false;audio.updateRemoteVehicles([],ear:.zero,forward:SIMD3(0,1,0),top:{_ in nil})
        try check(audio.remoteEngines.isEmpty && audio.vehicleLoops.cleared.contains("remote:traffic:7"),"Streamout retained compact voices")
        let selected=S.select(choices.map{S.Candidate(id:$0.id,model:$0.model,position:SIMD3<Double>($0.gtaPosition),speed:$0.speed)},listener:.zero,catalogue:.init(road:[400]))
        try check(selected.count==5 && !selected.contains{$0.candidate.id=="traffic:99"},"Common nearest-five policy bypassed")
        let distant=S.trafficSources([car(20,110,flags:2)],listener:.zero)
        let filtered=S.select(distant.map{S.Candidate(id:$0.id,model:$0.model,position:SIMD3<Double>($0.gtaPosition),speed:$0.speed)},listener:.zero,catalogue:.init(road:[400]))
        try check(!distant.isEmpty && filtered.isEmpty,"Heard candidate was incorrectly guaranteed a road voice")
        print("PASS typed traffic audio: \(checks) checks; actual spatial/dynamics/consumer with authored tables and inert sink; no playback or app acceptance")
    }
}
