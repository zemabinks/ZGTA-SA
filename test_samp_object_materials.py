#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Published SA-MP object materials: native CoreText and actual Metal readback."""
import json
import pathlib
import subprocess
from PIL import Image

ROOT=pathlib.Path(__file__).resolve().parent
out=ROOT/'local-only/research/object-materials';out.mkdir(parents=True,exist_ok=True)
files=['NativeRenderWareDFF.swift','NativeRenderWareTXD.swift','NativeRenderWareModel.swift','NativeSAMPTextCodec.swift','NativeSAMPProtocol.swift','NativeSAMPObjects.swift','NativeSAMPObjectMaterials.swift']
binary=out/'material-tests'
result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*[str(ROOT/'ios/App'/p) for p in files],str(ROOT/'tests/object_materials/main.swift'),'-o',str(binary)],capture_output=True,text=True)
(out/'build.log').write_text(result.stdout+result.stderr)
if result.returncode:raise SystemExit(f'Compile exit {result.returncode}\n'+result.stdout+result.stderr)
result=subprocess.run([str(binary),str(ROOT/'ios/App/NativeRenderWareModel.metal'),str(out)],capture_output=True,text=True,timeout=45)
(out/'stdout.log').write_text(result.stdout);(out/'stderr.log').write_text(result.stderr)
if result.returncode:raise SystemExit(f'Native test exit {result.returncode}\n'+result.stdout+result.stderr)
report=json.loads(result.stdout)
report['scope']='Published dimensions/channel order/native font rendering/material GPU overrides; original Windows glyph metrics and full application scene integration remain separate'
(out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
Image.frombytes('RGBA',(512,256),(out/'text-preview.rgba').read_bytes()).save(out/'text-preview.png')
print(json.dumps(report,indent=2,sort_keys=True))
