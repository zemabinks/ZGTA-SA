#!/usr/bin/env python3
"""Actual browser rotor-coast reference and native aircraft ownership tests.

References/model metadata stay local-only; no app, SDK or Rust library rebuild.
"""
from pathlib import Path
import os,platform,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),{archivedModules}=require('./smoke_vehicle_dynamics'),stop=archivedModules()(89888).s2,rows=[];
for(const kind of ['heli','plane'])for(const fps of [15,30,60,120])for(const initial of [0,.04,.179,.18,.181,.22,.34,.5]){
 let value=initial,frames=[];for(let step=0;step<fps*3;step++){value=stop(kind,value,50/fps);frames.push(value)}
 rows.push({kind,fps,initial,frames});
}
fs.writeFileSync(process.argv[1],JSON.stringify(rows));
'''
def renderer_glue():
 source=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 start=source.index('            if let kit=player?.kit {')
 parked=source.index('            if player==nil,let parked,let frame=groundVehicle?.otherVehicle(parked.id) {',start)
 brace=source.index('{',parked);depth=1;end=brace+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 # Compile the actual consecutive remote-kit/parked clauses, with the actual
 # production rig Input and real NativeOtherVehicles snapshots. Only the outer
 # Metal renderer/player containers are reduced to the fields these clauses use.
 clauses=source[start:end]
 return '''
import Foundation
struct RendererAirPlayer {var kit:[Float]}
struct RendererParkedVehicle {var id:String}
struct RendererAirRig {struct Joints {var working:NativeVehicleRig.Working?=nil};struct Document {var id:Int;var joints=Joints()};var document:Document}
func rendererAirInput(_ vehicle:NativeGroundVehicle?,id:String?,player:RendererAirPlayer?,model:Int,initial:NativeVehicleRig.Input)->NativeVehicleRig.Input {
 let groundVehicle=vehicle,parked=id.map{RendererParkedVehicle(id:$0)},rig=RendererAirRig(document:.init(id:model))
 var input=initial
'''+clauses+'''
 return input
}
'''
def main():
 out=ROOT/'local-only/native-physics/tests/vehicle-air-handoff';out.mkdir(parents=True,exist_ok=True)
 machine=platform.machine();assert machine in ['arm64','x86_64']
 names=['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeVehicleRig']
 with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as temporary:
  work=Path(temporary);reference=work/'reference.json'
  subprocess.run(['node','-e',JS,str(reference)],cwd=ROOT,check=True)
  sources=[]
  for name in names:
   target=work/(name+'.swift');shutil.copyfile(ROOT/'ios/App'/target.name,target);sources.append(str(target))
  (work/'main.swift').write_text(renderer_glue()+(ROOT/'smoke_vehicle_air_handoff.swift').read_text())
  environment=os.environ.copy();environment.pop('SDKROOT',None)
  subprocess.run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-target',machine+'-apple-macosx13.0','-module-cache-path',str(ROOT/'local-only/native-physics/swift-module-cache'),'-I',str(ROOT/'native-physics/include'),*sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-physics/macos-'+machine)),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],env=environment,check=True)
  subprocess.run([str(work/'verify'),str(ROOT),str(reference)],check=True)
if __name__=='__main__':main()
