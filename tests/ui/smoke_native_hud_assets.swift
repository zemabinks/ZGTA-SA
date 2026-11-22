// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

// Authored transport records/clock and explicit decoder decision. Execute the
// complete production owner; no UIKit, image data, sockets or retail.
private final class DeferredTask:NativeResourceTask {
    let url:URL,maximum:Int,completion:NativeResourceTransport.Completion
    var resumes=0,cancelled=false,onCancel:(()->Void)?
    init(_ url:URL,_ maximum:Int,_ completion:@escaping NativeResourceTransport.Completion){self.url=url;self.maximum=maximum;self.completion=completion}
    func resume(){resumes+=1}
    func cancel(){cancelled=true;onCancel?()}
    func finish(_ marker:String?,status:Int=200,error:Error?=nil){
        completion(marker.map{Data($0.utf8)},HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:nil),error)
    }
}
private final class Scene {
    typealias Owner=NativeHUDAssetOwner<String>
    var now=0.0,current="A",tasks:[DeferredTask]=[],outputs:[String]=[]
    lazy var owner:Owner=Owner(clock:{[weak self]in self?.now ?? .nan},factory:{[weak self]url,maximum,completion in
        let task=DeferredTask(url,maximum,completion);self?.tasks.append(task);return task
    })
    @discardableResult func load(_ key:String,names:[String]=["map"],maximum:Int=100,
                                valid:(([String:Data])->Bool)?=nil,publish:(()->Void)?=nil)->Bool {
        current=key
        return owner.load(key:key,requests:Dictionary(uniqueKeysWithValues:names.map{($0,Owner.Request(url:URL(string:"http://authored.invalid/"+key+"/"+$0)!,maximumBytes:maximum))}),
            isCurrent:{[weak self]in self?.current==key},publish:{[weak self]files in
                self?.outputs.append(files["map"].flatMap{String(data:$0,encoding:.utf8)} ?? "missing")
                publish?();return valid?(files) ?? (files.count==names.count)
            })
    }
}
@main enum Tests {
    static var checks=0
    static func check(_ value:Bool,_ text:String){checks+=1;if !value{FileHandle.standardError.write(Data(("FAIL: "+text+"\n").utf8));exit(1)}}
    static func drain(){RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
    static func main(){
        do {
            let s=Scene();check(s.load("A"),"First request rejected");let old=s.tasks[0]
            check(!s.load("A")&&s.tasks.count==1,"Repeated pending poll created another request")
            check(s.load("B")&&old.cancelled,"New join did not retire its predecessor")
            s.tasks[1].finish("new");drain();old.finish("old");drain()
            check(s.outputs==["new"],"Late cancelled response replaced the newer join")
            check(!s.load("B")&&s.tasks.count==2,"Ready image is fetched on every HUD tick")
        }
        do {
            let s=Scene();s.load("A");let old=s.tasks[0];s.load("B");let middle=s.tasks[1];s.load("A")
            s.tasks[2].finish("new-A");drain();old.finish("old-A");middle.finish("B");drain()
            check(s.outputs==["new-A"],"A/B/A reuse admitted the first A epoch")
            check(old.cancelled&&middle.cancelled,"Superseded batch tasks retained work")
        }
        do {
            let s=Scene();s.load("A");s.tasks[0].finish(nil,status:503);drain()
            check(s.outputs==["missing"],"Failed batch invented an image")
            for _ in 0..<20{check(!s.load("A"),"Failure caused immediate request storm")}
            s.now=2.1;check(s.load("A"),"Transient same-server failure permanently blocks recovery")
            s.tasks[1].finish("recovered");drain();check(s.outputs.last=="recovered","Retry never published")
            s.now=100;check(!s.load("A")&&s.tasks.count==2,"Recovered ready batch failed to retain cache")
        }
        do {
            let s=Scene();s.load("A",maximum:3);s.tasks[0].finish("oversized");drain()
            check(s.outputs==["missing"],"Owner accepted oversized transport data")
            s.now=3;s.load("A",maximum:3);s.tasks[1].finish("yes",status:404);drain()
            check(s.outputs.last=="missing","Non-success response became image data")
            s.now=40;check(s.load("A",maximum:3),"Repeated failures exceeded bounded retry delay")
            s.tasks[2].finish("yes");drain();check(s.outputs.last=="yes","Valid bounded retry failed")
        }
        do {
            let s=Scene();s.load("A");s.current="B";s.tasks[0].finish("wrong-source");drain()
            check(s.outputs.isEmpty,"Changed resource binding published before the next poll")
            check(s.load("B"),"Changed binding did not get its own request")
            s.tasks[1].finish("B");drain();check(s.outputs==["B"],"Current resource source did not publish")
        }
        do {
            let s=Scene();s.load("A",publish:{_ = s.load("B")});s.tasks[0].finish("A");drain()
            check(s.tasks.count==2&&s.owner.key=="B","Publish reentry did not start the next source")
            s.tasks[1].finish("B");drain();check(s.outputs==["A","B"],"Old delivery completion cleared the reentrant source")
            check(!s.load("B"),"Reentrant current source never became ready")
        }
        do {
            let s=Scene();s.load("A");let old=s.tasks[0];old.onCancel={old.finish("cancel-callback")}
            s.owner.cancel();drain();check(s.outputs.isEmpty&&s.owner.key==nil,"Synchronous cancellation callback published retired data")
            check(s.load("A"),"Explicit cancellation poisoned next load");s.tasks[1].finish("again");drain()
            s.tasks[1].finish("duplicate");drain();check(s.outputs==["again"],"Duplicate completion published twice")
            old.onCancel=nil
        }
        do {
            let s=Scene();check(s.load("A",maximum:0),"Invalid bound did not settle the attempted load")
            check(s.tasks.isEmpty&&s.outputs.isEmpty,"Invalid bound reached transport/publisher")
            s.now=3;check(s.load("A"),"Invalid bound permanently blocked a later valid request")
            s.tasks[0].finish("valid");drain();check(s.outputs==["valid"],"Valid request after bound error failed")
        }
        do {
            let s=Scene();s.load("A",names:["map","metadata"])
            s.tasks[0].finish("map");drain();check(s.outputs.isEmpty,"Incomplete batch published before its remaining response")
            s.tasks[1].finish(nil,status:503);drain();check(s.outputs.count==1,"Settled partial batch did not publish exactly once")
            s.now=3;check(s.load("A",names:["map","metadata"]),"Partial batch incorrectly became ready")
            s.tasks[2].finish("map");s.tasks[3].finish("metadata");drain();check(!s.load("A",names:["map","metadata"]),"Complete decoded batch kept retrying")
        }
        do {
            let s=Scene();s.now = .nan;check(!s.load("A")&&s.tasks.isEmpty,"Invalid clock began transport work")
            s.now=0;s.load("A");s.now = .nan;s.tasks[0].finish(nil,status:503);drain()
            s.now=5;check(s.load("A"),"Invalid completion clock poisoned later recovery")
            s.tasks[1].finish("clock-restored");drain();check(s.outputs.last=="clock-restored","Restored clock request never became ready")
        }
        do {
            let s=Scene();s.load("A",valid:{_ in false});s.tasks[0].finish("undecodable");drain()
            check(s.outputs==["undecodable"],"Decoder did not receive a successful bounded response")
            s.now=2.1;check(s.load("A"),"A rejected decode permanently became ready")
            s.tasks[1].finish("decoded");drain();check(!s.load("A"),"Accepted decoded retry never became ready")
        }
        do {
            let s=Scene();var deadline=0.0
            for (index,delay) in [2.0,4.0,8.0,16.0,30.0,30.0,30.0].enumerated() {
                check(s.load("A"),"A due retry was suppressed")
                s.tasks[index].finish(nil,status:503);drain()
                deadline=s.now+delay;s.now=deadline-0.001
                check(!s.load("A"),"Retry ran before its bounded backoff deadline")
                s.now=deadline
            }
            s.current="B";check(s.load("B"),"A new source inherited the previous source's backoff")
            s.tasks.last!.finish(nil,status:503);drain();s.now+=2.001
            check(s.load("B"),"New source did not restart with the initial retry interval")
            s.tasks.last!.finish("B");drain()
        }
        do {
            let address=ServerAddress("http://127.0.0.1:18942")!
            let first=NativeHUDResourceIdentity.current(server:address)
            check(first==NativeHUDResourceIdentity.current(server:address),"An unchanged source identity is unstable")
            let binding=first.binding
            let variants:[NativeResourceStore.RuntimeBinding]=[
                .init(generation:UUID(),mode:binding.mode,contentID:binding.contentID,developmentOrigin:binding.developmentOrigin,playable:binding.playable),
                .init(generation:binding.generation,mode:.installed,contentID:binding.contentID,developmentOrigin:binding.developmentOrigin,playable:binding.playable),
                .init(generation:binding.generation,mode:binding.mode,contentID:"other-content",developmentOrigin:binding.developmentOrigin,playable:binding.playable),
                .init(generation:binding.generation,mode:binding.mode,contentID:binding.contentID,developmentOrigin:"http://other.invalid",playable:binding.playable),
                .init(generation:binding.generation,mode:binding.mode,contentID:binding.contentID,developmentOrigin:binding.developmentOrigin,playable:!binding.playable)
            ]
            for variant in variants {
                NativeResourceStore.shared.runtimeBinding=variant
                check(first != NativeHUDResourceIdentity.current(server:address),"A resource admission dimension is missing from the HUD identity")
            }
            NativeResourceStore.shared.runtimeBinding=binding
            check(first != NativeHUDResourceIdentity.current(server:ServerAddress("http://127.0.0.1:18943")!),"Different servers share a HUD identity")
            var tasks:[DeferredTask]=[],published=0
            let owner=NativeHUDAssetOwner<NativeHUDResourceIdentity>(clock:{0},factory:{url,maximum,completion in
                let task=DeferredTask(url,maximum,completion);tasks.append(task);return task
            })
            let request=["map":NativeHUDAssetOwner<NativeHUDResourceIdentity>.Request(url:address.path("tools/map/radar.webp"),maximumBytes:100)]
            owner.load(key:first,requests:request,isCurrent:{NativeHUDResourceIdentity.current(server:address)==first}){_ in published+=1;return true}
            NativeResourceStore.shared.runtimeBinding=variants[0]
            tasks[0].finish("stale-before-poll");drain()
            check(published==0,"Changed admission published its stale asset before the next HUD tick")
            let next=NativeHUDResourceIdentity.current(server:address)
            check(owner.load(key:next,requests:request,isCurrent:{NativeHUDResourceIdentity.current(server:address)==next}){_ in published+=1;return true},"A same-server repair did not start a new request epoch")
            tasks[1].finish("fresh");drain();check(published==1,"Repaired admission did not publish exactly once")
        }
        print("PASS HUD asset owner: \(checks) authored lifetime/bounds/retry/reentry checks; no UIKit, real image, network, App or retail comparison")
    }
}
