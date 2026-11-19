// SPDX-License-Identifier: AGPL-3.0-only
// Authored wire inputs, actual Client/adapter methods and class-admission code.
// The recording transport/UI/resource boundaries below are NOT a live join,
// actual UIKit presentation, model upload or proof of rendered appearance.
import Foundation
import CoreGraphics
import simd
import Darwin

enum RecordedTransport {
    static var next:UInt64=0,handles=Set<UInt64>(),sent=[Data]()
    static var rpcIDs:[UInt8]{sent.compactMap{(try?NativeSAMPProtocol.rpc($0))?.id}}
}
func zgtasa_samp_abi_version()->UInt32{1}
func zgtasa_samp_open(_ address:UnsafePointer<CChar>,_ size:UInt32,_ pass:UnsafePointer<UInt8>?,_ passSize:UInt32,_ timeout:UInt32)->UInt64{
    RecordedTransport.next+=1;RecordedTransport.handles.insert(RecordedTransport.next);return RecordedTransport.next
}
func zgtasa_samp_close(_ handle:UInt64){RecordedTransport.handles.remove(handle)}
func zgtasa_samp_send(_ handle:UInt64,_ data:UnsafePointer<UInt8>?,_ size:UInt32,_ reliability:UInt32,_ channel:UInt32)->Int32{
    guard RecordedTransport.handles.contains(handle),let data else{return -1}
    RecordedTransport.sent.append(Data(bytes:data,count:Int(size)));return 0
}
func zgtasa_samp_poll(_ handle:UInt64,_ data:UnsafeMutablePointer<UInt8>?,_ size:UInt32,_ needed:UnsafeMutablePointer<UInt32>)->Int32{
    preconditionFailure("No transport polling or sockets in this state-machine fixture")
}
protocol NativeResourceTask:AnyObject{func resume();func cancel()}
struct ServerAddress{func path(_ value:String)->URL{preconditionFailure("No asset-origin HTTP in this fixture")}}
enum NativeResourceTransport{
    static func dataTask(with url:URL,completionHandler:@escaping(Data?,URLResponse?,Error?)->Void)->NativeResourceTask{
        preconditionFailure("No HTTP request may be treated as successful")
    }
}
// ACTUAL_WIRE_TYPES
// ACTUAL_LEGACY_PROTOCOL

