#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual producer tests over independently authored DFF/TXD/SKN/HND carriers.

No original game files, SDK, network, services or installed app caches are used.
An optional historical checkout executes its literal converter on these same
authored inputs; the portable default does not require another checkout.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import struct
import sys
import tempfile
import time
from PIL import Image, __version__ as pillow_version
sys.dont_write_bytecode = True

import prepare_native_models as converter
import prepare_native_ped_atlas as producer
import prepare_native_resource_package as package

ROOT = Path(__file__).resolve().parent
sha = lambda data: hashlib.sha256(data).hexdigest()
checks = []


def check(value, label):
    checks.append({'label': label, 'passed': bool(value)})
    if not value:
        raise AssertionError(label)


def rejects(action, label):
    try:
        action()
    except (OSError, ValueError, KeyError, TypeError, struct.error):
        check(True, label)
        return
    check(False, label)


def chunk(kind, data=b''):
    return struct.pack('<III', kind, len(data), 0x1803ffff)+data


def string(value):
    data = value.encode()+b'\0'
    return chunk(2, data+b'\0'*((-len(data)) % 4))


def dff(names):
    count = max(1, len(names))
    frames = chunk(14, chunk(1, struct.pack('<I12fii', 1, 1,0,0, 0,1,0, 0,0,1, 0,0,0, -1,0))+chunk(3))
    geometry = struct.pack('<HBBIII', 4, 1, 0, count, count*3, 1)
    geometry += b''.join(struct.pack('<2f', *uv) for _ in range(count) for uv in [(0,0),(1,0),(0,1)])
    geometry += b''.join(struct.pack('<4H', i*3+1, i*3, i, i*3+2) for i in range(count))
    geometry += struct.pack('<4fII', 0,0,0,1,1,0)
    geometry += b''.join(struct.pack('<3f', *p) for i in range(count) for p in [(i,0,0),(i+1,0,0),(i,1,1)])
    materials = []
    for name in names or ['']:
        texture = chunk(6, chunk(1, struct.pack('<I', 0x1106))+string(name)+string('')) if name else b''
        materials.append(chunk(7, chunk(1, struct.pack('<I4BII3f', 0,255,255,255,255,0,int(bool(name)),1,1,1))+texture+chunk(3)))
    palette = chunk(8, chunk(1, struct.pack('<I', count)+struct.pack('<'+'i'*count, *([-1]*count)))+b''.join(materials))
    geometries = chunk(26, chunk(1, struct.pack('<I', 1))+chunk(15, chunk(1, geometry)+palette+chunk(3)))
    atomic = chunk(20, chunk(1, struct.pack('<4I', 0,0,4,0))+chunk(3))
    return chunk(16, chunk(1, struct.pack('<3I', 1,0,0))+frames+geometries+atomic+chunk(3))


def txd(images):
    natives = []
    for name, image in images.items():
        pixels = image.tobytes('raw', 'BGRA')
        header = struct.pack('<II', 9,0x1106)+name.encode().ljust(32,b'\0')+bytes(32)
        header += struct.pack('<IIHH4B', 0x500,21,image.width,image.height,32,1,4,0)
        natives.append(chunk(0x15, chunk(1, header+struct.pack('<I', len(pixels))+pixels)+chunk(3)))
    return chunk(0x16, chunk(1, struct.pack('<HH', len(images),0))+b''.join(natives)+chunk(3))


IDENTITY = struct.pack('<16f', 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)


def skeleton(vertices):
    result = bytearray(b'SKN1'+struct.pack('<III', vertices,2,2)+IDENTITY+IDENTITY)
    for parent, bone in [(-1,0),(0,1)]:
        result += struct.pack('<ii', parent,bone)+IDENTITY
    for frame in [0,1]:
        result += struct.pack('<I', frame)+IDENTITY
    for _ in range(vertices):
        result += struct.pack('<3f4B4f', 0,0,0,0,0,0,0,1,0,0,0)
    return bytes(result)


def hand():
    return b'HND1'+struct.pack('<III', 1,30,0)+b'idle_stance'.ljust(16,b'\0')+struct.pack('<I',1)+IDENTITY


def gradient(width, height, partial_alpha=False):
    image = Image.new('RGBA', (width,height))
    image.putdata([(x*255//max(1,width-1), y*255//max(1,height-1), (x*7+y*3)%256,
                    (x*11+y*13)%256 if partial_alpha else 255)
                   for y in range(height) for x in range(width)])
    return image


def spec(path):
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': sha(data)}


