import Foundation

var checks=0
func check(_ valid:@autoclosure()->Bool,_ message:String){checks+=1;precondition(valid(),message)}
let gun=NativeWeaponState.Weapon(id:22,name:"Synthetic gun",model:"",range:40,capacity:17,interval:0.3,animation:"fixture",fireKind:"INSTANT_HIT")
let smg=NativeWeaponState.Weapon(id:28,name:"Synthetic SMG",model:"",range:40,capacity:50,interval:0.08,animation:"fixture",fireKind:"INSTANT_HIT")

@main enum CombatTransitionVerification {
    static func main() throws {
        let values=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:[String:Any]]
        for rate in [30,60,120] {
            var clock=0.0,refresh=0,resync=0
            let state=NativeWeaponState(catalog:[gun,smg],clock:{clock})
            state.onNeedsRefresh={refresh+=1};state.onNeedsResync={resync+=1}
            let initial=values["baseline"]!,started=values["started"]!
            let nonce=(initial["ack"] as! [String:Any])["connection"] as! String
            state.setConnection(nonce);check(state.apply(initial),"Authoritative initial baseline")
            let request=state.beginReloadRequest();check(state.apply(started),"Actual reload start")
            state.finishReloadRequest(id:request,succeeded:true)
            let firstDeadline=state.reloadUntil
            check(abs(firstDeadline-1.8)<1e-9,"Actual server reload duration")
            clock=0.8;check(state.apply(started),"Equal revision/ACK duplicate is legitimate")
            check(state.reloadUntil<=firstDeadline+1e-9,"Duplicate reload snapshot extended the deadline")
            clock=1.1;check(state.apply(values["armour"]!),"Actual unrelated inventory revision during reload")
            check(state.reloadUntil<=firstDeadline+1e-9,"Unrelated revision restarted same server reload")
            clock=1.3;check(state.apply(values["rejected"]!),"Actual rejected-shot ACK during reload")
            check(state.reloadUntil<=firstDeadline+1e-9,"ACK progress restarted same server reload")
            while clock<firstDeadline+1.0/Double(rate){clock+=1.0/Double(rate);state.tick()}
            check(refresh==1 && resync==0 && state.reloading && !state.canFire,"Expired estimate refreshes once without inventing completion")
            clock=1.9;check(state.apply(values["completed"]!),"Actual authoritative reload completion")
            check(state.canFire && !state.reloading && state.rounds==17 && state.reserve==17 && state.reloadUntil==0,"Completion reconciles real ammunition")
            state.setConnection(nil);check(!state.canFire && !state.reloading && state.reloadUntil==0,"Peer loss clears reload histories")
        }
        var clock=0.0
        let replacement=NativeWeaponState(catalog:[gun,smg],clock:{clock})
        let baseline=values["secondBaseline"]!,first=values["firstReload"]!,new=values["replaced"]!
        replacement.setConnection((baseline["ack"] as! [String:Any])["connection"] as? String)
        check(replacement.apply(baseline) && replacement.apply(first),"Replacement scenario baseline")
        let oldDeadline=replacement.reloadUntil
        clock=0.4;check(replacement.apply(new),"New reload without intermediate cancel snapshot")
        check(replacement.reloadUntil>oldDeadline && abs(replacement.reloadUntil-2.2)<1e-9,"New server reload identity receives a fresh deadline")
        print("PASS combat transitions: \(checks) actual revision/ACK reload checks at30/60/120Hz")
    }
}
