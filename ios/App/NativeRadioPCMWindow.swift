// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// A bounded window, not a song cache. Samples are stereo interleaved; the
/// playback owner pads the difference from the program's requested duration.
struct NativeRadioPCMWindow {
    let rate:Int
    let requestedFrames:Int
    let decodedFrames:Int
    let samples:[Float]
}

protocol NativeRadioWindowSource:AnyObject {
    func contains(_ id:Int)->Bool
    func read(id:Int,offset:Int,frames:Int,completion:@escaping(Result<NativeRadioPCMWindow,Error>)->Void)
    func cancel()
}

/// A delayed window can still contain the current station sample. Trim its
/// elapsed prefix instead of endlessly discarding/redecoding behind the clock.
enum NativeRadioWindowReconciliation {
    static func remaining(planned:Int,scheduled:Int,readID:Int,currentID:Int?,readOffset:Int,currentOffset:Int,frames:Int)->Range<Int>? {
        guard planned>=0,scheduled>=planned,readOffset>=0,currentOffset>=readOffset,
              (1...8000).contains(frames),currentID==readID else{return nil}
        let skipped=scheduled-planned
        guard skipped<frames,currentOffset-readOffset==skipped else{return nil}
        return skipped..<frames
    }
}
