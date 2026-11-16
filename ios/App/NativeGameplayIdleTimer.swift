// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// One foreground gameplay owner may keep the display awake. A replaced
/// controller's delayed cleanup cannot release a newer game's ownership.
/// Access this UI resource only from the main thread in the application.
final class NativeGameplayIdleTimer {
    private let read:()->Bool
    private let write:(Bool)->Void
    private var owner:UUID?
    private var previous:Bool?

    init(read:@escaping()->Bool,write:@escaping(Bool)->Void){self.read=read;self.write=write}
    func claim(_ token:UUID,active:Bool){
        if owner==nil{previous=read()}
        owner=token;apply(active ? true:previous ?? false)
    }
    func setActive(_ token:UUID,_ active:Bool){
        guard owner==token else{return}
        apply(active ? true:previous ?? false)
    }
    func release(_ token:UUID){
        guard owner==token else{return}
        let restore=previous ?? false;owner=nil;previous=nil;apply(restore)
    }
    private func apply(_ value:Bool){if read() != value{write(value)}}
}

#if canImport(UIKit)
import UIKit
extension NativeGameplayIdleTimer {
    @MainActor static let shared=NativeGameplayIdleTimer(
        read:{UIApplication.shared.isIdleTimerDisabled},
        write:{UIApplication.shared.isIdleTimerDisabled=$0})
}
#endif