enum AlertStyle{case actionSheet}
enum ActionStyle{case `default`,cancel}
final class UIAlertAction{
    let title:String?;var isEnabled=true;let handler:((UIAlertAction)->Void)?
    init(title:String?,style:ActionStyle,handler:((UIAlertAction)->Void)?=nil){self.title=title;self.handler=handler}
}
class Controller{
    var title:String?,onDismiss:(()->Void)?
    var deferDismiss=false,completions=[()->Void]()
    func dismiss(animated:Bool,completion:(()->Void)?=nil){
        if deferDismiss{completions.append{[weak self]in self?.onDismiss?();completion?()}}
        else{onDismiss?();completion?()}
    }
    func finishDismiss(){let saved=completions;completions=[];for action in saved{action()}}
}
final class Popover{var sourceView:View?;var sourceRect=CGRect.zero}
final class UIAlertController:Controller{
    var message:String?,actions=[UIAlertAction]();let popoverPresentationController:Popover?=Popover()
    init(title:String?,message:String?,preferredStyle:AlertStyle){super.init();self.title=title;self.message=message}
    func addAction(_ value:UIAlertAction){actions.append(value)}
}
final class View{var window:Bool?=true;let bounds=CGRect(x:0,y:0,width:960,height:540)}
enum NativeSAMPArtworkSession{enum Phase{case idle,ready,downloading};struct Status{var phase:Phase}}
final class Artwork{var status=NativeSAMPArtworkSession.Status(phase:.idle)}
final class Label{var text:String?}
final class AdmissionRenderer{
    let selection=NativeActorSelection()
    var actorSelectionState:NativeActorSelection.State?{selection.state}
    var ready=Set([0,7,287,20001,20003]),skin=7,requests=[Int](),spawns=0,cancels=0
    var position=SIMD3<Float>(10,20,30),heading:Float=0
    func setLegacySkin(_ skin:Int){
        requests.append(skin);let request=selection.begin(domain:.legacy,skin:skin,sourceIdentity:"authored-source")
        if ready.contains(skin){self.skin=skin;_=selection.applied(request,nativeSkin:skin,sourceIdentity:"authored-source")}
    }
    func complete(_ skin:Int){guard let request=selection.state?.request,request.skin==skin else{return};ready.insert(skin);self.skin=skin;_=selection.applied(request,nativeSkin:skin,sourceIdentity:"authored-source")}
    func cancelActorSelection(){cancels+=1;selection.cancel()}
    func legacySpawned(generation:UInt64?){spawns+=1}
}
final class WeaponBoundary{
    var weapons=[24:50],resets=0,readies=0,gives=0
    func resetClientWeapons(){resets+=1;weapons=[:]}
    func setClientWeaponReady(_ ready:Bool){readies+=1}
    func giveClientWeapon(_ id:Int,amount:Int)->Bool{weapons[id]=amount;gives+=1;return true}
    func setClientAmmo(_ id:Int,amount:Int)->Bool{weapons[id]=amount;return true}
    func selectOriginalWeapon(_ id:Int)->Bool{true}
}
final class NetworkBoundary{
    let legacy:NativeSAMPWorldConnection?
    var sampGameplayGeneration:UInt64?{legacy?.client.gameplayGeneration}
    init(_ legacy:NativeSAMPWorldConnection){self.legacy=legacy}
}
class ClassOwner{
    let view=View(),status=Label(),weapons=WeaponBoundary(),network:NetworkBoundary
    var renderer:AdmissionRenderer?=AdmissionRenderer(),legacyArtwork:Artwork?,legacyClassSkin:Int?
    var legacyClassPresentation:UUID?
    var presentedViewController:Controller?,resets=0,presents=0,teleports=0,hudUpdates=0
    init(_ adapter:NativeSAMPWorldConnection){network=NetworkBoundary(adapter);renderer!.selection.onChange={[weak self]in self?.actorSelectionChanged($0)}}
    func resetControls(){resets+=1}
    func present(_ panel:Controller,animated:Bool){
        presents+=1;presentedViewController=panel
        panel.onDismiss={[weak self,weak panel]in if self?.presentedViewController === panel{self?.presentedViewController=nil}}
    }
    func dismiss(animated:Bool){presentedViewController=nil}
    func updateWeaponHUD(){hudUpdates+=1}
    func receive(_ event:[String:Any]){
        switch event["t"]as?String{
        // ACTUAL_CLASS_EVENT_CASES
        default:break
        }
    }
    // ACTUAL_CLASS_METHODS
}
// HISTORICAL_PRESENTATION_OWNER

