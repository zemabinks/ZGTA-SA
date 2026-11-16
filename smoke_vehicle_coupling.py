#!/usr/bin/env python3
"""Actual archived working state + native confirmed coupling/pool lifecycle.

Original resources and selected executable probes stay in ignored local-only.
This does not run an original retail executable or claim physical-device feel.
"""
from pathlib import Path
import hashlib,json,os,platform,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/vehicle-coupling'
NAMES=['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeVehicleCoupling']
JS=r'''
const fs=require('node:fs'),{archivedModules}=require('./smoke_vehicle_dynamics');
const load=archivedModules(),T=load(85339),source=load.factories[19737].toString();
const start=source.indexOf('uu=function(){let e=new d.Pq0'),end=source.indexOf('}(),',start)+3;
if(start<0||end<=start)throw Error('Archived working controller unavailable');
const expression=source.slice(start+3,end),catalog=require('./local-only/selfhost/coupling-catalog.json'),rows=[];
for(const [id,row]of Object.entries(catalog.models).filter(([_,r])=>r.working))for(const hz of [15,30,60,120,144])for(const initial of [0,1250,2500]){
 const make=Function('d','vn','vd','vh','return ('+expression+');');
 let posed=0;const controller=make(T,{[id]:row.working},v=>Number.isFinite(v)?T.cj9.clamp(v,0,2500):0,(_e,value)=>{posed=value});
 controller.seat(Number(id),initial);
 const built={id:Number(id),origin:row.origin,bounds:{box:{min:row.minimum,max:row.maximum}}},frames=[];
 for(let frame=0;frame<hz*8;frame++){
  const seconds=frame/hz,pad=seconds<2?-1:seconds<4?1:seconds<5?0:seconds<6?.07:seconds<7?-.08:.4;
  controller.drive(1/hz,{built,group:new T.YJl(),pad,vehicles:{hitchedAt:()=>null},solid:null,physics:null});
  frames.push({pad,value:controller.left(Number(id)),precise:posed,kit:controller.kit});
 }
 rows.push({id:Number(id),hz,initial,frames});
}
const plates=[];
for(const value of [0,1,500,1250,2499,2500]){
 const shapes=[],profile=catalog.models[530],controller=Function('d','vn','vd','vh','return ('+expression+');')(T,{530:profile.working},v=>Number.isFinite(v)?T.cj9.clamp(v,0,2500):0,()=>{});
 const world={createCollider(descriptor){shapes.push(descriptor);return{isValid:()=>true,setTranslationWrtParent(v){descriptor.position=[v.x,v.y,v.z]}}},removeCollider(){}};
 const physics={world,RAPIER:{ColliderDesc:{cuboid(x,y,z){const row={half:[x,y,z]};for(const key of ['Density','Friction','Restitution','CollisionGroups','SolverGroups'])row['set'+key]=function(value){this[key]=value;return this};return row}}}};
 controller.seat(530,value);controller.drive(1/60,{built:{id:530,origin:profile.origin,bounds:{box:{min:profile.minimum,max:profile.maximum}}},group:new T.YJl(),pad:0,solid:{rigid:{},solids:[{collisionGroups:()=>8454127,solverGroups:()=>33554944}]},physics});
 plates.push({value,shapes:shapes.map(s=>({half:s.half,position:s.position,friction:s.Friction,restitution:s.Restitution,density:s.Density}))});
}
const controlsStart=source.indexOf('v6={nobody:!0,abandoned:!0'),controlsEnd=source.indexOf(',kt=e=>',controlsStart);
if(controlsStart<0||controlsEnd<controlsStart)throw Error('Original unattended input constants unavailable');
const controls=Function('let '+source.slice(controlsStart,controlsEnd)+';return {base:v6,braked:v8,held:ke,riderless:v9,riderlessBraked:v7};')();
const {createLibrary}=require('./prepare_native_vehicle_rigs'),library=createLibrary(),moving=[];
const vhStart=source.indexOf('function vh(e,t){'),vhEnd=source.indexOf('var vm=l(39851)',vhStart),vh=source.slice(vhStart,vhEnd);
if(vhStart<0||vhEnd<vhStart)throw Error('Original working collision transform unavailable');
for(const id of [406,443,486,530]){
 const profile=catalog.models[id],built=library.build(id);built.origin=built.root.position.y;built.collision=built.parsed.collision;
 const invoke=Function('d','vn','vd','vo','vl','let vi=new d.Pq0,vs=new d.Pq0,vc=new d.kn4,vu=new d.kn4;return ('+vh+');')(T,{[id]:profile.working},v=>Number.isFinite(v)?T.cj9.clamp(v,0,2500):0,(e,_spec,v)=>built.coupling.pose(e,v),{WQ:load(58683).WQ});
 const frames=[];
 for(const value of [0,1,100,1250,2499,2500]){
  const shapes=profile.working.movingShapes.map(shape=>({at:new T.Pq0(...shape.at),index:shape.index,position:null}));
  const solids={moving:shapes.map(shape=>({at:shape.at,collider:{isValid:()=>true,setTranslationWrtParent(v){shape.position=[v.x,v.y,v.z]}}}))};
  invoke(built,value,solids);frames.push({value,shapes:shapes.map(({index,position})=>({index,position}))});
 }
 moving.push({id,frames});library.geometry.xd(built.root,null);
}
fs.writeFileSync(process.argv[1],JSON.stringify({sourceSHA256:require('node:crypto').createHash('sha256').update(expression).digest('hex'),rows,plates,controls,moving}));
'''

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    catalog=ROOT/'local-only/selfhost/coupling-catalog.json'
    if not catalog.exists():subprocess.run(['node','prepare_native_vehicle_coupling.js'],cwd=ROOT,check=True)
    paths=[ROOT/'ios/App'/(name+'.swift') for name in NAMES]+[ROOT/'native-physics/include/ZGTARapier.h',ROOT/'smoke_vehicle_coupling.swift',Path(__file__),ROOT/'prepare_native_vehicle_coupling.js']
    snapshot={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temporary:
        work=Path(temporary);reference=work/'working.json'
        subprocess.run(['node','-e',JS,str(reference)],cwd=ROOT,check=True)
        sources=[]
        for name in NAMES:
            p=work/(name+'.swift');p.write_bytes(snapshot['ios/App/'+name+'.swift']);sources.append(str(p))
        main=work/'main.swift';main.write_bytes(snapshot['smoke_vehicle_coupling.swift']);sources.append(str(main));exe=work/'verify'
        environment=os.environ.copy();environment.pop('SDKROOT',None)
        result=subprocess.run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-target',platform.machine()+'-apple-macosx13.0','-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(exe)],env=environment,capture_output=True,text=True)
        (OUT/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(exe),str(ROOT),str(reference)],capture_output=True,text=True)
        unchanged=all((ROOT/name).read_bytes()==value for name,value in snapshot.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','output':result.stdout+result.stderr,'sourceUnchanged':unchanged,
                'sourceHashes':{name:hashlib.sha256(value).hexdigest() for name,value in snapshot.items()},'catalogSHA256':hashlib.sha256(catalog.read_bytes()).hexdigest(),
                'referenceSHA256':hashlib.sha256(reference.read_bytes()).hexdigest(),
                'limits':['Actual archived working scalar controller; no original retail executable or physical-device test',
                          'Coupling uses independent confirmed topology, not the archived client optimistic network policy']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged,'Source changed during test'
if __name__=='__main__':main()
