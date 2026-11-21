// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Admission identity is independent of packet time, movement and render rate.
/// Removed/rebound actors cannot inherit an earlier completed shot pose merely
/// because the service later reuses their wire ID and model number.
enum NativeShotOwners {
    struct Player:Equatable {
        let code:String,vehicle:String?,riding:String?,seat:Int,skin:Int
        let alive:Bool,vehicleAlive:Bool
    }
    struct Vehicle:Equatable {
        let code:String,driver:String?,traffic:UInt16?,alive:Bool
    }
    final class Ledger<State:Equatable> {
        private struct Entry {let state:State,generation:UInt64}
        private var entries:[String:Entry]=[:]
        private var serial:UInt64=0
        func receive(_ states:[String:State]) {
            entries=entries.filter{states[$0.key] != nil}
            for (id,state) in states where entries[id]?.state != state {
                serial &+= 1
                if serial==0{serial=1}
                entries[id]=Entry(state:state,generation:serial)
            }
        }
        func generation(_ id:String)->UInt64?{entries[id]?.generation}
    }
}