@main enum SpawnInfoSmoke{
    struct Failure:Error{let message:String}
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw Failure(message:message)}}
    static func rpc(_ client:NativeSAMPClient,_ id:UInt8,_ fill:(inout NativeSAMPProtocol.Writer)->Void)throws{
        var w=NativeSAMPProtocol.Writer();fill(&w);try client.receive(NativeSAMPProtocol.rpc(id,w))
    }
    static func spawn(_ version:NativeSAMPProtocol.Version,skin:Int=287,custom:Int=0,point:SIMD3<Float>=SIMD3(100,200,30),angle:Float=90,weapon:Int=24)->NativeSAMPProtocol.Writer{
        var w=NativeSAMPProtocol.Writer();w.integer(255,size:1);w.integer(UInt32(skin),size:4)
        if version == .dl{w.integer(UInt32(bitPattern:Int32(custom)),size:4)}
        w.integer(0,size:1);w.vector(point);w.float(angle)
        for id in [weapon,0,0]{w.integer(UInt32(id),size:4)}
        for ammo in [50,0,0]{w.integer(UInt32(ammo),size:4)}
        return w
    }
    static func initialize(_ client:NativeSAMPClient)throws{
        client.connect(automaticPolling:false)
        var accept=Data(repeating:0,count:13);accept[0]=34;try client.receive(accept)
        try rpc(client,139){w in
            for _ in 0..<4{w.bit(false)};w.float(0);w.bit(false);w.float(0)
            for _ in 0..<3{w.bit(false)};w.integer(2,size:4);w.integer(7,size:2);w.bit(false);w.integer(0,size:4)
            w.integer(12,size:1);w.integer(10,size:1);w.float(0.008)
        }
        try check(client.state == .selecting,"Actual InitGame/requestClass did not select")
    }
    static func classReply(_ client:NativeSAMPClient,_ row:NativeSAMPProtocol.Writer)throws{
        try rpc(client,128){w in w.integer(1,size:1);w.bytes(row.data)}
    }
    static func exercise(_ version:NativeSAMPProtocol.Version)throws{
        RecordedTransport.sent=[]
        let client=NativeSAMPClient(address:"127.0.0.1:1",nickname:"Authored_QA",version:version,installationID:"A")
        let adapter=NativeSAMPWorldConnection(client:client),ui=ClassOwner(adapter)
        var events=[[String:Any]](),positions=[SIMD3<Float>](),states=[NativeConnectionRecovery.State]()
        adapter.onState={states.append($0)}
        adapter.onEvent={message in
            events.append(message)
            // Actual NMP placement forwarding is isolated below; all other
            // adapter events reach the actual selected GVC case statements.
            if let point=message["point"]as?SIMD3<Float>,message["t"]as?String=="position"{
                positions.append(point);ui.renderer!.position=point;ui.renderer!.heading=message["heading"]as?Float ?? ui.renderer!.heading;ui.teleports+=1
            }
            ui.receive(message)
        }
        try initialize(client)
        try check(client.gravity==0.008,"InitGame gravity was not retained")
        try rpc(client,146){$0.float(0.004)}
        let first=spawn(version,skin:7,point:SIMD3(100,200,30),angle:45)
        try classReply(client,first)
        try check(events.filter{$0["t"]as?String=="class"}.count==1,"RPC128 did not retain selection callback")
        try check(events.last?["point"]as?SIMD3<Float>==SIMD3(100,200,29),"Class root conversion changed")
        try check(abs((events.last?["heading"]as?Float ?? 9)+Float.pi/4)<0.00001,"Class heading changed")
        try check(ui.renderer!.position==SIMD3(10,20,30),"Class response overwrote explicit preview position")
        try check(ui.presents==1 && ui.legacyClassSkin==7,"Normal class UI did not open once")
        client.requestSpawn();try check(client.state == .spawning,"Actual requestSpawn guard failed")
        try rpc(client,129){$0.integer(1,size:4)}
        try check(client.state == .spawned && ui.legacyClassSkin==nil,"Normal authorized spawn failed")
        try check(positions.last==SIMD3(100,200,29),"Actual spawn placement lost one root conversion")
        ui.presentedViewController?.dismiss(animated:false)

        // A legitimate next-spawn update while alive must have no live-world
        // effects. Freeze, vitals and inventory are intentionally nondefault.
        try rpc(client,15){$0.integer(0,size:1)}
        var foot=NativeSAMPProtocol.Foot(position:SIMD3(100,200,30),heading:0)
        foot.health=67;foot.armour=22;foot.weapon=24;foot.keys=8
        try check(client.sendFoot(foot),"Fixture recording transport rejected actual foot packet")
        let before=(classes:events.filter{$0["t"]as?String=="class"}.count,presents:ui.presents,resets:ui.resets,skin:ui.renderer!.skin,requests:ui.renderer!.requests.count,
                    weapons:ui.weapons.weapons,gives:ui.weapons.gives,teleports:ui.teleports,sends:RecordedTransport.sent.count,states:states.count,spawns:ui.renderer!.spawns)
        let nextPoint=SIMD3<Float>(-2100,1850,1001),next=spawn(version,skin:287,custom:20003,point:nextPoint,angle:270,weapon:31)
        try client.receive(NativeSAMPProtocol.rpc(68,next))
        try check(events.filter{$0["t"]as?String=="class"}.count==before.classes,"RPC68 reopened class selection while live")
        try check(client.state == .spawned && states.count==before.states,"RPC68 changed live connection state")
        try check(ui.legacyClassSkin==nil && ui.presents==before.presents && ui.resets==before.resets,"RPC68 changed live UI or input")
        try check(ui.renderer!.skin==before.skin && ui.renderer!.requests.count==before.requests,"RPC68 replaced live actor intent")
        try check(ui.teleports==before.teleports && ui.renderer!.position==SIMD3(100,200,29),"RPC68 teleported the live actor")
        try check(ui.weapons.weapons==before.weapons && ui.weapons.gives==before.gives,"RPC68 applied future spawn weapons early")
        try check(client.health==67 && client.armour==22 && !client.controllable,"RPC68 reset live vitals or frozen controls")
        try check(RecordedTransport.sent.count==before.sends && ui.renderer!.spawns==before.spawns,"RPC68 sent spawn acknowledgement")
        try check(events.last?["selection"]as?Bool==false && events.last?["point"]==nil,"Future metadata exposed live placement")
        try rpc(client,129){$0.integer(1,size:4)}
        try check(ui.renderer!.spawns==before.spawns,"Unrequested Allow1 spawned live actor")
        try rpc(client,129){$0.integer(2,size:4)}
        let effective=version == .dl ? 20003:287
        try check(ui.renderer!.skin==effective && positions.last==nextPoint-SIMD3(0,0,1),"Forced spawn failed to use updated cached info")
        try check(ui.weapons.weapons[31]==50 && ui.renderer!.spawns==before.spawns+1,"Forced spawn lost future weapons or duplicated")
        try check(client.health==100 && client.armour==0 && client.controllable,"Authorized spawn did not reset spawn state")

        try check(client.gravity==0.004,"Class/normal/forced spawn reset per-player gravity")
        // A spectator-off authorized spawn also consumes the most recent data.
        let spectatePoint=SIMD3<Float>(400,500,40)
        try client.receive(NativeSAMPProtocol.rpc(68,spawn(version,skin:7,point:spectatePoint,angle:180,weapon:22)))
        try rpc(client,124){$0.integer(1,size:4)}
        let count=ui.renderer!.spawns
        try rpc(client,124){$0.integer(0,size:4)}
        try check(!client.spectating && client.state == .spawned && ui.renderer!.spawns==count+1,"Spectator-off did not complete one cached spawn")
        try check(positions.last==spectatePoint-SIMD3(0,0,1) && ui.renderer!.skin==7,"Spectator-off used stale spawn transform/skin")

        try check(client.gravity==0.004,"Spectator-off spawn reset per-player gravity")
        // Initial metadata alone cannot authorize/open a selection screen.
        client.disconnect();try initialize(client);let oldPresents=ui.presents
        try client.receive(NativeSAMPProtocol.rpc(68,spawn(version,skin:287)))
        try check(ui.presents==oldPresents && ui.legacyClassSkin==nil,"RPC68 before128 invented a class screen")
        try classReply(client,spawn(version,skin:7));let panel=ui.presentedViewController as!UIAlertController
        let action=panel.actions.first{$0.title=="SPAWN"}!,originalPresents=ui.presents,originalResets=ui.resets
        ui.renderer!.ready.remove(287)
        try client.receive(NativeSAMPProtocol.rpc(68,spawn(version,skin:287)))
        try check(ui.presentedViewController === panel && ui.presents==originalPresents && ui.resets==originalResets,"Selection metadata reopened UI/reset input")
        try check(ui.legacyClassSkin==287 && !action.isEnabled && panel.message!.contains("LOADING"),"Selection override bypassed new actor readiness")
        ui.renderer!.complete(287)
        try check(action.isEnabled && panel.message=="Skin 287","Current resource completion did not restore spawn admission")
        panel.dismiss(animated:false);action.handler?(action)
        try check(client.state == .spawning,"Existing SPAWN action retained the old skin capture")
        // Metadata arriving after request129 must not clear its pending guard.
        try client.receive(NativeSAMPProtocol.rpc(68,spawn(version,skin:7,point:SIMD3(600,700,50),angle:90,weapon:28)))
        try check(client.state == .spawning && ui.presents==originalPresents,"Pending spawn metadata changed handshake phase")
        let spawnCount=ui.renderer!.spawns
        try rpc(client,129){$0.integer(1,size:4)}
        try check(client.state == .spawned && ui.renderer!.spawns==spawnCount+1 && ui.renderer!.skin==7,"RPC68 deadlocked or used old pending spawn skin")
        try check(positions.last==SIMD3(600,700,49) && ui.weapons.weapons[28]==50,"Pending spawn used stale position/weapons")

        // Rejection and reconnect remain guarded; malformed data is atomic.
        try check(client.reportDeath(),"Actual death report failed")
        client.requestRespawn();try classReply(client,spawn(version,skin:7));client.requestSpawn()
        try rpc(client,129){$0.integer(0,size:4)}
        try check(client.state == .selecting,"Declined spawn did not reopen retry guard")
        try client.receive(NativeSAMPProtocol.rpc(68,spawn(version,skin:287)));client.requestSpawn()
        try check(client.state == .spawning,"Updated spawn data blocked retry after denial")
        try rpc(client,129){$0.integer(1,size:4)};try check(ui.renderer!.skin==287,"Retry spawned stale rejected skin")
        let saved=(ui.presents,ui.resets,ui.renderer!.requests.count,RecordedTransport.sent.count)
        let invalid=Data(spawn(version,skin:7).data.prefix(5))
        do{var w=NativeSAMPProtocol.Writer();w.bytes(invalid);try client.receive(NativeSAMPProtocol.rpc(68,w));throw Failure(message:"Truncated spawn data accepted")}
        catch NativeSAMPProtocol.Error.truncated{}
        try check(ui.presents==saved.0 && ui.resets==saved.1 && ui.renderer!.requests.count==saved.2 && RecordedTransport.sent.count==saved.3,"Malformed spawn data mutated visible/transport state")
        client.disconnect();let previous=ui.renderer!.spawns;try initialize(client)
        try rpc(client,129){$0.integer(2,size:4)}
        try check(ui.renderer!.spawns==previous,"Reconnect reused stale spawn data")
        // An accepted class owns one pending presentation. A metadata update
        // may change its skin while another modal is still dismissing.
        let modal=Controller();modal.title="OTHER";modal.deferDismiss=true
        ui.present(modal,animated:false);let presented=ui.presents
        try classReply(client,spawn(version,skin:7))
        try client.receive(NativeSAMPProtocol.rpc(68,spawn(version,skin:287)))
        try check(ui.presentedViewController === modal && ui.legacyClassSkin==287,"Pending selection lost metadata ownership")
        modal.finishDismiss()
        try check(ui.presents==presented+1 && (ui.presentedViewController as?UIAlertController)?.message=="Skin 287","Spawn-info override made pending selection vanish")
        ui.presentedViewController?.dismiss(animated:false)
        let second=Controller();second.deferDismiss=true;ui.present(second,animated:false)
        try classReply(client,spawn(version,skin:7));let obsolete=ui.legacyClassPresentation
        try classReply(client,spawn(version,skin:287));let latest=ui.legacyClassPresentation
        try check(obsolete != latest,"Distinct admitted classes share presentation owner")
        let beforePresentation=ui.presents;second.finishDismiss()
        try check(ui.presents==beforePresentation+1 && (ui.presentedViewController as?UIAlertController)?.message=="Skin 287","Old dismissal published stale/duplicate selection")
        ui.presentedViewController?.dismiss(animated:false)
        let cancelled=Controller();cancelled.deferDismiss=true;ui.present(cancelled,animated:false)
        try classReply(client,spawn(version,skin:7));ui.legacyClassSkin=nil
        let beforeCancel=ui.presents;cancelled.finishDismiss()
        try check(ui.presents==beforeCancel && ui.presentedViewController==nil,"Cancelled selection returned from stale dismissal")
        // HISTORICAL_PRESENTATION_CHECK
        client.disconnect()
    }
    static func main(){do{
        try exercise(.v037);try exercise(.dl)
        print(String(data:try JSONSerialization.data(withJSONObject:["status":"PASS","checks":checks,"profiles":2,"actualClientAdapter":true,"actualSelectedGVCMethods":true,"transportAndUIBoundaries":true,"renderedOrLiveAcceptance":false],options:[.sortedKeys]),encoding:.utf8)!)
    }catch{print(String(data:try!JSONSerialization.data(withJSONObject:["status":"FAIL","checks":checks,"failure":(error as?Failure)?.message ?? String(describing:error)],options:[.sortedKeys]),encoding:.utf8)!);exit(1)}}
}
