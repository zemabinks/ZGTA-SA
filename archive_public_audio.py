#!/usr/bin/env python3
"""Fill ignored local WAV bank gaps listed by the archived browser client."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import io
from pathlib import Path
import urllib.error
import urllib.request
import wave

from prepare_native_audio import json_module

ROOT = Path(__file__).resolve().parent
SOUND = ROOT / 'local-only/site/game/sound'
BASE = 'https://play.samp.directory/game/sound/'


def wanted():
    table, _ = json_module(35409)
    extra, _ = json_module(93265)
    result = {f'{bank}_{index}': row for bank, rows in table['e4'].items()
              for index, row in enumerate(rows)}
    result.update(extra['R2'])
    result.update(table['OS'])
    return result


def fetch(item):
    name, _ = item
    if len(name.split('_')) != 2 or not all(part.isdigit() for part in name.split('_')):
        return name, 'invalid sample name'
    target = SOUND / f'b{name}.wav'
    if target.is_file():
        return name, 'already local'
    request = urllib.request.Request(BASE + target.name,
                                     headers={'User-Agent': 'ZGTA-SA-local-archive/1.0'})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = response.read(2_000_001)
        if len(payload) > 2_000_000:
            return name, 'exceeds 2 MB limit'
        with wave.open(io.BytesIO(payload)) as source:
            if source.getnframes() == 0 or source.getsampwidth() != 2 or source.getnchannels() not in (1, 2):
                return name, 'invalid PCM audio'
    except (urllib.error.URLError, TimeoutError, wave.Error, EOFError) as error:
        return name, str(error)
    temporary = target.with_suffix('.partial')
    temporary.write_bytes(payload)
    temporary.chmod(0o600)
    temporary.replace(target)
    return name, 'saved'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    SOUND.mkdir(parents=True, exist_ok=True)
    # The weather mixer references this public Vorbis stream separately from
    # numeric WAV banks. Its native PCM derivative is prepared locally later.
    stream = SOUND/'t167.ogg'
    if not stream.is_file():
        request = urllib.request.Request(BASE+stream.name,headers={
            'User-Agent':'Mozilla/5.0','Referer':'https://play.samp.directory/'})
        with urllib.request.urlopen(request,timeout=30) as response:
            payload = response.read(20_000_001)
        if not payload.startswith(b'OggS') or len(payload)>20_000_000:
            raise ValueError('Invalid sandstorm Vorbis stream')
        temporary = stream.with_suffix('.partial');temporary.write_bytes(payload)
        temporary.chmod(0o600);temporary.replace(stream)
    missing = [(name, row) for name, row in wanted().items()
               if not (SOUND / f'b{name}.wav').is_file()]
    print(f'{len(missing)} public WAV banks are missing locally', flush=True)
    saved = 0
    with ThreadPoolExecutor(max_workers=max(1, min(8, args.workers))) as pool:
        for count, future in enumerate(as_completed([pool.submit(fetch, item) for item in missing]), 1):
            name, result = future.result()
            saved += result == 'saved'
            if result != 'saved':
                print(f'b{name}.wav: {result}', flush=True)
            if count % 40 == 0:
                print(f'Checked {count}/{len(missing)}; saved {saved}', flush=True)
    print(f'Saved {saved}/{len(missing)} missing WAV files under {SOUND}', flush=True)


if __name__ == '__main__':
    main()
