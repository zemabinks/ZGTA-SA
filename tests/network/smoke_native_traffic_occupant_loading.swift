// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

private enum TestClock {static var now=100.0}
private final class Request:NativeResourceTask {
    let request:URLRequest,maximum:Int,completion:NativeResourceTransport.Completion
    var resumes=0,cancels=0,onCancel:(()->Void)?
    init(_ request:URLRequest,_ maximum:Int,_ completion:@escaping NativeResourceTransport.Completion) {
        self.request=request;self.maximum=maximum;self.completion=completion
    }
    func resume(){resumes+=1}
    func cancel(){cancels+=1;onCancel?()}
    func finish(_ data:Data?,status:Int=200) {
        completion(data,HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil),nil)
    }
}
private final class Traffic {struct Configuration {var level=1.0};var traffic=Configuration()}
private final class Renderer {
    let ambientTraffic=Traffic()
    var server=ServerAddress("http://127.0.0.1:18942"),source="first"
    var trafficOccupantCatalog:(source:String,value:NativeTrafficOccupants.Catalog)?
    var trafficOccupantTask:NativeResourceTask?,trafficOccupantToken=UUID(),trafficOccupantSource:String?
    var trafficOccupantRetryAfter=0.0
    func fixedCJSourceIdentity()->String{source}
    // ACTUAL_RESOURCE_METHODS
}
@main private enum TrafficOccupantLoadingTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func drain()throws {
        var done=false;DispatchQueue.main.async{done=true}
        let deadline=Date().addingTimeInterval(2)
        while !done && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.001))}
        try check(done,"Main publication queue timeout")
    }
    static func main(){do{try run();print("PASS traffic occupant loading: \(checks) checks; literal renderer methods and actual decoder, authored tables, explicit HTTP/clock boundary; no sockets, rendering or retail acceptance")}
        catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        var requests:[Request]=[]
        NativeResourceTransport.install({_,_ in fatalError("Loader bypassed bounded transport")},bounded:{r,m,c in
            let task=Request(r,m,c);requests.append(task);return task
        })
        let data=Data(#"{"schema":1,"fallback":[5,6],"overrides":{},"hiddenModels":[]}"#.utf8),renderer=Renderer()
        renderer.ambientTraffic.traffic.level=0;renderer.loadTrafficOccupantsIfNeeded()
        try check(requests.isEmpty,"Disabled traffic requested occupant resources")
        renderer.ambientTraffic.traffic.level=1;renderer.loadTrafficOccupantsIfNeeded()
        try check(requests.count==1 && requests[0].maximum==65536 && requests[0].resumes==1,"Initial bounded request/resume")
        try check(requests[0].request.url!.path=="/game/native/traffic-occupants.json","Wrong occupant resource")
        for _ in 0..<60{renderer.loadTrafficOccupantsIfNeeded()}
        try check(requests.count==1 && requests[0].cancels==0,"Active ticks replaced pending request")
        TestClock.now=101;requests[0].finish(nil,status:503);try drain()
        try check(renderer.trafficOccupantTask==nil && renderer.trafficOccupantCatalog==nil,"Failed request published metadata or retained task")
        TestClock.now=105.999;renderer.loadTrafficOccupantsIfNeeded()
        try check(requests.count==1,"Retry used initial request time instead of completion time")
        TestClock.now=106;renderer.loadTrafficOccupantsIfNeeded()
        try check(requests.count==2,"Failed request never retried")
        requests[1].finish(Data("{}".utf8));try drain()
        try check(renderer.trafficOccupantCatalog==nil && renderer.trafficOccupantTask==nil,"Malformed table accepted")
        TestClock.now=111;renderer.loadTrafficOccupantsIfNeeded();requests[2].finish(data);try drain()
        try check(renderer.trafficOccupantCatalog?.source=="first" && renderer.trafficOccupantRetryAfter==0,"Successful retry not published")
        renderer.loadTrafficOccupantsIfNeeded();try check(requests.count==3,"Ready table repeatedly reloaded")
        // Cache A -> pending B -> cached A must retire B before returning.
        renderer.source="second";renderer.loadTrafficOccupantsIfNeeded();let retired=requests[3]
        renderer.source="first";renderer.loadTrafficOccupantsIfNeeded()
        try check(retired.cancels==1 && renderer.trafficOccupantTask==nil,"Cached-source return retained another source's pending request")
        retired.finish(data);try drain()
        try check(renderer.trafficOccupantCatalog?.source=="first","Retired source replaced cached table")
        renderer.source="second";renderer.loadTrafficOccupantsIfNeeded()
        try check(requests.count==5,"Retired pending source blocked a new request")
        let second=requests[4],oldToken=renderer.trafficOccupantToken;var revokedBeforeCancel=false
        second.onCancel={revokedBeforeCancel=renderer.trafficOccupantToken != oldToken}
        renderer.source="third";renderer.loadTrafficOccupantsIfNeeded()
        try check(revokedBeforeCancel && second.cancels==1 && requests.count==6,"Source token not revoked before cancellation")
        let third=requests[5];second.finish(data);try drain()
        try check(renderer.trafficOccupantTask === third && renderer.trafficOccupantCatalog?.source=="first","Stale callback cleared replacement request")
        renderer.ambientTraffic.traffic.level=0;renderer.cancelTrafficOccupantLoad();third.finish(data);try drain()
        try check(third.cancels==1 && renderer.trafficOccupantTask==nil && renderer.trafficOccupantSource==nil && renderer.trafficOccupantRetryAfter==0,"Disable/reset retained loader ownership")
        try check(renderer.trafficOccupantCatalog?.source=="first","Cancelled callback published new metadata")
        renderer.loadTrafficOccupantsIfNeeded();try check(requests.count==6,"Disabled loader retried")
    }
}
