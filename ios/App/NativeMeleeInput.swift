import Foundation

/// Public9737 melee input buffer. Weapon9 alone continuously requests strikes
/// while held; other melee weapons use a .4s edge buffer. Retail input feel is
/// not established by that browser evidence.
final class NativeMeleeInput {
    struct Frame {var attack=false;var guarding=false;var blocking=false}
    private var weapon:Int?
    private var previousHeld=false
    private var queuedWeapon:Int?
    private var remaining:Double=0
    func press(weapon:Int){queuedWeapon=weapon}
    // After a task/input loss, an already-held button is not a fresh edge.
    // A new explicit press still works, or a neutral sample re-arms the edge.
    func cancel(){queuedWeapon=nil;remaining=0;previousHeld=true;weapon=nil}
    func accepted(){remaining=0;queuedWeapon=nil}
    func update(delta:Double,weapon:Int,held:Bool,ready:Bool,canAct:Bool,
                guardHeld:Bool,blockHeld:Bool,canGuard:Bool,firing:Bool)->Frame {
        guard delta.isFinite,delta>=0 else{cancel();return Frame()}
        if self.weapon != weapon {remaining=0;self.weapon=weapon}
        let queued=queuedWeapon==weapon
        let edge=queued || held && !previousHeld
        previousHeld=held
        if weapon==9 {remaining=0}
        else {remaining=edge ? 0.4:max(0,remaining-delta)}
        let requested=weapon==9 ? held || queued:remaining>0
        queuedWeapon=nil
        let guarding=canGuard && canAct && guardHeld && !held && !firing
        return Frame(attack:requested && ready && canAct,guarding:guarding,blocking:guarding && blockHeld)
    }
}
