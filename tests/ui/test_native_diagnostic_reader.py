#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Reject damaged diagnostic transport instead of inventing missing measurements."""
from pathlib import Path
import base64
import hashlib
import json
import sys
import unittest
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.development.read_native_diagnostics import reassemble, InvalidRecord, PREFIX

IDENTITY = '12345678-1234-1234-1234-123456789012'
def authored(data=b'x'*1025, identity=IDENTITY):
    count = (len(data)+511)//512
    return [dict(id=identity, part=n, count=count, sha256=hashlib.sha256(data).hexdigest(), data=base64.b64encode(data[n*512:(n+1)*512]).decode()) for n in range(count)]
def messages(rows):
    return [PREFIX+json.dumps(row, separators=(',', ':')) for row in rows]

class DiagnosticReader(unittest.TestCase):
    def test_exact_out_of_order_and_identical_duplicates(self):
        rows = authored()
        self.assertEqual(reassemble(['unrelated', *messages(rows[::-1]+rows[:1])]), {IDENTITY:b'x'*1025})
    def test_missing_chunk_and_no_records(self):
        for lines in [[], ['unrelated'], messages(authored()[1:])]:
            with self.assertRaises(InvalidRecord): reassemble(lines)
    def test_truncated_and_oversized_lines(self):
        for line in [messages(authored())[0][:-1], PREFIX+' '*921]:
            with self.assertRaises(InvalidRecord): reassemble([line])
    def test_wrong_checksum_and_conflicting_duplicate(self):
        rows=authored(); rows[-1]['data']=base64.b64encode(b'Y').decode()
        with self.assertRaises(InvalidRecord): reassemble(messages(rows))
        rows=authored(); changed=dict(rows[0],data=base64.b64encode(b'y'*512).decode())
        with self.assertRaises(InvalidRecord): reassemble(messages([*rows,changed]))
    def test_schema_identity_and_type_bounds(self):
        changes=[{'id':'../../escape'},{'part':True},{'count':True},{'part':-1},{'part':3},{'count':257},{'count':0},{'sha256':'X'*64},{'data':'!invalid'},{'data':None},{'data':''},{'data':base64.b64encode(b'x'*513).decode()},{'extra':0}]
        for patch in changes:
            with self.subTest(patch=patch):
                rows=authored();rows[0].update(patch)
                with self.assertRaises(InvalidRecord): reassemble(messages(rows))
    def test_conflicting_header(self):
        for patch in [{'count':4},{'sha256':'0'*64}]:
            rows=authored();rows[1].update(patch)
            with self.assertRaises(InvalidRecord): reassemble(messages(rows))
    def test_interleaved_independent_records(self):
        other='23456789-2345-2345-2345-234567890123'
        rows=authored()+authored(b'abc',other)
        result=reassemble(messages(rows[::2]+rows[1::2]))
        self.assertEqual(result,{IDENTITY:b'x'*1025,other:b'abc'})

if __name__=='__main__': unittest.main()
