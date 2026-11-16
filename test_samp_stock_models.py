#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Generated metadata/path/parent checks plus exact owner-file resolution."""
import copy
import json
import pathlib
import struct
import subprocess
import tempfile
from prepare_native_stock_models import generate

ROOT=pathlib.Path(__file__).resolve().parent
out=ROOT/'local-only/research/stock-models/tests';out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(dir=out,prefix='generated-') as temporary:
    work=pathlib.Path(temporary);data=work/'data';assets=work/'assets';data.mkdir();assets.mkdir()
    (data/'default.dat').write_text('IDE DATA/base.ide\nIDE DATA/vehicles.ide\n')
    (data/'gta.dat').write_text('# Inactive IDE intentionally omitted\n')
    (data/'base.ide').write_text('objs\n1000, test_panel, child, 100, 0\n1001, missing_piece, missing_dict, 100, 0\nend\ntxdp\nchild, parent\nend\n')
    (data/'vehicles.ide').write_text('cars\n400, test_car\ttestdict, car, HANDLING, NAME, null, normal, 10\nend\n')
    (data/'inactive.ide').write_text('objs\n1777, unused, child, 50, 0\nend\n')
    for name in ['test_panel.dff','test_car.dff','child.txd','parent.txd','testdict.txd','vehicle.txd']:
        (assets/name).write_bytes(struct.pack('<III',16 if name.endswith('.dff') else 22,0,0x1803ffff))
    manifest,report=generate(work,assets)
    assert report['models']==3 and report['activeIDEs']==2 and report['modelsWithRawDFF']==2
    fixture=work/'catalog.json';fixture.write_text(json.dumps(manifest))
    bad=[]
    def reject(label,change):
        value=copy.deepcopy(manifest);change(value);p=work/(label+'.json');p.write_text(json.dumps(value));bad.append(str(p))
    reject('schema',lambda v:v.update(schema=9))
    reject('duplicate',lambda v:v['models'].append(v['models'][0]))
    reject('negative-id',lambda v:v['models'][0].update(id=-1000))
    reject('model-path',lambda v:v['models'][0].update(model='../escape'))
    reject('cycle',lambda v:v['parents'].update(parent='child'))
    reject('asset-path',lambda v:v['assets']['child.txd'].update(path='../escape.txd'))
    reject('asset-host',lambda v:v['assets']['child.txd'].update(path='//evil.example/escape.txd'))
    reject('asset-hash',lambda v:v['assets']['child.txd'].update(sha256='wrong'))
    reject('asset-size',lambda v:v['assets']['child.txd'].update(bytes=-1))
    rejection=work/'rejections.json';rejection.write_text(json.dumps(bad))
    # Independent generator failures, no filename-based exceptions.
    (data/'base.ide').write_text('objs\n1000, ../escape, child, 100, 0\nend\n')
    try:generate(work,assets)
    except ValueError:pass
    else:raise AssertionError('Generator accepted path model')
    (data/'base.ide').write_text('objs\n1000, test_panel, child, 100, 0\nend\ntxdp\nchild,parent\nparent,child\nend\n')
    try:generate(work,assets)
    except ValueError:pass
    else:raise AssertionError('Generator accepted parent cycle')
    binary=out/'stock-tests'
    compile=subprocess.run(['xcrun','swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(ROOT/'ios/App/NativeSAMPStockModels.swift'),str(ROOT/'tests/stock_models/main.swift'),'-o',str(binary)],capture_output=True,text=True)
    (out/'build.log').write_text(compile.stdout+compile.stderr)
    if compile.returncode:raise SystemExit(compile.stdout+compile.stderr)
    result=subprocess.run([str(binary),str(fixture),str(rejection),str(ROOT/'local-only/original-world-assets/game/native/stock-models.json'),str(ROOT/'local-only/site')],capture_output=True,text=True)
    (out/'stdout.log').write_text(result.stdout);(out/'stderr.log').write_text(result.stderr)
    if result.returncode:raise SystemExit(f'Stock lookup test {result.returncode}\n'+result.stdout+result.stderr)
    report=json.loads(result.stdout);(out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))
