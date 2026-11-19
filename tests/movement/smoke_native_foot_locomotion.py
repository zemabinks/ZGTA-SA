#!/usr/bin/env python3
"""Exercise original 9737 input acceleration/facing/root-coordinate clauses."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),source=fs.readFileSync(process.argv[2],'utf8');
const begin=source.indexOf('let tv=Math.min(1,tm?'),end=source.indexOf(';tc=(Y=e9',begin),control=source.slice(begin,end);
const step=source.indexOf('let k=af(G-W),j=L*e;'),turnBegin=source.indexOf('if(',step)+3,turnEnd=source.indexOf(',ed=',turnBegin),turn=source.slice(turnBegin,turnEnd);
const ratioBegin=source.indexOf('K+=d.cj9.clamp(V-K',turnEnd),ratioEnd=source.indexOf(',el=',ratioBegin),ratio=source.slice(ratioBegin,ratioEnd);
if(begin<0||end<0||step<0||ratioBegin<0)throw Error('Original locomotion clauses not found');
const script=`(()=>{let V=0,K=0,J=0,eX={x:0,y:0},W=0,G=0,eJ=false;const af=x=>((x+Math.PI)%(2*Math.PI)+2*Math.PI)%(2*Math.PI)-Math.PI,d={cj9:{clamp:(x,a,b)=>Math.min(b,Math.max(a,x))}},rX=128/60,rZ=.07*50,r2=.07*50;return(p,l)=>{
 let er=p.stick[0],ea=p.stick[1],eP=-p.cameraHeading,tm=p.crouching&&p.aiming,e5=p.gunUp,eU=p.throwing?'throw':p.isGun?'gun':'launch',eB={flags:{arm:p.armAim,moveFire:p.movingFire,moveAim:p.movingAim}},eE=p.crouching,eR=p.aiming,eV=p.hipFire,es=eR&&p.armAim&&!eE,eC=p.throwing,eW=p.swinging,eG=p.stunned,eD=false,ex=p.guardStance,eS=p.poise,eL=p.attackHeld,ei=!!p.walking,eQ=false,ek=false,eo=false,tK={x:0,y:0};
 const C={busy:p.busy,rolling:p.rolling,gunShooting:p.gunShooting,firing:p.throwing};let e3=Math.hypot(er,ea)>0,e4=e5&&!eB.flags.arm&&!eE;eJ&&!e4&&(V=K=+!!e3);eJ=e4;
 ${control};
 let e=l,L=p.turningRate,et=-1,Z=p.air?1:0,e_=false,ez=false;
 let k=af(G-W),j=L*e;void(${turn});${ratio};
 return{ratio:K,heading:-W,strafe:eR&&!es||ex?[tK.x,tK.y]:null,pushing:eo};}})()`;
const original=vm.runInNewContext(script),cases=[];
for(let i=0;i<5600;i++){
 const mode=Math.floor(i/140)%10,p={stick:i%140<110?[Math.sin(i*.019)*.9,Math.cos(i*.019)*.9]:[0,0],cameraHeading:Math.sin(i*.013)*2.4,walking:i>=2800&&i%211>=100,aiming:mode>=2,crouching:mode===3||mode===7,guardStance:mode===4,gunUp:mode>=5,armAim:mode===6||mode===7,movingAim:mode!==8,movingFire:mode!==9,gunShooting:i%100>=20&&i%100<80,attackHeld:i%100>=20&&i%100<80,isGun:mode!==1,hipFire:mode===9,poise:mode===4&&i%50>30,busy:i%217>200,stunned:i%311>300,rolling:i%433>420,swinging:mode===1&&i%90>40,air:i%500>460,turningRate:6.544984694978735,throwing:mode===1&&i%90<20,heavy:false},delta=[1/60,1/50,1/75][i%3];
 cases.push({input:p,delta,expected:original(p,delta)});
}
fs.writeFileSync(process.argv[3],JSON.stringify(cases));
'''
SWIFT=r'''
let cases=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [[String:Any]]
let motor=NativeFootLocomotion()
for (frame,row) in cases.enumerated(){
 let p=row["input"] as! [String:Any],expected=row["expected"] as! [String:Any],xy=p["stick"] as! [NSNumber]
 func n(_ key:String)->Double{(p[key] as! NSNumber).doubleValue};func b(_ key:String)->Bool{p[key] as! Bool}
 var input=NativeFootLocomotion.Input();input.stick=SIMD2(xy[0].doubleValue,xy[1].doubleValue);input.cameraHeading=n("cameraHeading");input.walking=b("walking");input.aiming=b("aiming");input.crouching=b("crouching");input.guardStance=b("guardStance");input.gunUp=b("gunUp");input.armAim=b("armAim");input.movingAim=b("movingAim");input.movingFire=b("movingFire");input.gunShooting=b("gunShooting");input.attackHeld=b("attackHeld");input.isGun=b("isGun");input.hipFire=b("hipFire");input.poise=b("poise");input.busy=b("busy");input.stunned=b("stunned");input.rolling=b("rolling");input.swinging=b("swinging");input.air=b("air");input.turningRate=n("turningRate");input.throwing=b("throwing")
 let actual=motor.update(delta:(row["delta"] as! NSNumber).doubleValue,input:input)
 let heading=(expected["heading"] as! NSNumber).doubleValue,difference=atan2(sin(actual.heading-heading),cos(actual.heading-heading))
 assert(abs(actual.ratio-(expected["ratio"] as! NSNumber).doubleValue)<0.000000001,"frame \(frame) ratio")
 assert(abs(difference)<0.000000001,"frame \(frame) heading \(actual.heading) JS \(heading)")
 assert(actual.pushing==expected["pushing"] as! Bool,"pushing")
 if let vector=expected["strafe"] as? [NSNumber]{assert(actual.strafe != nil && simd_distance(actual.strafe!,SIMD2(vector[0].doubleValue,vector[1].doubleValue))<0.000000001,"frame \(frame) strafe")}
 else {assert(actual.strafe==nil,"unexpected strafe")}
}
for angle in [-3.0,-1,0,1,3]{let v=NativeFootLocomotion.worldTravel(SIMD2(0.4,1.2),heading:angle);assert(abs(Double(v.x)-(cos(angle)*0.4+sin(angle)*1.2))<0.000001);assert(abs(Double(v.y)-(-sin(angle)*0.4+cos(angle)*1.2))<0.000001)}
print("PASS: \(cases.count) actual 9737 acceleration/facing/strafe/walk-modifier frames and GTA root-travel rotation")
'''
def main():
 source=next(p for p in (ROOT/'local-only/site/_next/static/chunks').glob('*.js') if 'let tv=Math.min(1,tm?' in p.read_text())
 with tempfile.TemporaryDirectory(prefix='zgta-foot-locomotion-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(source),str(work/'reference.json')],check=True)
  helper=FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]
  (work/'verify.swift').write_text((ROOT/'ios/App/NativeFootLocomotion.swift').read_text()+helper+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
