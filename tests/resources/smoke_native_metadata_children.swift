// SPDX-License-Identifier: AGPL-3.0-only
// Literal renderer child-request admission. Ground/support effects are explicit
// spies; the sibling physics fixture uses the actual native physical owner.
import Foundation
private struct Failure:Error,CustomStringConvertible{let description:String;init(_ s:String){description=s}}
private var checks=0
private func check(_ value:@autoclosure()->Bool,_ text:String)throws{checks+=1;if !value(){throw Failure(text)}}
private final class Request:NativeResourceTask {
    let url:URL,completion:NativeResourceTransport.Completion
    var resumes=0
    init(_ r:URLRequest,_ c:@escaping NativeResourceTransport.Completion){url=r.url!;completion=c}
    func resume(){resumes+=1};func cancel(){}
    func deliver(_ data:Data?,status:Int=200)throws{
        let done=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async{self.completion(data,HTTPURLResponse(url:self.url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil),nil);done.signal()}
        try check(done.wait(timeout:.now()+5) == .success,"child response delivery timeout")
    }
}
private final class Ground {
    var values:[Data]=[],work:[Int]=[],main=true,onLoad:(()->Void)?
    func loadCouplingDefinitions(_ data:Data){main = main && Thread.isMainThread;values.append(data);let action=onLoad;onLoad=nil;action?()}
    func setWorkingValue(_ value:Int){main = main && Thread.isMainThread;work.append(value)}
}
private final class Support {
    var invalidations=0,values:[Data]=[],main=true
    func invalidatePoses(){main = main && Thread.isMainThread;invalidations+=1}
    func load(_ data:Data)->Bool{main = main && Thread.isMainThread;values.append(data);return true}
}
private final class Harness {
    struct Vehicle{let id:String,work:Int?}
    var server=ServerAddress("http://127.0.0.1:18008"),binding="a"
    var modelIndexToken=UUID(),vehicleCouplingMetadataToken=UUID(),vehicleTreadsMetadataToken=UUID()
    var groundVehicle:Ground?=Ground(),supportScene:Support?=Support(),driving=true,currentVehicleID="authored"
    var remoteVehicles=[Vehicle(id:"authored",work:120)]
    func fixedCJSourceIdentity()->String{binding+"|"+(server?.display ?? "")}
    func beginParent(){
        // ACTUAL_MODEL_REQUEST_HEADER
    }
    // ACTUAL_CHILD_METHODS
}
private func drain()throws{var done=false;DispatchQueue.main.async{done=true};let end=Date().addingTimeInterval(5);while !done && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))};try check(done,"main queue timeout")}
@main private enum Main {
    static func main(){do{try run();print("PASS \(checks) literal coupling/treads admission checks; ground/support effects explicit spies")}
        catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    private static func run()throws{
        var requests:[Request]=[];NativeResourceTransport.install({r,c in let t=Request(r,c);requests.append(t);return t})
        let h=Harness(),old=Data([1]),fresh=Data([2])
        h.loadVehicleCouplingDefinitions();try requests.last!.deliver(old);h.binding="b";try drain()
        try check(h.groundVehicle!.values.isEmpty && h.supportScene!.invalidations==0 && h.groundVehicle!.work.isEmpty,"old-source coupling callback reached ground/support/working state")
        h.loadVehicleCouplingDefinitions();let prior=requests.count-1;h.loadVehicleCouplingDefinitions();try requests.last!.deliver(fresh);try drain();try requests[prior].deliver(old);try drain()
        try check(h.groundVehicle!.values==[fresh] && h.supportScene!.invalidations==1 && h.groundVehicle!.work==[120],"same-source old coupling request overwrote latest or repeated side effects")
        h.loadVehicleCouplingDefinitions();try requests.last!.deliver(old);h.beginParent();try drain()
        try check(h.groundVehicle!.values==[fresh],"new parent generation admitted old coupling child publication")
        h.loadVehicleTreads();try requests.last!.deliver(old);h.binding="c";try drain()
        try check(h.supportScene!.values.isEmpty,"old-source treads callback changed support data")
        h.loadVehicleTreads();let oldTreads=requests.count-1;h.loadVehicleTreads();try requests.last!.deliver(fresh);try drain();try requests[oldTreads].deliver(old);try drain()
        try check(h.supportScene!.values==[fresh],"same-source older treads request replaced latest")
        h.loadVehicleTreads();try requests.last!.deliver(old);h.beginParent();try drain()
        try check(h.supportScene!.values==[fresh],"new parent generation admitted old treads child publication")
        // Independent child subjects may publish in either arrival order.
        h.loadVehicleCouplingDefinitions();let independent=requests.count-1;h.loadVehicleTreads();try requests.last!.deliver(fresh);try requests[independent].deliver(fresh);try drain()
        try check(h.supportScene!.values==[fresh,fresh] && h.groundVehicle!.values==[fresh,fresh],"one child request invalidated another subject")
        h.groundVehicle!.onLoad={h.loadVehicleCouplingDefinitions()}
        h.loadVehicleCouplingDefinitions();let reentry=requests.count;try requests.last!.deliver(fresh);try drain()
        try check(requests.count==reentry+1,"coupling application reentry did not retain its new request")
        try requests.last!.deliver(fresh);try drain()
        try check(h.groundVehicle!.values.count==4,"reentered coupling publication lost")
        let accepted=h.groundVehicle!.values;h.loadVehicleCouplingDefinitions();let rejected=requests.count-1;h.loadVehicleCouplingDefinitions();try requests.last!.deliver(nil,status:503);try drain();try requests[rejected].deliver(old);try drain()
        try check(h.groundVehicle!.values==accepted,"failed latest child reload admitted older data")
        try check(h.groundVehicle!.main && h.supportScene!.main && requests.allSatisfy{$0.resumes==1},"child effects left main owner or request resumed repeatedly")
    }
}
