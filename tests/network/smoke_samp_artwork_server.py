#!/usr/bin/env python3
"""Optional real open.mp DL handshake; separate synthetic, disposable server."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,subprocess,tempfile,time,uuid
ROOT=Path(__file__).resolve().parents[2]
def run(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
def main():
 out=ROOT/'local-only/research/samp-artwork/server';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/NativeSAMPArtwork.swift','ios/App/NativeSAMPClient.swift','ios/App/NativeSAMPProtocol.swift','ios/App/NativeSAMPGameplayCommands.swift','tests/network/smoke_samp_artwork_server.py','tests/network/smoke_samp_artwork_server.swift']
 before={p:(ROOT/p).read_bytes()for p in paths}
 name='zgtasa-artwork-qa-'+uuid.uuid4().hex[:10];image='zgta-artwork-qa:'+uuid.uuid4().hex[:10]
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as temp:
  work=Path(temp);(work/'main.swift').write_bytes(before['tests/network/smoke_samp_artwork_server.swift'])
  result=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-samp/include'),*[str(ROOT/p)for p in paths[:4]],str(work/'main.swift'),'-L',str(ROOT/('local-only/native-samp/macos-'+platform.machine())),'-lzgtasa_samp','-lresolv','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  config=json.loads((ROOT/'local-only/interop-openmp/release/Server/config.json').read_text())
  config.update(name='ZGTA isolated DL artwork QA',announce=False,max_players=4)
  config['network'].update(port=7789,bind='0.0.0.0',public_addr='127.0.0.1',minimum_connection_time=0,use_lan_mode=True)
  config['artwork'].update(enable=True,port=7789,web_server_bind='0.0.0.0',cdn='',models_path='models',show_crc_logs=True)
  config['rcon'].update(enable=False,password=uuid.uuid4().hex)
  (work/'config.json').write_text(json.dumps(config,indent=2)+'\n');(work/'models').mkdir()
  (work/'models/synthetic.dff').write_bytes(b'ZGTA independent synthetic DFF; HTTP/protocol only, no rendering.\n'*17)
  (work/'models/synthetic.txd').write_bytes(b'ZGTA independent synthetic TXD; HTTP/protocol only, no rendering.\n'*13)
  (work/'models/artconfig.txt').write_text('AddSimpleModel(-1,19379,-1000,"synthetic.dff","synthetic.txd");\n')
  (work/'Dockerfile').write_text('FROM zgta-openmp-qa:1.6.7.3218-files\nCOPY --chown=65534:65534 config.json /srv/openmp/config.json\nCOPY --chown=65534:65534 models/ /srv/openmp/models/\n')
  with(out/'docker-build.log').open('w')as log:run(['docker','build','-t',image,str(work)],stdout=log,stderr=subprocess.STDOUT)
  started=False
  try:
   run(['docker','run','--rm','-d','--name',name,'-p','127.0.0.1:7789:7789/udp','-p','127.0.0.1:7789:7789/tcp',image],stdout=subprocess.DEVNULL);started=True
   deadline=time.monotonic()+12
   while time.monotonic()<deadline:
    logs=subprocess.run(['docker','logs',name],capture_output=True,text=True).stdout
    if 'Started server on' in logs:break
    time.sleep(0.25)
   result=subprocess.run([str(work/'verify'),str(work/'cache'),str(out/'native-report.json')],capture_output=True,text=True,timeout=30)
   (out/'native.log').write_text(result.stdout+result.stderr)
   logs=subprocess.run(['docker','logs',name],capture_output=True,text=True);(out/'server.log').write_text(logs.stdout+logs.stderr)
   unchanged=all((ROOT/p).read_bytes()==b for p,b in before.items())
   report={'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(b).hexdigest()for p,b in before.items()},'output':result.stdout+result.stderr,'serverImage':'zgta-openmp-qa:1.6.7.3218-files','ports':'separate localhost7789 UDP+TCP; existing7777 server untouched','limits':['Actual official open.mp server RPC/HTTP completion and stock class/spawn transaction','Synthetic text files are transfer fixtures, not native RenderWare model acceptance','Standalone NativeSAMPClient+artwork helper: application UI integration and runtime custom-model importer remain separate']}
   (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
  finally:
   if started:subprocess.run(['docker','stop','--time','1',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   subprocess.run(['docker','image','rm',image],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if __name__=='__main__':main()
