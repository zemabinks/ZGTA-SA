#!/usr/bin/env python3
"""Original wY train layout plus actual Renderer owned/remote/parked collection."""
from pathlib import Path
import os,platform,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),load=require('./smoke_vehicle_dynamics').archivedModules(),T=load(85339),trains=load(91584);
(async()=>{
 load.e=async id=>{if(id!==1873)throw Error('Unexpected import')};load.t=id=>({default:load(id)});await trains.fX();
 const models=JSON.parse(fs.readFileSync('local-only/site/game/native/vehicles.physics.json')).models,rows=[];
 const gta=v=>[v.x,-v.z,v.y],vector=v=>[v.x,v.y,v.z],qv=q=>[q.x,q.y,q.z,q.w];
 function matrix(p,q,origin){const x=new T.Pq0(1,0,0).applyQuaternion(q),y=new T.Pq0(0,0,-1).applyQuaternion(q),z=new T.Pq0(0,1,0).applyQuaternion(q),at=p.clone().addScaledVector(z,origin);return [...gta(x),0,...gta(y),0,...gta(z),0,...gta(at),1].map(Math.fround)}
 for(const model of [537,538,449])for(const node of [0,36,100,300,500,900])for(const direction of [-1,1])for(const tilted of [false,true]){
  const config=models[model],line=model===449?trains.ZF().find(l=>l.tram):trains.ZF()[0],p=new T.Pq0().fromArray(line.points,(node%line.count)*3),nearest=trains.VO(model,p);
  const yaw=Math.atan2(-nearest.way.x,-nearest.way.z)+(direction<0?Math.PI:0),heading=Math.fround(-yaw),pitch=Math.fround(tilted?.04:0),roll=Math.fround(tilted?-.025:0),q=new T.PTz().setFromEuler(new T.O9p(pitch,-heading,-roll,'YXZ'));
  q.set(...qv(q).map(Math.fround));const expected=[],configs=(trains.Wm[model]||[]).map(id=>({...models[id],id:String(id)}));
  trains.wY({...config,id:String(model)},p,q,configs,(i,position,rotation)=>expected.push({model:String(configs[i].id),matrix:matrix(position,rotation,configs[i].origin)}),{});
  rows.push({model:String(model),position:gta(p),physicalPosition:vector(p),rotation:qv(q),heading,pitch,roll,expected});
 }
 fs.writeFileSync(process.argv[1],JSON.stringify(rows));
})().catch(e=>{console.error(e.stack);process.exitCode=1});
'''
def renderer_collection():
 source=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 start=source.index('        var parkedTransforms:[String:simd_float4x4] = [:]',source.index('    private func drawActors'))
 end=source.index('        for (name, position, angle, pitch, clip, elapsed, weapon) in modelInstances {',start)
 return '''
import Foundation
import simd
struct RemoteVehicle {var id:String;var code:String;var position:SIMD3<Float>;var heading:Float;var pitch:Float=0;var roll:Float=0}
struct TrainLayoutPlayer {var vehicleID:String?;var code:String;var position:SIMD3<Float>;var heading:Float;var pitch:Float=0;var roll:Float=0}
struct TrainDrawPlan {var matrices:[String:simd_float4x4];var identities:[String:String];var instances:Int}
func rendererTrainPlan(_ groundVehicle:NativeGroundVehicle?,driving:Bool,currentVehicleID:String?,camera:SIMD3<Float>,remoteVehicles:[RemoteVehicle],remotePlayers:[TrainLayoutPlayer],models:[String:String])->TrainDrawPlan {
 var modelInstances:[(String,SIMD3<Float>,Float,Float,String,Double,Int)]=[]
 var vehicleAppearanceCodes:[String:[String]]=[:]
 let drivenVehicleIDs=Set(remotePlayers.compactMap(\\.vehicleID))
 func actorName(code:String)->String? {models[String(code.split(separator: ".").first ?? "")]}
 func key(_ name:String,_ p:SIMD3<Float>)->String {"\\(name):\\(p.x):\\(p.y):\\(p.z)"}
 func predictedVehicle(_ raw:RemoteVehicle)->RemoteVehicle {
  guard let frame=groundVehicle?.otherVehicle(raw.id) else{return raw};var out=raw
  out.position=frame.position;out.heading=frame.heading;out.pitch=frame.pitch;out.roll=frame.roll;return out
 }
'''+source[start:end]+'''
 return TrainDrawPlan(matrices:carriageTransforms,identities:carriageIdentifiers,instances:modelInstances.count)
}
'''
def main():
 out=ROOT/'local-only/native-physics/tests/train-layout';out.mkdir(parents=True,exist_ok=True)
 machine=platform.machine();assert machine in ['x86_64','arm64']
 names=['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics']
 with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as tmp:
  work=Path(tmp);reference=work/'reference.json';subprocess.run(['node','-e',JS,str(reference)],cwd=ROOT,check=True)
  sources=[]
  for name in names:
   target=work/(name+'.swift');shutil.copyfile(ROOT/'ios/App'/target.name,target);sources.append(str(target))
  (work/'main.swift').write_text(renderer_collection()+(ROOT/'smoke_train_layout.swift').read_text())
  env=os.environ.copy();env.pop('SDKROOT',None)
  subprocess.run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-target',machine+'-apple-macosx13.0','-module-cache-path',str(ROOT/'local-only/native-physics/swift-module-cache'),'-I',str(ROOT/'native-physics/include'),*sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-physics/macos-'+machine)),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],env=env,check=True)
  subprocess.run([str(work/'verify'),str(ROOT),str(reference)],check=True)
if __name__=='__main__':main()
