// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
let checkLock=NSLock()
func check(_ value:Bool,_ label:String){checkLock.lock();checks+=1;checkLock.unlock();if !value{fputs("FAIL \(label)\n",stderr);exit(1)}}
func wait(_ label:String,_ condition:()->Bool){let end=Date().addingTimeInterval(8);while !condition(){if Date()>end{fputs("TIMEOUT \(label)\n",stderr);exit(1)};Thread.sleep(forTimeInterval:0.002)}}
final class Sink {
    private let lock=NSLock();private var values:[Result<NativePedAtlasLoader.Payload,Error>]=[]
    var count:Int{lock.lock();defer{lock.unlock()};return values.count}
    func add(_ result:Result<NativePedAtlasLoader.Payload,Error>){lock.lock();values.append(result);lock.unlock()}
    func at(_ i:Int)->Result<NativePedAtlasLoader.Payload,Error>{lock.lock();defer{lock.unlock()};return values[i]}
    func payload(_ i:Int=0)->NativePedAtlasLoader.Payload{if case .success(let p)=at(i){return p};fputs("FAIL expected payload\n",stderr);exit(1)}
}
final class Peer {
    final class Task:NativeResourceTask {
        let url:URL,maximum:Int,completion:NativeResourceTransport.Completion
        private let lock=NSLock();private var started=false,done=false,stopped=false
        private(set) var cancels=0
        init(_ url:URL,_ maximum:Int,_ completion:@escaping NativeResourceTransport.Completion){self.url=url;self.maximum=maximum;self.completion=completion}
        func resume(){lock.lock();started=true;lock.unlock()}
        func cancel(){lock.lock();cancels+=1;stopped=true;let deliver = !done;done=true;lock.unlock();if deliver{completion(nil,nil,URLError(.cancelled))}}
        var pending:Bool{lock.lock();defer{lock.unlock()};return started && !done}
        var cancelled:Bool{lock.lock();defer{lock.unlock()};return stopped}
        func reply(_ data:Data?,late:Bool=false){
            lock.lock();guard late || !done else{lock.unlock();return};done=true;lock.unlock()
            let response=HTTPURLResponse(url:url,statusCode:data == nil ? 404:200,httpVersion:"HTTP/1.1",headerFields:nil)!
            completion(data,response,nil)
        }
    }
    let root:URL
    private let lock=NSLock();private var tasks:[Task]=[]
    var inline=false,corrupt:String?
    init(_ root:URL){self.root=root}
    func make(_ url:URL,_ maximum:Int,_ completion:@escaping NativeResourceTransport.Completion)->NativeResourceTask{
        let task=Task(url,maximum,completion);lock.lock();tasks.append(task);lock.unlock()
        if inline{reply(task)};return task
    }
    var all:[Task]{lock.lock();defer{lock.unlock()};return tasks}
    var pending:[Task]{all.filter(\.pending)}
    func data(_ task:Task)->Data? {
        var data=try? Data(contentsOf:root.appendingPathComponent(String(task.url.path.dropFirst())))
        if task.url.path==corrupt, data?.isEmpty==false{data![0] ^= 1};return data
    }
    func reply(_ task:Task,late:Bool=false){task.reply(data(task),late:late)}
    func drain(){for task in pending{reply(task)}}
}
func snapshot(_ loader:NativePedAtlasLoader)->NativePedAtlasLoader.Snapshot {
    let semaphore=DispatchSemaphore(value:0);var result:NativePedAtlasLoader.Snapshot?
    loader.snapshot{result=$0;semaphore.signal()};check(semaphore.wait(timeout:.now()+5) == .success,"snapshot callback")
    return result!
}
func finish(_ peer:Peer,_ sink:Sink,_ count:Int=1){wait("resource completion"){peer.drain();return sink.count>=count}}
func idle(_ loader:NativePedAtlasLoader){wait("all reservations released"){let s=snapshot(loader);return s.requests==0 && s.transfers==0 && s.encodedBytes==0}}
let root=URL(fileURLWithPath:CommandLine.arguments[1]),server=ServerAddress("http://127.0.0.1:1")!
let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("fixtures.json"))) as! [[String:Any]]
func row(_ name:String)->[String:Any]{catalog.first{$0["model"] as?String==name}!}
func path(_ name:String)->String{row(name)["path"] as!String}
func make(_ peer:Peer,_ limits:NativePedAtlasLoader.Limits = .init())->NativePedAtlasLoader{NativePedAtlasLoader(limits:limits,callbackQueue:DispatchQueue(label:"authored.callback"),transfer:peer.make)}
do {
    let peer=Peer(root),loader=make(peer),sink=Sink()
    let request=loader.load(model:"authored",path:path("authored"),source:"one",server:server,completion:sink.add)
    finish(peer,sink);let payload=sink.payload()
    check(payload.source=="one" && payload.world.vertices.count==3,"actual validated geometry/source")
    check(snapshot(loader).encodedBytes>0,"unconsumed payload lost reservation")
    let count=payload.consume{manifest,files in check(manifest.model=="authored","manifest identity");return files.count}
    check(count==4,"complete family consumption")
    check(payload.consume{_,_ in 1}==nil,"payload consumed twice")
    idle(loader);request.cancel();Thread.sleep(forTimeInterval:0.01);check(sink.count==1,"cancel replayed completed callback")
}
do {
    let peer=Peer(root),loader=make(peer),sink=Sink()
    let request=loader.load(model:"authored",path:path("authored"),source:"old",server:server,completion:sink.add)
    wait("metadata starts"){!peer.pending.isEmpty};peer.drain()
    wait("members start"){peer.pending.count>=2};let active=peer.pending
    request.cancel();wait("cancel callback"){sink.count==1};idle(loader)
    check(active.allSatisfy(\.cancelled),"underlying tasks not cancelled")
    for task in active{peer.reply(task,late:true)}
    Thread.sleep(forTimeInterval:0.02);check(sink.count==1,"late old tasks delivered a second result")
    let fresh=Sink();_=loader.load(model:"authored",path:path("authored"),source:"new",server:server,completion:fresh.add)
    finish(peer,fresh);check(fresh.payload().source=="new","new source was replaced by stale work");fresh.payload().close();idle(loader)
}
do {
    let peer=Peer(root),loader=make(peer),sink=Sink()
    let metadata=row("authored")["manifest"] as! [String:Any],members=metadata["resources"] as! [String:[String:Any]]
    peer.corrupt="/"+(members["atlas"]!["path"] as!String)
    _=loader.load(model:"authored",path:path("authored"),source:"one",server:server,completion:sink.add)
    finish(peer,sink);if case .success=sink.at(0){check(false,"corrupt atlas admitted")};idle(loader)
    check(peer.all.filter{!$0.url.path.hasSuffix("authored.json")}.contains(where:\.cancelled),"failed family did not cancel sibling work")
}
do {
    let peer=Peer(root);peer.inline=true;let loader=make(peer),sink=Sink()
    _=loader.load(model:"authored",path:path("authored"),source:"inline",server:server,completion:sink.add)
    wait("inline completion"){sink.count==1};check(sink.payload().source=="inline","factory completion raced task registration")
    sink.payload().close();idle(loader)
}
do {
    let peer=Peer(root),a=row("largea")["manifest"] as! [String:Any],b=row("largeb")["manifest"] as! [String:Any]
    func total(_ m:[String:Any])->Int{(m["resources"] as! [String:[String:Any]]).values.reduce(0){$0+($1["bytes"] as!Int)}}
    var limits=NativePedAtlasLoader.Limits();limits.requests=2;limits.activeTransfers=2;limits.manifestBytes=4096;limits.encodedBytes=max(total(a),total(b))+4096
    let loader=make(peer,limits),sink=Sink()
    _=loader.load(model:"largea",path:path("largea"),source:"a",server:server,priority:1,completion:sink.add)
    _=loader.load(model:"largeb",path:path("largeb"),source:"b",server:server,completion:sink.add)
    finish(peer,sink)
    let before=snapshot(loader)
    check(before.families<=2 && before.transfers<=2 && before.encodedBytes<=limits.encodedBytes && before.payloads==1,"encoded/concurrency limits")
    let overflow=Sink();_=loader.load(model:"authored",path:path("authored"),source:"overflow",server:server,completion:overflow.add)
    wait("queue rejects"){overflow.count==1};if case .success=overflow.at(0){check(false,"queue limit admitted")}
    check(peer.all.filter{$0.url.path.contains("largeb") && !$0.url.path.hasSuffix("largeb.json")}.isEmpty,"held payload reservation allowed second family body")
    sink.payload().close();finish(peer,sink,2);sink.payload(1).close();idle(loader)
}
do {
    let peer=Peer(root),loader=make(peer),sink=Sink()
    let request=loader.load(model:"authored",path:path("authored"),source:"consume-cancel",server:server,completion:sink.add)
    finish(peer,sink)
    _=sink.payload().consume{_,files in
        request.cancel();check(!files.isEmpty && snapshot(loader).encodedBytes>0,"cancel released currently consumed storage early")
    }
    idle(loader);check(sink.count==1,"consumption cancellation repeated callback")
}
do {
    let peer=Peer(root),sink=Sink();var loader:NativePedAtlasLoader?=make(peer)
    _=loader!.load(model:"authored",path:path("authored"),source:"deinit",server:server,completion:sink.add)
    wait("deinit task starts"){!peer.pending.isEmpty};let active=peer.pending;loader=nil
    wait("owner death cancels"){active.allSatisfy(\.cancelled)}
}
print("PASS ped atlas loader: \(checks) actual ownership/bounds/cancellation checks; authored transfer spies")

