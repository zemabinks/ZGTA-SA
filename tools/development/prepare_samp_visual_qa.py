#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Prepare an owner-local, nonannouncing DL visual fixture on loopback7793.

Only this independent generator/Pawn source is distributable. Owner army DFF/
TXD, generated binaries, official server bundle and logs stay in local-only.
Does not install or launch any iOS app.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,math,shutil,struct,subprocess,time,uuid
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-ui-dl-102'
BASE='zgta-openmp-qa:1.6.7.3218-files'
def pack(fmt,*values):return struct.pack('<'+fmt,*values)
def chunk(kind,data=b''):return pack('III',kind,len(data),0x1803ffff)+data
def sign_assets():
    frame=chunk(14,chunk(1,pack('I12fiI',1,1,0,0,0,1,0,0,0,1,0,0,0,-1,0))+chunk(3))
    texture=chunk(6,chunk(1,pack('I',0x1101))+chunk(2,b'qa_sign\0')+chunk(2,b'\0')+chunk(3))
    material=chunk(7,chunk(1,pack('I4BII3f',0,255,255,255,255,0,1,1,1,1))+texture+chunk(3))
    materials=chunk(8,chunk(1,pack('Ii',1,-1))+material)
    geometry=pack('HBBIII',0x16,1,0,2,4,1)+pack('8f',0,1,1,1,0,0,1,0)+pack('8H',1,0,0,2,1,2,0,3)
    geometry+=pack('4fII',0,0,1,math.sqrt(10),1,1)+pack('12f',-3,0,0,3,0,0,-3,0,2,3,0,2)+pack('12f',*(0,-1,0)*4)
    geometries=chunk(26,chunk(1,pack('I',1))+chunk(15,chunk(1,geometry)+materials+chunk(3)))
    atomic=chunk(20,chunk(1,pack('4I',0,0,5,0))+chunk(3))
    lo=(-3,-.15,0);hi=(3,.15,2);center=(0,0,1)
    collision=pack('4sI22sH',b'COL3',140,b'zgta_own_sign',0)+pack('10f',*lo,*hi,*center,math.sqrt(10.0225))
    collision+=pack('HHHBx7I',0,1,0,0,2,0,116,0,0,0,0)+pack('3I',0,0,0)+pack('6f4B',*lo,*hi,0,0,0,255)
    assert len(collision)==148
    dff=chunk(16,chunk(1,pack('3I',1,0,0))+frame+geometries+atomic+chunk(3,chunk(0x253f2fa,collision)))
    pixels=bytes([255,255,255,255])*16
    fields=pack('II32s32sIIHHBBBB',9,0x1101,b'qa_sign',b'',0x500,21,4,4,32,1,4,1)
    txd=chunk(22,chunk(1,pack('HH',1,2))+chunk(21,chunk(1,fields+pack('I',len(pixels))+pixels)+chunk(3))+chunk(3))
    return dff,txd
