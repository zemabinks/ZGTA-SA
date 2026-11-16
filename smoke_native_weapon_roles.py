#!/usr/bin/env python3
"""Inventory attack classification against actual owner-local OP profiles."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/combat-88/weapon-roles';OUT.mkdir(parents=True,exist_ok=True)
APP=['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery']
FILES=[f'ios/App/{n}.swift' for n in APP]+['smoke_native_weapon_roles.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}
SWIFT=r'''
import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game/native")
let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:game.appendingPathComponent("weapons.json"))) as! [String:Any]
let profiles=try JSONSerialization.jsonObject(with:Data(contentsOf:game.appendingPathComponent("foot-animation.json"))) as! [String:Any]
let stats=catalog["stats"] as! [String:[String:Any]],rows=profiles["weapons"] as! [[String:Any]]
var checks=0,utilityIDs:[Int]=[],attackIDs:[Int]=[]
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
for row in rows {
    let id=row["id"] as! Int,s=stats[String(id)]!,use=row["use"] as? String
    let melee=use=="melee",ranged=["gun","stream","launch","throw"].contains(use ?? "")
    let weapon=NativeWeaponState.Weapon(id:id,name:s["name"] as! String,model:"",range:40,
        capacity:(s["clip"] as? NSNumber)?.intValue ?? 0,interval:0.1,animation:"",fireKind:s["fire"] as! String)
    check(weapon.isMelee==melee,"Utility misclassified as melee: \(id), OP.use=\(use ?? "nil")")
    check(weapon.isGun==ranged,"Utility misclassified as an ammunition attack: \(id), OP.use=\(use ?? "nil")")
    check(weapon.supportsAttack==(melee || ranged),"Utility exposes an attack UI capability: \(id)")
    let value=NativeWeaponState(catalog:[weapon]);value.setConnection("roles")
    let state:[String:Any]=["revision":0,"selected":id,"weapons":id==0 ? []:[["id":id,"clip":5,"rest":20]],"reload":NSNull(),"ack":["connection":"roles","processedShot":0]]
    check(value.apply(state),"Actual catalog role fixture rejected")
    check(value.canFire==(melee || ranged),"Unsupported utility exposes fire readiness: \(id)")
    let seq=NativeShotSequence();check(seq.negotiate("roles"),"Ticket baseline")
    let before=value.rounds
    let accepted=value.consumeAnimationShot(weapon:id,ticket:seq.reserve())
    check(accepted==(melee || ranged),"Unsupported utility consumed an animation shot: \(id)")
    check(value.rounds==before-(ranged ? 1:0),"Wrong role consumed predicted ammo: \(id)")
    if !melee && !ranged {
        utilityIDs.append(id)
        check(!value.fire(ticket:seq.reserve()) && value.pendingShotCount==0 && value.rounds==before,"Fallback gun path spent utility ammo: \(id)")
    } else {attackIDs.append(id)}
}
print("PASS actual weapon roles: \(checks) checks /\(rows.count) OP profiles; utilities\(utilityIDs), attacks\(attackIDs.count)")
'''
def main():
    with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temp:
        p=Path(temp);sources=[]
        for n in APP:
            source=p/(n+'.swift');source.write_bytes(inputs[f'ios/App/{n}.swift']);sources.append(str(source))
        source=p/'main.swift';source.write_text(SWIFT);sources.append(str(source));exe=p/'verify'
        subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),*sources,'-o',str(exe)],check=True)
        result=subprocess.run([str(exe),str(ROOT)],capture_output=True,text=True)
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
            'sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in inputs.items()},
            'dataHashes':{n:hashlib.sha256((ROOT/'local-only/site/game/native'/n).read_bytes()).hexdigest() for n in ['weapons.json','foot-animation.json']},
            'limit':'Actual catalog/profile consistency and native prediction; utility actions/acquisition and retail runtime are not implemented by this gate'},indent=2)+'\n')
        print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
if __name__=='__main__':main()