if CommandLine.arguments.count>2 {
    let base=URL(string:CommandLine.arguments[2])!,origin=ServerAddress(base.absoluteString)!
    let configuration=URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies=false;configuration.httpCookieStorage=nil
    let controlSession=URLSession(configuration:configuration)
    // Actual production bounded task + actual URLSession socket, configured
    // only for this fixture process. No current App or browser session exists.
    NativeResourceTransport.install({request,completion in controlSession.dataTask(with:request,completionHandler:completion)},
        bounded:{request,maximum,completion in NativeBoundedResourceTask(request:request,maximumBytes:maximum,configuration:configuration,completion:completion)})
    func control(_ mode:String?=nil)->[String:Any] {
        var req=URLRequest(url:base.appendingPathComponent("control"));req.timeoutInterval=5
        if let mode{req.httpMethod="POST";req.httpBody=try! JSONSerialization.data(withJSONObject:["mode":mode])}
        let semaphore=DispatchSemaphore(value:0);var result:[String:Any]?
        controlSession.dataTask(with:req){data,reply,error in
            if let data,(reply as?HTTPURLResponse)?.statusCode==200,error==nil{result=(try?JSONSerialization.jsonObject(with:data)) as? [String:Any]};semaphore.signal()
        }.resume()
        check(semaphore.wait(timeout:.now()+6) == .success && result != nil,"real HTTP control response")
        return result!
    }
    let loader=NativePedAtlasLoader(callbackQueue:DispatchQueue(label:"authored.real-http"))
    _=control("ok");let first=Sink()
    _=loader.load(model:"authored",path:path("authored"),source:"real-one",server:origin,completion:first.add)
    wait("actual HTTP family"){first.count==1}
    check(first.payload().manifest.model=="authored" && first.payload().world.vertices.count==3,"real HTTP complete validated family")
    _=first.payload().consume{_,files in check(files.count==4,"HTTP all pinned members")};idle(loader)
    let countAfterFirst=(control()["records"] as! [Any]).count
    check(countAfterFirst==5,"real HTTP fetched exactly manifest+four members")
    _=control("corrupt");let corrupt=Sink()
    _=loader.load(model:"authored",path:path("authored"),source:"real-bad",server:origin,completion:corrupt.add)
    wait("actual corrupt HTTP family"){corrupt.count==1};if case .success=corrupt.at(0){check(false,"real corrupt family admitted")};idle(loader)
    _=control("oversize");let oversized=Sink()
    _=loader.load(model:"authored",path:path("authored"),source:"real-large",server:origin,completion:oversized.add)
    wait("actual bounded HTTP rejection"){oversized.count==1};if case .success=oversized.at(0){check(false,"oversized real member admitted")};idle(loader)
    _=control("delay");let cancelled=Sink(),before=control()["aborted"] as!Int
    let request=loader.load(model:"authored",path:path("authored"),source:"real-old",server:origin,completion:cancelled.add)
    wait("real delayed member request"){(control()["activeMembers"] as!Int)>0}
    request.cancel();wait("real cancellation completion"){cancelled.count==1};idle(loader)
    wait("actual socket abort"){(control()["aborted"] as!Int)>before && (control()["activeMembers"] as!Int)==0}
    check(cancelled.count==1,"real cancellation callback duplicated")
    let afterCancel=(control()["records"] as![Any]).count
    Thread.sleep(forTimeInterval:0.05)
    check((control()["records"] as![Any]).count==afterCancel,"cancelled family replayed GETs")
    _=control("ok");let fresh=Sink()
    _=loader.load(model:"authored",path:path("authored"),source:"real-fresh",server:origin,completion:fresh.add)
    wait("actual new source after cancelled transfer"){fresh.count==1}
    check(fresh.payload().source=="real-fresh","old cancelled HTTP replaced new family")
    fresh.payload().close();idle(loader);controlSession.invalidateAndCancel()
    print("PASS actual URLSession -> disposable Node HTTP atlas family/corruption/cap/cancel/fresh-source; total \(checks) checks")
}
