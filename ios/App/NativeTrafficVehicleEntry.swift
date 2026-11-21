// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// The original service materializes compact traffic as a registered vehicle
/// before ordinary entry. A target prefix is never a registered vehicle ID.
/// No request/ACK here grants local driving or substitutes for server consent.
struct NativeTrafficVehicleEntry {
    struct Pending:Equatable {let trafficID:UInt16,since:Double}
    struct Vehicle {let id:String,trafficID:UInt16?}
    enum Result:Equatable {case waiting,ready(String),expired}
    private(set) var pending:Pending?
    @discardableResult mutating func request(_ id:UInt16,at now:Double)->Bool {
        guard pending==nil,now.isFinite else{return false}
        pending=Pending(trafficID:id,since:now);return true
    }
    mutating func cancel(){pending=nil}
    mutating func poll(at now:Double,vehicles:[Vehicle],ready:(String)->Bool)->Result {
        guard let pending else{return .waiting}
        guard now.isFinite,now>=pending.since,now-pending.since<2.5 else{self.pending=nil;return .expired}
        for vehicle in vehicles where vehicle.trafficID==pending.trafficID && !vehicle.id.isEmpty {
            if ready(vehicle.id){self.pending=nil;return .ready(vehicle.id)}
        }
        return .waiting
    }
}
