#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored native-area/compact-traffic conversion checks; no game files."""
from pathlib import Path
import copy,struct,sys,unittest
ROOT=Path(__file__).resolve().parents[2]
if str(ROOT)not in sys.path:sys.path.insert(0,str(ROOT))
from tools.assets import prepare_traffic_roads as roads

def native(area,targets,*,vehicle_count=None,navigation=None,packed=None):
    # Independent semantic fixture writer, not an archived binary literal.
    vehicle_count=len(targets)if vehicle_count is None else vehicle_count
    navigation=[dict(xy=(40,0),target=(area,1),direction=(100,0),flags=1<<8|1<<11)]if navigation is None else navigation
    links=sum(map(len,targets));data=bytearray(struct.pack('<5I',len(targets),vehicle_count,len(targets)-vehicle_count,len(navigation),links))
    first=0
    for index,neighbors in enumerate(targets):
        row=bytearray(28);struct.pack_into('<3h',row,8,index*80,area*8,24)
        struct.pack_into('<3H',row,16,first,area,index);row[22]=2
        struct.pack_into('<I',row,24,len(neighbors)|((2 if index==0 else 1)<<12));data.extend(row);first+=len(neighbors)
    for row in navigation:data.extend(struct.pack('<2h2H2bI',*row['xy'],*row['target'],*row['direction'],row['flags']))
    for neighbors in targets:
        for target in neighbors:data.extend(struct.pack('<2H',*target))
    if links:data.extend(bytes(192*4))
    for value in (packed if packed is not None else [0]*links):data.extend(struct.pack('<H',value))
    data.extend(bytes(links+(192 if links else 0)));data.extend(bytes(links+(192 if links else 0)))
    return bytes(data)

def areas():
    empty={i:roads.decode_area(native(i,[],navigation=[]),i)for i in range(64)}
    empty[0]=roads.decode_area(native(0,[[(0,1)],[(0,0)],[(0,2)]],vehicle_count=2,packed=[0,0,65535]),0)
    return empty

class TrafficRoadTests(unittest.TestCase):
    def test_vehicle_only_identity_and_sections(self):
        data,summary=roads.encode_graph(areas())
        self.assertEqual(struct.unpack_from('<5I',data),(0x44524453,1,2,2,1))
        self.assertEqual((summary['nodes'],summary['links'],summary['navigation']),(2,2,1))
        self.assertEqual(struct.unpack_from('<6h',data,32),(0,0,24,80,0,24))
        self.assertEqual(struct.unpack_from('<3I',data,44),(0,1,2))
        self.assertEqual(struct.unpack_from('<2I',data,56),(1|2<<12,1|1<<12))
        self.assertEqual(data[64:68],bytes(4))
        self.assertEqual(struct.unpack_from('<2I',data,68),(1,0))
        self.assertEqual(struct.unpack_from('<2I',data,76),(0,0))
        self.assertEqual(struct.unpack_from('<2h',data,84),(40,0))
        self.assertEqual(struct.unpack_from('<I',data,88),(1,))
        self.assertEqual(struct.unpack_from('<2b',data,92),(100,0))
        self.assertEqual(struct.unpack_from('<I',data,96),(1<<8|1<<11,))
        self.assertEqual(len(data),100)
    def test_cross_area_navigation_mapping(self):
        rows=areas();rows[0]=roads.decode_area(native(0,[[(1,0)]],navigation=[],packed=[1024]),0)
        nav=[dict(xy=(4,8),target=(1,0),direction=(-99,4),flags=2<<12)]
        rows[1]=roads.decode_area(native(1,[[(0,0)]],navigation=nav,packed=[1024]),1)
        data,_=roads.encode_graph(rows)
        self.assertEqual(struct.unpack_from('<2I',data,68),(1,0))
        self.assertEqual(struct.unpack_from('<2I',data,76),(0,0))
        self.assertEqual(struct.unpack_from('<I',data,88),(1,))
        self.assertEqual(struct.unpack_from('<2b',data,92),(-99,4))
    def test_all_areas_required(self):
        rows=areas();del rows[63]
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_unresolved_and_pedestrian_targets(self):
        for target in [(0,2),(64,0),(1,0)]:
            with self.subTest(target=target):
                rows=areas();rows[0]['nodes'][0]['targets']=[(*target,0)]
                with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_navigation_references(self):
        for packed in [1,1024,65535]:
            with self.subTest(packed=packed):
                rows=areas();rows[0]['nodes'][0]['navigation']=[packed]
                with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_navigation_target(self):
        rows=areas();rows[0]['navigation'][0]['target']=(0,2)
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_duplicate_identity(self):
        for key in ['nodes','navigation']:
            with self.subTest(kind=key):
                rows=areas();rows[0][key].append(copy.deepcopy(rows[0][key][0]))
                with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_adjacency_and_empty_graph(self):
        rows=areas();rows[0]['nodes'][0]['navigation']=[]
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
        rows={i:dict(nodes=[],navigation=[])for i in range(64)}
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_raw_validation_is_retained(self):
        data=native(0,[[(0,1)],[(0,0)]])
        for truncated in [data[:-1],data[:20]]:
            with self.assertRaises(roads.PathFormatError):roads.decode_area(truncated,0)
        with self.assertRaises(roads.PathFormatError):roads.decode_area(data,1)
    def test_water_paths_require_explicit_profile(self):
        rows=areas()
        nav=[dict(xy=(80,8),target=(1,1),direction=(0,100),flags=2<<8|2<<11)]
        rows[1]=roads.decode_area(native(1,[[(1,1)],[(1,0)]],navigation=nav,packed=[1024,1024]),1)
        for node in rows[1]['nodes']:node['flags']|=128
        _,roads_only=roads.encode_graph(rows)
        _,all_paths=roads.encode_graph(rows,'all-vehicle-paths')
        self.assertEqual((roads_only['nodes'],roads_only['navigation'],roads_only['excludedWaterNodes']),(2,1,2))
        self.assertEqual((all_paths['nodes'],all_paths['navigation'],all_paths['excludedWaterNodes']),(4,2,0))
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows,'unknown')
    def test_cross_profile_edge_is_not_silently_dropped(self):
        rows=areas();rows[0]['nodes'][1]['flags']|=128
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)
    def test_stacked_edges_keep_their_signed_navigation_attachment(self):
        rows=areas();row=rows[0];row['nodes']=[]
        for index,x,z,other in [(0,80,80,1),(1,0,80,0),(2,80,-32,3),(3,0,-32,2)]:
            row['nodes'].append(dict(area=0,index=index,xyz=(x,0,z),flags=1,targets=[(0,other,0)],navigation=[0]))
        row['navigation'][0].update(target=(0,0),direction=(100,0))
        data,summary=roads.encode_graph(rows)
        self.assertEqual(summary['edgeLocalNavigationBindings'],1)
        self.assertEqual(summary['edgeLocalNavigationLinks'],2)
        self.assertEqual(summary['navigation'],2)
        # Four nodes, four edges, two navigation rows. Both lower directed
        # edges use the new row, which points towards lower endpoint2.
        self.assertEqual(struct.unpack_from('<4I',data,112),(0,0,1,1))
        self.assertEqual(struct.unpack_from('<2I',data,136),(0,2))
        row['navigation'][0]['direction']=(0,100)
        with self.assertRaises(roads.PathFormatError):roads.encode_graph(rows)

if __name__=='__main__':unittest.main()