def write_source(work, model, images):
    folder = work/'sources'/model
    folder.mkdir(parents=True)
    source = folder/(model+'.dff')
    source.write_bytes(dff(list(images)))
    source.with_suffix('.txd').write_bytes(txd(images))
    old = folder/'existing.bin'
    converter.convert(source, old, pedestrian=True)
    vertices = struct.unpack_from('<I', old.read_bytes(), 4)[0]
    skin = folder/'existing.skel.bin'
    skin.write_bytes(skeleton(vertices))
    attachment = folder/'existing.hand.bin'
    attachment.write_bytes(hand())
    return {'model': model, 'sources': {'dff': spec(source), 'txd': spec(source.with_suffix('.txd')),
            'mesh': spec(old), 'skeleton': spec(skin), 'hand': spec(attachment),
            'parts': spec(old.with_suffix('.parts.json'))}}


def repack_overlay(directory, model, changes=None, family_change=None):
    """Re-pin synthetic tampering so inner invariants, not just outer SHA, run."""
    overlay, paths = producer.validate_overlay(directory)
    old_url = overlay['models'][model]
    family = producer.decode_json(paths[old_url].read_bytes())
    removed = {old_url}
    additions = []
    for role, value in (changes or {}).items():
        removed.add(family['resources'][role]['path'])
        row = producer.resource(model, role, value)
        path = directory/'files'/row['path'];path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(value)
        family['resources'][role] = row
        additions.append(row)
    if family_change:
        family_change(family)
    value = producer.canonical(family)+b'\n'
    row = {'path': producer.PREFIX+sha(value)+'/'+model+'.json', 'bytes': len(value), 'sha256': sha(value)}
    path = directory/'files'/row['path'];path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(value)
    overlay['models'][model] = row['path']
    overlay['resources'] = [r for r in overlay['resources'] if r['path'] not in removed]+additions+[row]
    (directory/'overlay.json').write_bytes(producer.canonical(overlay)+b'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root', type=Path, help='Optional literal previous converter; no original assets read')
    parser.add_argument('--output', type=Path, default=ROOT/'local-only/research/ped-atlas-119'/('authored-'+str(time.time_ns())+'.json'))
    args = parser.parse_args()
    tracked = [Path(__file__), ROOT/'prepare_native_models.py', ROOT/'prepare_native_ped_atlas.py',
               ROOT/'prepare_native_resource_package.py', ROOT/'prepare_native_stock_package.py']
    before = {str(path): sha(path.read_bytes()) for path in tracked}
    historical = None
    if args.historical_root:
        path = args.historical_root/'prepare_native_models.py'
        module = importlib.util.spec_from_file_location('literal_historical_ped_converter', path)
        historical = importlib.util.module_from_spec(module);module.loader.exec_module(historical)
        before[str(path)] = sha(path.read_bytes())
    cases = {}
    with tempfile.TemporaryDirectory(prefix='zgta-ped-authored-') as temporary:
        work = Path(temporary).resolve()/'local-only';work.mkdir()
        empty = work/'empty';empty.mkdir();converter.GAME = empty
        if historical:
            historical.GAME = empty
        inputs = {'vertical': {'body': gradient(128,256)}, 'horizontal': {'body': gradient(256,128)},
                  'square': {'body': gradient(256,256)},
                  'mixed': {'body': gradient(128,256), 'watch': gradient(128,64), 'detail': gradient(64,64,True)},
                  'white': {}}
        selected = []
        for model, images in inputs.items():
            entry = write_source(work, model, images);selected.append(entry)
            source = Path(entry['sources']['dff']['path']);legacy = Path(entry['sources']['mesh']['path'])
            default = source.parent/'default.bin';converter.convert(source,default,pedestrian=True)
            explicit = source.parent/'explicit.bin';converter.convert(source,explicit,pedestrian=True,ped_atlas_layout='legacy')
            for suffix in ['.bin','.parts.json','.png']:
                check(default.with_suffix(suffix).read_bytes() == explicit.with_suffix(suffix).read_bytes(), model+' default legacy '+suffix)
            if historical:
                original = source.parent/'historical.bin';historical.convert(source,original,pedestrian=True)
                for suffix in ['.bin','.parts.json','.png']:
                    check(default.with_suffix(suffix).read_bytes() == original.with_suffix(suffix).read_bytes(), model+' literal historical legacy '+suffix)
            vehicle_a = source.parent/'vehicle-a.bin';vehicle_b = source.parent/'vehicle-b.bin'
            converter.convert(source,vehicle_a,pedestrian=False)
            converter.convert(source,vehicle_b,pedestrian=False,ped_atlas_layout='tight-native')
            if historical:
                old = source.parent/'vehicle-old.bin';historical.convert(source,old,pedestrian=False)
            for suffix in ['.bin','.parts.json','.png']:
                check(vehicle_a.with_suffix(suffix).read_bytes() == vehicle_b.with_suffix(suffix).read_bytes(), model+' nonped unchanged '+suffix)
                if historical:
                    check(vehicle_a.with_suffix(suffix).read_bytes() == old.with_suffix(suffix).read_bytes(), model+' historical nonped '+suffix)
            check(not vehicle_b.with_suffix('.atlas.json').exists(), model+' no nonped layout sidecar')
        output = work/'overlay'
        result = producer.build({'schema':1,'models':selected}, output)
        overlay, paths = producer.validate_overlay(output)
        check(result['models'] == 5 and result['resources'] == 35, 'Complete five-family graph')
        for entry in selected:
            model = entry['model'];family = producer.decode_json(paths[overlay['models'][model]].read_bytes())
            values = {role: paths[row['path']].read_bytes() for role,row in family['resources'].items()}
            layout = producer.decode_json(values['layout'])
            check(family['sourceIdentity'] == producer.source_identity(model,layout), model+' canonical source identity')
            for role in ['mesh','skeleton','hand','parts']:
                check(values[role] == Path(entry['sources'][role]['path']).read_bytes(), model+' unchanged '+role)
            from io import BytesIO
            with Image.open(BytesIO(values['atlas'])) as atlas:
                for row in layout['layers'][1:]:
                    x,y,w,h = row['rect'];expected = inputs[model][row['texture']]
                    crop = atlas.crop((x,y,x+w,y+h))
                    check(crop.tobytes() == expected.tobytes(), model+' native RGBA pixels '+row['texture'])
                    for px,py in [(0,0),(w-1,0),(0,h-1),(w-1,h-1),(w//2,h//2)]:
                        check(crop.getpixel((px,py)) == expected.getpixel((px,py)), model+' orientation '+row['texture']+str((px,py)))
            cases[model] = {'atlas':layout['atlas'],'cell':layout['cell'],'layers':len(layout['layers']),
                            'RGBA8Bytes':layout['logicalRGBA8Bytes'],'sourceIdentity':family['sourceIdentity']}
        # Validate normal prepared graph extension, rather than a cache seeding shortcut.
        base_local = work/'base/local-only';site = base_local/'site'
        for name in package.REQUIRED:
            path = site/name;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b'authored-core-placeholder' if name.endswith('.bin') else b'{}\n')
        index = {'peds':{str(i):model for i,model in enumerate(inputs)}, 'vehicles':{'1':'authored-car'}, 'weapons':{'2':'authored-gun'}}
        (site/producer.INDEX).write_bytes(producer.canonical(index)+b'\n')
        package.prepare(base_local,verify=True)
        base_catalog = base_local/'resources-v1/catalog.json';base_before = sha(base_catalog.read_bytes())
        destination = work/'extended/local-only';destination.mkdir(parents=True)
        result = producer.extend(base_catalog,output,destination)
        catalog = producer.decode_json((destination/'resources-v1/catalog.json').read_bytes())
        rows = catalog['manifest']['resources'];updated_index = next(row for row in rows if row['path']==producer.INDEX)
        updated = producer.decode_json(Path(catalog['files'][updated_index['sha256']]['path']).read_bytes())
        check(updated['peds']==index['peds'] and updated['vehicles']==index['vehicles'] and updated['weapons']==index['weapons'], 'Preserve every old model map')
        check(updated['pedAtlasV1']==overlay['models'], 'Optional all-string pedAtlasV1 map')
        check(all(isinstance(v,dict) and all(isinstance(k,str) and isinstance(x,str) for k,x in v.items()) for v in updated.values()), 'Old typed index schema remains valid')
        check(all(any(row['path']==item['path'] and row['required'] and row['sha256']==item['sha256'] for row in rows) for item in overlay['resources']), 'Every family dependency enters normal required manifest')
        check(sha(base_catalog.read_bytes())==base_before, 'Base catalogue input unchanged')
        check(not (destination/'resource-source-roots.json').exists(), 'No source approval inferred/written')
        frozen = sha((destination/'resources-v1/catalog.json').read_bytes())
        rejects(lambda:producer.extend(base_catalog,output,destination),'Existing catalogue preserved')
        check(sha((destination/'resources-v1/catalog.json').read_bytes())==frozen,'Rejected overwrite leaves active catalogue intact')
        # Producer failure is atomic and leaves no selected output or staging directory.
        negative = 0
        def bad_build(entry, label):
            nonlocal negative
            negative += 1;target = work/('rejected-'+str(negative))
            rejects(lambda:producer.build({'schema':1,'models':[entry]},target), label)
            check(not target.exists() and not list(work.glob('.ped-atlas-partial-*')), label+' atomic cleanup')
        altered = copy.deepcopy(selected[0]);altered['sources']['dff']['sha256']='0'*64;bad_build(altered,'Reject changed source digest')
        altered = copy.deepcopy(selected[0]);del altered['sources']['skeleton'];bad_build(altered,'Reject missing required skeleton')
        altered = copy.deepcopy(selected[0]);altered['model']='null';bad_build(altered,'Reject segmented CJ in ordinary family')
        for role, value, label in [('mesh',b'wrong vertex order','Reject old mesh mismatch'),
                                   ('skeleton',skeleton(4),'Reject wrong SKN vertex count'),
                                   ('parts',b'{"parts":[]}', 'Reject old parts mismatch'),
                                   ('hand',b'HND1','Reject incomplete advertised hand')]:
            altered=copy.deepcopy(selected[0]);path=work/('bad-'+role);path.write_bytes(value);altered['sources'][role]=spec(path);bad_build(altered,label)
        altered=copy.deepcopy(selected[0]);linked=work/'linked-source';linked.symlink_to(altered['sources']['dff']['path']);altered['sources']['dff']['path']=str(linked);bad_build(altered,'Reject source file alias')
        linked_dir=work/'linked-directory';linked_dir.symlink_to(work/'sources',target_is_directory=True)
        altered=copy.deepcopy(selected[0]);altered['sources']['dff']['path']=str(linked_dir/'vertical/vertical.dff');bad_build(altered,'Reject source parent alias')
        rejects(lambda:producer.build({'schema':1,'models':[selected[0],selected[0]]},work/'duplicate'),'Reject duplicate model')
        rejects(lambda:producer.build({'schema':1,'models':[selected[0]]},output),'Reject existing output without replacement')
        rejects(lambda:producer.build({'schema':1,'models':[selected[0]]},linked_dir/'new'),'Reject output through alias')
        rejects(lambda:producer.build({'schema':1,'models':[selected[0]]},work/'..'/'outside-private'),'Reject output parent traversal')
        rejects(lambda:producer.build({'schema':1,'models':[None]},work/'invalid-row'),'Reject nonobject selected source row')
        missing=copy.deepcopy(selected[0]);folder=work/'missing/vertical';folder.mkdir(parents=True);p=folder/'vertical.dff';p.write_bytes(dff(['missing']));missing['sources']['dff']=spec(p);bad_build(missing,'Reject unpinned shared texture fallback')
        huge=bytearray(Path(selected[0]['sources']['txd']['path']).read_bytes());native=converter.first(converter.children(huge,converter.first(list(converter.chunks(huge,0,len(huge))),0x16)),0x15);info=converter.first(converter.children(huge,native),1);struct.pack_into('<H',huge,info[1]+80,65535)
        altered=copy.deepcopy(selected[0]);p=work/'huge/vertical.txd';p.parent.mkdir();p.write_bytes(huge);altered['sources']['txd']=spec(p);bad_build(altered,'Reject excessive dimensions before pixel decode')
        import shutil
        for label, transform in [
            ('Reject inner source identity',lambda d:repack_overlay(d,'vertical',family_change=lambda f:f.update(sourceIdentity='0'*64))),
            ('Reject missing complete dependency',lambda d:repack_overlay(d,'vertical',family_change=lambda f:f['resources'].pop('skeleton'))),
            ('Reject wrong layout family binding',lambda d:repack_overlay(d,'vertical',changes={'layout':producer.canonical({**producer.decode_json(paths[producer.decode_json(paths[overlay['models']['vertical']].read_bytes())['resources']['layout']['path']].read_bytes()),'meshSHA256':'0'*64})+b'\n'})),
        ]:
            target=work/('tampered-'+str(len(checks)));shutil.copytree(output,target);transform(target)
            rejects(lambda:producer.validate_overlay(target),label)
        # Every chosen source and production input remains unchanged.
        for entry in selected:
            for role, row in entry['sources'].items():
                check(sha(Path(row['path']).read_bytes())==row['sha256'],entry['model']+' preserved selected source '+role)
    check(all(sha(Path(path).read_bytes())==value for path,value in before.items()),'Actual source inputs unchanged')
    report={'status':'PASS AUTHORED SOURCE-BOUND PRODUCER TESTS','checks':len(checks),'cases':cases,'assertions':checks,
            'inputSHA256':before,'sourceUnchanged':True,'historicalExecuted':historical is not None,
            'Pillow':pillow_version,'originalModelsConverted':0,'originalPixelsDecoded':0,
            'limits':['No Metal, physical-device, native import or retail visual acceptance.',
                      'Normal prepared extension exercised on independently authored temporary resource graph only.']}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'checks':len(checks),'historicalExecuted':report['historicalExecuted'],'report':str(args.output)},indent=2))


if __name__=='__main__':
    main()
