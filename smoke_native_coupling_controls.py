#!/usr/bin/env python3
"""Actual GameVC coupling publication, working touch input and contextual UI."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/coupling-integration';OUT.mkdir(parents=True,exist_ok=True)
FILES=['ios/App/NativeGameViewController.swift','ios/App/NativeGameBindings.swift','ios/App/NativeVehicleCoupling.swift','ios/App/NativeMultiplayerClient.swift','ios/App/ServerAddress.swift','ios/App/NativeInventoryPrediction.swift','ios/App/NativeWeaponState.swift','smoke_native_coupling_controls.py','smoke_native_coupling_controls.swift']
def main():
 inputs={n:(ROOT/n).read_bytes() for n in FILES};vc=inputs[FILES[0]].decode();mp=inputs[FILES[3]].decode();coupling=inputs[FILES[2]].decode()
 markers=['private func requestVehicleCoupling(','private func sendCurrentPosition(','private func completeVehicleExit(',
  'private func updateAuxiliaryControls(','private func setDrivingControls(','@objc private func toggleCrouch()',
  '@objc private func pressNozzleUp()','@objc private func pressNozzleDown()','@objc private func releaseNozzleUp()','@objc private func releaseNozzleDown()',
  'private var usingPistol:','private var usingMelee:','private var magazine:','private var reserve:']
 methods='\n'.join(function(vc,m).replace('@objc ','').replace('private ','') for m in markers)
 callbacks='\n'.join(function(vc,m) for m in ['        network.onInventoryConnection =','        network.onCouplings =','        renderer?.onCouplingRequest ='])
 reset=next(line.strip() for line in vc.splitlines() if line.strip().startswith('flightBrakePressed = false; hornPressed = false;'))+'\n'+next(line.strip() for line in vc.splitlines() if line.strip().startswith('renderer?.vehicleWorkingControl=0;vehicleTuck=0'))
 axis=next(line.strip() for line in vc.splitlines() if line.strip().startswith('renderer?.vehicleWorkingControl = acceptsInput'))
 position=function(mp,'    func sendPosition(');position=position[:position.index('{')]
 exit_method=function(mp,'    func sendExit(');exit_method=exit_method[:exit_method.index('{')]
 types='\n'+function(mp,'struct RemoteVehicle {')+'\n'+function(mp,'struct NativeCouplingLink:')+'\nfinal class NativeVehicleCoupling {\n'+function(coupling,'    enum Kind:')+'\n'+function(coupling,'    struct Request:')+'\n}\n'
 source='import Foundation\nimport simd\n'+types
 source+='\n'+'\n'.join(inputs[n].decode() for n in ['ios/App/NativeGameBindings.swift','ios/App/ServerAddress.swift','ios/App/NativeInventoryPrediction.swift','ios/App/NativeWeaponState.swift'])
 source+='\n'+inputs['smoke_native_coupling_controls.swift'].decode().replace('// ACTUAL_METHODS',methods).replace('// ACTUAL_CALLBACKS',callbacks).replace('// ACTUAL_RESET_AUX',reset).replace('// ACTUAL_AXIS',axis)
 source=source.replace('// ACTUAL_POSITION_SIGNATURE',position).replace('// ACTUAL_EXIT_SIGNATURE',exit_method)
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temp:
  p=Path(temp);(p/'main.swift').write_text(source);exe=p/'verify'
  compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),str(p/'main.swift'),'-o',str(exe)],capture_output=True,text=True)
  (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  result=subprocess.run([str(exe)],capture_output=True,text=True)
  (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
   'sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in inputs.items()},
   'limits':['Extracted actual GameVC methods and callbacks plus real bindings/inventory/request types; controlled Renderer/network/button carriers','No UIKit rendering, physical controller, native joint or retail runtime claim; URLSession packet ordering has a separate real wire gate']},indent=2)+'\n')
  print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
if __name__=='__main__':main()
