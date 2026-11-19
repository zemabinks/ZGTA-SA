// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// A detailed cell's indexed solid prefix and transparent suffix. Missing
/// metadata stays on the compatibility path; malformed ranges never draw.
struct NativeWorldDrawPlan:Equatable {
    enum Invalid:Error{case range}
    struct Range:Equatable {let start:Int,count:Int}
    let solid:Range,clear:Range
    init(indexCount:Int,solidCount:Int)throws {
        guard indexCount>0,indexCount<3_000_000,indexCount%3==0,
              solidCount>=0,solidCount<=indexCount,solidCount%3==0 else{throw Invalid.range}
        solid=Range(start:0,count:solidCount)
        clear=Range(start:solidCount,count:indexCount-solidCount)
    }
    /// Match the index against the actual geometry before accepting its split.
    init?(indexCount:Int,triangles:Int?,blend:Int?) {
        guard let triangles,let blend,triangles>0,triangles<1_000_000,
              triangles*3==indexCount,let plan=try? Self(indexCount:indexCount,solidCount:blend) else{return nil}
        self=plan
    }
}
