#!/usr/bin/env python3
"""Extract original vehicle boarding/driver clip choices into local-only data."""
import hashlib
import json
from pathlib import Path
from extract_client_catalog import bundle_with, json_literal

ROOT = Path(__file__).resolve().parent

def main():
    path, source = bundle_with("y5=JSON.parse('")
    table = json_literal(source,"y5=JSON.parse('","')")
    physics = json.loads((ROOT/'local-only/site/game/native/vehicles.physics.json').read_text())['models']
    models = {}
    def wire(name): return name.replace(':','/') if name else ''
    for model, row in physics.items():
        choice = table['o'].get(model,[0])
        group = table['T'][choice[0]]
        astride = choice[1] if len(choice)>1 else None
        flags = row['table'].get('modelFlags',0)
        if astride:
            prefix = 'wf' if astride=='wayfarer' else astride
            clips = {key:f'{astride}/{prefix}_{value}' for key,value in
                     [('sit','ride'),('still','still'),('left','left'),('right','right'),('forward','fwd'),('backward','back'),('passenger','passenger')]}
            if row.get('type') == 'bicycle':
                clips.update({role:f'{astride}/{prefix}_{role}' for role in ['pedal','sprint','bunnyhop']})
        else:
            if row['kind']=='boat' and not flags & 1024: names=['drive_boat','drive_boat_l','drive_boat_r']
            elif group.get('special',0)&4: names=['kart_drive','kart_l','kart_r']
            elif group.get('special',0)&8: names=['drive_truck','drive_truck_l','drive_truck_r']
            elif flags&4: names=['car_lsit','drive_lo_l','drive_lo_r']
            else: names=['car_sit','drive_l','drive_r']
            clips = {key:'ped/'+name for key,name in zip(['sit','left','right'],names)}
            clips['still'] = clips['sit']
            clips['passenger'] = 'ped/car_sitplo' if flags&4 else 'ped/car_sitp'
            clips['deadLeft'] = 'ped/car_dead_lhs'
            clips['deadRight'] = 'ped/car_dead_rhs'
            if not (row['kind']=='boat' and not flags&1024) and not flags&4 and not group.get('special',0)&12:
                clips.update({'slowLeft':'ped/drive_l_slow','slowRight':'ped/drive_r_slow'})
        clips['entry'] = wire((group.get('getIn') or ['ped:car_getin_lhs'])[0])
        clips['exit'] = wire((group.get('getOut') or ['ped:car_getout_lhs'])[0])
        models[model] = {'astride':bool(astride),'clips':clips,
                         'boarding':{key:[wire(x) for x in value] for key,value in group.items()
                                     if isinstance(value,list) and all(isinstance(x,str) or x is None for x in value)}}
    output = ROOT/'local-only/site/game/native/seating.json'
    output.write_text(json.dumps({'version':1,'source':path.name,
        'sha256':hashlib.sha256(source.encode()).hexdigest(),'models':models},separators=(',',':')))
    print(f'Prepared exact driver/boarding clip choices for {len(models)} vehicles')

if __name__=='__main__': main()
