#!/usr/bin/env python3
"""Compare independent input eligibility to bounded actual archived expressions."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/combat-88/eligibility';OUT.mkdir(parents=True,exist_ok=True)
FILES=['ios/App/NativeCombatEligibility.swift','ios/App/NativeGunAnimation.swift','smoke_native_combat_eligibility.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}
JS=r'''
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 g.fetch=async url=>{const p=path.join(process.cwd(),'local-only/site',String(url).split('?')[0]);if(!fs.existsSync(p))return{ok:false};const b=fs.readFileSync(p);return{ok:true,json:async()=>JSON.parse(b),arrayBuffer:async()=>{const a=new Bytes(b.length);a.set(b);return a.buffer}}};
 g.setTimeout=(f,t)=>{const timer=setTimeout(f,t);timer.unref();return timer};g.clearTimeout=clearTimeout;
 await load(49368).av();const F=load(60662),folder=path.join(process.cwd(),'local-only/site/_next/static/chunks');
 const source=fs.readFileSync(path.join(folder,fs.readdirSync(folder).find(n=>n.startsWith('9737.'))),'utf8');
 const a=source.indexOf('let eH=!Z&&!(null==C?void 0:C.busy)'),b=source.indexOf(',e0=',a);
 const c=source.indexOf('te=eH&&!e7,tt=e0&&ef&&te,tl='),d=source.indexOf(';e0&&',c);
 if([a,b,c,d].some(n=>n<0))throw Error('Actual control boundaries changed');
 const prefix=source.slice(a,b)+';',control='let '+source.slice(c,d)+';';
 const cases=[],profiles=[];
 for(const id of [22,24,30,34,35,36,37,41,42,43]) {
  const eB=F.U1(id);profiles.push({id,requiresAim:!!eB.sight,use:eB.use});
  for(let mask=0;mask<256;mask++) {
   const bit=n=>!!(mask&(1<<n));
   const context={Z:bit(0)?1:0,C:{busy:bit(1),stunned:bit(2),rolling:bit(3)},em:bit(4),e_:false,e7:false,e0:eB.aims,ef:bit(5),ew:true,tk:bit(6)?1:0,eB};
   const value=vm.runInNewContext('(function(){'+prefix+control+'return {aim:!!tt,fire:!!tl}})()',context);
   cases.push({id,airborne:bit(0),busy:bit(1),stunned:bit(2),rolling:bit(3),blocked:bit(4),aimHeld:bit(5),reloading:bit(6),ready:!bit(7),aims:eB.aims,
    expectedAim:value.aim,expectedRequest:value.fire&&!bit(7)});
  }
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({cases,profiles,sourceRanges:[[a,b],[c,d]],limit:'e7 recent-stun-while-moving false; no retail execution'}));
})().catch(e=>{console.error(e.stack);process.exitCode=1});
'''
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
let definitions=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
for profile in reference["profiles"] as! [[String:Any]] {
 let id=profile["id"] as! Int
 check(definitions[id]!.requiresAim==profile["requiresAim"] as! Bool,"Sight metadata mismatch\(id)")
}
for row in reference["cases"] as! [[String:Any]] {
 let id=row["id"] as! Int,definition=definitions[id]!
 let c=NativeCombatEligibility.Context(blocked:row["blocked"] as! Bool,airborne:row["airborne"] as! Bool,busy:row["busy"] as! Bool,
  stunned:row["stunned"] as! Bool,rolling:row["rolling"] as! Bool,requiresAim:definition.requiresAim,aimHeld:row["aimHeld"] as! Bool,
  ready:row["ready"] as! Bool,reloading:row["reloading"] as! Bool)
 check((c.canAim && c.aimHeld)==row["expectedAim"] as! Bool,"Aiming task eligibility differs from actual input expression")
 check(c.canRequestFire==row["expectedRequest"] as! Bool,"New fire intent differs from actual input expression")
 check(c.heldTrigger(true)==(!c.blocked && !c.stunned),"Raw held input survived stun/domain loss")
 check(c.canEmitShot==(!c.blocked && !c.stunned && c.ready && !c.reloading),"Committed marker got new-start-only restrictions")
}
for field in ["dead","vehicle","swim","climb","parachute","boarding","unsupported-flight"] {
 var c=NativeCombatEligibility.Context()
 if field=="dead"{c.alive=false}else if field=="unsupported-flight"{c.flying=true}else{c.blocked=true}
 check(!c.canRequestFire && !c.canEmitShot && !c.canAim && !c.heldTrigger(true),"Lost task ownership leaked \(field) combat")
}
var jet=NativeCombatEligibility.Context(airborne:true,flying:true,arm:true)
check(jet.canRequestFire && jet.canEmitShot,"Eligible arm gun lost jetpack capability")
jet.stunned=true;check(!jet.canRequestFire && !jet.canEmitShot && !jet.heldTrigger(true),"Jetpack arm gun bypassed stun")
let committed=NativeCombatEligibility.Context(airborne:true,busy:true,rolling:true,requiresAim:true)
check(!committed.canRequestFire && committed.canEmitShot,"Committed shot was canceled by new-start-only restrictions")
print("PASS combat task eligibility: \(checks) checks /\((reference["cases"] as! [Any]).count) actual archived control combinations, scope/launcher sights + context ownership")
'''
def main():
    with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temp:
        p=Path(temp);js=p/'reference.js';js.write_text(JS);reference=p/'reference.json'
        subprocess.run(['node',str(js),str(reference)],cwd=ROOT,check=True)
        source=p/'verify.swift';source.write_text('\n'.join(inputs[n].decode() for n in FILES if n.endswith('.swift'))+'\n'+SWIFT)
        exe=p/'verify';subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),str(source),'-o',str(exe)],check=True)
        result=subprocess.run([str(exe),str(ROOT),str(reference)],capture_output=True,text=True)
        (OUT/'reference.json').write_bytes(reference.read_bytes())
        files=[next((ROOT/'local-only/site/_next/static/chunks').glob('9737.*.js')),ROOT/'local-only/site/game/native/foot-animation.json']
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
            'sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in inputs.items()},'dataHashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
            'limits':['Ordinary actual archived-expression execution; no REA capture ID or retail runtime','Recent-stun movement latch e7 held false; current native task ownership/jetpack tests are independent invariants']},indent=2)+'\n')
        print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
if __name__=='__main__':main()
