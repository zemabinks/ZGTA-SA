// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Driver-only detached lifetime. Removing a compact car does not remove its
/// already falling driver. A full connection/resource reset does. Tombstones
/// follow the authoritative actor generation, rather than a visible-seat list.
final class NativeTrafficRiderRetention<Owner> {
    struct Key:Hashable {let id:UInt16,generation:UInt64}
    struct Detached {
        let serial:UInt64,key:Key,owner:Owner
        var age:Double
    }
    struct Passenger {
        let key:Key,seat:Int,owner:Owner
    }
    private(set) var detached:[Detached]=[]
    private(set) var passengers:[Passenger]=[]
    private var thrown:Set<Key>=[]
    private var serial:UInt64=0
    func isThrown(id:UInt16,generation:UInt64)->Bool{thrown.contains(.init(id:id,generation:generation))}
    @discardableResult func detach(id:UInt16,generation:UInt64,owner:Owner)->Bool {
        let key=Key(id:id,generation:generation)
        guard thrown.insert(key).inserted else{return false}
        serial &+= 1
        detached.append(.init(serial:serial,key:key,owner:owner,age:0))
        return true
    }
    func synchronize(generations:[UInt16:UInt64],promoted:Set<UInt16>=[],admitted:Set<UInt16>?=nil) {
        thrown=thrown.filter{generations[$0.id]==$0.generation}
        // Reuse the native scene's existing resource/distance admission. The
        // archive's larger quality-dependent car budget is a separate gap.
        passengers.removeAll{passenger in
            generations[passenger.key.id] != passenger.key.generation || promoted.contains(passenger.key.id) ||
            admitted.map{!$0.contains(passenger.key.id)} == true
        }
    }
    /// Passenger controllers retain their last completed draw binding when
    /// the driver is thrown. They do not enter the driver's timed list.
    func retainPassenger(id:UInt16,generation:UInt64,seat:Int,owner:Owner) {
        let key=Key(id:id,generation:generation)
        guard (1...2).contains(seat),!passengers.contains(where:{$0.key==key && $0.seat==seat})else{return}
        passengers.append(.init(key:key,seat:seat,owner:owner))
    }
    /// Called before current seated work: a newly detached record receives no
    /// second update in the same display interval. Equality at four survives.
    func advance(delta:Double) {
        guard delta.isFinite,delta>=0 else{return}
        for index in detached.indices{detached[index].age+=delta}
        detached.removeAll{$0.age>4}
    }
    func complete(_ serial:UInt64){detached.removeAll{$0.serial==serial}}
    func reset(){detached=[];passengers=[];thrown=[]}
}
