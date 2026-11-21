// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Visibility belongs to a particular held weapon and hand, not its shared
/// model mesh. The original holder exposes embedded flash meshes for .05s.
final class NativeWeaponFlash {
    private struct Held {let weapon:Int;var model:String?;var right = -Double.infinity,left = -Double.infinity}
    private var held:[String:Held]=[:]
    func clear(){held.removeAll()}
    func retain(_ identities:Set<String>){held=held.filter{identities.contains($0.key)}}
    func select(identity:String,weapon:Int,model:String?=nil){
        if var value=held[identity],value.weapon==weapon,
           model==nil || value.model==nil || value.model==model {
            if let model{value.model=model};held[identity]=value;return
        }
        held[identity]=Held(weapon:weapon,model:model)
    }
    func fire(identity:String,weapon:Int,left:Bool,twin:Bool,at now:Double,model:String?=nil,ready:Bool=true){
        guard now.isFinite else{return}
        guard ready else{held[identity]=nil;return}
        select(identity:identity,weapon:weapon,model:model)
        var value=held[identity]!
        if left && twin{value.left=now+0.05}else{value.right=now+0.05}
        held[identity]=value
    }
    func visible(identity:String,weapon:Int,left:Bool,at now:Double)->Bool{
        guard now.isFinite,let value=held[identity],value.weapon==weapon else{return false}
        return now < (left ? value.left:value.right)
    }
}
