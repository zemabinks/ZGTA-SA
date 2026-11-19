#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Owned disposable open.mp DL server: valid RW transfer -> real GPU import gate.

Requires the existing local QA Docker image/native transport library. No original
assets, passwords, cookies, production servers or public networking are used.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import importlib.util
import json
import pathlib
import platform
import subprocess
import tempfile
import time
import uuid

ROOT=pathlib.Path(__file__).resolve().parents[2]
out=ROOT/'local-only/research/artwork-session/server';out.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('session_fixtures',ROOT/'tests/artwork_session/fixtures.py')
fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
dff,txd=fixtures.assets()
base_config=ROOT.parent/'ZGTA-SA-core-101/local-only/interop-openmp/release/Server/config.json'
with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-') as temporary:
    work=pathlib.Path(temporary);(work/'main.swift').write_bytes((ROOT/'tests/artwork_session/server.swift').read_bytes())
    files=['NativeSAMPArtwork.swift','NativeSAMPArtworkSession.swift','NativeSAMPClient.swift','NativeSAMPProtocol.swift','NativeRenderWareDFF.swift','NativeRenderWareTXD.swift','NativeRenderWareModel.swift']
    command=['xcrun','swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules','-I',str(ROOT/'native-samp/include'),*[str(ROOT/'ios/App'/p) for p in files],str(work/'main.swift'),'-L',str(ROOT/('local-only/native-samp/macos-'+platform.machine())),'-lzgtasa_samp','-lresolv','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')]
    build=subprocess.run(command,capture_output=True,text=True);(out/'build.log').write_text(build.stdout+build.stderr)
    if build.returncode:raise SystemExit(build.stdout+build.stderr)
    reports=[]
    for model_count in (1,0):
        name='zgta-native-import-'+uuid.uuid4().hex[:10];image=name+':qa';port=7793
        model_folder=work/'models';model_folder.mkdir(exist_ok=True)
        (model_folder/'fixture.dff').write_bytes(dff);(model_folder/'fixture.txd').write_bytes(txd)
        (model_folder/'artconfig.txt').write_text('AddSimpleModel(-1,19379,-1000,"fixture.dff","fixture.txd");\n' if model_count else '')
        config=json.loads(base_config.read_text());config.update(name='ZGTA isolated native import QA',announce=False,max_players=4)
        config['network'].update(port=port,bind='0.0.0.0',public_addr='127.0.0.1',minimum_connection_time=0,use_lan_mode=True)
        config['artwork'].update(enable=True,port=port,web_server_bind='0.0.0.0',cdn='',models_path='models',show_crc_logs=True)
        config['rcon'].update(enable=False,password=uuid.uuid4().hex)
        (work/'config.json').write_text(json.dumps(config,indent=2)+'\n')
        (work/'Dockerfile').write_text('FROM zgta-openmp-qa:1.6.7.3218-files\nCOPY --chown=65534:65534 config.json /srv/openmp/config.json\nCOPY --chown=65534:65534 models/ /srv/openmp/models/\n')
        started=False
        try:
            with (out/f'build-{model_count}.log').open('w') as log:subprocess.run(['docker','build','-t',image,str(work)],stdout=log,stderr=subprocess.STDOUT,check=True)
            subprocess.run(['docker','run','--rm','-d','--name',name,'-p',f'127.0.0.1:{port}:{port}/udp','-p',f'127.0.0.1:{port}:{port}/tcp',image],stdout=subprocess.DEVNULL,check=True);started=True
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                logs=subprocess.run(['docker','logs',name],capture_output=True,text=True).stdout
                if 'Started server on' in logs:break
                time.sleep(.25)
            report_path=out/f'report-{model_count}.json'
            result=subprocess.run([str(work/'verify'),str(work/f'cache-{model_count}'),str(report_path),f'127.0.0.1:{port}',str(model_count)],capture_output=True,text=True,timeout=40)
            (out/f'native-{model_count}.log').write_text(result.stdout+result.stderr)
            logs=subprocess.run(['docker','logs',name],capture_output=True,text=True);(out/f'server-{model_count}.log').write_text(logs.stdout+logs.stderr)
            (out/f'exit-code-{model_count}.json').write_text(json.dumps({'exitCode':result.returncode}))
            if result.returncode:raise SystemExit(f'Native server test exit {result.returncode}\n'+result.stdout+result.stderr)
            reports.append(json.loads(report_path.read_text()))
        finally:
            if started:subprocess.run(['docker','stop','--time','1',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            subprocess.run(['docker','image','rm',image],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    report={'status':'PASS','scenarios':reports,'scope':'Actual owned open.mp server; valid generated DFF/TXD; native CPU+GPU registration barrier; empty catalog boundary; stock spawn. Full app renderer integration remains separate.'}
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))
