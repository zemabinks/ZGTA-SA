import Foundation

/// Current-connection account/mission requests. A fresh WebSocket inventory
/// nonce and world baseline must be ready before gameplay actions are accepted.
final class NativeGameplayClient {
    private let server:ServerAddress
    private(set) var state:[String:Any]=[:]
    private var generation:UInt64=0
    private var connectionGeneration:UInt64=0
    private var tasks:[UUID:URLSessionDataTask]=[:]
    private var actionID:UUID?
    private var refreshID:UUID?
    private(set) var connectionReady=false
    var inventoryConnection:String? {
        didSet {
            guard inventoryConnection != oldValue else{return}
            connectionReady=false;invalidatePendingRequests(connectionBoundary:true);state=[:]
        }
    }
    var onState:(([String:Any])->Void)?
    var onResult:((String)->Void)?
    init(server:ServerAddress){self.server=server}
    deinit {for task in tasks.values{task.cancel()}}

    func setConnectionReady(_ ready:Bool) {
        connectionReady=ready && inventoryConnection?.isEmpty == false
        if !connectionReady {invalidatePendingRequests(connectionBoundary:true);state=[:]}
    }
    private func invalidatePendingRequests(connectionBoundary:Bool=false) {
        generation &+= 1
        if connectionBoundary {connectionGeneration &+= 1}
        let old=Array(tasks.values);tasks.removeAll();actionID=nil;refreshID=nil
        for task in old{task.cancel()}
    }
    private func request(_ path:String)->URLRequest {
        var request=URLRequest(url:server.path(path),cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:8)
        if let inventoryConnection{request.setValue(inventoryConnection,forHTTPHeaderField:"X-ZGTA-Inventory-Connection")}
        return request
    }
    func refresh() {
        guard connectionReady,actionID==nil,refreshID==nil else{return}
        let id=UUID(),epoch=generation,connection=inventoryConnection
        refreshID=id
        let task=URLSession.shared.dataTask(with:request("api/local/state")) { [weak self] data,response,error in
            let next=data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
            DispatchQueue.main.async {
                guard let self,self.connectionReady,self.generation==epoch,self.inventoryConnection==connection,self.refreshID==id else{return}
                self.tasks.removeValue(forKey:id);self.refreshID=nil
                if let next,(response as? HTTPURLResponse)?.statusCode==200 {
                    self.state=next;self.onState?(next)
                } else if let error {self.onResult?("GAMEPLAY: \(error.localizedDescription)")}
            }
        }
        tasks[id]=task;task.resume()
    }
    /// Progress already represented by an owned HUD/animation can omit the
    /// successful status toast. Errors and connection fences always remain.
    func perform(_ action:String,payload:[String:Any]=[:],reportSuccess:Bool=true,completion:((Bool?)->Void)?=nil) {
        guard connectionReady else {onResult?("MULTIPLAYER IS RECONNECTING");completion?(false);return}
        guard actionID==nil else{completion?(false);return}
        // An older GET must never arrive after this mutation and roll back the
        // newer state. Cancel it and invalidate already queued completions too.
        invalidatePendingRequests()
        let id=UUID(),epoch=generation,connection=inventoryConnection,connectionEpoch=connectionGeneration
        actionID=id
        var request=request("api/local/action");request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try? JSONSerialization.data(withJSONObject:payload.merging(["action":action]){_,new in new})
        let task=URLSession.shared.dataTask(with:request) { [weak self] data,response,error in
            let body=data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]} ?? [:]
            DispatchQueue.main.async {
                guard let self,self.connectionReady,self.generation==epoch,self.inventoryConnection==connection,self.actionID==id else{return}
                self.tasks.removeValue(forKey:id);self.actionID=nil
                if (response as? HTTPURLResponse)?.statusCode==200,let next=body["state"] as? [String:Any] {
                    self.state=next;self.onState?(next)
                    guard self.connectionReady,self.connectionGeneration==connectionEpoch,self.inventoryConnection==connection else{return}
                    if reportSuccess,self.generation==epoch {self.onResult?((body["message"] as? String) ?? "DONE")}
                    guard self.connectionReady,self.connectionGeneration==connectionEpoch,self.inventoryConnection==connection else{return}
                    completion?(true)
                } else {
                    self.onResult?((body["error"] as? String) ?? error?.localizedDescription ?? "Action failed")
                    guard self.connectionReady,self.connectionGeneration==connectionEpoch,self.inventoryConnection==connection else{return}
                    completion?(response == nil ? nil:false)
                }
            }
        }
        tasks[id]=task;task.resume()
    }
}
