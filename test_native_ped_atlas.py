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


def dff(names, samplers=None):
    count = max(1, len(names))
    frames = chunk(14, chunk(1, struct.pack('<I12fii', 1, 1,0,0, 0,1,0, 0,0,1, 0,0,0, -1,0))+chunk(3))
    geometry = struct.pack('<HBBIII', 4, 1, 0, count, count*3, 1)
    geometry += b''.join(struct.pack('<2f', *uv) for _ in range(count) for uv in [(0,0),(1,0),(0,1)])
    geometry += b''.join(struct.pack('<4H', i*3+1, i*3, i, i*3+2) for i in range(count))
    geometry += struct.pack('<4fII', 0,0,0,1,1,0)
    geometry += b''.join(struct.pack('<3f', *p) for i in range(count) for p in [(i,0,0),(i+1,0,0),(i,1,1)])
    materials = []
    for index, name in enumerate(names or ['']):
        sampler = 0x1106 if samplers is None else samplers[index]
        texture = chunk(6, chunk(1, struct.pack('<I', sampler))+string(name)+string('')) if name else b''
        materials.append(chunk(7, chunk(1, struct.pack('<I4BII3f', 0,255,255,255,255,0,int(bool(name)),1,1,1))+texture+chunk(3)))
    palette = chunk(8, chunk(1, struct.pack('<I', count)+struct.pack('<'+'i'*count, *([-1]*count)))+b''.join(materials))
    geometries = chunk(26, chunk(1, struct.pack('<I', 1))+chunk(15, chunk(1, geometry)+palette+chunk(3)))
    atomic = chunk(20, chunk(1, struct.pack('<4I', 0,0,4,0))+chunk(3))
    return chunk(16, chunk(1, struct.pack('<3I', 1,0,0))+frames+geometries+atomic+chunk(3))


def txd(images, filtering=0x1106):
    natives = []
    for name, image in images.items():
        pixels = image.tobytes('raw', 'BGRA')
        sampler = filtering[name] if isinstance(filtering, dict) else filtering
        header = struct.pack('<II', 9,sampler)+name.encode().ljust(32,b'\0')+bytes(32)
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
        row = producer.resource(model, role, value, version=overlay['schema'])
        path = directory/'files'/row['path'];path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(value)
        family['resources'][role] = row
        additions.append(row)
    if family_change:
        family_change(family)
    value = producer.canonical(family)+b'\n'
    row = {'path': producer.version_config(overlay['schema'])['prefix']+sha(value)+'/'+model+'.json', 'bytes': len(value), 'sha256': sha(value)}
    path = directory/'files'/row['path'];path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(value)
    overlay['models'][model] = row['path']
    overlay['resources'] = [r for r in overlay['resources'] if r['path'] not in removed]+additions+[row]
    (directory/'overlay.json').write_bytes(producer.canonical(overlay)+b'\n')


