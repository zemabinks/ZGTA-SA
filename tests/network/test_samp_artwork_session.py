#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real HTTP/cache + generated valid RW importer lifecycle regressions."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import http.server
import importlib.util
import json
import pathlib
import subprocess
import threading

ROOT=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--skip-build',action='store_true');args=parser.parse_args()
out=ROOT/'local-only/research/artwork-session'
out.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('session_fixtures',ROOT/'tests/artwork_session/fixtures.py')
fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
dff,txd=fixtures.assets()
from tests.resources.smoke_native_renderware_dff import synthetic
skinned=synthetic()
(out/'fixture.dff').write_bytes(dff);(out/'fixture.txd').write_bytes(txd)
(out/'skinned.dff').write_bytes(skinned)
requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append({'path':self.path,'agent':self.headers.get('User-Agent'),'cookie':self.headers.get('Cookie')})
        body=dff if self.path=='/dff' else txd if self.path=='/txd' else skinned if self.path=='/skinned' else bytes(len(dff))
        self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers()
        try:self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError):pass
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
try:
    binary=out/'session-tests'
    files=['NativeSAMPArtwork.swift','NativeSAMPArtworkSession.swift','NativeRenderWareDFF.swift','NativeRenderWareTXD.swift','NativeRenderWareModel.swift']
    if not args.skip_build:
        build=subprocess.run(['xcrun','swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*[str(ROOT/'ios/App'/p) for p in files],str(ROOT/'tests/artwork_session/main.swift'),'-o',str(binary)],capture_output=True,text=True)
        (out/'build.log').write_text(build.stdout+build.stderr)
        if build.returncode:raise SystemExit(f'Compile exit {build.returncode}\n'+build.stdout+build.stderr)
    result=subprocess.run([str(binary),str(out),f'http://127.0.0.1:{server.server_port}'],capture_output=True,text=True,timeout=80)
    (out/'stdout.log').write_text(result.stdout);(out/'stderr.log').write_text(result.stderr)
    (out/'exit-code.json').write_text(json.dumps({'exitCode':result.returncode}))
    if result.returncode:raise SystemExit(f'Native test exit {result.returncode}\n'+result.stdout+result.stderr)
    report=json.loads(result.stdout);report['httpRequests']=len(requests)
    report['cookieFree']=all(x['cookie'] is None for x in requests)
    report['sampUserAgent']=all(x['agent']=='SAMP/0.3' for x in requests)
    assert report['cookieFree'] and report['sampUserAgent']
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))
finally:server.shutdown();server.server_close()
