"""Read a bounded SA INITIAL configuration without running script commands.

The numeric registry describes argument counts, not command implementations.
Unknown syntax or ambiguous population setup fails instead of producing a
partial preset. Campaign execution and mission reconstruction are not provided.
"""
# SPDX-License-Identifier: AGPL-3.0-only
import heapq
import math
import re
import struct

MAX_SCRIPT_BYTES = 16 * 1024 * 1024
# Public opcode/argument syntax used by the supported classic INITIAL profile.
# See Sanny Builder's default SA command metadata, not CLEO/extensions.
SHAPES = {
    0x0002: 1, 0x0004: 2, 0x0005: 2, 0x0008: 2, 0x0015: 2, 0x001A: 2,
    0x004D: 1, 0x004E: 0, 0x0086: 2, 0x00D6: 1, 0x0107: 5, 0x014B: 13,
    0x014C: 2, 0x016C: 5, 0x016D: 5, 0x0176: 2, 0x0177: 2, 0x018B: 2,
    0x01BB: 4, 0x01C7: 1, 0x0213: 6, 0x029B: 5, 0x02B9: 1, 0x02FA: 2,
    0x032B: 7, 0x034D: 4, 0x0392: 2, 0x03A4: 1, 0x0400: 7, 0x0453: 4,
    0x04CE: 5, 0x04F8: 13, 0x0517: 5, 0x0518: 6, 0x0550: 2, 0x0566: 2,
    0x0570: 5, 0x06C8: 1, 0x0767: 2, 0x076A: 2, 0x076C: 3, 0x07F7: 2,
    0x07FB: 2, 0x0814: 16, 0x0827: 2, 0x0874: 2, 0x08CA: 0, 0x0958: 4,
    0x0959: 4, 0x095A: 4, 0x09B4: 5, 0x09B7: 2, 0x09CA: 6, 0x09E2: 14,
    0x0A17: 2,
}
ZONE_COMMANDS = {0x0767, 0x076A, 0x076C, 0x0874, 0x09B7}
ARGUMENT_BYTES = {1: 4, 2: 2, 3: 2, 4: 1, 5: 2, 6: 4, 7: 6, 8: 6,
                  9: 8, 10: 2, 11: 2, 12: 6, 13: 6, 15: 16, 16: 2,
                  17: 2, 18: 6, 19: 6}
KEY = re.compile(r'[A-Z0-9_]{1,7}\Z')


def require(value, message):
    if not value:
        raise ValueError('Original zone initialization: ' + message)


def _argument(data, at, end):
    require(at < end, 'truncated argument')
    tag = data[at]
    at += 1
    if tag == 14:
        require(at < end, 'truncated string length')
        count = data[at]
        at += 1
    else:
        require(tag in ARGUMENT_BYTES, 'unsupported argument tag')
        count = ARGUMENT_BYTES[tag]
    require(at + count <= end, 'argument exceeds segment')
    raw = data[at:at + count]
    value = None
    if tag in (1, 4, 5):
        value = int.from_bytes(raw, 'little', signed=True)
    elif tag in (9, 14, 15):
        value = raw.split(b'\0', 1)[0].decode('latin1')
    elif tag == 6:
        require(math.isfinite(struct.unpack('<f', raw)[0]), 'nonfinite argument')
    return at + count, (tag, value)


def _instruction(data, at, begin, end):
    require(begin <= at and at + 2 <= end, 'opcode exceeds segment')
    raw = struct.unpack_from('<H', data, at)[0]
    opcode = raw & 0x7fff
    require(opcode in SHAPES, 'unsupported initializer opcode')
    require(not raw & 0x8000 or opcode not in ZONE_COMMANDS | {2, 0x4d, 0x4e, 0x8ca},
            'negated setup/control opcode')
    cursor = at + 2
    arguments = []
    for _ in range(SHAPES[opcode]):
        cursor, value = _argument(data, cursor, end)
        arguments.append(value)
    return dict(offset=at, end=cursor, opcode=opcode, arguments=arguments)


