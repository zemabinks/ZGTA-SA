// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// A kinematic target advances once for each actual physical step. Display
/// sampling and several catch-up steps sharing one wall timestamp cannot
/// consume its time. The application explicitly rebases after suspension.
struct NativeSAMPObjectSimulationClock {
    private(set) var timestamp:Double?
    mutating func reset(){timestamp=nil}
    mutating func advance(delta:Double,now:Double)->Double? {
        guard delta.isFinite,delta>0,delta<=0.5,now.isFinite else{return nil}
        let next=(timestamp ?? (now-delta))+delta
        guard next.isFinite else{return nil}
        timestamp=next;return next
    }
}
