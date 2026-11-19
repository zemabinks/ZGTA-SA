#!/usr/bin/env python3
"""Compare all six original working-part scene hierarchies with native poses."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/working-rigs'
JS=r'''
const fs=require('node:fs'),path=require('node:path'),{createLibrary,exportRig}=require('./tools/assets/prepare_native_vehicle_rigs');
const output=process.argv[1],library=createLibrary(),cases=[];
for(const id of [406,443,486,525,530,592]){
 const built=library.build(id),metadata=exportRig(built,output,{atlas:false}),objects=[];
 built.root.userData.model.traverse(o=>objects.push(o));
 if(!metadata.joints.working)throw Error('Missing working metadata '+id);
 if(!metadata.joints.working.parts.length&&built.coupling.configuration(built).working.available)throw Error('Configured original part was not exported '+id);
 const frames=[];
 for(let n=0;n<101;n++){
  const work=n*25;built.coupling.pose(built,work);built.root.updateMatrixWorld(true);
  const inverse=built.root.matrixWorld.clone().invert();
  frames.push({work,matrices:objects.map(o=>[...inverse.clone().multiply(o.matrixWorld).elements])});
 }
 cases.push({id,model:built.definition.model,frames,parts:metadata.joints.working.parts.length});
 library.geometry.xd(built.root,null);
}
fs.writeFileSync(path.join(output,'references.json'),JSON.stringify(cases));
'''
SWIFT=r'''
import Foundation
import simd
let folder=URL(fileURLWithPath:CommandLine.arguments[1])
let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("references.json"))) as! [[String:Any]]
var checks=0,frames=0,maxError=0.0
for row in cases {
 let model=row["model"] as! String,rig=NativeVehicleRig(data:try Data(contentsOf:folder.appendingPathComponent(model+".rig.json")))!
 var state=NativeVehicleRig.State()
 for frame in row["frames"] as! [[String:Any]] {
  var input=NativeVehicleRig.Input();input.work=(frame["work"] as! NSNumber).doubleValue
  let actual=rig.pose(input,state:&state,delta:0),expected=frame["matrices"] as! [[Double]]
  precondition(actual.matrices.count==expected.count)
  for (node,matrix) in actual.matrices.enumerated(){for c in 0..<4{for a in 0..<4{
   let error=abs(matrix[c][a]-expected[node][c*4+a]);maxError=max(maxError,error);checks+=1
   precondition(error<1e-8,"Original working rig matrix differs \(model) node\(node), work\(input.work), error\(error)")
  }}};frames+=1
 }
}
print("PASS working vehicle rigs: \(checks) matrix checks, \(frames) actual archived poses for all6 working models, maximum error\(maxError)")
'''
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=[ROOT/'ios/App/NativeVehicleRig.swift',ROOT/'ios/App/NativeVehiclePaint.swift',ROOT/'tools/assets/prepare_native_vehicle_rigs.js',ROOT/'tools/assets/prepare_native_vehicle_coupling.js',Path(__file__)]
    snapshot={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp)
        subprocess.run(['node','-e',JS,str(work)],cwd=ROOT,check=True)
        (work/'main.swift').write_text(SWIFT)
        rig=work/'NativeVehicleRig.swift';rig.write_bytes(snapshot['ios/App/NativeVehicleRig.swift']);exe=work/'verify'
        paint=work/'NativeVehiclePaint.swift';paint.write_bytes(snapshot['ios/App/NativeVehiclePaint.swift'])
        result=subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-module-cache-path',str(OUT/'modules'),str(paint),str(rig),str(work/'main.swift'),'-o',str(exe)],capture_output=True,text=True)
        (OUT/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(exe),str(work)],capture_output=True,text=True)
        unchanged=all((ROOT/name).read_bytes()==data for name,data in snapshot.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','output':result.stdout+result.stderr,'sourceUnchanged':unchanged,
                'sourceHashes':{name:hashlib.sha256(data).hexdigest() for name,data in snapshot.items()},
                'limits':['Actual archived rest hierarchy/working transform comparison; no GPU, physics-tool interaction or original retail runtime claim']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