def _initial_segment(data):
    require(isinstance(data, bytes) and 32 <= len(data) <= MAX_SCRIPT_BYTES, 'script byte budget/type')
    at = 0
    mission = None
    for expected in (ord('s'), 0, 1, 2, 3, 4):
        require(at + 8 <= len(data) and data[at:at + 3] == b'\x02\0\x01', 'SCM chunk header')
        next_at = struct.unpack_from('<I', data, at + 3)[0]
        require(data[at + 7] == expected and at + 8 <= next_at <= len(data), 'SCM chunk order/range')
        if expected == 1:
            require(at + 24 <= next_at, 'mission-table header')
            main_size, largest, count, exclusive, _ = struct.unpack_from('<IIHHI', data, at + 8)
            require(0 < count <= 4096 and exclusive <= count and next_at == at + 24 + count * 4,
                    'mission-table count/extent')
            offsets = struct.unpack_from('<' + 'I' * count, data, at + 24)
            require(offsets[0] == main_size and next_at < main_size < len(data), 'main/initial segment boundary')
            ends = (*offsets[1:], len(data))
            require(all(0 < start < finish <= len(data) and finish - start <= largest
                        for start, finish in zip(offsets, ends)), 'declared segment range')
            mission = (offsets[0], ends[0])
        at = next_at
    require(mission is not None and at < mission[0], 'missing initializer segment')
    main = _instruction(data, at, at, mission[0])
    first = _instruction(data, mission[0], mission[0], mission[1])
    require(main['opcode'] == first['opcode'] == 0x3a4 and
            main['arguments'] == [(9, 'MAIN')] and first['arguments'] == [(9, 'INITIAL')],
            'unsupported main/initializer entry names')
    return mission


def decode_initialization(data):
    """Return literal zone operations only, with bounded control-flow evidence."""
    begin, end = _initial_segment(data)
    queue = [begin]
    nodes, edges = {}, {}
    occupied = bytearray(end - begin)
    while queue:
        at = heapq.heappop(queue)
        if at in nodes:
            continue
        require(len(nodes) < 50000, 'instruction budget')
        require(begin <= at < end and occupied[at - begin] != 2, 'branch into argument/outside initializer')
        row = _instruction(data, at, begin, end)
        lo, hi = at - begin, row['end'] - begin
        require(not any(occupied[lo:hi]), 'overlapping instruction boundaries')
        occupied[lo] = 1
        occupied[lo + 1:hi] = bytes([2]) * (hi - lo - 1)
        nodes[at] = row
        targets = []
        if row['opcode'] in (2, 0x4d):
            tag, label = row['arguments'][0]
            require(tag in (1, 4, 5) and type(label) is int, 'nonliteral branch')
            targets.append(label if label >= 0 else begin - label)
        if row['opcode'] not in (2, 0x4e):
            targets.append(row['end'])
        edges[at] = targets
        for target in targets:
            require(begin <= target < end, 'branch outside initializer')
            heapq.heappush(queue, target)
    resets = [at for at, row in nodes.items() if row['opcode'] == 0x8ca]
    exits = [at for at, row in nodes.items() if row['opcode'] == 0x4e]
    require(len(resets) == 1 and exits, 'unique reset/terminator required')
    reset = resets[0]
    # Test static dominance without evaluating any condition or command.
    reached, pending = set(), [begin]
    while pending:
        at = pending.pop()
        if at == reset or at in reached:
            continue
        reached.add(at)
        pending.extend(edges[at])
    require(all(at not in reached for at in exits), 'reset can be bypassed')
    operations, block = [], {reset}
    cursor = nodes[reset]['end']
    while cursor in nodes and nodes[cursor]['opcode'] in ZONE_COMMANDS:
        row = nodes[cursor]
        require(row['arguments'][0][0] == 9 and KEY.fullmatch(row['arguments'][0][1] or ''), 'zone key literal')
        values = []
        for tag, value in row['arguments'][1:]:
            require(tag in (1, 4, 5) and type(value) is int, 'zone value literal')
            values.append(value)
        operations.append(dict(opcode=row['opcode'], key=row['arguments'][0][1], values=values))
        block.add(cursor)
        cursor = row['end']
    require(operations and any(row['opcode'] == 0x767 for row in operations), 'missing population assignments')
    require(all(at in block for at, row in nodes.items() if row['opcode'] in ZONE_COMMANDS), 'split/conditional zone setup')
    require(all(target == reset for source, targets in edges.items() if source not in block
                for target in targets if target in block), 'branch enters partial setup')
    return dict(profile='zgta-sa-initial-zone-syntax-v1', operations=operations,
                proof=dict(initialBytes=end - begin, instructions=len(nodes), resetDominatesTerminators=True,
                           singleLiteralBlock=True, runtimeExecution=False))


