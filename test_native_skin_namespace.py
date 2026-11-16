#!/usr/bin/env python3
"""Compare native skin identities with the owner's actual browser wire catalogue.

All extracted catalogues and regenerated metadata stay in ignored local-only/.
This gate does not open a browser, connect a player, or render a game frame.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import subprocess
import sys
import tempfile

import prepare_native_models as models
import prepare_native_samp_skins as skins
from smoke_native_climb_runtime import function

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/research/skin-identity-104'


def balanced(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, quote, escaped = 0, None, False
    for at in range(opening, len(source)):
        char = source[at]
        if quote:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ('"', "'", '`'):
            quote = char
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return source[start:at + 1]
    raise ValueError('Unbalanced reference function')


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=ROOT / 'local-only/site/game/native/models/index.json')
    parser.add_argument('--model-overrides', type=Path)
    parser.add_argument('--out', type=Path, default=OUT)
    args = parser.parse_args()
    OUT = args.out.resolve()
    if (ROOT / 'local-only').resolve() not in OUT.parents:
        raise ValueError('Namespace evidence must stay owner-local')
    OUT.mkdir(parents=True, exist_ok=True)
    checks = 0

    def check(value, message):
        nonlocal checks
        checks += 1
        if not value:
            raise AssertionError(message)

    def bundle(rows):
        return "80799:e=>{e.exports=JSON.parse('" + json.dumps(rows) + "')}"

    synthetic = [{'id': 14, 'model': 'test_beta', 'txd': 'TEST_BETA'},
                 {'id': 0, 'model': 'null', 'txd': 'generic'},
                 {'id': 7, 'model': 'test_alpha', 'txd': 'test_alpha'}]
    parsed = models.canonical_pedestrian_rows(bundle(synthetic))
    check(models.pedestrian_model_index(parsed, {'null', 'test_alpha', 'test_beta'}) ==
          {'14': 'test_beta', '7': 'test_alpha'}, 'Explicit IDs were replaced by positions')
    check(models.pedestrian_model_index(parsed, {'test_alpha'}) == {'7': 'test_alpha'},
          'Unavailable model was advertised')
    malformed = [[], {}, [None]]
    for bad in [True, -1, 312, 7.0, '7', None]:
        row = dict(synthetic[2], id=bad)
        malformed.append([row])
    aliases = models.canonical_pedestrian_rows(bundle([
        synthetic[2], dict(synthetic[2], id=14, model='TEST_ALPHA')]))
    check(models.pedestrian_model_index(aliases, {'test_alpha'}) ==
          {'7': 'test_alpha', '14': 'test_alpha'}, 'Explicit same-resource alias was lost')
    malformed += [[synthetic[2], synthetic[2]],
                  [synthetic[2], dict(synthetic[2], id=14, txd='different_texture')]]
    for name in ['', '../unsafe', 'a' * 41, 'bad name', 'é']:
        malformed.append([dict(synthetic[2], model=name)])
        malformed.append([dict(synthetic[2], txd=name)])
    for rows in malformed:
        try:
            models.canonical_pedestrian_rows(bundle(rows))
        except (ValueError, TypeError, KeyError):
            check(True, 'Rejected malformed catalogue')
        else:
            check(False, 'Malformed catalogue was accepted')

    chunks = ROOT / 'local-only/site/_next/static/chunks'
    primary = []
    primary_sources = []
    for name in ['7625.9f01e629ca3317ba.js', '231-37f5250a7fde671c.js']:
        path = chunks / name
        primary.append(models.canonical_pedestrian_rows(path.read_text()))
        primary_sources.append({'name': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    check(primary[0] == primary[1], 'Archived browser modules disagree')
    canonical = primary[0]
    by_id = {row['id']: row for row in canonical}
    check(by_id[2]['model'] == 'maccer' and by_id[7]['model'] == 'male01' and
          by_id[14]['model'] == 'bmori' and by_id[287]['model'] == 'army',
          'Pinned browser skin identities changed')

    index_path = args.index.resolve()
    original_index_data = index_path.read_bytes()
    original = json.loads(original_index_data)
    available = set(original['peds'].values())
    corrected = copy.deepcopy(original)
    corrected['peds'] = models.pedestrian_model_index(canonical, available)
    check(set(corrected['peds'].values()) == set(original['peds'].values()),
          'Migration lost/added an unverified ped')
    check(set(corrected['peds'].values()) == available, 'Migration changed model identities')
    check(corrected['vehicles'] == original['vehicles'] and corrected['weapons'] == original['weapons'],
          'Ped migration changed another model catalogue')
    check(corrected['peds']['7'] == 'male01' and corrected['peds']['14'] == 'bmori',
          'Known reciprocal mismatch remains')
    if 'maccer' in available:
        check(corrected['peds'].get('2') == 'maccer', 'Available Maccer has the wrong wire ID')
    else:
        check('2' not in corrected['peds'], 'Missing Maccer was substituted')
    for row in canonical:
        if row['model'] == 'null' or row['model'] not in available:
            check(str(row['id']) not in corrected['peds'], 'Unavailable model was substituted')

    # Retain the original 265-model migration as its own pinned fixture even
    # when the current COW site already exposes Maccer or a larger import.
    styles_path = ROOT / 'local-only/site/game/world/peds.json'
    compact_rows = json.loads(styles_path.read_text())['peds']
    compact = {str(number): row[0].lower() for number, row in enumerate(compact_rows)
               if row[0].lower() in available and row[0].lower() != 'null'}
    check(len(compact) == 265, 'The pinned original pedestrian population changed')
    pin = ROOT / 'local-only/research/skin-identity-104/pinned-265'
    pin.mkdir(parents=True, exist_ok=True)
    pinned = pin / 'index.json'
    if not pinned.exists():
        document = copy.deepcopy(original)
        document['peds'] = compact
        pinned.write_bytes(original_index_data if original['peds'] == compact else
                           (json.dumps(document, separators=(',', ':')) + '\n').encode())
        (pin / 'provenance.json').write_text(json.dumps({
            'sourceIndexSHA256': hashlib.sha256(original_index_data).hexdigest(),
            'animationListSHA256': hashlib.sha256(styles_path.read_bytes()).hexdigest(),
            'capturedCompactIndex': original['peds'] == compact,
            'pinnedIndexSHA256': hashlib.sha256(pinned.read_bytes()).hexdigest()
        }, indent=2) + '\n')
    pinned_document = json.loads(pinned.read_text())
    pin_provenance = json.loads((pin / 'provenance.json').read_text())
    check(hashlib.sha256(pinned.read_bytes()).hexdigest() == pin_provenance['pinnedIndexSHA256'],
          'Pinned migration fixture was modified')
    check(pinned_document['peds'] == compact, 'Pinned compact model identities changed')
    migrated_pin = models.pedestrian_model_index(canonical, set(compact.values()))
    check(len(migrated_pin) == 265 and set(migrated_pin.values()) == set(compact.values()),
          'Pinned265 migration lost/added models')
    (pin / 'report.json').write_text(json.dumps({'status': 'PASS', 'models': 265,
        'mapping': [{'oldCompactID': int(key), 'model': name,
                     'wireID': next(row['id'] for row in canonical if row['model'] == name)}
                    for key, name in compact.items()], 'source': pin_provenance}, indent=2) + '\n')

    ide = ROOT / 'local-only/research/stock-models/retail-ide/data/peds.ide'
    if not ide.is_file():
        raise FileNotFoundError('Import the owner peds.ide into ' + str(ide))

    model_root = ROOT / 'local-only/site/game/native/models'
    def model_file(name, suffix):
        override = args.model_overrides / (name + suffix) if args.model_overrides else None
        return override if override is not None and override.is_file() else model_root / (name + suffix)
    for name in available:
        mesh = model_file(name, '.bin')
        image = model_file(name, '.png')
        skeleton = model_file(name, '.skel.bin')
        check(mesh.is_file() and image.is_file() and skeleton.is_file(), 'Missing declared pedestrian resources: ' + name)
        with mesh.open('rb') as stream:
            mesh_header = stream.read(16)
        with skeleton.open('rb') as stream:
            skin_header = stream.read(16)
        check(len(mesh_header) == len(skin_header) == 16 and mesh_header[:4] == b'WRL2' and skin_header[:4] == b'SKN1',
              'Invalid declared pedestrian resources: ' + name)
        check(int.from_bytes(mesh_header[4:8], 'little') == int.from_bytes(skin_header[4:8], 'little') > 0,
              'Mesh and skin vertex counts differ: ' + name)
    # Per-ped legacy animation archives are large and are not rewritten by an
    # index migration. Hash only the mesh, atlas, parts and skin files at issue.
    model_files = sorted(model_file(name, suffix) for name in available
                         for suffix in ('.bin', '.png', '.parts.json', '.skel.bin')
                         if model_file(name, suffix).is_file())
    before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in model_files}
    overlay = OUT / 'overlay/game/native'
    (overlay / 'models').mkdir(parents=True, exist_ok=True)
    output_index = overlay / 'models/index.json'
    output_index.write_text(json.dumps(corrected, separators=(',', ':')) + '\n')
    output_skins = overlay / 'samp-skins.json'
    skin_map = skins.prepare(ide, output_index, output_skins)
    if 'maccer' in available:
        check(by_id[2]['model'] == 'maccer' and not any(row['legacyID'] == 2 for row in skin_map['skins']),
              'Maccer supplement conflicts with retail IDE')
        skin_map['skins'].append({'legacyID': 2, 'nativeID': 2, 'model': 'maccer'})
        skin_map['skins'].sort(key=lambda row: row['legacyID'])
        skin_map['sourceHashes']['browserModelCatalog80799'] = primary_sources[0]['sha256']
        output_skins.write_text(json.dumps(skin_map, indent=2) + '\n')
    mapped = [row for row in skin_map['skins'] if row['nativeID'] is not None]
    check({row['model'] for row in mapped}.issubset(available), 'SA-MP catalogue advertised an absent model')
    for row in mapped:
        check(row['legacyID'] == row['nativeID'] and
              corrected['peds'][str(row['nativeID'])] == row['model'],
              'Browser and SA-MP identities disagree')

    main_path = chunks / '9737.c81ad6ccfd85b371.js'
    browser = main_path.read_text()
    server_path = ROOT / 'selfhost_backend.js'
    backend = server_path.read_text()
    # Evaluate only the pinned pure lookup and our pure row function. The real
    # backend module is never required: that would acquire a live state lock.
    js = "const vm=require('node:vm'),fs=require('node:fs');\n"
    js += 'const table=' + json.dumps(canonical) + ';\n'
    js += 'const ah=vm.runInNewContext(' + json.dumps('(' + balanced(browser, 'function ah(') + ')') + ',{l8:table});\n'
    helpers = '\n'.join(balanced(backend, marker) for marker in
                        ['function finite(', 'function limited(', 'function rounded('])
    row_function = balanced(backend, '  row(peer) {')
    factory = '(function(){' + helpers + '\nclass Game{' + row_function + '}return new Game()})()'
    js += 'const server=vm.runInNewContext(' + json.dumps(factory) + ',{Date,Math,Number});\n'
    js += 'const index=' + json.dumps(corrected['peds']) + ';let checks=0;\n'
    js += '''for(const [skin,model]of Object.entries(index)){
      for(const driving of [false,true]){
        const peer={player:{number:2,name:'Synthetic fixture',health:100,armour:0},lastSeen:Date.now(),
          state:{skin:Number(skin),walking:!driving,driving,car:'411.0.0.0.',x:0,y:0,z:0}};
        const row=server.row(peer),wire=driving?row[31]:Number(row[2].slice(1));
        if(wire!==Number(skin)||ah(wire).model.toLowerCase()!==model)throw Error('Cross-client identity mismatch');
        checks++;
      }
    }
    if(ah(7).model.toLowerCase()!=='male01'||ah(2).model.toLowerCase()!=='maccer')throw Error('Browser golden changed');
    console.log(JSON.stringify({checks,pureServerAndBrowserLookup:true,liveConnections:0}));
    '''
    (OUT / 'actual-reference.cjs').write_text(js)
    result = subprocess.run(['node', str(OUT / 'actual-reference.cjs')], capture_output=True, text=True, check=True)
    reference = json.loads(result.stdout)

    renderer_path = ROOT / 'ios/App/NativeWorldRenderer.swift'
    client_path = ROOT / 'ios/App/NativeMultiplayerClient.swift'
    renderer = renderer_path.read_text()
    client = client_path.read_text()
    swift = '''import Foundation
final class VisibilitySpy{var resets=0;func reset(){resets+=1}}
final class Renderer{
 var pedModels:[String:String]=[:],vehicleModels:[String:String]=[:],legacyPedModels:[String:Int]=[:]
 var localSkin=7,pendingLocalSkin:Int?,localLegacySkin:Int?,pendingLegacySkin:Int?
 var sampSkinCatalog:NativeSAMPSkinCatalog?,onStatus:((String)->Void)?
 var ownRiderCapture:Int?,ownRiderPrevious:Int?,ownRiderFeet:Int?
 let ownCameraVisibility=VisibilitySpy();var loaded:[String]=[]
 func loadActor(_ name:String){loaded.append(name)}
 func prepareFootAnimation(){}
 func resolve(_ code:String)->String?{actorName(code:code)}
'''
    swift += '\n'.join(function(renderer, marker) for marker in [
        '    @discardableResult func setLocalSkin(', '    @discardableResult func setLegacySkin(',
        '    @discardableResult func loadLegacySkinCatalog(', '    private func actorName('])
    swift += '}\nfinal class Client{var localSkin=7;'
    swift += function(client, '    func setLocalSkin(') + '}\n'
    swift += '''let index=try JSONDecoder().decode([String:[String:String]].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let renderer=Renderer(),client=Client();renderer.pedModels=index["peds"]!
let catalog=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
precondition(renderer.loadLegacySkinCatalog(catalog));var checks=0
for(key,name)in index["peds"]!{let id=Int(key)!
 precondition(renderer.setLocalSkin(id)&&renderer.localSkin==id&&renderer.loaded.last==name);checks+=1
 precondition(renderer.resolve("s"+key)==name);checks+=1
 client.setLocalSkin(id);precondition(client.localSkin==id);checks+=1
 if let mapping=renderer.sampSkinCatalog?.mappings[id],let native=mapping.nativeID {
  precondition(renderer.setLegacySkin(id)&&renderer.localSkin==native&&renderer.localLegacySkin==id&&renderer.loaded.last==mapping.model)
 }else{let before=renderer.localSkin;precondition(!renderer.setLegacySkin(id)&&renderer.localSkin==before)};checks+=1
}
let previous=renderer.localSkin
    if index["peds"]!["2"] == nil {
     precondition(!renderer.setLocalSkin(2)&&renderer.localSkin==previous&&renderer.resolve("s2")==nil)
    }else{precondition(renderer.setLocalSkin(2)&&renderer.resolve("s2")=="maccer")};checks+=1
let beforeCJ=renderer.localSkin
precondition(!renderer.setLegacySkin(0)&&renderer.localSkin==beforeCJ);checks+=1
renderer.pedModels["20001"]="samp-dl-20001";renderer.legacyPedModels["samp-dl-20001"]=1
precondition(renderer.setLegacySkin(20001)&&renderer.loaded.last=="samp-dl-20001");checks+=1
print("PASS actual skin lookup/setters: \\(checks) checks; actor loading and animation owners are explicit spies")
'''
    with tempfile.TemporaryDirectory(prefix='swift-', dir=OUT) as temp:
        work = Path(temp)
        (work / 'main.swift').write_text(swift)
        command = ['xcrun', 'swiftc', '-Onone', '-module-cache-path', str(OUT / 'modules'),
                   str(ROOT / 'ios/App/NativeSAMPSkinCatalog.swift'), str(work / 'main.swift'), '-o', str(work / 'verify')]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (OUT / 'compile.log').write_text(compiled.stdout + compiled.stderr)
        compiled.check_returncode()
        run = subprocess.run([str(work / 'verify'), str(output_index), str(output_skins)], capture_output=True, text=True)
        (OUT / 'swift-run.log').write_text(run.stdout + run.stderr)
        run.check_returncode()

    check(index_path.read_bytes() == original_index_data, 'Shared original index changed')
    check(all(hashlib.sha256(path.read_bytes()).hexdigest() == digest for path, digest in before.items()),
          'Per-model asset bytes changed')
    mapping = [{'model': name, 'oldCompactID': int(key),
                'browserWireID': next(row['id'] for row in canonical if row['model'] == name)}
               for key, name in original['peds'].items()]
    report = {'status': 'PASS', 'pythonChecks': checks, 'reference': reference, 'swiftOutput': run.stdout,
              'availableModelCount': len(available), 'browserWireEntryCount': len(corrected['peds']),
              'mappedSAMPSkinCount': len(mapped),
              'pinned265Migration': {'status': 'PASS', 'directory': str(pin), 'models': 265},
              'primarySources': primary_sources,
              'browserResolverSHA256': hashlib.sha256(main_path.read_bytes()).hexdigest(),
              'converterSHA256': hashlib.sha256((ROOT / 'prepare_native_models.py').read_bytes()).hexdigest(),
              'originalIndexSHA256': hashlib.sha256(original_index_data).hexdigest(),
              'correctedIndexSHA256': hashlib.sha256(output_index.read_bytes()).hexdigest(),
              'correctedSkinMapSHA256': hashlib.sha256(output_skins.read_bytes()).hexdigest(),
              'sourceHashes': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in [renderer_path, client_path, server_path, ROOT / 'ios/App/NativeSAMPSkinCatalog.swift']},
              'perModelBytesUnchanged': True, 'modelFiles': [{'path': str(path), 'sha256': digest, 'bytes': path.stat().st_size}
                                                           for path, digest in before.items()],
              'mapping': mapping,
              'limits': ['Corrected metadata exists only in the ignored overlay; live App/server still use their current assets',
                         'Actual pure browser lookup/server row and extracted native setters/lookup; no live transport or actor/GPU rendering',
                         'Pinned265 migration and the current available population are reported separately; no substituted missing models',
                         'No device/browser actions or original/shared asset changes']}
    (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS skin namespace: {checks} Python checks, {reference["checks"]} actual reference rows; ' + run.stdout.strip())


if __name__ == '__main__':
    main()
