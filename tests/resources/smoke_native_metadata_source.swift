// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
private struct Failure:Error,CustomStringConvertible{let description:String;init(_ s:String){description=s}}
private var checks=0
private func check(_ value:@autoclosure()->Bool,_ message:String)throws{checks+=1;if !value(){throw Failure(message)}}
private final class Request:NativeResourceTask {
    let url:URL,completion:NativeResourceTransport.Completion
    var resumes=0,cancels=0
    init(_ r:URLRequest,_ c:@escaping NativeResourceTransport.Completion){url=r.url!;completion=c}
    func resume(){resumes+=1};func cancel(){cancels+=1}
    func deliver(_ data:Data?,status:Int=200)throws {
        let done=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async{self.completion(data,HTTPURLResponse(url:self.url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil),nil);done.signal()}
        try check(done.wait(timeout:.now()+5) == .success,"transport callback timeout")
    }
}
private final class Harness {
    var server=ServerAddress("http://127.0.0.1:18006"),binding="source-a"
    var seating:NativeVehicleSeating?
    var modelIndexToken=UUID()
    var vehicleCouplingMetadataToken=UUID(),vehicleTreadsMetadataToken=UUID()
    func fixedCJSourceIdentity()->String{binding+"|"+(server?.display ?? "")}
    func loadSeating(){
        guard let server else{return}
        // ACTUAL_MODEL_REQUEST_HEADER
        // ACTUAL_SEATING_REQUEST
    }
}
private func drain()throws {
    var done=false;DispatchQueue.main.async{done=true}
    let end=Date().addingTimeInterval(5)
    while !done && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))}
    try check(done,"main publication queue timeout")
}
private func seating(_ clip:String)throws->Data {
    try JSONSerialization.data(withJSONObject:["models":["420":["astride":false,"clips":["sit":clip],"boarding":[String:[String]]()]]])
}
@main private enum Main {
    static func main(){do{try run();print("PASS \(checks) actual seating request/decode/publication checks; authored metadata, no UI or retail acceptance")}
        catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    private static func run()throws {
        var requests:[Request]=[]
        NativeResourceTransport.install({r,c in let t=Request(r,c);requests.append(t);return t})
        let h=Harness(),old=try seating("ped/car_sit"),new=try seating("ped/car_sit_lo")
        if CommandLine.arguments.contains("--source-only") {
            h.loadSeating();try requests[0].deliver(old);h.binding="source-b";try drain()
            try check(h.seating==nil,"old seating publication installed after resource replacement without another load")
            return
        }
        if CommandLine.arguments.contains("--failed-latest") {
            h.loadSeating();try requests[0].deliver(new);try drain()
            h.loadSeating();let retired=requests.count-1;h.loadSeating();try requests.last!.deliver(nil,status:503);try drain()
            try requests[retired].deliver(old);try drain()
            try check(h.seating?.models["420"]?.clip("sit")=="ped/car_sit_lo","late request replaced accepted seating after failed latest reload")
            return
        }
        if !CommandLine.arguments.contains("--same-source-only") {
            h.loadSeating();try check(requests.count==1,"initial seating request absent")
            try requests[0].deliver(old)
            h.binding="source-b";h.loadSeating();try drain()
            try check(h.seating==nil,"completed old-source seating publication installed into new resource source")
            try requests[1].deliver(new);try drain()
        } else {h.loadSeating();try requests[0].deliver(new);try drain()}
        try check(h.seating?.models["420"]?.clip("sit")=="ped/car_sit_lo","current seating metadata absent")
        h.loadSeating();let prior=requests.count-1;h.loadSeating();let latest=requests.count-1
        try requests[latest].deliver(new);try drain();try requests[prior].deliver(old);try drain()
        try check(h.seating?.models["420"]?.clip("sit")=="ped/car_sit_lo","same-source late seating request overwrote latest vehicle animation table")
        h.loadSeating();try requests.last!.deliver(nil,status:503);try drain()
        try check(h.seating?.models["420"]?.clip("sit")=="ped/car_sit_lo","failed latest request discarded accepted table")
        try check(requests.allSatisfy{$0.resumes==1},"seating requests resumed more than once")
    }
}
