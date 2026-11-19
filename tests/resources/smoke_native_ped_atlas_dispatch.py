#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Literal Renderer loading/publication/draw with authored storage boundaries."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib,json,subprocess,tempfile
from pathlib import Path
from tests.resources.smoke_native_ped_atlas_support import family,write_family,canonical,digest
ROOT=Path(__file__).resolve().parents[2]

def block(s,marker):
 a=s.index(marker);o=s.index('{',a);d=1;e=o+1
 while d:d+=(s[e]=='{')-(s[e]=='}');e+=1
 return s[a:e]
def main():
 out=ROOT/'local-only/research/ped-atlas-120/dispatch';out.mkdir(parents=True,exist_ok=True);w=Path(tempfile.mkdtemp(prefix='gate-',dir=out));files=w/'files';files.mkdir()
 rows=[]
 for label in ['valid','variant','badskin','badhand','badparts','validv2','variantv2']:
  v=family('authored',body=(16,8) if label.startswith('variant') else (8,16),version=2 if label.endswith('v2') else 1)
  if label.startswith('bad'):
   role={'badskin':'skeleton','badhand':'hand','badparts':'parts'}[label]
   raw=b'invalid authored carrier';suffix={'skeleton':'.skel.bin','hand':'.hand.bin','parts':'.parts.json'}[role]
   v['files'][role]=raw;v['manifest']['resources'][role]={'path':'game/native/models/ped-atlas-v1/'+digest(raw)+'/authored'+suffix,'bytes':len(raw),'sha256':digest(raw)}
   v['metadata']=canonical(v['manifest'])+b'\n';v['path']='game/native/models/ped-atlas-v1/'+digest(v['metadata'])+'/authored.json'
  row=write_family(files,v);row['case']=label;rows.append(row)
 (files/'fixtures.json').write_text(json.dumps(rows))
 names=['NativeWorldRenderer','NativeSkeletalActor','NativeActorAnimation','WorldBinary','NativePedAtlasLayout','NativePedAtlasLoader','ServerAddress']
 data={n:(ROOT/'ios/App'/f'{n}.swift').read_text() for n in names};r=data['NativeWorldRenderer'];s=data['NativeSkeletalActor'];a=data['NativeActorAnimation']
 skin=s[:s.index('/// Shared raw ANP3')].replace('import Metal','')
 skin+=block(s,'struct NativeSkinVertex {')+'\n'
 skin+=s[s.index('final class NativeSkeletalActor {'):s.index('    /// With a locomotion base,')]+block(s,'    func bind(pose: Pose,')+'\n}\n'
 hand=a[a.index('struct NativeActorAttachment {'):a.index('    func frame(clip:',a.index('struct NativeActorAttachment {'))]+'}\n'
 support=(ROOT/'tests/resources/smoke_native_ped_atlas_loader.swift').read_text().split('let root=URL(fileURLWithPath:CommandLine.arguments[1])')[0]
 # Remove its imports only; actual resource queue remains the real production class.
 support=support.replace('import Foundation','')
 methods='\n'.join(block(r,m).replace('private ','') for m in ['private func pedAtlasError(','private func clearPedAtlas(','private func invalidatePedAtlasSourceIfChanged(','private func bindPedAtlasFamilies(','private func loadPedAtlasActor('])
 types='\n'.join(block(r,m).replace('private ','') for m in ['private struct Mesh {','private struct ActorPart:','private struct ActorParts:'])
 gpu='\n'.join(block(r,m).replace('private ','') for m in ['private struct PedAtlasGPU {','private struct PedAtlasLoad {'])
 first=r.index('            if let pose, let actor = skeletalActors[name], let skeletalPipeline {',r.index('private func drawActors('))
 end=r.index('\n            if clip.isEmpty,let context=vehicleContext',first)
 dispatch=r[first:end]
 guard=next(x.strip() for x in r.splitlines() if 'guard self.fixedCJSourceIdentity()==actorSource,self.pedAtlasFamilies[name]==nil' in x)
 # The production callback returns Void. Only expose whether it continued;
 # retain its exact predicate instead of replacing it with a fixture constant.
 guard=guard.replace('else{return}','else{return false}')
 main=(ROOT/'tests/resources/smoke_native_ped_atlas_dispatch.swift').read_text()
 for key,value in {'ACTUAL_SKIN_PARSER':skin,'ACTUAL_HAND_PARSER':hand,'ACTUAL_LOADER_TEST_SUPPORT':support,'ACTUAL_MESH_TYPES':types,'ACTUAL_GPU_TYPES':gpu,'ACTUAL_UNIFORMS':block(r,'    private struct Uniforms {').replace('private ',''),'ACTUAL_OWNER_METHODS':methods,'ACTUAL_GENERIC_GUARD':guard,'ACTUAL_DRAW_DISPATCH':dispatch}.items():main=main.replace('// '+key,value)
 (w/'main.swift').write_text(main);sources=[]
 for n in ['WorldBinary','NativePedAtlasLayout','NativePedAtlasLoader','ServerAddress']:
  p=w/(n+'.swift');p.write_text(data[n]);sources.append(str(p))
 cmd=['nice','-n','15','swiftc','-whole-module-optimization','-num-threads','1','-Onone','-swift-version','5','-module-cache-path',str(w/'modules'),*sources,str(w/'main.swift'),'-o',str(w/'verify')]
 c=subprocess.run(cmd,capture_output=True,text=True,timeout=240);(w/'compile.log').write_text(c.stdout+c.stderr)
 if c.returncode:print(c.stdout+c.stderr);c.check_returncode()
 result=subprocess.run([str(w/'verify'),str(files)],capture_output=True,text=True,timeout=120)
 unchanged=all((ROOT/'ios/App'/f'{n}.swift').read_text()==v for n,v in data.items())
 report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','output':result.stdout+result.stderr,'sourceHashes':{n:hashlib.sha256(v.encode()).hexdigest() for n,v in data.items()},'sourceUnchanged':unchanged,'command':cmd,'limits':['Real source and actual SKN parser, deterministic authored transfers.','Image/GPU allocation and animation sampling are explicit spies; actual Metal pixels have a separate gate.']}
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
