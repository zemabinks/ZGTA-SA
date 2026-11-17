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
    private var gameplayActive=false
    private var resourceOwners=Set<UUID>()

    init(read:@escaping()->Bool,write:@escaping(Bool)->Void){self.read=read;self.write=write}
    func claim(_ token:UUID,active:Bool){
        if owner==nil,resourceOwners.isEmpty{previous=read()}
        owner=token;gameplayActive=active;refresh()
    }
    func setActive(_ token:UUID,_ active:Bool){
        guard owner==token else{return}
        gameplayActive=active;refresh()
    }
    func release(_ token:UUID){
        guard owner==token else{return}
        owner=nil;gameplayActive=false;refresh()
    }
    /// Installation has an independent foreground lease. Completing a cache
    /// transfer cannot release a still-active game's display-sleep ownership.
    func setResourceActive(_ token:UUID,_ active:Bool){
        if active {
            if owner==nil,resourceOwners.isEmpty{previous=read()}
            resourceOwners.insert(token)
        }else{resourceOwners.remove(token)}
        refresh()
    }
    private func refresh(){
        if owner==nil,resourceOwners.isEmpty {
            if let restore=previous{previous=nil;apply(restore)}
        }else{apply(gameplayActive || !resourceOwners.isEmpty ? true:previous ?? false)}
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