def test_v2(work, historical, historical_producer):
    from io import BytesIO
    import shutil
    images = {'body': gradient(128,256,True)}
    inputs = [
        ('native_nearest', images, [0x11106], 0x1101),
        ('native_linear2', images, [0x11101], 0x1102),
        ('native_linear6', images, [0x11101], 0x1106),
        ('native_mixed', {'body':gradient(128,256), 'watch':gradient(128,64,True)},
         [0x11106,0x11101], {'body':0x1101,'watch':0x1106}),
        ('native_white', {}, None, 0x1101),
    ]
    selected=[]
    for model,pixels,declarations,native in inputs:
        entry=write_source(work,model,pixels);source=Path(entry['sources']['dff']['path'])
        source.write_bytes(dff(list(pixels),declarations))
        source.with_suffix('.txd').write_bytes(txd(pixels,native))
        entry['sources']['dff']=spec(source);entry['sources']['txd']=spec(source.with_suffix('.txd'))
        selected.append(entry)
    selection={'schema':1,'models':selected}
    v1=work/'v1-source-profiles';producer.build(selection,v1)
    v2=work/'v2-source-profiles';producer.build(selection,v2,version=2)
    one=work/'v2-one';producer.build({'schema':1,'models':[selected[0]]},one,version=2)
    overlay1,files1=producer.validate_overlay(v1);overlay2,files2=producer.validate_overlay(v2)
    check(overlay2['schema']==2 and overlay2['format']=='zgta-ped-atlas-overlay-v2','V2 opt-in overlay contract')
    for entry in selected:
        model=entry['model'];family1=producer.decode_json(files1[overlay1['models'][model]].read_bytes())
        family2=producer.decode_json(files2[overlay2['models'][model]].read_bytes())
        check(family2['schema']==2 and family2['format']=='zgta-ped-atlas-family-v2','V2 family contract '+model)
        check(family1['sourceIdentity']==family2['sourceIdentity'],'Unchanged original source identity '+model)
        for role in ['mesh','atlas','skeleton','parts','hand']:
            r1,r2=family1['resources'][role],family2['resources'][role]
            check(r1['sha256']==r2['sha256'] and files1[r1['path']].read_bytes()==files2[r2['path']].read_bytes(),
                  'V2 unchanged original member '+model+' '+role)
        layout=producer.decode_json(files2[family2['resources']['layout']['path']].read_bytes())
        check(layout['schema']==2 and layout['layout']=='ped-tight-native-v2' and layout['sampling']=='rw-native-base-repeat-v2','V2 sampling tag '+model)
        check(layout['layers'][0]['sampler']==converter.white_ped_sampler(),'Explicit synthetic white '+model)
        for row in layout['layers'][1:]:
            expected=next(data for name,data,_,_ in inputs if name==model)[row['texture']]
            with Image.open(BytesIO(files2[family2['resources']['atlas']['path']].read_bytes())) as atlas:
                x,y,w,h=row['rect'];check(atlas.crop((x,y,x+w,y+h)).tobytes()==expected.tobytes(),'V2 native RGBA crop '+model+row['texture'])
            native=next(native for name,_,_,native in inputs if name==model)
            packed=native[row['texture']] if isinstance(native,dict) else native
            check(row['sampler']['packed']==packed and row['sampler']['filter']==packed&255,'Found-native precedence '+model+row['texture'])
            check(row['sampler']['source']=='found-native-txd' and row['sampler']['storedMipCount']==1 and row['sampler']['nativeFlags']&4==0,'No automatic/new mips '+model+row['texture'])
        check(layout['maximumRGBA8Bytes']==512*1024,'Existing v2 pixel cap '+model)
    # Literal119 source executes the same valid v1 families; v2 is rejected there.
    historical_v1=False
    if historical_producer is not None:
        old=work/'literal-historical-v1';historical_producer.build(selection,old)
        for path in sorted(v1.rglob('*')):
            if path.is_file():
                check(path.read_bytes()==(old/path.relative_to(v1)).read_bytes(),'Literal historical v1 byte graph '+path.name)
        rejects(lambda:historical_producer.validate_overlay(v2),'Literal v1 rejects v2 overlay')
        historical_v1=True
    if historical is not None:
        rejects(lambda:historical.convert(Path(selected[0]['sources']['dff']['path']),work/'old-v2.bin',pedestrian=True,ped_atlas_layout='tight-native-v2'),'Literal previous converter rejects v2 opt-in')
    # Both versions enter the normal graph without changing existing string maps.
    local=work/'v2-base/local-only';site=local/'site'
    for name in package.REQUIRED:
        path=site/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'authored'if name.endswith('.bin')else b'{}\n')
    index={'peds':{str(i):row['model']for i,row in enumerate(selected)},'vehicles':{},'weapons':{}}
    (site/producer.INDEX).write_bytes(producer.canonical(index)+b'\n');package.prepare(local,verify=True)
    base=local/'resources-v1/catalog.json';first=work/'v2-first/local-only';first.mkdir(parents=True)
    producer.extend(base,v1,first);first_catalog=first/'resources-v1/catalog.json';first_hash=sha(first_catalog.read_bytes())
    second=work/'v2-second/local-only';second.mkdir(parents=True);producer.extend(first_catalog,v2,second)
    catalog=producer.decode_json((second/'resources-v1/catalog.json').read_bytes())
    index_row=next(row for row in catalog['manifest']['resources']if row['path']==producer.INDEX)
    merged=producer.decode_json(Path(catalog['files'][index_row['sha256']]['path']).read_bytes())
    check(merged['peds']==index['peds'] and merged['pedAtlasV1']==overlay1['models'] and merged['pedAtlasV2']==overlay2['models'],'Preserve v1 map and add v2 string map')
    check(all(isinstance(v,dict) and all(isinstance(k,str)and isinstance(x,str)for k,x in v.items())for v in merged.values()),'V2 retains old index cast')
    check(all(any(row['path']==item['path']and row['sha256']==item['sha256']and row['required']for row in catalog['manifest']['resources'])for item in overlay1['resources']+overlay2['resources']),'Complete required v1+v2 graphs')
    check(sha(first_catalog.read_bytes())==first_hash,'V2 preserves input v1 catalogue')
    check(not(second/'resource-source-roots.json').exists(),'V2 grants no source approval')
    _,one_files=producer.validate_overlay(one);one_overlay=producer.decode_json((one/'overlay.json').read_bytes())
    family=producer.decode_json(one_files[one_overlay['models']['native_nearest']].read_bytes())
    good_layout=producer.decode_json(one_files[family['resources']['layout']['path']].read_bytes())
    invalid=[('source','fresh-dff'),('packed',0x1106),('filter',3),('addressU',2),('addressV',3),
             ('storedMipCount',2),('nativeFlags',4),('nativeFlags',2),('rasterFormat',0x9600),
             ('dffPacked',[]),('dffPacked',[0x1106]),('dffPacked',[0x11106,0x11106]),('filter',True)]
    def reject_layout(value,label):
        folder=work/('v2-invalid-'+str(len(checks)));shutil.copytree(one,folder)
        repack_overlay(folder,'native_nearest',changes={'layout':producer.canonical(value)+b'\n'})
        rejects(lambda:producer.validate_overlay(folder),label)
    for key,value in invalid:
        wrong=copy.deepcopy(good_layout);wrong['layers'][1]['sampler'][key]=value;reject_layout(wrong,'Reject v2 provenance '+key+str(value))
    wrong=copy.deepcopy(good_layout);wrong['layers'][0]['sampler']['source']='found-native-txd';reject_layout(wrong,'Reject non-synthetic white')
    wrong=copy.deepcopy(good_layout);del wrong['layers'][1]['sampler'];reject_layout(wrong,'Reject missing v2 sampler')
    wrong=copy.deepcopy(good_layout);wrong['schema']=1;wrong['layout']='ped-tight-native-v1';wrong['sampling']='legacy-inset-fract-linear-no-mips';reject_layout(wrong,'Reject v2 family with valid v1 layout')
    wrong=copy.deepcopy(good_layout);wrong['sampling']='legacy-inset-fract-linear-no-mips';reject_layout(wrong,'Reject v2 with v1 sampling tag')
    wrong=copy.deepcopy(good_layout);wrong['maximumRGBA8Bytes']=1024*1024;reject_layout(wrong,'Reject widened v2 pixel cap')
    folder=work/'v2-invalid-family';shutil.copytree(one,folder)
    repack_overlay(folder,'native_nearest',family_change=lambda f:f.update(schema=1,format='zgta-ped-atlas-family-v1'))
    rejects(lambda:producer.validate_overlay(folder),'Reject mixed namespace/family version')
    rejects(lambda:producer.build(selection,work/'unsupported-v3',version=3),'Reject unsupported family version')
    # Source sampler rejection occurs before any visible output family is published.
    broken=copy.deepcopy(selected[0]);path=work/'unsupported/native_nearest.txd';path.parent.mkdir()
    path.write_bytes(txd(images,0x1103));broken['sources']['txd']=spec(path)
    rejects(lambda:producer.build({'schema':1,'models':[broken]},work/'rejected-v2-build',version=2),'Reject unsupported found-native source filter')
    check(not(work/'rejected-v2-build').exists()and not list(work.glob('.ped-atlas-partial-*')),'V2 rejected source leaves no partial family')
    return {'models':len(selected),'historicalV1Executed':historical_v1,'v1OverlayBytesPreserved':True,
            'samePixelsMeshSkeletonPartsHand':True,'sourceFilterCases':[1,2,6],'mipsGenerated':0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root', type=Path, help='Optional literal previous converter; no original assets read')
    parser.add_argument('--output', type=Path, default=ROOT/'local-only/research/ped-atlas-119'/('authored-'+str(time.time_ns())+'.json'))
    args = parser.parse_args()
    tracked = [Path(__file__), ROOT/'prepare_native_models.py', ROOT/'prepare_native_ped_atlas.py',
               ROOT/'prepare_native_resource_package.py', ROOT/'prepare_native_stock_package.py']
    before = {str(path): sha(path.read_bytes()) for path in tracked}
    historical = None
    historical_producer = None
    if args.historical_root:
        path = args.historical_root/'prepare_native_models.py'
        module = importlib.util.spec_from_file_location('literal_historical_ped_converter', path)
        historical = importlib.util.module_from_spec(module);module.loader.exec_module(historical)
        before[str(path)] = sha(path.read_bytes())
        helper=args.historical_root/'prepare_native_ped_atlas.py'
        if helper.is_file():
            # Bind the literal helper to its matching literal converter, rather
            # than accidentally execute a mixed current/historical dependency.
            previous=sys.modules.get('prepare_native_models');sys.modules['prepare_native_models']=historical
            try:
                module=importlib.util.spec_from_file_location('literal_historical_ped_family',helper)
                historical_producer=importlib.util.module_from_spec(module);module.loader.exec_module(historical_producer)
            finally:
                if previous is None:sys.modules.pop('prepare_native_models',None)
                else:sys.modules['prepare_native_models']=previous
            before[str(helper)]=sha(helper.read_bytes())
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
        v2_results=test_v2(work,historical,historical_producer)
        # Every chosen source and production input remains unchanged.
        for entry in selected:
            for role, row in entry['sources'].items():
                check(sha(Path(row['path']).read_bytes())==row['sha256'],entry['model']+' preserved selected source '+role)
    check(all(sha(Path(path).read_bytes())==value for path,value in before.items()),'Actual source inputs unchanged')
    report={'status':'PASS AUTHORED SOURCE-BOUND PRODUCER TESTS','checks':len(checks),'cases':cases,'assertions':checks,
            'inputSHA256':before,'sourceUnchanged':True,'historicalExecuted':historical is not None,
            'v2':v2_results,
            'Pillow':pillow_version,'originalModelsConverted':0,'originalPixelsDecoded':0,
            'limits':['No Metal, physical-device, native import or retail visual acceptance.',
                      'Normal prepared extension exercised on independently authored temporary resource graph only.']}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'checks':len(checks),'historicalExecuted':report['historicalExecuted'],'report':str(args.output)},indent=2))


if __name__=='__main__':
    main()
