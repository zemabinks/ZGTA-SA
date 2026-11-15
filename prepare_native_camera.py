#!/usr/bin/env python3
"""Extract original camera profiles and zoom settings into local-only data."""
import hashlib,json,re
from prepare_native_atmosphere import ROOT,array


def object_literal(source,name):
 match=re.search(r'\b'+re.escape(name)+r'=\{',source);begin=match.end()-1;depth=0
 for end in range(begin,len(source)):
  depth+=(source[end]=='{')-(source[end]=='}')
  if depth==0:
   text=source[begin:end+1]
   text=re.sub(r'([,{])([A-Za-z_]\w*):',r'\1"\2":',text)
   text=re.sub(r'(?<=[\[,:])\s*(-?)\.(\d)',r'\g<1>0.\2',text)
   return json.loads(text)
 raise ValueError(name)


def main():
 chunks=ROOT/'local-only/site/_next/static/chunks'
 main=next(p for p in chunks.glob('*.js') if 'yM=[...wD.c$,24]' in p.read_text())
 vehicle=next(p for p in chunks.glob('*.js') if '98726:(e,t,l)' in p.read_text())
 source=main.read_text();module=vehicle.read_text().split('98726:(e,t,l)',1)[1]
 result={'source':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [main,vehicle]},
         'vehicleProfiles':object_literal(module,'i'),'vehicleDistances':object_literal(module,'s'),
         'vehicleAngles':object_literal(module,'u'),'cinematic':object_literal(module,'c'),
         'footDistances':array(source,'r0'),'footSights':object_literal(source,'aa'),
         'footWeaponFov':json.loads(re.search(r'\br5=new Map\((\[.+?\])\)',source).group(1))}
 weapons_path=ROOT/'local-only/site/game/native/weapons.json'
 weapons=json.loads(weapons_path.read_text())
 result['source'][weapons_path.name]=hashlib.sha256(weapons_path.read_bytes()).hexdigest()
 result['weaponSights']={weapon:('scope' if stat['fire']=='INSTANT_HIT' else 'camera' if stat['fire']=='CAMERA' else 'rocket')
                         for weapon,stat in weapons['stats'].items() if int(stat.get('flags','0'),16)&4}
 output=ROOT/'local-only/site/game/native/camera.json';output.parent.mkdir(parents=True,exist_ok=True)
 output.write_text(json.dumps(result,separators=(',',':'))+'\n');output.chmod(0o600)
 print(f'Prepared original on-foot and {len(result["vehicleProfiles"])} vehicle camera profiles in {output}')
if __name__=='__main__':main()
