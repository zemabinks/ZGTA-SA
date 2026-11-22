"""Decode original population resources without inventing zone assignments.

The result retains source order, duplicates and raw byte values. It is resource
data, not a claim that original population generation has been implemented.
"""
# SPDX-License-Identifier: AGPL-3.0-only
import math
import re

MAX_TEXT_BYTES = 1024 * 1024
MODEL = re.compile(r'[A-Za-z0-9_]{1,32}\Z')
LABEL = re.compile(r'[A-Za-z0-9_]{1,8}\Z')


def records(text):
    if not isinstance(text, str) or len(text.encode('utf-8')) > MAX_TEXT_BYTES or '\0' in text:
        raise ValueError('Population text size/type')
    for line in text.splitlines():
        line = line.split('//', 1)[0].split('#', 1)[0].strip()
        if line:
            yield line


def parse_cycle(text):
    rows = []
    for line in records(text):
        tokens = line.split()
        if len(tokens) != 24 or any(not re.fullmatch(r'[0-9]{1,3}', v) for v in tokens):
            raise ValueError('Population cycle requires 24 unsigned bytes per row')
        row = tuple(map(int, tokens))
        if max(row) > 255:
            raise ValueError('Population cycle byte range')
        rows.append(row)
        if len(rows) > 480:
            raise ValueError('Population cycle row budget')
    if len(rows) != 480:
        raise ValueError('Population cycle requires 20 types × 2 week parts × 12 time slots')
    return tuple(rows)


def cycle_row(rows, zone_type, week_part, hour):
    if (type(zone_type) is not int or not 0 <= zone_type < 20 or
            type(week_part) is not int or week_part not in (0, 1) or
            type(hour) not in (int, float) or not math.isfinite(hour) or not 0 <= hour < 24 or
            len(rows) != 480):
        raise ValueError('Population cycle address')
    return rows[(zone_type * 2 + week_part) * 12 + int(hour // 2)]


def parse_groups(text, kind):
    if kind not in ('pedestrian', 'vehicle'):
        raise ValueError('Population group kind')
    count = 57 if kind == 'pedestrian' else 34
    groups = []
    for line in records(text):
        names = line.replace(',', ' ').split()
        if not 1 <= len(names) <= 128 or any(not MODEL.fullmatch(n) for n in names):
            raise ValueError('Population model group')
        # Keep duplicates and tokens past the engine capacity. Model lookup
        # happens before truncation, so slicing unresolved source names is wrong.
        groups.append(tuple(n.lower() for n in names))
        if len(groups) > count:
            raise ValueError('Population group row budget')
    if len(groups) != count:
        raise ValueError('Population group count')
    return tuple(groups)


def resolve_groups(groups, model_ids, kind):
    """Resolve against a complete IDE index, never an available-mesh subset.

    Empty groups retain their row identity instead of shifting all later groups.
    Callers must handle those explicitly before admitting a runtime profile.
    """
    if kind not in ('pedestrian', 'vehicle') or not isinstance(model_ids, dict):
        raise ValueError('Population group resolution')
    first, last = (1, 311) if kind == 'pedestrian' else (400, 611)
    count, capacity = (57, 21) if kind == 'pedestrian' else (34, 23)
    if len(groups) != count:
        raise ValueError('Population group count')
    lookup = {}
    for name, value in model_ids.items():
        if not isinstance(name, str) or not MODEL.fullmatch(name) or type(value) is not int or not first <= value <= last:
            raise ValueError('Population model identity')
        key = name.lower()
        if key in lookup:
            raise ValueError('Ambiguous population model name')
        lookup[key] = value
    return tuple(tuple(lookup[n] for n in group if n in lookup)[:capacity] for group in groups)


def parse_zones(text):
    result = []
    state = 'before'
    for line in records(text):
        if line.lower() == 'zone' and state == 'before':
            state = 'rows'
            continue
        if line.lower() == 'end' and state == 'rows':
            state = 'after'
            continue
        if state != 'rows':
            raise ValueError('Original zone section')
        tokens = [v.strip() for v in line.split(',')]
        if len(tokens) != 10 or not LABEL.fullmatch(tokens[0]) or not LABEL.fullmatch(tokens[9]):
            raise ValueError('Original zone row')
        try:
            kind, level = int(tokens[1]), int(tokens[8])
            points = tuple(float(v) for v in tokens[2:8])
        except ValueError as error:
            raise ValueError('Original zone numeric fields') from error
        if (not 0 <= kind <= 3 or not 0 <= level <= 255 or
                any(not math.isfinite(v) or abs(v) > 1e6 for v in points) or
                any(points[i] > points[i + 3] for i in range(3))):
            raise ValueError('Original zone bounds/type')
        result.append(dict(name=tokens[0], kind=kind, minimum=points[:3], maximum=points[3:],
                           level=level, label=tokens[9]))
        if len(result) > 4096:
            raise ValueError('Original zone count')
    if state != 'after' or not result:
        raise ValueError('Incomplete original zone section')
    return result
