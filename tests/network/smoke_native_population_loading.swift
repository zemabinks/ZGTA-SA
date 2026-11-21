// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

enum TestClock{static var now:Double=100}
protocol NativeResourceTask:AnyObject{func cancel();func resume()}
final class TaskSpy:NativeResourceTask {
    let url:URL,maximum:Int,completion:(Data?,URLResponse?,Error?)->Void
    var cancelled=false,resumed=false
    init(url:URL,maximum:Int,completion:@escaping(Data?,URLResponse?,Error?)->Void){self.url=url;self.maximum=maximum;self.completion=completion}
    func cancel(){cancelled=true}
    func resume(){resumed=true}
    func finish(_ data:Data?,status:Int=200){completion(data,HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:nil),nil)}
}
enum NativeResourceTransport {
    static var requests:[TaskSpy]=[]
    static func boundedDataTask(with url:URL,maximumBytes:Int,completion:@escaping(Data?,URLResponse?,Error?)->Void)->NativeResourceTask {
        let task=TaskSpy(url:url,maximum:maximumBytes,completion:completion);requests.append(task);return task
    }
}
struct Server {let url:URL;func path(_ path:String)->URL{url.appendingPathComponent(path)}}
final class Bodies {var clears=0;func removeAll(){clears+=1}}
final class Renderer {
    let ambientPedestrians=NativeAmbientPedestrians()
    var ambientPathTask:NativeResourceTask?,ambientPathToken=UUID(),ambientPathSource:String?,ambientPathRetryAfter:Double=0
    var presentedAmbientPedestrians:[Int]=[],ambientAnimations:[Int:Int]=[:],ambientGround:[Int:Int]=[:]
    var ambientBodies:Bodies?=Bodies(),source="first"
    var server:Server?=Server(url:URL(string:"http://127.0.0.1:18942")!)
    var onStatus:((String)->Void)?
    func fixedCJSourceIdentity()->String{source}
    /* ACTUAL_RENDERER_METHODS */
}
@main enum PopulationLoadingTests {
    static var checks=0
    static func check(_ value:Bool,_ label:String)throws{checks+=1;if !value{throw NSError(domain:label,code:1)}}
    static func bytes<T:FixedWidthInteger>(_ values:[T])->Data {
        var result=Data();for value in values{var v=value.littleEndian;withUnsafeBytes(of:&v){result.append(contentsOf:$0)}};return result
    }
    static func graph(shift:Int16=0)->Data {
        // Invented two-node/two-edge graph, independently encoded for this
        // test. No original game bytes, observations or coordinates embedded.
        var data=bytes([UInt32(0x44504453),1,2,2,0,0,0,0])
        for part in [bytes([Int16(8)+shift,16,24,80,160,240]),bytes([UInt32(0),1,2]),Data([0,0]),Data([0,0]),bytes([UInt16(1),0]),Data([0,0])] {
            data.append(part);data.append(Data(count:(4-part.count%4)%4))
        };return data
    }
    static func drain()throws {
        var done=false;DispatchQueue.main.async{done=true}
        let deadline=Date().addingTimeInterval(2)
        while !done && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.001))}
        try check(done,"Main queue callback did not run")
    }
    static func main()throws {
        let renderer=Renderer(),data=graph(),hash=NativeAmbientPedestrianPaths.crc32(data)
        var errors:[String]=[];renderer.onStatus={errors.append($0)}
        renderer.configureAmbientPedestrians(level:1,paths:hash)
        try check(NativeResourceTransport.requests.count==1,"Initial graph load missing")
        let first=NativeResourceTransport.requests[0]
        try check(first.resumed && first.maximum==NativeAmbientPedestrianPaths.maximumBytes,"Graph load bypassed bounded transport")
        try check(URLComponents(url:first.url,resolvingAgainstBaseURL:false)?.queryItems==[.init(name:"v",value:hash)],"Graph identity missing from request")
        for _ in 0..<10{renderer.configureAmbientPedestrians(level:1,paths:hash)}
        try check(NativeResourceTransport.requests.count==1 && !first.cancelled,"Repeated same graph announcement cancelled live load")
        first.finish(nil,status:503);try drain()
        try check(renderer.ambientPathTask==nil && renderer.ambientPedestrians.graph==nil && errors.count==1,"Failed transfer published a graph or lost completion ownership")
        TestClock.now=104.999;renderer.advanceAmbientPedestrians(at:TestClock.now,active:true)
        try check(NativeResourceTransport.requests.count==1,"Failed graph retried before backoff")
        TestClock.now=105;renderer.advanceAmbientPedestrians(at:TestClock.now,active:false)
        try check(NativeResourceTransport.requests.count==1,"Inactive gameplay retried graph")
        renderer.advanceAmbientPedestrians(at:TestClock.now,active:true)
        try check(NativeResourceTransport.requests.count==2,"Failed graph never retried during active gameplay")
        let second=NativeResourceTransport.requests[1]
        for _ in 0..<60{renderer.advanceAmbientPedestrians(at:TestClock.now,active:true)}
        try check(NativeResourceTransport.requests.count==2 && !second.cancelled,"Active ticks duplicated/cancelled live graph request")
        TestClock.now=200;second.finish(graph(shift:1));try drain()
        try check(renderer.ambientPedestrians.graph==nil && errors.count==2,"Wrong graph CRC admitted")
        TestClock.now=204.999;renderer.advanceAmbientPedestrians(at:TestClock.now,active:true)
        try check(NativeResourceTransport.requests.count==2,"Backoff started at request time instead of failure completion")
        TestClock.now=205;renderer.advanceAmbientPedestrians(at:TestClock.now,active:true)
        try check(NativeResourceTransport.requests.count==3,"Verification failure did not retry")
        let third=NativeResourceTransport.requests[2];third.finish(data);try drain()
        try check(renderer.ambientPedestrians.graph?.crc32==hash && renderer.ambientPathTask==nil,"Verified retry not installed")
        TestClock.now=500;renderer.advanceAmbientPedestrians(at:TestClock.now,active:true)
        renderer.configureAmbientPedestrians(level:2,paths:hash)
        try check(NativeResourceTransport.requests.count==3,"Ready graph reloaded on tick/level update")
        renderer.source="second";renderer.reloadAmbientPedestrianSourceIfChanged()
        try check(NativeResourceTransport.requests.count==4 && renderer.ambientPedestrians.graph==nil,"Source replacement retained previous graph")
        let fourth=NativeResourceTransport.requests[3]
        let alternate=graph(shift:2),alternateHash=NativeAmbientPedestrianPaths.crc32(alternate)
        renderer.configureAmbientPedestrians(level:1,paths:alternateHash)
        try check(fourth.cancelled && NativeResourceTransport.requests.count==5,"Changed graph did not replace old load")
        fourth.finish(data);try drain()
        try check(renderer.ambientPathTask != nil && renderer.ambientPedestrians.graph==nil,"Stale completion cleared replacement task")
        let fifth=NativeResourceTransport.requests[4]
        renderer.configureAmbientPedestrians(level:0,paths:nil)
        try check(fifth.cancelled && renderer.ambientPathTask==nil && renderer.ambientPathSource==nil,"Disable retained graph request/source")
        fifth.finish(alternate);try drain()
        try check(renderer.ambientPedestrians.graph==nil && renderer.ambientPedestrians.level==0,"Disabled completion published a graph")
        renderer.advanceAmbientPedestrians(at:TestClock.now+100,active:true)
        try check(NativeResourceTransport.requests.count==5,"Disabled population retried graph")
        renderer.configureAmbientPedestrians(level:1,paths:hash)
        try check(NativeResourceTransport.requests.count==6,"Re-enable inherited old backoff")
        NativeResourceTransport.requests[5].finish(data);try drain()
        try check(renderer.ambientPedestrians.graph?.crc32==hash,"Re-enabled graph missing")
        print("PASS renderer population graph loading: \(checks) checks, literal production methods, actual decoder/store; HTTP/time seams only")
    }
}
