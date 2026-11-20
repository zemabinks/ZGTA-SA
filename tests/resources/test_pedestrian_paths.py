#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Invented native DAT graph and exact SDPD section/identity checks."""
from pathlib import Path
import copy,hashlib,json,struct,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tools.assets.prepare_pedestrian_paths import decode_area,encode_graph,convert,PathFormatError

def area_bytes(area, vehicle=False, target=None):
    count=2 if vehicle else 1;links=1 if target else 0;reserve=192 if links else 0
    address=20+count*28;packed=address+(links+reserve)*4
    lengths=packed+links*2;intersection=lengths+links+reserve
    data=bytearray(intersection+links+reserve)
    struct.pack_into('<5I',data,0,count,int(vehicle),1,0,links)
    for index in range(count):
        at=20+index*28
        struct.pack_into('<3h',data,at+8,*((8,16,24)if area==0 else(80,160,240)))
        struct.pack_into('<3H',data,at+16,0,area,index)
        data[at+22]=8 if area==0 else 16
        struct.pack_into('<I',data,at+24,1 if target and index==count-1 else 0)
    if target:
        struct.pack_into('<2H',data,address,*target[:2]);data[intersection]=target[2]
    return bytes(data)

class Paths(unittest.TestCase):
    def graph(self):
        graph={i:decode_area(struct.pack('<5I',0,0,0,0,0),i)for i in range(64)}
        graph[0]=decode_area(area_bytes(0,True,(1,0,3)),0)
        graph[1]=decode_area(area_bytes(1,False,(0,1,1)),1)
        return graph
    def test_exact_sections_units_width_and_cross_area_identity(self):
        graph=self.graph();before=copy.deepcopy(graph);data,report=encode_graph(graph)
        self.assertEqual(graph,before)
        self.assertEqual(struct.unpack_from('<8I',data),(0x44504453,1,2,2,0,0,0,0))
        self.assertEqual(struct.unpack_from('<6h',data,32),(8,16,24,80,160,240))
        self.assertEqual(struct.unpack_from('<3I',data,44),(0,1,2))
        self.assertEqual(data[56:60],b'\0\0\0\0')
        self.assertEqual(data[60:64],bytes([8,16,0,0]))
        self.assertEqual(struct.unpack_from('<2H',data,64),(1,0))
        self.assertEqual(data[68:],bytes([3,1,0,0]))
        self.assertEqual((report['nodes'],report['links']),(2,2))
    def test_native_truncation_and_extra_sections_rejected(self):
        data=area_bytes(0,True,(1,0,3))
        for value in [data[:n]for n in [0,1,19,20,21,40,len(data)-1]]+[data+b'\0']:
            with self.subTest(bytes=len(value)),self.assertRaises(PathFormatError):decode_area(value,0)
    def test_identity_degree_and_counts_rejected(self):
        data=area_bytes(0,True,(1,0,3))
        for offset,fmt,value in [(0,'I',65536),(4,'I',2),(20+18,'H',1),(20+20,'H',7),(20+28+16,'H',4)]:
            changed=bytearray(data);struct.pack_into('<'+fmt,changed,offset,value)
            with self.subTest(offset=offset),self.assertRaises(PathFormatError):decode_area(bytes(changed),0)
    def test_missing_region_vehicle_target_and_duplicate_identity_fail(self):
        graph=self.graph();del graph[63]
        with self.assertRaises(PathFormatError):encode_graph(graph)
        graph=self.graph();graph[1][0]['targets']=[(0,0,0)]
        with self.assertRaises(PathFormatError):encode_graph(graph)
        graph=self.graph();graph[1].append(graph[1][0])
        with self.assertRaises(PathFormatError):encode_graph(graph)
    def files(self, root):
        folder=root/'data/Paths';folder.mkdir(parents=True)
        rows=[]
        for area in range(64):
            data=area_bytes(0,True,(1,0,3))if area==0 else area_bytes(1,False,(0,1,1))if area==1 else struct.pack('<5I',0,0,0,0,0)
            path=folder/f'NODES{area}.DAT';path.write_bytes(data)
            rows.append(dict(path=f'data/Paths/NODES{area}.DAT',bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
        receipt=root/'receipt.json';receipt.write_text(json.dumps(dict(schema=1,profile='zgta-raw-resources-v1',resources=rows)))
        return receipt
    def test_case_preserving_receipt_bound_full_conversion(self):
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory);receipt=self.files(root)
            data,report=convert(root,receipt)
            self.assertEqual(data,encode_graph(self.graph())[0]);self.assertTrue(report['originalReceiptVerified'])
            self.assertEqual(len(report['sourceFiles']),64)
            member=root/'data/Paths/NODES1.DAT';changed=bytearray(member.read_bytes());changed[29]^=1;member.write_bytes(changed)
            with self.assertRaises(PathFormatError):convert(root,receipt)
    def test_ambiguous_and_symbolic_members_rejected(self):
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory);self.files(root);member=root/'data/Paths/NODES1.DAT'
            original=member.read_bytes();member.unlink();member.symlink_to(root/'data/Paths/NODES2.DAT')
            with self.assertRaises(PathFormatError):convert(root)
            member.unlink();member.write_bytes(original)
            # On a case-sensitive volume this is ambiguous; on a folding
            # volume its same-file semantics are not a separate witness.
            alias=root/'data/Paths/nodes1.dat'
            if not alias.exists():
                alias.write_bytes(original)
                with self.assertRaises(PathFormatError):convert(root)

if __name__=='__main__':unittest.main()
