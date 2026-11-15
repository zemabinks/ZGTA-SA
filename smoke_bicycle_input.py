#!/usr/bin/env python3
"""Compile the actual Renderer vehicle mapping against real native bodies."""
from pathlib import Path
import os
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
CONTEXT = '''
struct RendererInputContext {
 var inside=true,hop=false,brake=false,pad=false
 var health=100,vehicleHealth=1000
 var forward:Float=0,turn:Float=0,sideways:Float=0,lookVertical:Float=0,lift:Float=0,jets:Float=0,wetness:Float=0
 var kind="bicycle"
}
struct RiderInputStub {let inside:Bool}
func rendererInput(_ vehicle:NativeGroundVehicle,_ context:RendererInputContext)->NativeVehicleDynamics.Input {
 let vehicleHealth=context.vehicleHealth,health=context.health
 let ownRiderPlayback:RiderInputStub?=RiderInputStub(inside:context.inside)
 let entryStarted=0.0
 let forward=context.forward,turn=context.turn,sideways=context.sideways,lookVertical=context.lookVertical,lift=context.lift
 let vehicleHandbrake=context.brake,vehicleHop=context.hop,vehicleControllerInput=context.pad,vehicleJetControl=context.jets,roadWetness=context.wetness,vehicleKind=context.kind
 var steeringInput:Float=0
 var groundVehicle:NativeGroundVehicle?=vehicle
 __PREFIX__
 guard let groundVehicle else{fatalError("Missing test vehicle")}
 __MAPPING__
 return __ACTUAL_INPUT__
}
'''


def main():
    source = (ROOT / 'ios/App/NativeWorldRenderer.swift').read_text()
    anchor = source.index('let start = camera')
    start = source.index('if driving {', anchor) + len('if driving {')
    prefix = source[start:source.index('let table = activeHandling', start)]
    start = source.index('if let groundVehicle, groundVehicle.active {', start) + len('if let groundVehicle, groundVehicle.active {')
    finish = source.index('groundVehicle.update(', start)
    mapping = source[start:finish]
    argument = re.match(r'groundVehicle\.update\([^\n]*input:\s*(\w+),', source[finish:])
    assert argument, 'Renderer native-input call boundary changed; review extraction'
    assert 'vehicleHop' in mapping, 'Renderer still couples bicycle hop to its brake'
    assert 'groundVehicle?.cancelPendingInput()' in source, 'Renderer cancellation does not clear pending hop'
    function = CONTEXT.replace('__PREFIX__', prefix).replace('__MAPPING__', mapping).replace('__ACTUAL_INPUT__', argument[1])
    output = ROOT / 'local-only/native-physics/tests/bicycle-input'
    output.mkdir(parents=True, exist_ok=True)
    machine = platform.machine()
    assert machine in ['arm64', 'x86_64']
    names = ['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeSprintController','NativeVehicleInputOwnership']
    with tempfile.TemporaryDirectory(prefix='snapshot-', dir=output) as temporary:
        snapshot=Path(temporary);files=[]
        for name in names:
            file=snapshot/(name+'.swift');shutil.copyfile(ROOT/'ios/App'/file.name,file);files.append(file)
        (snapshot/'main.swift').write_text('import Foundation\n'+function+(ROOT/'smoke_bicycle_input.swift').read_text())
        environment=os.environ.copy();environment.pop('SDKROOT',None)
        subprocess.run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-target',machine+'-apple-macosx13.0','-module-cache-path',str(ROOT/'local-only/native-physics/swift-module-cache'),'-I',str(ROOT/'native-physics/include'),*map(str,files),str(snapshot/'main.swift'),'-L',str(ROOT/('local-only/native-physics/macos-'+machine)),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(snapshot/'verify')],env=environment,check=True)
        subprocess.run([str(snapshot/'verify'),str(ROOT)],check=True)


if __name__ == '__main__':
    main()