def _float32(value):
    require(type(value) in (int, float), 'numeric coordinate')
    try:
        value = struct.unpack('<f', struct.pack('<f', value))[0]
    except (OverflowError, struct.error) as error:
        raise ValueError('Original zone initialization: coordinate float range') from error
    require(math.isfinite(value), 'finite coordinate')
    return value


def _engine_integer(value):
    value = int(_float32(value))
    require(-32768 <= value <= 32767, 'zone coordinate short range')
    return value


def compile_zone_settings(zones, initialization):
    """Apply decoded literals to source-level zone rules, preserving raw data elsewhere.

    Defaults and integer bounds follow the community reconstruction. They are
    not a certificate of original-executable runtime behavior.
    """
    require(isinstance(zones, list) and 0 < len(zones) <= 4096, 'navigation zone list')
    engine = [dict(infoKey='SAN_AND', textKey='SAN_AND', minimum=[-3000, -3000, -2000],
                   maximum=[3000, 3000, 2000], kind=0, level=0)]
    for zone in zones:
        require(type(zone['kind']) is int and zone['kind'] in (0, 1), 'navigation zone kind')
        require(isinstance(zone['name'], str) and isinstance(zone['label'], str), 'zone labels')
        key, text = zone['name'].upper()[:7], zone['label'].upper()[:7]
        require(KEY.fullmatch(key) and KEY.fullmatch(text), 'engine zone key')
        require(len(zone['minimum']) == len(zone['maximum']) == 3, 'zone coordinate dimensions')
        minimum = [_engine_integer(v) for v in zone['minimum']]
        maximum = [_engine_integer(v) for v in zone['maximum']]
        require(all(lo <= hi for lo, hi in zip(minimum, maximum)), 'zone bounds order')
        engine.append(dict(infoKey=key, textKey=text, minimum=minimum, maximum=maximum,
                           kind=zone['kind'], level=zone['level']))
    settings = {row['infoKey']: dict(populationType=5, raceMask=15, noCops=False,
                dealerStrength=0, gangStrength=[0] * 10) for row in engine}
    for row in initialization['operations']:
        key, values, opcode = row['key'], row['values'], row['opcode']
        require(key in settings, 'zone assignment has no source zone')
        require(type(opcode) is int and opcode in ZONE_COMMANDS and
                isinstance(values, (list, tuple)) and len(values) == SHAPES[opcode] - 1 and
                all(type(value) is int for value in values), 'zone operation shape')
        state = settings[key]
        if opcode == 0x767:
            require(0 <= values[0] < 20, 'population type range')
            state['populationType'] = values[0]
        elif opcode == 0x76a:
            require(0 <= values[0] <= 255, 'dealer byte range')
            state['dealerStrength'] = values[0]
        elif opcode == 0x76c:
            require(0 <= values[0] < 10 and 0 <= values[1] <= 255, 'gang/strength range')
            state['gangStrength'][values[0]] = values[1]
        elif opcode == 0x874:
            require(0 <= values[0] <= 15, 'race bitfield range')
            state['raceMask'] = values[0]
        elif opcode == 0x9b7:
            require(values[0] in (0, 1), 'no-cops boolean')
            state['noCops'] = bool(values[0])
        else:
            require(False, 'unsupported zone operation')
    return dict(version=1, profile='zgta-original-zone-configuration-v1', engineZones=engine,
                byInfoKey=settings, initializationProof=initialization['proof'],
                literalOperations=len(initialization['operations']),
                scope='Static initializer literals and source-level zone/default rules; no campaign execution, density/AI activation or retail runtime verification.')


def zone_index(configuration, position):
    """Source-level inclusive lookup; width+height decides size, with stable ties."""
    require(isinstance(position, (list, tuple)) and len(position) == 3, 'GTA position dimensions')
    point = [_float32(v) for v in position]
    rows = configuration['engineZones']
    best = 0
    size = lambda row: row['maximum'][0] - row['minimum'][0] + row['maximum'][1] - row['minimum'][1]
    for index, row in enumerate(rows):
        if all(row['minimum'][axis] <= point[axis] <= row['maximum'][axis] for axis in range(3)) and size(row) < size(rows[best]):
            best = index
    return best
