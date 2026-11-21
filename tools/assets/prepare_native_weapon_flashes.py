#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Convert owned DFF flash descendants to separate local-only actor resources.

Existing body meshes, atlases and model identities are never replaced. No
original geometry, textures or generated metadata belong in the source repo.
"""
from pathlib import Path
import argparse, hashlib, json, re, sys
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from tools.assets import prepare_native_models as models

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game',type=Path,default=ROOT/'local-only/site/game')
    parser.add_argument('--output',type=Path)
    parser.add_argument('models',nargs='*')
    args=parser.parse_args();game=args.game.resolve();out=args.output or game/'native/models'
    document=json.loads((game/'native/weapons.json').read_text())
    known={r['modelName'].lower()for r in document['definitions']if r.get('modelName')}
    selected=set(args.models)if args.models else known
    if not selected<=known or any(not re.fullmatch('[a-z0-9_]{1,40}',n)for n in selected):
        parser.error('Select models from the installed weapon catalogue')
    models.GAME=game
    report=dict(schema=1,selection='weapon-flash',models=[],absent=[])
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    for name in sorted(selected):
        source=game/(name+'.dff');txd=source.with_suffix('.txd')
        if not source.is_file()or not txd.is_file():
            raise ValueError('Selected owned weapon resource is missing: '+name)
        destination=out/(name+'.flash.bin')
        try:vertices,triangles=models.convert(source,destination,selection='weapon-flash')
        except ValueError as error:
            if str(error)!='DFF has no weapon flash geometry':raise
            report['absent'].append(name);continue
        report['models'].append(dict(model=name,vertices=vertices,triangles=triangles,
            sourceDFFSHA256=digest(source),sourceTXDSHA256=digest(txd),
            files={p.name:digest(p)for p in [destination,destination.with_suffix('.png'),destination.with_suffix('.parts.json')]}))
    out.mkdir(parents=True,exist_ok=True)
    (out/'weapon-flashes.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
    print('Prepared',len(report['models']),'owned weapon flash resources;',len(report['absent']),'models have no flash geometry')
if __name__=='__main__':main()
