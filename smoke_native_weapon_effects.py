#!/usr/bin/env python3
"""Compare native projectile trajectories with the archived browser manager.

The browser manager executes with minimal vector/scene adapters and a flat
ground ray. Native Swift runs its actual helper against those same cases.
No browser assets or copied JavaScript are written outside temporary files.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent

JAVASCRIPT = r'''
const fs=require('node:fs'),vm=require('node:vm');
const text=fs.readFileSync(process.argv[2],'utf8'),a=text.indexOf('let cY=function(e)'),b=text.indexOf('}({scene:',a);
const segment=text.slice(a,b+1).replace('return{lob(e,t,l)', 'return{__list:()=>p,__fires:()=>h,lob(e,t,l)');
const constants=text.slice(text.indexOf('kf={16:'),text.indexOf(',kv=function',text.indexOf('kf={16:')));
class V {constructor(x=0,y=0,z=0){this.set(x,y,z)}set(x,y,z){this.x=x;this.y=y;this.z=z;return this}copy(v){return this.set(v.x,v.y,v.z)}clone(){return new V(this.x,this.y,this.z)}multiplyScalar(v){this.x*=v;this.y*=v;this.z*=v;return this}add(v){this.x+=v.x;this.y+=v.y;this.z+=v.z;return this}addScaledVector(v,n){this.x+=v.x*n;this.y+=v.y*n;this.z+=v.z*n;return this}subVectors(a,b){return this.set(a.x-b.x,a.y-b.y,a.z-b.z)}sub(v){return this.subVectors(this,v)}length(){return Math.hypot(this.x,this.y,this.z)}lengthSq(){return this.dot(this)}normalize(){return this.multiplyScalar(1/(this.length()||1))}dot(v){return this.x*v.x+this.y*v.y+this.z*v.z}angleTo(v){return Math.acos(Math.max(-1,Math.min(1,this.dot(v)/(this.length()*v.length()))))}lerp(v,n){return this.set(this.x+(v.x-this.x)*n,this.y+(v.y-this.y)*n,this.z+(v.z-this.z)*n)}distanceTo(v){return Math.hypot(this.x-v.x,this.y-v.y,this.z-v.z)}distanceToSquared(v){return (this.x-v.x)**2+(this.y-v.y)**2+(this.z-v.z)**2}round(){this.x=Math.round(this.x);this.y=Math.round(this.y);this.z=Math.round(this.z);return this}setY(y){this.y=y;return this}}
V.prototype.divideScalar=function(value){return this.multiplyScalar(1/value)};
class Group {constructor(){this.position=new V;this.quaternion={};this.visible=true}add(){}removeFromParent(){}rotateX(){}lookAt(){}}
const sandbox={d:{YJl:Group,Pq0:V,PTz:class{},tBo:class{},kn4:class{},cj9:{clamp:(v,a,b)=>Math.max(a,Math.min(b,v))}},fw:{ZQ:18},F:{cm:()=>Promise.reject(0)},console};
vm.createContext(sandbox);vm.runInContext('let '+constants+';'+segment+';globalThis.factory=cY;',sandbox);
const gta=v=>[v.x,-v.z,v.y],vec=v=>new V(v[0],v[2],-v[1]);
const cases=[
{name:'grenade_arc',weapon:16,start:[0,10,20],direction:[1,0,0],dt:.125,steps:8},
{name:'grenade_fuse',weapon:16,start:[0,10,100],direction:[1,0,0],dt:.125,steps:16},
{name:'rocket_flight',weapon:35,start:[2,3,10],direction:[1,0,0],dt:.125,steps:8},
{name:'rocket_expiry',weapon:35,start:[2,3,100],direction:[1,0,0],dt:.125,steps:40},
{name:'rocket_carry',weapon:35,start:[2,3,10],direction:[1,0,0],carry:[3,4,2],dt:.125,steps:8},
{name:'grenade_bounce',weapon:16,start:[0,0,.2],direction:[1,0,-1],dt:.125,steps:1,ground:true},
{name:'molotov_contact',weapon:18,start:[0,0,.2],direction:[1,0,-1],dt:.125,steps:1,ground:true},
{name:'satchel_stick',weapon:39,start:[0,0,.2],direction:[1,0,-1],dt:.125,steps:1,ground:true},
{name:'seeker',weapon:36,start:[0,0,10],direction:[1,0,0],dt:.125,steps:8,target:[50,30,10]}
];
for(const c of cases){const events=[];const feel=(p,d,len)=>{if(!c.ground||d.y>=0)return null;const distance=-p.y/d.y;return distance>=0&&distance<=len?{distance,normal:new V(0,1,0)}:null};
const manager=sandbox.factory({scene:{add(){},remove(){}},feel,onBoom:(weapon,position)=>events.push({weapon,position:gta(position)})});
const direction=vec(c.direction).normalize();if([35,36].includes(c.weapon))manager.launch(c.weapon,vec(c.start),direction,null,{carry:c.carry?vec(c.carry):null});else manager.lob(c.weapon,vec(c.start),direction);
const cars=c.target?[{id:'target',position:vec(c.target)}]:[];
for(let i=0;i<c.steps;i++)manager.update(c.dt,{cars});
c.expected={projectiles:manager.__list().map(p=>({position:gta(p.holder.position),velocity:gta(p.velocity),stuck:p.stuck,lying:p.lying})),events};}
fs.writeFileSync(process.argv[3],JSON.stringify(cases));
'''

SWIFT = r'''
func vector(_ value: Any) -> SIMD3<Float> {
    let row = value as! [NSNumber]; return SIMD3(row[0].floatValue,row[1].floatValue,row[2].floatValue)
}
func close(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, _ context: String) {
    assert(simd_distance(actual,expected) < 0.005, "\(context): \(actual) != \(expected)")
}
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String:Any]]
for value in cases {
    let helper = NativeWeaponEffects()
    let name = value["name"] as! String
    let weapon = value["weapon"] as! Int
    var events: [NativeWeaponEffects.Detonation] = []
    helper.onDetonation = { events.append($0) }
    if value["ground"] as? Bool == true {
        helper.trace = { p,d,length in
            guard d.z < 0 else {return nil};let distance = -p.z/d.z
            return distance>=0 && distance<=length ? NativeWeaponEffects.Contact(distance: distance,normal: SIMD3(0,0,1)) : nil
        }
    }
    let start = vector(value["start"]!)
    let way = simd_normalize(vector(value["direction"]!))
    if weapon==35 || weapon==36 {
        var carry = SIMD3<Float>.zero
        if let row = value["carry"] { carry = vector(row) }
        helper.launch(weapon: weapon,from: start,direction: way,carry: carry)
    } else {helper.lob(weapon: weapon,from: start,direction: way)}
    var vehicles: [NativeWeaponEffects.Target] = []
    if let target = value["target"] { vehicles = [NativeWeaponEffects.Target(id:"target",position:vector(target))] }
    for _ in 0..<(value["steps"] as! Int) {helper.update(delta:(value["dt"] as! NSNumber).floatValue,vehicles:vehicles)}
    let expected = value["expected"] as! [String:Any]
    let projectiles = expected["projectiles"] as! [[String:Any]]
    let referenceEvents = expected["events"] as! [[String:Any]]
    assert(helper.projectiles.count==projectiles.count,"\(name) count")
    for (actual,reference) in zip(helper.projectiles,projectiles) {
        close(actual.position,vector(reference["position"]!),name+" position")
        close(actual.velocity,vector(reference["velocity"]!),name+" velocity")
        assert(actual.stuck == (reference["stuck"] as! Bool))
        assert(actual.lying == (reference["lying"] as! Bool))
    }
    assert(events.count==referenceEvents.count,"\(name) events")
    for (actual,reference) in zip(events,referenceEvents) {close(actual.position,vector(reference["position"]!),name+" detonation")}
}
let grenade=NativeWeaponEffects.blast(weapon:16,position:SIMD3(0,0,0.9))
assert(grenade.damage(atFeet:.zero)==82.5)
assert(abs(grenade.damage(atFeet:SIMD3(4.5,0,0))-41.25)<0.0001)
assert(grenade.damage(atFeet:SIMD3(9,0,0))==0)
let helper=NativeWeaponEffects();var hits:[String]=[]
helper.onStreamHit={id,_ in hits.append(id)}
let targets=[NativeWeaponEffects.Target(id:"near",position:SIMD3(2,0,0)),NativeWeaponEffects.Target(id:"wide",position:SIMD3(2,1,0)),NativeWeaponEffects.Target(id:"far",position:SIMD3(8,0,0))]
helper.stream(weapon:37,from:SIMD3(0,0,0.9),direction:SIMD3(1,0,0),delta:0.1,people:targets)
assert(hits==["near"])
helper.stream(weapon:37,from:SIMD3(0,0,0.9),direction:SIMD3(1,0,0),delta:0.1,people:targets)
assert(hits.count==1)
helper.trace={_,_,_ in NativeWeaponEffects.Contact(distance:1,normal:SIMD3(-1,0,0))}
helper.stream(weapon:37,from:SIMD3(0,0,0.9),direction:SIMD3(1,0,0),delta:0.2,people:targets)
assert(hits.count==1,"blocked stream cannot hit")
helper.clear();helper.lob(weapon:39,from:.zero,direction:SIMD3(1,0,0));assert(helper.detonateSatchels());assert(helper.projectiles.isEmpty)
let snapshot = try JSONSerialization.jsonObject(with: Data("[{\"id\":\"p-14\",\"weapon\":16,\"position\":[1480.123,-1738.456,13.789],\"velocity\":[0.12,3.45,-6.78],\"age\":0.2,\"lifetime\":2}]".utf8)) as! [[String:Any]]
helper.synchronizeServer(snapshot)
assert(helper.projectiles.count == 1,"fractional JSON snapshots must reconcile")
close(helper.projectiles[0].position,SIMD3(1480.123,-1738.456,13.789),"network snapshot position")
close(helper.projectiles[0].velocity,SIMD3(0.12,3.45,-6.78),"network snapshot velocity")
print("PASS: \(cases.count) projectile paths/fuses/bounces match archived JS; radial falloff, stream cadence/occlusion and satchel detonation pass")
'''


def main():
    chunk = next(path for path in (ROOT / 'local-only/site/_next/static/chunks').glob('*.js')
                 if 'let cY=function(e)' in path.read_text())
    with tempfile.TemporaryDirectory(prefix='zgta-projectiles-') as temporary:
        work = Path(temporary)
        js = work / 'reference.js'; js.write_text(JAVASCRIPT)
        cases = work / 'cases.json'
        subprocess.run(['node', str(js), str(chunk), str(cases)], check=True)
        swift = work / 'verify.swift'
        swift.write_text((ROOT / 'ios/App/NativeWeaponEffects.swift').read_text() + SWIFT)
        subprocess.run(['swift', '-module-cache-path', str(work / 'modules'), str(swift), str(cases)], check=True)


if __name__ == '__main__':
    main()
