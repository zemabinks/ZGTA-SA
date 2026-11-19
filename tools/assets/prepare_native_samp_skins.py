#!/usr/bin/env python3
"""Join an owned retail peds.ide with converted browser model names, locally."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[2]
def prepare(peds,index,output):
    local=(ROOT/'local-only').resolve();output=output.resolve()
    if local not in output.parents:raise ValueError('Generated game metadata must stay inside this project local-only directory')
    data=peds.read_bytes();raw=index.read_bytes()
    if len(data)>2_000_000 or len(raw)>2_000_000:raise ValueError('Unexpectedly large model catalogue')
    document=json.loads(raw);native=document.get('peds')
    if not isinstance(native,dict)or len(native)>1024:raise ValueError('Missing converted pedestrian catalogue')
    models={}
    for key,model in native.items():
        if not isinstance(key,str)or not key.isdecimal()or not isinstance(model,str)or not re.fullmatch(r'[a-z0-9_]{1,40}',model):raise ValueError('Invalid converted pedestrian entry')
        if model in models:raise ValueError('Ambiguous converted model name: '+model)
        models[model]=int(key)
    inside=False;seen=set();rows=[]
    for source in data.decode('cp1252').splitlines():
        line=source.split('#',1)[0].strip()
        if not line:continue
        if line.lower()=='peds':inside=True;continue
        if line.lower()=='end':inside=False;continue
        if not inside:continue
        parts=[part.strip()for part in line.split(',')]
        if len(parts)<3:raise ValueError('Malformed retail pedestrian row')
        identifier=int(parts[0]);model=parts[1].lower()
        if not 0<=identifier<=311 or identifier in seen or not re.fullmatch(r'[a-z0-9_]{1,40}',model):raise ValueError('Invalid/duplicate retail skin ID')
        seen.add(identifier);rows.append({'legacyID':identifier,'model':model,'nativeID':models.get(model)})
    if not rows:raise ValueError('Retail peds section is empty')
    result={'schema':1,'sourceHashes':{'pedsIDE':hashlib.sha256(data).hexdigest(),'nativeModelIndex':hashlib.sha256(raw).hexdigest()},'skins':sorted(rows,key=lambda row:row['legacyID'])}
    output.parent.mkdir(parents=True,exist_ok=True);temporary=output.with_suffix('.tmp');temporary.write_text(json.dumps(result,indent=2)+'\n');temporary.chmod(0o600);temporary.replace(output)
    return result
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--peds',type=Path,required=True,help='Owned retail GTA San Andreas data/peds.ide')
    p.add_argument('--index',type=Path,default=ROOT/'local-only/site/game/native/models/index.json');p.add_argument('--output',type=Path,default=ROOT/'local-only/original-world-assets/game/native/samp-skins.json')
    a=p.parse_args();result=prepare(a.peds.resolve(),a.index.resolve(),a.output)
    available=sum(row['nativeID']is not None for row in result['skins']);print('Prepared owner-local SA-MP skin map:',available,'converted,',len(result['skins'])-available,'unavailable. No game data added to public source.')
if __name__=='__main__':main()
