#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Reassemble complete checksummed native diagnostic records into local-only files.

Missing, conflicting or truncated chunks are errors; no partial record is emitted.
This transports diagnostics, not a gameplay parity verdict.
"""
from pathlib import Path
import argparse
import base64
import binascii
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
PREFIX = 'FootContactRecord '
PAYLOAD_BYTES = 512
MAXIMUM_RECORD_BYTES = 128 * 1024
MAXIMUM_LINE_BYTES = 920

class InvalidRecord(ValueError):
    pass

def reassemble(messages):
    groups = {}
    for message in messages:
        if PREFIX not in message:
            continue
        line = message.split(PREFIX, 1)[1]
        if len(line.encode('utf-8')) > MAXIMUM_LINE_BYTES:
            raise InvalidRecord('Oversized diagnostic line')
        try:
            row = json.loads(line)
        except (ValueError, TypeError) as error:
            raise InvalidRecord('Truncated or malformed diagnostic line') from error
        if not isinstance(row, dict) or set(row) != {'id', 'part', 'count', 'sha256', 'data'}:
            raise InvalidRecord('Unknown diagnostic schema')
        key, checksum, part, count = (row[n] for n in ['id', 'sha256', 'part', 'count'])
        if not isinstance(key, str) or not re.fullmatch(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}', key):
            raise InvalidRecord('Invalid record identity')
        if not isinstance(checksum, str) or not re.fullmatch(r'[0-9a-f]{64}', checksum):
            raise InvalidRecord('Invalid record checksum')
        if type(part) is not int or type(count) is not int or not 1 <= count <= 256 or not 0 <= part < count:
            raise InvalidRecord('Invalid chunk position')
        try:
            if not isinstance(row['data'], str):
                raise ValueError('Base64 must be a string')
            data = base64.b64decode(row['data'], validate=True)
        except (ValueError, binascii.Error) as error:
            raise InvalidRecord('Invalid chunk encoding') from error
        if not 1 <= len(data) <= PAYLOAD_BYTES or (part < count - 1 and len(data) != PAYLOAD_BYTES):
            raise InvalidRecord('Invalid chunk length')
        if key not in groups:
            if len(groups) >= 64:
                raise InvalidRecord('Too many concurrent diagnostic records')
            groups[key] = (count, checksum, {})
        previous_count, previous_checksum, chunks = groups[key]
        if count != previous_count or checksum != previous_checksum:
            raise InvalidRecord('Conflicting record headers')
        if part in chunks and chunks[part] != data:
            raise InvalidRecord('Conflicting duplicate chunk')
        chunks[part] = data
    if not groups:
        raise InvalidRecord('No bounded diagnostic records found')
    records = {}
    for key, (count, checksum, chunks) in groups.items():
        if set(chunks) != set(range(count)):
            raise InvalidRecord('Incomplete diagnostic record: ' + key)
        data = b''.join(chunks[n] for n in range(count))
        if len(data) > MAXIMUM_RECORD_BYTES or hashlib.sha256(data).hexdigest() != checksum:
            raise InvalidRecord('Diagnostic checksum mismatch: ' + key)
        records[key] = data
    return records

def log_messages(path):
    with path.open() as source:
        for line in source:
            try:
                row = json.loads(line)
            except ValueError:
                # Plain log export is supported; damaged NDJSON is not repaired.
                yield line.rstrip('\n')
                continue
            yield row.get('eventMessage', '') if isinstance(row, dict) else ''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    local = (ROOT / 'local-only').resolve()
    destination = args.output_dir.resolve()
    if local not in destination.parents or destination.exists():
        parser.error('Use a new output directory under this checkout’s local-only folder')
    records = reassemble(log_messages(args.input))
    destination.mkdir(parents=True)
    receipt = []
    for key, data in sorted(records.items()):
        (destination / (key + '.bin')).write_bytes(data)
        receipt.append(dict(id=key, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    (destination / 'receipt.json').write_text(json.dumps(dict(status='COMPLETE_RECORDS_ONLY', records=receipt), indent=2)+'\n')
    print(json.dumps(dict(status='COMPLETE_RECORDS_ONLY', records=len(records), output=str(destination))))
if __name__ == '__main__':
    main()
