#!/usr/bin/env python3
"""Replay public bA.eu/ed boarding phases against every archived seat."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{archivedModules}=require(path.join(process.cwd(),'smoke_vehicle_dynamics'));
(async()=>{
 const load=archivedModules(),factory=load.factories[49368],g=factory.constructor('return globalThis')(),Bytes=factory.constructor('return Uint8Array')();
 g.fetch=async url=>{const bytes=fs.readFileSync(path.join(process.cwd(),'local-only/site',url.split('?')[0]));return{ok:true,json:async()=>JSON.parse(bytes),arrayBuffer:async()=>{const a=new Bytes(bytes.length);a.set(bytes);return a.buffer}}};
 const T=load(85339),api=load(49368),ped=await api.av(),models=JSON.parse(fs.readFileSync('local-only/site/game/native/riders.json')).models,physics=JSON.parse(fs.readFileSync('local-only/site/game/native/vehicles.physics.json')).models;
 const source=fs.readFileSync('local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js','utf8'),common=source.slice(source.indexOf('ee=()=>-p.origin+o.lift'),source.indexOf(',ea=()=>',source.indexOf('ee=()=>-p.origin+o.lift'))),start=source.indexOf('eu=function(e){var t,l,n,a,o;'),phases=source.slice(start,source.indexOf(',ep=()=>',start));
 const make=factory.constructor('d','h','m','f','p','r','b_','I','o','bl','t','M',`let v=new d.Pq0;let ${common};let ${phases};return {enter:eu,leave:ed}`),clips={},lengths={},roots={},rows=[];
 async function clip(name){if(!name)return null;name=name.replace(':','/');if(clips[name])return clips[name];const[block,key]=name.split('/'),p=api.iA((block==='ped'?ped.clips:await api.nN(block)).get(key));if(!p)return null;p.name=name;clips[name]=p;lengths[name]=p.duration;const out=new T.Pq0,q=new T.PTz;roots[name]=[0,p.duration].map(at=>{if(p.root?.places)api.XM(p.root,at,q,out);else out.set(0,0,0);return out.toArray()});return p}
 const root=(p,time,out)=>{if(p?.root?.places)api.XM(p.root,time,new T.PTz,out);else out.set(0,0,0);return out};
 for(const[id,model]of Object.entries(models)){
  const group=model.group,h={group,astride:model.astride,afloat:physics[id].kind==='boat',shuffle:await clip(group.shuffle),crawl:null},seats=model.seats.map(s=>({...s,at:new T.Pq0(...s.at),via:s.via?new T.Pq0(...s.via):null}));
  for(const role of['open','openRear','getIn','getInRear','pullOut','closeIn','closeInRear','getOut','getOutRear','closeOut','closeOutRear'])h[role]=await Promise.all(group[role].map(clip));
  for(let seat=0;seat<seats.length;seat++)for(const side of[-1,1]){
   for(const jack of[false,true])for(const opened of[0,.5,1]){
    const original=make(T,h,seats,seats[seat],{origin:model.origin},()=>opened,root,new T.Pq0,{lift:1},()=> 'door',null,new T.Pq0);
    const phases=original.enter(side,jack).map(p=>({...p,clip:p.clip.name,anchor:p.anchor.toArray()}));rows.push({id,seat,side,jack,opened,enter:true,expected:phases});
   }
   for(const leaveOpen of[false,true]){
    const original=make(T,h,seats,seats[seat],{origin:model.origin},()=>0,root,new T.Pq0,{lift:1},()=> 'door',null,new T.Pq0);
    const phases=original.leave(side,null,leaveOpen).map(p=>({...p,clip:p.clip.name,anchor:p.anchor.toArray()}));rows.push({id,seat,side,leaveOpen,enter:false,expected:phases});
   }
  }
 }
 fs.writeFileSync(process.argv[2],JSON.stringify({models,physics:Object.fromEntries(Object.entries(physics).map(([id,p])=>[id,{kind:p.kind}])),lengths,roots,rows}));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
'''
SWIFT=r'''
let doc=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [String:Any],models=doc["models"] as! [String:[String:Any]],physics=doc["physics"] as! [String:[String:Any]],lengths=doc["lengths"] as! [String:NSNumber],roots=doc["roots"] as! [String:[[NSNumber]]],rows=doc["rows"] as! [[String:Any]]
func vector(_ a:[NSNumber])->SIMD3<Double>{SIMD3(a[0].doubleValue,a[1].doubleValue,a[2].doubleValue)}
let planner=NativeBoardingAnimation(duration:{lengths[$0]?.doubleValue},root:{name,time in let rows=roots[name]!,values=rows[time>0 ? 1:0];return vector(values)})
var checks=0,largest:Double=0
func equal(_ a:Double,_ b:Double,_ label:String){let error=abs(a-b);largest=max(largest,error);assert(error<0.000000001,"\(label):\(a) vs \(b),\(error)");checks+=1}
for row in rows{
 let id=row["id"] as! String,model=models[id]!,group=model["group"] as! [String:Any],seat=(row["seat"] as! NSNumber).intValue,side=(row["side"] as! NSNumber).intValue,expected=row["expected"] as! [[String:Any]]
 let seats=(model["seats"] as! [[String:Any]]).map{NativeBoardingAnimation.Seat(at:vector($0["at"] as! [NSNumber]),side:($0["side"] as! NSNumber).intValue,rear:$0["rear"] as! Bool,opens:$0["opens"] as! Bool,door:($0["door"] as? NSNumber)?.intValue,via:($0["via"] as? [NSNumber]).map(vector))}
 var clips:[String:[String]]=[:]
 for(key,value)in group{if let paths=value as? [String]{clips[key]=paths.map{$0.replacingOccurrences(of:":",with:"/")}}}
 func n(_ key:String)->Double{(group[key] as! NSNumber).doubleValue};func a(_ key:String)->[Double]{(group[key] as! [NSNumber]).map(\.doubleValue)}
 let config=NativeBoardingAnimation.Configuration(seats:seats,seat:seat,origin:(model["origin"] as! NSNumber).doubleValue,astride:model["astride"] as! Bool,afloat:physics[id]!["kind"] as! String=="boat",clips:clips,shuffle:(group["shuffle"] as? String).flatMap{$0.isEmpty ? nil:$0.replacingOccurrences(of:":",with:"/")},getInTime:n("getInTime"),getOutTime:n("getOutTime"),special:Int(n("special")),doorOpenOut:a("doorOpenOut"),doorCloseIn:a("doorCloseIn"),doorOpenIn:a("doorOpenIn"),doorCloseOut:a("doorCloseOut"))
 let actual=(row["enter"] as! Bool) ? planner.enter(config,side:side,jack:row["jack"] as! Bool,doorOpen:(row["opened"] as! NSNumber).doubleValue):planner.leave(config,side:side,leaveOpen:row["leaveOpen"] as! Bool)
 assert(actual.phases.count==expected.count,"\(id) seat\(seat) side\(side) phase count \(actual.phases.count) vs \(expected.count)")
 for(index,phase)in actual.phases.enumerated(){let want=expected[index];assert(phase.clip==want["clip"] as! String,"clip");let v=vector(want["anchor"] as! [NSNumber]);for axis in 0..<3{equal(phase.anchor[axis],v[axis],"\(id) seat\(seat) phase\(index) anchor")};for(key,value)in[("lower",phase.lower),("door",phase.door)]{if let value{let q=(want[key] as! [NSNumber]).map(\.doubleValue);for axis in 0..<4{equal(value[axis],q[axis],"\(id) \(key)")}}else{assert(want[key]==nil || want[key] is NSNull,"unexpected \(key)")}};assert(phase.part==(want["part"] as? NSNumber)?.intValue);assert(phase.quits==(want["quits"] as? Bool ?? false));assert(phase.closes==(want["closes"] as? Bool ?? false))}
}
print("PASS: \(rows.count) actual browser boarding/exit phase plans across every archived seat; \(checks) anchor/door/lowering checks, maxerror \(largest)m")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-boarding-animation-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  (work/'verify.swift').write_text((ROOT/'ios/App/NativeBoardingAnimation.swift').read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
