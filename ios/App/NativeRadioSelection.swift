import Foundation

/// Cycle the radio's actual currently available station/off ring.
enum NativeRadioSelection {
    static func cycle(_ current:Int,choices:[Int],direction:Int)->Int? {
        guard !choices.isEmpty,direction != 0 else{return nil}
        let index=choices.firstIndex(of:current) ?? 0
        return choices[(index+(direction>0 ? 1:choices.count-1)) % choices.count]
    }
}
