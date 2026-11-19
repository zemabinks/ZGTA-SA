#!/usr/bin/env python3
"""Extract archived time/weather color tables into ignored native game data."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib
import json
from pathlib import Path

from tools.assets.prepare_native_audio import json_module

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'local-only/site/game/native/environment.json'


def main():
    table, path = json_module(98459)
    audio_weather, schedule_path = json_module(93265)
    assert len(table['c$']) == 8 and table['c$'][0] == 0
    assert len(table['kP']) == len(table['Ge']) == 23
    assert all(len(weather) == 8 and all(len(row) == 12 for row in weather)
               for weather in table['Ge'])
    result = {'source': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [path, schedule_path]},
              'hours': table['c$'], 'weatherNames': table['kP'],
              'colors': table['Ge'], 'sequences': audio_weather['k8'],
              'initialWeather': 10, 'initialHour': 12}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    OUTPUT.chmod(0o600)
    print(f'Prepared {len(table["Ge"])} weather types ×8 time rows in {OUTPUT}')


if __name__ == '__main__':
    main()