def command(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--start',action='store_true');parser.add_argument('--stop',action='store_true');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True);state=OUT/'server-state.json'
    if args.stop:
        info=json.loads(state.read_text());command(['docker','stop','--time','1',info['containerID']],stdout=subprocess.DEVNULL)
        subprocess.run(['docker','image','rm',info['image']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);info['status']='STOPPED';state.write_text(json.dumps(info,indent=2)+'\n');return
    work=OUT/'server';models=work/'models';models.mkdir(parents=True,exist_ok=True);work.chmod(0o777)
    dff,txd=sign_assets();(models/'qa-sign.dff').write_bytes(dff);(models/'qa-sign.txd').write_bytes(txd)
    for suffix in ['dff','txd']:shutil.copyfile(ROOT/'local-only/site/game'/('army.'+suffix),models/('owner-army.'+suffix))
    (models/'artconfig.txt').write_text('AddCharModel(287,20001,"owner-army.dff","owner-army.txd");\nAddSimpleModel(-1,19379,-1000,"qa-sign.dff","qa-sign.txd");\n')
    shutil.copyfile(ROOT/'tests/network/smoke_samp_visual.pwn',work/'visual.pwn')
    compiled=subprocess.run(['docker','run','--rm','--pull=never','--network=none','--entrypoint','/bin/sh','-v',str(work)+':/qa',BASE,'-c','LD_LIBRARY_PATH=/srv/openmp/qawno /srv/openmp/qawno/pawncc /qa/visual.pwn -i/srv/openmp/qawno/include -o/qa/visual.amx'],capture_output=True,text=True)
    (OUT/'pawn-compile.log').write_text(compiled.stdout+compiled.stderr)
    if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
    config=ROOT/'local-only/interop-openmp/release/Server/config.json'
    if not config.exists():config=ROOT.parent/'ZGTA-SA-core-101/local-only/interop-openmp/release/Server/config.json'
    settings=json.loads(config.read_text());settings.update(name='ZGTA isolated DL visual QA',announce=False,max_players=8)
    settings['network'].update(port=7793,bind='0.0.0.0',public_addr='127.0.0.1',minimum_connection_time=0,use_lan_mode=True,stream_rate=100)
    settings['artwork'].update(enable=True,port=7793,web_server_bind='0.0.0.0',cdn='',models_path='models',show_crc_logs=True)
    settings['pawn'].update(main_scripts=['visual 1'],side_scripts=[],legacy_plugins=[]);settings['rcon'].update(enable=False,password=uuid.uuid4().hex)
    (work/'config.json').write_text(json.dumps(settings,indent=2)+'\n')
    (work/'Dockerfile').write_text('FROM '+BASE+'\nCOPY --chown=65534:65534 config.json /srv/openmp/config.json\nCOPY --chown=65534:65534 visual.amx /srv/openmp/gamemodes/visual.amx\nCOPY --chown=65534:65534 models/ /srv/openmp/models/\n')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    info={'status':'PREPARED_NOT_STARTED','serverAddress':'127.0.0.1:7793','baseImage':BASE,'modelHashes':{p.name:sha(p)for p in models.glob('*')if p.is_file()},'publicSourceHashes':{p:sha(ROOT/p)for p in ['tools/development/prepare_samp_visual_qa.py','tests/network/smoke_samp_visual.pwn']},'compiledModeSHA256':sha(work/'visual.amx'),'models':{'ped':20001,'basePed':287,'object':-1000,'baseObject':19379,'authoredSign':'4vertices/2triangles,UVrectangle,materialslot0,embeddedCOL3box'},'poses':{'spawnNetworkRoot':[2296.5663,2451.6270,10.8203],'sign':[2296.5,2459,10.2],'car':[2301.5,2451.6,10.82]},'appInstalledOrLaunched':False,'originalAndGeneratedBinariesOwnerLocal':True}
    if args.start:
        image='zgtasa-dl-ui-qa:'+uuid.uuid4().hex[:10];name='zgta-dl-ui-qa-102-'+uuid.uuid4().hex[:10]
        with(OUT/'docker-build.log').open('w')as log:command(['docker','build','--pull=false','-t',image,str(work)],stdout=log,stderr=subprocess.STDOUT)
        ident=subprocess.check_output(['docker','run','--rm','--pull=never','-d','--name',name,'--label','org.zgtasa.qa=core102-dl-ui','-p','127.0.0.1:7793:7793/udp','-p','127.0.0.1:7793:7793/tcp',image],text=True).strip()
        info.update(status='STARTING',containerID=ident,containerName=name,image=image)
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            logs=subprocess.run(['docker','logs',ident],capture_output=True,text=True);(OUT/'server-startup.log').write_text(logs.stdout+logs.stderr)
            if 'Legacy Network started on'in logs.stdout+logs.stderr:info['status']='SERVER_STARTED_NOT_APP_TESTED';break
            time.sleep(.2)
    state.write_text(json.dumps(info,indent=2)+'\n');print(json.dumps({k:v for k,v in info.items()if k not in ['modelHashes','publicSourceHashes']},indent=2))
if __name__=='__main__':main()
