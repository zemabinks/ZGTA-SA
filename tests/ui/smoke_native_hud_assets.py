#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual HUD request owner with authored clocks, transport and decode decisions.

The identity and binding declarations are extracted literally. The surrounding
resource-store spy is explicit; UIKit decoding/rendering and real IO are separate.
"""
from pathlib import Path
import hashlib,json,os,subprocess,sys,time

ROOT=Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from tests.movement.smoke_native_climb_runtime import function

def main():
    os.setpriority(os.PRIO_PROCESS,0,15)
    paths=[ROOT/'ios/App'/name for name in ['NativeHUDAssetOwner.swift','ServerAddress.swift',
        'NativeGameHUD.swift','NativeResourceStore.swift','NativeGameViewController.swift']]
    paths += [Path(__file__).resolve(),Path(__file__).with_suffix('.swift')]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    hud=paths[2].read_text();store=paths[3].read_text();controller=paths[4].read_text()
    identity=function(hud,'private struct NativeHUDResourceIdentity:Equatable').replace('private struct','struct',1)
    binding=function(store,'    struct RuntimeBinding: Equatable')
    mode=function(store,'    enum Mode: String, Codable')
    hud_load=function(hud,'    func load(server:ServerAddress)')
    map_load=function(hud,'    func loadMap(server:ServerAddress)')
    assert 'NativeResourceStore.shared.runtimeBinding' in identity
    assert 'resourceOwner.load(' in hud_load and 'mapOwner.load(' in map_load
    assert hud_load.count('NativeHUDResourceIdentity.current(server:server)==identity')==2
    assert map_load.count('NativeHUDResourceIdentity.current(server:server)==identity')==2
    assert 'loadedServer' not in hud
    tick=controller[controller.index('if link.timestamp - lastHUD > 0.1, let renderer {'):]
    tick=tick[:tick.index('status.expireIfNeeded()')]
    assert 'gameHUD.loadFont(server:server)' in tick and 'gameHUD.radar.loadMap(server:server)' in tick
    out=ROOT/'local-only/research/hud-asset-owner'/str(time.time_ns());out.mkdir(parents=True)
    carrier='import Foundation\n'+identity+'\nfinal class NativeResourceStore {\n'+mode+'\n'+binding+'''
        static let shared=NativeResourceStore()
        var runtimeBinding=RuntimeBinding(generation:UUID(),mode:.development,contentID:nil,
            developmentOrigin:nil,playable:false)
    }
    '''
    (out/'IdentityCarrier.swift').write_text(carrier)
    report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=hashes,
        scope='Complete production owner and transport declarations; literal HUD identity/binding with an explicit mutable store spy; authored deferred tasks, clock and decoder decisions. Wiring checks are static. No UIKit, real images, network, App, device or retail comparison.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-swift-version','5','-parse-as-library','-Onone',
            '-whole-module-optimization','-j','1','-num-threads','1',
            '-module-cache-path',str(out/'modules'),str(paths[1]),str(paths[0]),
            str(out/'IdentityCarrier.swift'),str(paths[-1]),'-o',str(out/'test')]
        r=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=240)
        (out/'compile.log').write_text(r.stdout+r.stderr);report['compileExit']=r.returncode
        assert r.returncode==0,r.stderr[-6000:]
        r=subprocess.run([str(out/'test')],cwd=ROOT,capture_output=True,text=True,timeout=30)
        (out/'runtime.log').write_text(r.stdout+r.stderr)
        report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
        assert r.returncode==0 and 'PASS HUD asset owner:' in r.stdout,r.stdout+r.stderr
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items()),completedAt=time.time())
        save();print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'},indent=2),flush=True)
    assert report['sourcesHeld']

if __name__=='__main__':main()
