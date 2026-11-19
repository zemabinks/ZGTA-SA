#!/usr/bin/env python3
"""Compare actual42000.ur emergency horn input to its native translation."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),source=require(process.cwd()+'/smoke_vehicle_dynamics').archivedModules()(42000).ur(),frames=[];
let time=0;
for(let i=0;i<12000;i++){
 time += [4,16,50,80,120,250,400][i%7];
 const id=i%643<500?'car-a':'car-b',emergency=i%997<800,pressed=i%23<13;
 const output=source.update(pressed,time,id,emergency);
 frames.push({id,time,emergency,pressed,output:{...output}});
}
fs.writeFileSync(process.argv[2],JSON.stringify(frames));
'''
SWIFT=r'''
let frames=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]],controller=NativeVehicleHornController()
for (index,row) in frames.enumerated(){
 let result=controller.update(pressed:row["pressed"] as! Bool,milliseconds:row["time"] as! Double,identity:row["id"] as? String,emergency:row["emergency"] as! Bool)
 let expected=row["output"] as! [String:Bool]
 precondition(result.horn==expected["horn"] && result.siren==expected["siren"],"frame \(index) horn/siren mismatch")
}
print("PASS: \(frames.count) actual emergency horn/siren tap/hold/identity frames")
// A synthetic release after focus loss must not count as an intentional tap.
for hz in [15.0,30.0,60.0,120.0] {
 let horn=NativeVehicleHornController(),tick=1000/hz
 _=horn.update(pressed:true,milliseconds:0,identity:"ambulance",emergency:true)
 horn.cancelPress()
 let cancelled=horn.update(pressed:false,milliseconds:tick,identity:"ambulance",emergency:true)
 precondition(!cancelled.horn && !cancelled.siren,"cancelled gesture toggled siren at \(hz)Hz")
 _=horn.update(pressed:true,milliseconds:1000,identity:"ambulance",emergency:true)
 precondition(horn.update(pressed:false,milliseconds:1000+tick,identity:"ambulance",emergency:true).siren)
 _=horn.update(pressed:true,milliseconds:2000,identity:"ambulance",emergency:true)
 horn.cancelPress()
 precondition(horn.update(pressed:false,milliseconds:2000+tick,identity:"ambulance",emergency:true).siren,"cancellation lost active siren")
}
print("PASS: interrupted horn gestures preserve siren at15/30/60/120Hz")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-horn-')as directory:
  work=Path(directory);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'fixture.json')],cwd=ROOT,check=True)
  (work/'verify.swift').write_text((ROOT/'ios/App/NativeVehicleHornController.swift').read_text()+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'fixture.json')],check=True)
if __name__=='__main__':main()
