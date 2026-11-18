#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Independently authored complete resource families for atlas regressions."""
import hashlib,json,struct,zlib
from pathlib import Path

def digest(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def png(width,height,pixels):
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 rows=b''.join(b'\0'+pixels[y*width*4:(y+1)*width*4] for y in range(height))
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
def mesh(layers=2):
 positions=[(-.8,-.8,.5),(.8,-.8,.5),(0,.8,.5)]
 return (struct.pack('<4I',0x324c5257,3,3,layers)+b''.join(struct.pack('<3f',*p) for p in positions)+
         struct.pack('<6f',0,0,1,0,.5,1)+struct.pack('<3I',0,1,2)+bytes([200,180,160,255]*3)+
         struct.pack('<4H',1 if layers>1 else 0,1 if layers>1 else 0,1 if layers>1 else 0,0)+bytes([80,100,120,255]*3)+bytes(layers*2))
def skeleton():
 identity=struct.pack('<16f',1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)
 frames=struct.pack('<ii',-1,0)+identity+struct.pack('<ii',0,1)+identity
 vertices=b''.join(struct.pack('<3f4B4f',*p,0,0,0,0,1,0,0,0) for p in [(-.8,-.8,.5),(.8,-.8,.5),(0,.8,.5)])
 return struct.pack('<4I',0x314e4b53,3,2,1)+identity+identity+frames+struct.pack('<I',1)+identity+vertices

def family(model='authored',mixed=False,body=(8,16),txd=True):
 cw,ch=body;rects=[[0,0,cw,ch],[cw,0,cw,ch]];columns=2
 if mixed:rects += [[0,ch,max(1,cw//2),max(1,ch//4)],[cw,ch,1,1]]
 if not txd:cw=ch=1;rects=[[0,0,1,1]];columns=1
 aw,ah=cw*columns,ch*(2 if mixed and txd else 1);pixels=bytearray([255]*(aw*ah*4))
 for slot,(x,y,w,h) in enumerate(rects[1:],1):
  for yy in range(h):
   for xx in range(w):
    at=((y+yy)*aw+x+xx)*4
    pixels[at:at+4]=bytes([(xx*31+slot*19)%256,(yy*17+slot*37)%256,(xx*7+yy*11+slot*13)%256,255 if slot%2 else 128])
 binary=mesh(len(rects));image=png(aw,ah,bytes(pixels))
 layout={'schema':1,'layout':'ped-tight-native-v1','sampling':'legacy-inset-fract-linear-no-mips','cell':[cw,ch],'columns':columns,'atlas':[aw,ah],
         'layers':[{'slot':i,'texture':None if i==0 else 'authored_'+str(i),'rect':r} for i,r in enumerate(rects)],
         'logicalRGBA8Bytes':aw*ah*4,'maximumRGBA8Bytes':512*1024,'meshSHA256':digest(binary),'atlasSHA256':digest(image),
         'sourceDFFSHA256':digest(b'independent authored geometry '+model.encode()),'sourceTXDSHA256':digest(b'independent authored pixels '+model.encode()) if txd else None}
 raw={'mesh':binary,'atlas':image,'layout':canonical(layout)+b'\n','skeleton':skeleton()}
 suffix={'mesh':'.bin','atlas':'.png','layout':'.atlas.json','skeleton':'.skel.bin'}
 resources={k:{'path':'game/native/models/ped-atlas-v1/'+digest(v)+'/'+model+suffix[k],'bytes':len(v),'sha256':digest(v)} for k,v in raw.items()}
 identity=digest(canonical({'model':model,'sourceDFFSHA256':layout['sourceDFFSHA256'],'sourceTXDSHA256':layout['sourceTXDSHA256']}))
 manifest={'schema':1,'format':'zgta-ped-atlas-family-v1','model':model,'sourceIdentity':identity,'resources':resources}
 metadata=canonical(manifest)+b'\n';path='game/native/models/ped-atlas-v1/'+digest(metadata)+'/'+model+'.json'
 return {'model':model,'path':path,'manifest':manifest,'metadata':metadata,'layout':layout,'files':raw,'pixels':bytes(pixels),'size':(aw,ah)}

def write_family(root:Path,value):
 for role,data in value['files'].items():
  path=root/value['manifest']['resources'][role]['path'];path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
 target=root/value['path'];target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(value['metadata'])
 return {k:value[k] for k in ['model','path','manifest','layout']}
