#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual row-to-animation armour checks with authored values and CLP tracks."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.network.smoke_native_remote_motion import block

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--reference',type=Path);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    names=['NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePedestrianReaction','NativeRemoteFootAnimation','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeHumanShots','NativeMultiplayerClient','NativeActorAnimation','NativeOriginalWorldCommands','NativeWorldRenderer']
    paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[ROOT/'tests/network/smoke_native_remote_motion.swift',ROOT/'tests/movement/smoke_native_remote_struck.swift',Path(__file__),Path(__file__).with_suffix('.swift')]
    if args.reference:paths.append(args.reference.resolve())
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();frozen={str(p):sha(p)for p in paths}
    actor=paths[0].read_text();common=actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
    common+='\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
    common+='\n'+'\n'.join(p.read_text()for p in paths[1:11])
    network=paths[11].read_text();common+='\n'+'\n'.join(block(network,n)for n in ['struct NativeVehicleSeatSession {','struct RemotePlayer {','struct RemoteVehicle {','struct NativeHealthPrediction {'])
    common+='\n'+block(paths[12].read_text(),'struct NativePedestrianMotion {')+'\n'+paths[13].read_text()
    owner=block(paths[15].read_text(),'private final class PacketOwner {').replace('// ACTUAL_PACKET',block(network,'    private func updateRows(').replace('ProcessInfo.processInfo.systemUptime','receiptTime'))
    renderer=paths[14].read_text();a=renderer.index('                    let state=NativeRemoteFootAnimation.Snapshot(');b=renderer.index('                    sampledRemoteFootIDs.insert',a)
    snapshot='private func snapshot(_ player:RemotePlayer)->NativeRemoteFootAnimation.Snapshot {\nlet footPosition=player.position,groundContext=false,riderTime=1.0\nlet humanShots=NativeHumanShots()\n'+renderer[a:b]+'\nreturn state\n}\n'
    source=paths[18].read_text()
    for marker,value in [('COMMON',common),('PACKET_OWNER',owner),('RENDER_SNAPSHOT',snapshot),('FIXTURE_LIBRARY',block(paths[16].read_text(),'func fixture()'))]:
        assert '// ACTUAL_'+marker in source;source=source.replace('// ACTUAL_'+marker,value)
    out=ROOT/'local-only/research/remote-armour-test'/str(time.time_ns());out.mkdir(parents=True);(out/'Gate.swift').write_text(source)
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Literal packet decoder with receipt-clock seam, complete row structs, literal renderer snapshot with real empty recent-hit store, and actual CLP/foot/remote/reaction controllers. Authored numeric values and clip tracks; optional private selected scalar records. Type-only skeletal boundary; no GPU, real socket, browser UI, device, local damage authority or retail acceptance.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']))+'\n')
    start=time.time();save()
    try:
        with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(out/'Gate.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=300)
        report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-4000:]
        r=subprocess.run([str(out/'gate'),*([str(args.reference.resolve())]if args.reference else[])],capture_output=True,text=True,timeout=30);(out/'runtime.log').write_text(r.stdout+r.stderr);report.update(runtimeExit=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,r.stdout+r.stderr
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(seconds=time.time()-start,inputsHeld=all(sha(Path(p))==h for p,h in frozen.items()));save();print({k:v for k,v in report.items()if k!='sourceHashes'},flush=True)
if __name__=='__main__':main()
