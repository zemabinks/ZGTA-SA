#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual flash-only conversion with independently generated RW clumps."""
from pathlib import Path
import hashlib,json,os,struct,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tools.assets import prepare_native_models as models
from tests.artwork_session.fixtures import assets,chunk,p
def main():
    os.setpriority(os.PRIO_PROCESS,0,15)
    inputs=[Path(__file__).resolve(),ROOT/'tools/assets/prepare_native_models.py',ROOT/'tools/assets/prepare_native_weapon_flashes.py',ROOT/'tests/artwork_session/fixtures.py']
    frozen={str(f):hashlib.sha256(f.read_bytes()).hexdigest()for f in inputs}
    out=ROOT/'local-only/research/weapon-flashes-170'/str(time.time_ns());out.mkdir(parents=True)
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Actual converter, independently generated textured DFF/TXD; no original assets or GPU acceptance')
    try:
        with tempfile.TemporaryDirectory(dir=out)as temporary:
            work=Path(temporary);original,txd=assets()
            root=models.first(list(models.chunks(original,0,len(original))),16)
            geometry=next(original[a-12:b]for kind,a,b in models.children(original,root)if kind==26)
            frames=p('I',3)
            for parent,x in [(-1,0),(0,2),(1,3)]:
                frames+=p('12fiI',1,0,0,0,1,0,0,0,1,x,0,0,parent,0)
            names=['body','GuNfLaSh','child']
            frame=chunk(14,chunk(1,frames)+b''.join(chunk(3,chunk(0x253f2fe,n.encode()+b'\0'))for n in names))
            atomics=b''.join(chunk(20,chunk(1,p('4I',i,0,5,0))+chunk(3))for i in [0,2])
            fixture=chunk(16,chunk(1,p('3I',2,0,0))+frame+geometry+atomics+chunk(3))
            source=work/'own.dff';source.write_bytes(fixture);source.with_suffix('.txd').write_bytes(txd)
            old_game=models.GAME;models.GAME=work
            try:
                body=work/'body.bin';flash=work/'own.flash.bin'
                bv,bf=models.convert(source,body);before={f.name:hashlib.sha256(f.read_bytes()).hexdigest()for f in work.glob('body.*')}
                fv,ff=models.convert(source,flash,selection='weapon-flash')
                assert (bv,bf,fv,ff)==(3,1,3,1),(bv,bf,fv,ff)
                assert before=={f.name:hashlib.sha256(f.read_bytes()).hexdigest()for f in work.glob('body.*')}
                body_parts=json.loads(body.with_suffix('.parts.json').read_text())['parts']
                flash_parts=json.loads(flash.with_suffix('.parts.json').read_text())['parts']
                assert [r['name']for r in body_parts]==['body']
                assert [r['name']for r in flash_parts]==['child']
                coords=struct.unpack_from('<9f',flash.read_bytes(),16)
                assert coords[0]==5 and coords[3]==6,coords
                noflash=work/'plain.dff';noflash.write_bytes(original);noflash.with_suffix('.txd').write_bytes(txd)
                try:models.convert(noflash,work/'missing.flash.bin',selection='weapon-flash')
                except ValueError as error:assert str(error)=='DFF has no weapon flash geometry'
                else:raise AssertionError('Flashless model fell back to full body')
                assert not(work/'missing.flash.bin').exists()
                for invalid in ['invalid']:
                    try:models.convert(source,work/'bad.bin',selection=invalid)
                    except ValueError:pass
                    else:raise AssertionError('Invalid selection')
            finally:models.GAME=old_game
        report.update(status='PASS',checks=9)
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items())
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
if __name__=='__main__':main()
