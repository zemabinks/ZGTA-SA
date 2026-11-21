#!/usr/bin/env python3
"""CPU-only literal renderer integration on entirely authored toy fixtures.

No game archive, imported model tables, graphics context or physics library is
required. --prepare-only writes/checks inputs without invoking any compiler.
An optional historical renderer must fail its explicitly selected witness.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,platform,subprocess

ROOT=Path(__file__).resolve().parents[2]
HELPERS=['NativeVehicleRig.swift','NativeVehiclePaint.swift','NativeVehicleDamage.swift',
         'NativeRemoteSuspension.swift','NativeRemoteBikeAnimation.swift']
HELPERS += ['NativeAmbientPedestrianProtocol.swift', 'NativeAmbientPedestrianPaths.swift', 'NativeAmbientTrafficProtocol.swift', 'NativeAmbientTrafficRoads.swift', 'NativeAmbientTraffic.swift', 'NativeAmbientTrafficMotion.swift', 'NativeAmbientTrafficPresentation.swift', 'NativeAmbientTrafficScene.swift']
METHOD='    private func vehicleRigFrame('
STRUCTS=['OwnVehicleDrawSnapshot','ParkedVehicleDrawSnapshot','VehicleDrawContext']

def digest(data):return hashlib.sha256(data).hexdigest()

def declaration(source,needle):
    """Return one complete Swift declaration, ignoring strings/comments."""
    begin=source.index(needle);brace=source.index('{',begin)
    index=brace;depth=0;quote=False;escape=False;line=False;comment=0
    while index<len(source):
        char=source[index];pair=source[index:index+2]
        if line:
            if char=='\n':line=False
        elif comment:
            if pair=='/*':comment+=1;index+=1
            elif pair=='*/':comment-=1;index+=1
        elif quote:
            if escape:escape=False
            elif char=='\\':escape=True
            elif char=='"':quote=False
        elif pair=='//':line=True;index+=1
        elif pair=='/*':comment=1;index+=1
        elif char=='"':quote=True
        elif char=='{':depth+=1
        elif char=='}':
            depth-=1
            if depth==0:return source[begin:index+1]
        index+=1
    raise ValueError('Unterminated Swift declaration '+needle)

def fixture():
    # Coordinates, hierarchy, palette and material groups are invented here.
    # 400 is merely a schema-valid identifier, not that game's actual vehicle.
    identity=[1 if row==column else 0 for column in range(4)for row in range(4)]
    quaternion=[0,0,0,1]
    nodes=[]
    for index,name in enumerate(['toy-root','toy-rotor','toy-front','toy-rear']):
        nodes.append(dict(name=name,parent=-1 if index==0 else 0,position=[0,0,0],rotation=quaternion,
                          scale=[1,1,1],matrix=identity,matrixAutoUpdate=True,visible=True,
                          wheel=index>=2,damaged=False,lowDetail=False))
    joints=dict(damage=[],wheels=[dict(node=index,home=[0,0,0],rest=quaternion,lean=quaternion,
                       front=index==2,left=True,bogie=False)for index in [2,3]],
                rotors=[dict(node=1,name='static_rotor',rest=quaternion)],gear=[],nozzles=[],rearSteerOnly=False)
    paint=dict(version=1,vertexRGB='neutral-paint-slot-rgb',palette=[[0,0,0],[255,255,255],[0,255,0]],
               defaults=[0,0],colorVariants=[[0,0,1,1]],customFlag=0x1000000,customLimit=0x2000000)
    draw=dict(node=0,start=0,count=3,materialVisible=True,lens=-1,texture=0,litTexture=0,
              alphaTest=0,paint=0,color=[1,1,1])
    rigs={kind:dict(version=2,id=400,kind=kind,nodes=nodes,draws=[draw],joints=joints,paint=paint,
                   binaryEncoding='VPC2',binarySHA256=digest(b'authored CPU-only toy mesh descriptor'))
          for kind in ['heli','plane','car','boat','bike','train']}
    suspension=dict(id=400,kind='car',origin=0,table=dict(upper=0.2,lower=-0.2,flags=0),
                    wheels=[dict(centre=[-0.5,0,-1],radius=0.3,front=True,left=True),
                            dict(centre=[-0.5,0,1],radius=0.3,front=False,left=True)])
    return dict(kind='authored CPU fixtures; no original assets',rigs=rigs,suspension=suspension)

def validate_fixture(value):
    assert set(value['rigs'])=={'heli','plane','car','boat','bike','train'}
    for kind,rig in value['rigs'].items():
        assert rig['kind']==kind and rig['version']==2 and len(rig['binarySHA256'])==64
        assert len(rig['nodes'])==4 and len(rig['paint']['palette'])==3
        for index,node in enumerate(rig['nodes']):
            assert -1<=node['parent']<index and len(node['matrix'])==16
            assert len(node['position'])==3 and len(node['rotation'])==4 and len(node['scale'])==3
        assert [row['node']for row in rig['joints']['wheels']]==[2,3]
    assert value['suspension']['table']['lower']<value['suspension']['table']['upper']

def harness(renderer):
    structures=[declaration(renderer,'    private struct '+name+' {')for name in STRUCTS]
    method=declaration(renderer,METHOD)
    assert method.count('ProcessInfo.processInfo.systemUptime')==1
    assert 'let player=context.player,parked=context.parked,own=context.own,token=context.token' in method
    # Preserve every method-body byte. Only declaration access changes; the
    # local ProcessInfo alias supplies an authored deterministic monotonic clock.
    public_structures=[s.replace('private struct ','struct ',1)for s in structures]
    callable_method=method.replace('private func ','func ',1)
    source='''import Foundation
import simd
final class VehiclePresentationHarness {
    typealias ProcessInfo=PresentationClock
    struct RemotePlayer {
        var id:String
        var speed:Float=0,steer:Float=0
        var kit:[Float]?=nil
        var vehicleDamage=String(repeating:"0",count:19)
        var vehicleHealth=1000
        var lights=false
    }
    struct RemoteVehicle {
        var damage=String(repeating:"0",count:19)
        var health=1000
    }
    final class GroundCarrier {
        func handlingFlags(_ model:String)->Int{0}
        func modelFlags(_ model:String)->Int{0}
    }
    var groundVehicle:GroundCarrier?=GroundCarrier()
    var camera=SIMD3<Float>.zero
    var vehicleRigTimes:[String:Double]=[:]
    var vehicleRigSpins:[String:SIMD2<Double>]=[:]
    var vehicleRigStates:[String:NativeVehicleRig.State]=[:]
    var remoteBikeFrames:[String:NativeRemoteBikeAnimation.Frame]=[:]
    var remoteSuspensionConfigurations:[Int:NativeRemoteSuspension.Configuration]=[:]
    var riderDoorHolds:[String:[Int:Double]]=[:]
    var queryCount=0
    var query:(NativeRemoteSuspension.Ray)->NativeRemoteSuspension.Contact={_ in .unavailable}
    func remoteSuspensionContact(_ ray:NativeRemoteSuspension.Ray)->NativeRemoteSuspension.Contact{
        queryCount+=1;return query(ray)
    }
'''+ '\n'.join(public_structures)+'\n'+callable_method+'\n}\n'
    return source,dict(methodSHA256=digest(method.encode()),
                       structureSHA256={name:digest(s.encode())for name,s in zip(STRUCTS,structures)},
                       bodyPreserved=callable_method[callable_method.index('{'):]==method[method.index('{'):])

def prepare(destination,renderer_source,helpers,test_source,fixtures):
    destination.mkdir(parents=True,exist_ok=True)
    source,extraction=harness(renderer_source)
    (destination/'RendererHarness.swift').write_text(source)
    (destination/'PresentationGate.swift').write_bytes(test_source)
    for name,data in helpers.items():(destination/name).write_bytes(data)
    (destination/'fixtures.json').write_text(json.dumps(fixtures,sort_keys=True)+'\n')
    return extraction

def execute(destination):
    environment=os.environ.copy();environment.pop('SDKROOT',None)
    executable=destination/'verify'
    command=['xcrun','--sdk','macosx','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1',
             '-target',platform.machine()+'-apple-macosx13.0','-module-cache-path',str(destination/'modules')]
    command += [str(destination/name)for name in HELPERS]
    command += [str(destination/'RendererHarness.swift'),str(destination/'PresentationGate.swift'),'-o',str(executable)]
    compiled=subprocess.run(command,env=environment,capture_output=True,text=True,timeout=240)
    (destination/'compile.log').write_text(compiled.stdout+compiled.stderr)
    if compiled.returncode:return dict(compileExitCode=compiled.returncode,status='COMPILE FAIL')
    result=subprocess.run([str(executable),str(destination/'fixtures.json')],capture_output=True,text=True,timeout=60)
    (destination/'run.log').write_text(result.stdout+result.stderr)
    return dict(compileExitCode=0,exitCode=result.returncode,output=result.stdout+result.stderr,
                status='PASS'if result.returncode==0 else'FAIL')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/research/vehicle-presentation-122')
    parser.add_argument('--historical-root',type=Path)
    parser.add_argument('--historical-witness',choices=['remote-aircraft','compact-health','compact-rotor'],default='remote-aircraft')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    paths=[ROOT/'ios/App'/name for name in HELPERS]+[ROOT/'ios/App/NativeWorldRenderer.swift',
             ROOT/'tests/vehicles/smoke_native_vehicle_presentation.swift',Path(__file__).resolve()]
    if args.historical_root:paths.append(args.historical_root.resolve()/'ios/App/NativeWorldRenderer.swift')
    snapshot={str(path):path.read_bytes()for path in paths}
    helpers={name:snapshot[str(ROOT/'ios/App'/name)]for name in HELPERS}
    renderer=snapshot[str(ROOT/'ios/App/NativeWorldRenderer.swift')].decode()
    test=snapshot[str(ROOT/'tests/vehicles/smoke_native_vehicle_presentation.swift')]
    fixtures=fixture();validate_fixture(fixtures)
    report=dict(status='PREPARED',compilerInvoked=False,
        sourceHashes={name:digest(data)for name,data in snapshot.items()},
        fixtureSHA256=digest(json.dumps(fixtures,sort_keys=True).encode()),
        currentExtraction=prepare(out/'current',renderer,helpers,test,fixtures),
        limits=['Authored toy rigs/contexts/clocks; no game archive or model-derived fixture data',
                'Actual renderer body plus production rig/paint/damage/suspension helpers; surrounding containers are reduced carriers',
                'No GPU, browser, device, networking, live multiplayer or parked-solver lifecycle validation',
                'Context tokens are supplied fixtures; production token construction is outside this gate'])
    if args.historical_root:
        old=snapshot[str(args.historical_root.resolve()/'ios/App/NativeWorldRenderer.swift')].decode()
        report['historicalExtraction']=prepare(out/'historical',old,helpers,test,fixtures)
    if not args.prepare_only:
        if platform.system()!='Darwin':raise RuntimeError('Apple CPU host with Swift simd/CryptoKit is required')
        report['compilerInvoked']=True;report['current']=execute(out/'current')
        report['status']='PASS'if report['current']['status']=='PASS'else'FAIL'
        if args.historical_root:
            report['historical']=execute(out/'historical')
            witness={'remote-aircraft':'remote helicopter presentation default','compact-health':'compact health alone invented scorched materials','compact-rotor':'compact heli rotor default'}[args.historical_witness]
            report['historicalWitness']=witness
            rejected=report['historical'].get('compileExitCode')==0 and report['historical'].get('exitCode')!=0 and witness in report['historical'].get('output','')
            report['historicalRejectedForExpectedReason']=rejected
            if not rejected:report['status']='FAIL'
    report['sourceUnchanged']=all(Path(name).read_bytes()==data for name,data in snapshot.items())
    if not report['sourceUnchanged']:report['status']='FAIL'
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({key:report[key]for key in ['status','compilerInvoked','sourceUnchanged']},sort_keys=True))
    return 0 if report['status']in ['PASS','PREPARED']else 1
if __name__=='__main__':raise SystemExit(main())
