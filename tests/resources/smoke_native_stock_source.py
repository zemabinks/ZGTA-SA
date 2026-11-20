#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Execute renderer source-lifetime statements against explicit resource spies.

Actual HTTP/RW/Metal/Rapier integration is a separate stock-runtime gate.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,marker):
    start=source.index(marker);i=source.index('{',start);depth=1;end=i+1
    while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('private ','')
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--renderer',type=Path,help='Historical source for a negative reproduction')
    args=parser.parse_args();path=args.renderer or ROOT/'ios/App/NativeWorldRenderer.swift'
    renderer=path.read_text();fixture=Path(__file__).with_suffix('.swift');carrier=fixture.read_text()
    markers=['private func synchronizeLegacyStockSource(', 'private func retireLegacyStockTextures(',
             'private func restoreLegacyArtworkTextures(', 'func invalidateLegacyImports(', 'var server: ServerAddress? {didSet{']
    parts=[]
    for marker in markers:
        if marker in renderer:parts.append(block(renderer,marker))
        elif args.renderer and marker.startswith('private func synchronize'):parts.append('func synchronizeLegacyStockSource() {}')
        elif args.renderer and marker.startswith('private func retire'):parts.append('func retireLegacyStockTextures(_ models:Set<Int32>,includeExternal:Bool=false) {}')
        elif args.renderer and marker.startswith('private func restore'):parts.append('func restoreLegacyArtworkTextures(_ keys:Set<NativeSAMPObjectMaterials.TextureRequest>) {}')
        else:raise AssertionError('Missing actual owner: '+marker)
    if 'private func invalidateStockPedResources(' in renderer:
        parts.append(block(renderer,'private func invalidateStockPedResources('))
    if not args.renderer:
        observer=block(renderer,'fixedCJObserver=NativeResourceStore.shared.observe')
        assert 'self.synchronizeLegacyStockSource()' in observer
        for marker in ['private func refreshLegacyStockReferences(', 'private func loadLegacyStockCatalogs(',
                       'private func loadLegacyDictionary(', 'private func synchronizeLegacyObjectPhysics(']:
            assert 'synchronizeLegacyStockSource()' in block(renderer,marker),marker
    source=carrier.replace('// ACTUAL_OWNERS','\n'.join(parts))
    if 'private func invalidateStockPedResources(' in renderer:
        source+='''
let pedOwner=Loader()
c.stockPedRuntime=pedOwner;c.stockPedIDs=["a":100];c.stockPedCatalogueSHA="old";c.stockPedErrors=[100]
c.synchronizeLegacyStockSource()
require(pedOwner.resets==0 && c.stockPedRuntime === pedOwner,"same source retired pedestrian resources")
c.generation+=1;c.synchronizeLegacyStockSource()
require(pedOwner.resets==1 && c.stockPedRuntime==nil,"source replacement did not retire pedestrian CPU/resident owner")
require(c.stockPedIDs.isEmpty && c.stockPedCatalogueSHA==nil && c.stockPedErrors.isEmpty,"source replacement retained old pedestrian registration/suppression")
print("PASS pedestrian retirement composition with the actual stock source owner")
'''
    out=ROOT/'local-only/research/stock-source-149/owners'/str(time.time_ns());out.mkdir(parents=True)
    (out/'main.swift').write_text(source)
    command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone',
             '-module-cache-path',str(out/'modules'),str(out/'main.swift'),'-o',str(out/'owners')]
    with(out/'build.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    if r.returncode:print((out/'build.log').read_text()[-5000:]);r.check_returncode()
    r=subprocess.run([str(out/'owners')],capture_output=True,text=True,timeout=30)
    (out/'runtime.log').write_text(r.stdout+r.stderr)
    report=dict(status='PASS'if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr,
                rendererSHA256=hashlib.sha256(renderer.encode()).hexdigest(),fixtureSHA256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                sourceUnchanged=path.read_text()==renderer,scope='Actual source/reset/texture-owner statements; resource, GPU, collider and download boundaries are explicit spies. HTTP/native runtime is separate.')
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    print(json.dumps(report));r.check_returncode();assert report['sourceUnchanged']
if __name__=='__main__':main()
