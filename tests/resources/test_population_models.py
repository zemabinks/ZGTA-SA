#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Malformed source-family admission, with an independent invented triangle."""
from pathlib import Path
import base64
import json
import runpy
import struct
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.assets.population_models import validate_family
family=runpy.run_path(str(Path(__file__).with_name('population_model_fixture.py')))['family']


def changed(index,at,fmt,value):
    parts=list(family());data=bytearray(parts[index]);struct.pack_into(fmt,data,at,value);parts[index]=bytes(data)
    return parts


def bad_cases():
    result=[changed(0,0,'<I',0),changed(0,4,'<I',0),changed(0,16,'<f',float('nan')),
            changed(0,76,'<I',3),changed(0,100,'<H',1),changed(1,16,'>I',0),
            changed(2,4,'<I',4),changed(2,8,'<I',513),changed(2,12,'<I',65),
            changed(2,144,'<i',0),changed(2,220,'<i',0),changed(2,288,'<I',2),
            changed(2,424,'<f',float('inf')),changed(2,436,'<B',2),changed(2,440,'<f',.5)]
    for index in range(3):
        for data in [b'',family()[index][:-1] if index!=1 else b'not a PNG',family()[index]+b'bad' if index!=1 else b'0'*33]:
            parts=list(family());parts[index]=data;result.append(parts)
    return result


class ModelFamilies(unittest.TestCase):
    def test_valid_family_reports_matching_counts(self):
        self.assertEqual(validate_family(*family()),dict(vertices=3,indices=3,layers=1,frames=2,bones=2,atlas=[1024,128]))

    def test_malformed_families_never_admit(self):
        for number,parts in enumerate(bad_cases()):
            with self.subTest(number=number),self.assertRaises(ValueError):validate_family(*parts)

    def test_node_and_preparer_agree_on_same_byte_families(self):
        cases=[family(),*bad_cases()]
        script="const fs=require('node:fs'),{validateFamily}=require(process.argv[1]);const rows=JSON.parse(fs.readFileSync(0,'utf8'));process.stdout.write(JSON.stringify(rows.map(row=>{try{validateFamily(...row.map(x=>Buffer.from(x,'base64')));return true}catch{return false}})));"
        result=subprocess.run(['node','-e',script,str(ROOT/'server/population/models.js')],input=json.dumps([[base64.b64encode(p).decode()for p in parts]for parts in cases]),text=True,capture_output=True,check=True,timeout=10)
        self.assertEqual(json.loads(result.stdout),[True]+[False]*len(bad_cases()))


if __name__=='__main__':unittest.main()
