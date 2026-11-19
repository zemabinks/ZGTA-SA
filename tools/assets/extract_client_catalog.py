#!/usr/bin/env python3
"""Derive local-only catalog data from the archived public browser bundles.

The extracted game data is never written outside local-only/.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHUNKS = ROOT / 'local-only' / 'site' / '_next' / 'static' / 'chunks'
OUTPUT = ROOT / 'local-only' / 'selfhost' / 'client-catalog.json'
HANDLING_OUTPUT = ROOT / 'local-only' / 'site' / 'game' / 'native' / 'handling.json'
WEAPON_OUTPUT = HANDLING_OUTPUT.with_name('weapons.json')


def bundle_with(marker):
    for path in CHUNKS.glob('*.js'):
        contents = path.read_text(encoding='utf-8')
        if marker in contents:
            return path, contents
    raise FileNotFoundError(f'Archived browser bundle containing {marker!r} was not found')


def json_literal(source, before, after):
    start = source.index(before) + len(before)
    end = source.index(after, start)
    # The bundle wraps JSON in a JavaScript single-quoted string.
    return json.loads(source[start:end].replace("\\'", "'"))


def main():
    vehicles_path, vehicles_js = bundle_with('"name":"Manana"')
    vehicle_data = json_literal(vehicles_js, "e.exports=JSON.parse('", "')")
    handling_path, handling_js = bundle_with('94736:P=>{P.exports=JSON.parse(')
    handling_data = json_literal(handling_js, "94736:P=>{P.exports=JSON.parse('", "')")
    weapon_path, weapon_js = bundle_with('"WEAPON_COLT45"')
    weapons = json_literal(weapon_js, "e.exports=JSON.parse('", "')")
    stats_path, stats_js = bundle_with('"targetRange":30,"range":35')
    stats = json_literal(stats_js, "e.exports=JSON.parse('", "')")['gc']
    game_path, game_js = bundle_with('let cZ=JSON.parse(\'{"gl"')
    dealerships = json_literal(game_js, "let cZ=JSON.parse('", "'),[c0,c1]")
    properties = json_literal(game_js, "ut=JSON.parse('", "'),ul=ut.Fb")
    if len(vehicle_data) < 200 or len(handling_data) < 200 or len(properties['Fb']) < 20 or len(dealerships['r1']) < 5:
        raise ValueError('Archived client catalog is incomplete')

    car_dealers = dealerships['r1']
    hangars = dealerships['bo']
    all_dealers = car_dealers + hangars
    stock = {vehicle_id: [] for dealer in all_dealers for vehicle_id in dealer['sells']}
    for dealer in all_dealers:
        for vehicle_id in dealer['sells']:
            stock[vehicle_id].append(dealer['key'])
    cars = []
    for vehicle in vehicle_data:
        model = vehicle['id']
        price = dealerships['Vt'].get(str(model), dealerships['B$'].get(str(model)))
        cars.append({
            'model': model,
            'name': vehicle['name'],
            'type': vehicle['type'],
            'colors': (vehicle.get('colors') or [1, 1])[:2],
            'price': price,
            'dealers': stock.get(model, []),
        })
    catalog = {
        'source': {
            vehicles_path.name: hashlib.sha256(vehicles_js.encode()).hexdigest(),
            game_path.name: hashlib.sha256(game_js.encode()).hexdigest(),
        },
        'vehicles': cars,
        'dealers': all_dealers,
        'homes': properties['Fb'],
        'interior_spawns': properties['LQ'],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    OUTPUT.chmod(0o600)
    # Keep the publisher's handling rows with the other ignored, local game
    # files. The native client loads these values from the host at runtime.
    HANDLING_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    HANDLING_OUTPUT.write_text(json.dumps({
        'source': {handling_path.name: hashlib.sha256(handling_js.encode()).hexdigest()},
        'rows': handling_data,
        'models': {str(vehicle['id']): vehicle for vehicle in vehicle_data},
        'vehicles': {str(car['model']): {'name': car['name'], 'type': car['type']}
                     for car in cars},
    }, separators=(',', ':')) + '\n', encoding='utf-8')
    HANDLING_OUTPUT.chmod(0o600)
    WEAPON_OUTPUT.write_text(json.dumps({'definitions': weapons, 'stats': stats,
        'source': {p.name: hashlib.sha256(s.encode()).hexdigest()
                   for p, s in [(weapon_path, weapon_js), (stats_path, stats_js)]}}, separators=(',', ':')) + '\n')
    WEAPON_OUTPUT.chmod(0o600)
    priced = sum(car['price'] is not None for car in cars)
    print(f'Wrote {len(cars)} vehicles ({priced} priced), {len(all_dealers)} dealers/hangars, '
          f'and {len(catalog["homes"])} homes to {OUTPUT}; '
          f'{len(handling_data)} handling rows to {HANDLING_OUTPUT}')


if __name__ == '__main__':
    main()
