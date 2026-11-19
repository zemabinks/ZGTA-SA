#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Author-created X8/A8 carriers through actual decode and both atlas producers.

D3D format 22 has no alpha channel; format 21 retains its alpha channel.
Reference: https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dformat
No original game resources, SDK, service, app cache or account is used.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,io,json,struct,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from PIL import Image
import tools.assets.prepare_native_models as converter
import tools.assets.prepare_native_ped_atlas as producer
from tests.resources import test_native_ped_atlas as fixtures
from tests.resources.test_native_ped_atlas import txd,write_source,spec,dff
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--converter-source",type=Path);args=parser.parse_args()
if args.converter_source:
 loader=importlib.util.spec_from_file_location("selected_texture_converter",args.converter_source);selected=importlib.util.module_from_spec(loader);loader.loader.exec_module(selected)
 converter=selected;producer.converter=selected;fixtures.converter=selected
OUT=ROOT/'local-only/research/texture-format-141/authored';OUT.mkdir(parents=True,exist_ok=True)
inputs=[args.converter_source if args.converter_source else ROOT/'tools/assets/prepare_native_models.py',ROOT/'tools/assets/prepare_native_ped_atlas.py',ROOT/'tests/resources/test_native_ped_atlas.py',Path(__file__).resolve()]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs};checks=0

def check(value,label):
 global checks
 checks+=1
 if not value:raise AssertionError(label)

def encode(image,code):
 data=bytearray(txd({'body':image}))
 root=converter.first(list(converter.chunks(data,0,len(data))),0x16)
 native=next(c for c in converter.children(data,root)if c[0]==0x15)
 info=converter.first(converter.children(data,native),1)
 struct.pack_into('<II',data,info[1]+72,0x600 if code==22 else 0x500,code)
 return bytes(data)

def run():
 pixels=[(231,37,19,a)for a in range(256)]
 image=Image.new('RGBA',(16,16));image.putdata(pixels)
 with tempfile.TemporaryDirectory(prefix='rgba-',dir=OUT)as temporary:
  work=Path(temporary);selected=[]
  for code in [21,22]:
   model='authored_a8'if code==21 else'authored_x8'
   entry=write_source(work,model,{'body':image});path=Path(entry['sources']['txd']['path']);path.write_bytes(encode(image,code))
   Path(entry['sources']['dff']['path']).write_bytes(dff(['body'],[0x11106]))
   decoded=converter.textures(path)
   check('body'in decoded,'Valid texture disappeared')
   expected=[(r,g,b,a if code==21 else 255)for r,g,b,a in pixels]
   for got,wanted in zip(decoded['body'].getdata(),expected):check(got==wanted,'X8 unused bits became opacity'if code==22 else'A8 alpha was changed')
   # Regenerate the actual legacy mesh after changing the authored source type.
   converter.convert(Path(entry['sources']['dff']['path']),Path(entry['sources']['mesh']['path']),pedestrian=True)
   for role in ['dff','txd','mesh','parts']:entry['sources'][role]=spec(Path(entry['sources'][role]['path']))
   selected.append(entry)
  for version in [1,2]:
   destination=work/('family-v'+str(version));producer.build({'schema':1,'models':selected},destination,version=version)
   overlay,files=producer.validate_overlay(destination)
   for entry in selected:
    model=entry['model'];family=producer.decode_json(files[overlay['models'][model]].read_bytes())
    layout=producer.decode_json(files[family['resources']['layout']['path']].read_bytes())
    layer=next(row for row in layout['layers']if row['texture']=='body')
    with Image.open(io.BytesIO(files[family['resources']['atlas']['path']].read_bytes()))as atlas:
     x,y,w,h=layer['rect'];crop=atlas.convert('RGBA').crop((x,y,x+w,y+h))
     if model=='authored_x8':
      check(crop.getextrema()[3]==(255,255),'Prepared family retained unused X8 bits as alpha')
      check(all(pixel[:3]==(231,37,19)for pixel in crop.getdata()),'Opaque preparation changed RGB')
     elif version==2:check(list(crop.getdata())==pixels,'Native-size A8 family lost original RGBA')
     else:check(crop.getextrema()[3][0]<255,'A8 family was flattened to opaque')
   again=work/('repeat-v'+str(version));producer.build({'schema':1,'models':selected},again,version=version)
   check((again/'overlay.json').read_bytes()==(destination/'overlay.json').read_bytes(),'Repeat preparation changed content-addressed graph')
 check(all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items()),'Source changed during producer test')

started=time.monotonic()
try:run()
except Exception as error:
 report=dict(status='FAIL',error=str(error),checks=checks,sourceHashes=hashes,seconds=time.monotonic()-started,syntheticOnly=True)
 (OUT/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise
report=dict(status='PASS',checks=checks,sourceHashes=hashes,seconds=time.monotonic()-started,syntheticOnly=True,scope='Literal texture decoder and v1/v2 prepared family builders/validators on authored TXD/DFF/SKN bytes; no native render or retail appearance claim.')
(OUT/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
