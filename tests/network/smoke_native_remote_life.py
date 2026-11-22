#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual remote row admission/animation, with authored numeric edge cases."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tests.network.smoke_native_remote_motion import block

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reference',type=Path);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    paths=[ROOT/'ios/App'/f'{n}.swift'for n in ['NativeMultiplayerClient','NativeActorAnimation','NativeOriginalWorldCommands']]
    paths += [Path(__file__),Path(__file__).with_suffix('.swift'),ROOT/'tests/network/smoke_native_remote_motion.swift']
    if args.reference:paths.append(args.reference.resolve())
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();frozen={str(p):sha(p)for p in paths}
    network,actor=paths[0].read_text(),paths[1].read_text()
    common='import Foundation\nimport CoreFoundation\nimport simd\n'+'\n'.join(block(network,n)for n in ['struct NativeVehicleSeatSession {','struct RemotePlayer {','struct RemoteVehicle {','struct NativeHealthPrediction {'])+'\n'+block(actor,'struct NativePedestrianMotion {')
    owner=block(paths[5].read_text(),'private final class PacketOwner {').replace('// ACTUAL_PACKET',block(network,'    private func updateRows(').replace('ProcessInfo.processInfo.systemUptime','receiptTime'))
    fixture=paths[4].read_text().replace('// ACTUAL_COMMON',common).replace('// ACTUAL_PACKET_OWNER',owner)
    out=ROOT/'local-only/research/remote-life-test'/str(time.time_ns());out.mkdir(parents=True)
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Actual packet structs, full ped-motion/number helper and literal row decoder with explicit receipt clock seam. Authored packet rows; optional separately retained selected source records. Not real networking, GPU, browser, phone or retail.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']))+'\n')
    start=time.time();save()
    try:
        (out/'Gate.swift').write_text(fixture)
        with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(paths[2]),str(out/'Gate.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=300)
        report['compileExit']=r.returncode;save();assert r.returncode==0
        r=subprocess.run([str(out/'gate'),*([str(args.reference.resolve())]if args.reference else[])],capture_output=True,text=True,timeout=30)
        (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(runtimeExit=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(seconds=time.time()-start,inputsHeld=all(sha(Path(p))==h for p,h in frozen.items()));save();print({k:v for k,v in report.items()if k!='sourceHashes'},flush=True)
if __name__=='__main__':main()
