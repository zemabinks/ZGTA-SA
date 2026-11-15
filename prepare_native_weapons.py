#!/usr/bin/env python3
"""Recover the archived client gun shop catalogue for local native/server use.

All extracted prices, placements, stats, and textures remain under ignored
local-only/. Source code contains the extraction procedure rather than the data.
"""
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
CHUNKS = ROOT / 'local-only/site/_next/static/chunks'
WEAPONS = ROOT / 'local-only/site/game/native/weapons.json'
OUTPUT = ROOT / 'local-only/selfhost/weapon-catalog.json'
NATIVE = ROOT / 'local-only/site/game/native/weapon-shop.json'


def literal(source, name):
    match = re.search(r'\b' + re.escape(name) + r"=JSON\.parse\('((?:[^'\\]|\\.)*)'\)", source)
    if not match:
        raise ValueError(f'Archived {name} JSON object was not found')
    return json.loads(match.group(1).replace("\\'", "'"))


def main():
    matches = [(path, path.read_text()) for path in CHUNKS.glob('*.js')
               if 'let cf=JSON.parse(' in path.read_text()]
    if len(matches) != 1:
        raise SystemExit('Exactly one archived gun shop client bundle is required')
    source_path, source = matches[0]
    shop, entries, businesses = literal(source, 'cf'), literal(source, 'uU'), literal(source, 'CZ')
    weapons = json.loads(WEAPONS.read_text())
    definitions = {entry['id']: entry for entry in weapons['definitions']}
    stats = weapons['stats']
    items = []
    for item in shop['ld']:
        weapon = definitions.get(item['id'], {})
        stat = stats.get(str(item['id']), {})
        items.append({**item, 'name': weapon.get('name', item['tag']),
                      'slot': stat.get('slot', -1), 'capacity': stat.get('clip', 0),
                      'fire': stat.get('fire', 'ARMOUR' if item['id'] == shop['Bq'] else 'UNKNOWN'),
                      'modelName': weapon.get('modelName', ''), 'stats': stat})
    known = [item for item in businesses['N$'] if item.get('kind') == 'ammu']
    shops = []
    for row in entries['i']:
        if row[0] not in {item['name'] for item in shop['uP']} or row[3] >= 100:
            continue
        door, outside = row[1:4], row[7:11]
        closest = min(known, key=lambda item: math.dist(item['door'], door)) if known else None
        if closest and math.dist(closest['door'], door) <= 10:
            key, name = closest['key'], closest['name']
        else:
            key, name = f'ammu-{len(shops)+1}', f'Ammu-Nation {len(shops)+1}'
        if any(math.dist(item['door'], door) < 1 for item in shops):
            continue
        interior = next(item for item in shop['uP'] if item['name'] == row[0])
        shops.append({'id': key, 'name': name, 'kind': row[0], 'door': door,
                      'out': outside, 'counter': interior['stand'],
                      'keeper': interior['keeper'], 'icon': 'radar_ammugun'})
    if len(items) != 16 or len(shops) < 10:
        raise ValueError('Archived gun shop catalogue is incomplete')
    document = {'version': 1, 'armourID': shop['Bq'], 'items': items, 'shops': shops,
                'source': {source_path.name: hashlib.sha256(source.encode()).hexdigest(),
                           WEAPONS.name: hashlib.sha256(WEAPONS.read_bytes()).hexdigest()},
                'evidence': {'purchasePrice': 'cP: refill when ammo > 0 or later pack; otherwise price',
                             'purchaseLimits': 'cM/cz: one item per slot; 1..20 packs; max 9999 rounds',
                             'serverRules': 'Server ownership, 8m exterior/counter access and reload timing are local policies.'}}
    for destination in [OUTPUT, NATIVE]:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(document, separators=(',', ':'), ensure_ascii=False)+'\n')
        destination.chmod(0o600)
    print(f'Prepared {len(items)} archived gun shop items and {len(shops)} entrances in ignored local data')


if __name__ == '__main__':
    main()
