#!/usr/bin/env python3
"""Export exact original first-seat coordinates/clip roles into ignored data."""
from pathlib import Path
import hashlib,json,math
import prepare_native_models as dff
import prepare_native_seating
ROOT=Path(__file__).resolve().parent

def main():
    prepare_native_seating.main()
    physics=json.loads((dff.GAME/'native/vehicles.physics.json').read_text())['models']
    seating=json.loads((dff.GAME/'native/seating.json').read_text())['models']
    models={};missing=[]
    for identifier,row in physics.items():
        model=row['model'];raw=(dff.GAME/(model+'.dff')).read_bytes()
        clump=dff.first(list(dff.chunks(raw,0,len(raw))),0x10)
        frame_chunk=dff.first(dff.children(raw,clump),0x0e)
        frames=dff.frame_list(raw,frame_chunk);names=dff.frame_names(raw,frame_chunk)
        if 'ped_frontseat' not in names:
            missing.append(identifier);continue
        seat=list(dff.transform((0,0,0),frames,names.index('ped_frontseat')))
        config=seating[identifier]
        if config['astride']:
            side=0
        elif row['kind']=='boat':
            side=0 if abs(seat[0])<0.15 else 1 if seat[0]>0 else -1
        elif abs(seat[0])<0.15:
            side=0
        else:
            seat[0]=-abs(seat[0]);side=-1
        if not all(math.isfinite(value) for value in seat):raise ValueError(f'Invalid rider seat:{identifier}')
        models[identifier]={'model':model,'astride':config['astride'],'clips':config['clips'],
                            'driverSeat':seat,'driverSide':side,
                            'origin':row['origin'],'sha256':hashlib.sha256(raw).hexdigest()}
    output=dff.GAME/'native/riders.json'
    output.write_text(json.dumps({'version':1,'models':models,'withoutSeat':missing},separators=(',',':'))+'\n')
    output.chmod(0o600)
    print(f'Prepared{len(models): d} original rider seats/clip profiles;{len(missing): d} original models have no front-seat frame')

if __name__=='__main__':main()
