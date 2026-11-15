#!/usr/bin/env python3
"""Extract audio routing from archived client bytes; keep derived data local."""
import hashlib
import json
from pathlib import Path
import re
import sys
import wave

ROOT = Path(__file__).resolve().parent
CHUNKS = ROOT / 'local-only/site/_next/static/chunks'
OUTPUT = ROOT / 'local-only/site/game/native/audio.json'


def prepare_streams():
    """Decode locally archived Vorbis ambience for native Core Audio playback."""
    folder = ROOT/'local-only/site/game/sound'
    for source in folder.glob('t*.ogg'):
        target = source.with_name('b'+source.stem+'.wav')
        if target.is_file() and target.stat().st_mtime >= source.stat().st_mtime:
            continue
        sys.path.insert(0,str(ROOT/'local-only/toolchains/python-audio'))
        try:
            import soundfile
        except ImportError as error:
            raise RuntimeError('Native stream conversion requires: python3 -m pip install --target '
                               'local-only/toolchains/python-audio soundfile==0.13.1') from error
        pcm,rate = soundfile.read(source,dtype='int16')
        soundfile.write(target,pcm,rate,subtype='PCM_16')
        target.chmod(0o600)


def json_module(module):
    for path in sorted(CHUNKS.glob('*.js')):
        text = path.read_text()
        found = re.search(rf'{module}:\w+=>\{{\w+\.exports=JSON\.parse\(\'(.*?)\'\)', text)
        if found:
            return json.loads(found.group(1)), path
    raise ValueError(f'Archived JSON module {module} unavailable')


def number_object(text, name):
    found = re.search(rf'\b{name}=(\{{[0-9:.,\[\]\-]+\}})', text)
    if not found:
        raise ValueError(f'Archived numeric map {name} unavailable')
    quoted = re.sub(r'([{,])(\d+):', r'\1"\2":', found.group(1))
    return json.loads(re.sub(r'([\[:,])(-?)\.', r'\1\g<2>0.', quoted))


def audio_effects(game, sound):
    # These lists belong to the archived99488 explosion mixer. Parse the
    # inert array literals without executing the downloaded game code.
    explosion = sound[sound.index('99488:'):]
    def array(name, nested=False):
        pattern = rf'\b{name}=(\[\[.*?\]\])' if nested else rf'\b{name}=(\[[^\]]+\])'
        found = re.search(pattern, explosion)
        if not found:
            raise ValueError(f'Archived explosion array {name} unavailable')
        return json.loads(re.sub(r'([\[:,])(-?)\.', r'\1\g<2>0.', found.group(1)))
    layers = [{'sample': row[0], 'offset': row[1], 'scale': row[2]} for row in array('p', True)]
    stereo = re.search(r'\bf="([0-9_]+)"', explosion)
    if not stereo:
        raise ValueError('Archived stereo explosion sample unavailable')
    stream_source = game[game.index('kN={'):game.index('},kz=', game.index('kN={'))]
    streams = {}
    for match in re.finditer(r'(\w+):\[(kv\(\d+(?:,\d+)?\)|"[0-9_]+"),([0-9.]+),([0-9.]+)\]', stream_source):
        name, sample, rate, gain = match.groups()
        if sample.startswith('kv'):
            numbers = [int(n) for n in re.findall(r'\d+', sample)]
            sample = f'{numbers[1] if len(numbers) > 1 else 143}_{numbers[0]}'
        else:
            sample = sample.strip('"')
        streams[name] = {'sample': sample, 'rate': float(rate), 'gain': float(gain)}
    if not all(name in streams for name in ['flame', 'spray', 'foam', 'fire']):
        raise ValueError('Archived stream sound routing unavailable')
    return {'layers': layers, 'stereoSample': stereo.group(1), 'pitches': array('h'),
            'attenuation': array('m', True)}, streams


def footstep_banks(game, vehicle):
    enum_path = next(path for path in CHUNKS.glob('*.js') if '77287:(e,t,l)' in path.read_text())
    material_module = enum_path.read_text().split('77287:', 1)[1]
    enum = re.search(r'\bo=\{(PLAIN:.*?WATER:\d+)\}', material_module)
    if not enum:
        raise ValueError('Archived footstep material enum unavailable')
    steps = dict((name, int(value)) for name, value in re.findall(r'(\w+):(\d+)', enum.group(1)))
    routing = re.search(r'\bkO=\{(.*?)\},kF=', game)
    if not routing:
        raise ValueError('Archived footstep bank routing unavailable')
    banks = {}
    for name, bank in re.findall(r'RZ\.(\w+)\]:(\d+)', routing.group(1)):
        banks[str(steps[name])] = {'bank': int(bank), 'first': 1 if name == 'PLAIN' else 0,
                                 'count': 4 if name == 'SAND' else 5}
    banks[str(steps['WATER'])] = {'bank': 128, 'first': 0, 'count': 5}
    return {'materials': [row[0] for row in vehicle['XP']], 'banks': banks,
            'water': steps['WATER']}


def main():
    prepare_streams()
    vehicle, vehicle_path = json_module(35409)
    extra, extra_path = json_module(93265)
    game_path = next(path for path in CHUNKS.glob('*.js') if 'kk={22:[52,53,6,7,8' in path.read_text())
    game = game_path.read_text()
    explosion, streams = audio_effects(game, extra_path.read_text())
    footsteps = footstep_banks(game, vehicle)
    siren_path=next(path for path in CHUNKS.glob('*.js') if re.search(r'(?:42000|42e3):.*?\{wail:"[^"]+",yelp:"[^"]+"\}',path.read_text()))
    siren_match=re.search(r'\{wail:"([^"]+)",yelp:"([^"]+)"\}',siren_path.read_text())
    sirens=dict(zip(['wail','yelp'],siren_match.groups()))
    emergency_match=re.search(r'(?:42000|42e3):.*?new Set\(\[([0-9,]+)\]\)',siren_path.read_text())
    emergency_models=[int(value) for value in emergency_match[1].split(',')]
    metadata = {f'{bank}_{index}': row for bank, rows in vehicle['e4'].items()
                for index, row in enumerate(rows)}
    metadata.update(extra['R2'])
    metadata.update(vehicle['OS'])
    samples = {}
    for path in sorted((ROOT / 'local-only/site/game/sound').glob('b*.wav')):
        name = path.stem[1:]
        with wave.open(str(path)) as source:
            sample_rate, frames = source.getframerate(), source.getnframes()
            loop = metadata.get(name, [sample_rate, -1])[1]
            if loop >= frames:
                raise ValueError(f'Invalid loop point {name}')
            samples[name] = {'rate': sample_rate, 'frames': frames, 'loop': loop,
                             'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    result = {
        'source': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in [vehicle_path, extra_path, game_path,siren_path]},
        'samples': samples,
        'road': vehicle['U2'], 'aircraft': vehicle['B$'],
        'boats': vehicle['eo'], 'special': vehicle['i0'], 'trains': vehicle['KX'],
        'weapons': number_object(game, 'kk'), 'reloads': number_object(game, 'kj'),
        'swings': number_object(game, 'kS'), 'meleeHits': number_object(game, 'k_'),
        'explosion': explosion, 'streams': streams,
        'footsteps': footsteps,
        'sirens':sirens,
        'sirenModels':emergency_models,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    OUTPUT.chmod(0o600)
    print(f'Prepared {len(samples)} real WAV samples and {len(vehicle["U2"])} road vehicle sound mappings in {OUTPUT}')


if __name__ == '__main__':
    main()
