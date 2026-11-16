// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
func require(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
for baseline in [false,true] {
    var system=baseline,writes=[Bool]()
    let timer=NativeGameplayIdleTimer(read:{system},write:{system=$0;writes.append($0)})
    let first=UUID(),second=UUID(),stale=UUID()
    timer.setActive(stale,true);timer.release(stale)
    require(system==baseline && writes.isEmpty,"no gameplay owner cannot change display sleep")
    timer.claim(first,active:false)
    require(system==baseline,"inactive initial loading preserves prior system policy")
    timer.setActive(first,true);require(system,"foreground game stays awake without touch events")
    timer.setActive(first,false);require(system==baseline,"background/resign restores prior policy")
    timer.setActive(first,true);require(system,"foreground resume reacquires display activity")
    timer.claim(second,active:true)
    timer.release(first);timer.setActive(first,false)
    require(system,"old controller cleanup cannot clear the new game's display lease")
    timer.setActive(second,false);require(system==baseline,"new owner background restores original baseline")
    timer.setActive(second,true);timer.release(second)
    require(system==baseline,"leaving gameplay restores baseline across controller replacement")
    let count=writes.count
    timer.release(second);timer.setActive(second,true)
    require(system==baseline && writes.count==count,"late resume/double cleanup cannot reacquire released ownership")
    var previous:UUID?
    for index in 0..<144 {
        let current=UUID();timer.claim(current,active:true)
        if let previous{timer.release(previous);timer.setActive(previous,false)}
        require(system,"replaced game lease survives delayed lifecycle events \(index)")
        timer.setActive(current,false);require(system==baseline,"background policy \(index)")
        timer.setActive(current,true);require(system,"foreground policy \(index)")
        previous=current
    }
    timer.release(previous!);require(system==baseline,"final game exit releases display activity")
    require(zip(writes,writes.dropFirst()).allSatisfy{$0 != $1},"repeated notifications do not rewrite an unchanged system value")
}
print("PASS gameplay idle ownership: \(checks) checks; replacement, stale callbacks, foreground/background and original policy restoration")
