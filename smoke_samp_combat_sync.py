#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Independent codec goldens from actual pinned open.mp packet write bodies.

References remain owner-local; no reference implementation is redistributed.
The byte collector is explicit and does not model RakNet or server policy.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from smoke_samp_artwork import balanced
ROOT=Path(__file__).resolve().parent
REFERENCE=ROOT/'local-only/research/samp-combat/core.hpp'
OUT=ROOT/'local-only/research/samp-combat/tests'

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    source=REFERENCE.read_text()
    names=['ios/App/NativeSAMPProtocol.swift','ios/App/NativeSAMPCombatSync.swift','tests/combat_sync/main.swift','tests/combat_sync/reference.cpp','smoke_samp_combat_sync.py']
    frozen={name:(ROOT/name).read_bytes()for name in names}
    packets='\n'.join(balanced(source,'struct '+name)+';'for name in ['PlayerAimSync','PlayerBulletSync'])
    shim='''#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
enum class NetworkPacketType {Packet};constexpr int OrderingChannel_SyncPacket=0;
template<int ID,NetworkPacketType Type,int Channel> struct NetworkPacketBase {static constexpr int PacketID=ID;};
struct Vector3 {float x,y,z;};
struct NetworkBitStream {
std::vector<uint8_t> bytes;
template<class T>void put(T v){auto p=reinterpret_cast<uint8_t*>(&v);bytes.insert(bytes.end(),p,p+sizeof(v));}
void writeUINT8(uint8_t v){put(v);}void writeUINT16(uint16_t v){put(v);}void writeFLOAT(float v){put(v);}
void writeVEC3(Vector3 v){writeFLOAT(v.x);writeFLOAT(v.y);writeFLOAT(v.z);}
bool readUINT8(uint8_t&){return false;}bool readUINT16(uint16_t&){return false;}
bool readFLOAT(float&){return false;}bool readVEC3(Vector3&){return false;}bool readPosVEC3(Vector3&){return false;}
};
'''
    with tempfile.TemporaryDirectory(dir=OUT,prefix='snapshot-')as temporary:
        work=Path(temporary);(work/'reference.hpp').write_text(shim+packets)
        subprocess.run(['xcrun','clang++','-std=c++17','-O1','-I',str(work),str(ROOT/'tests/combat_sync/reference.cpp'),'-o',str(work/'reference')],check=True)
        with(work/'goldens.json').open('w')as output:subprocess.run([str(work/'reference')],stdout=output,check=True)
        command=['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(ROOT/'ios/App/NativeSAMPProtocol.swift'),str(ROOT/'ios/App/NativeSAMPCombatSync.swift'),str(ROOT/'tests/combat_sync/main.swift'),'-o',str(work/'verify')]
        built=subprocess.run(command,capture_output=True,text=True);(OUT/'compile.log').write_text(built.stdout+built.stderr)
        if built.returncode:raise RuntimeError(built.stdout+built.stderr)
        result=subprocess.run([str(work/'verify'),str(work/'goldens.json')],capture_output=True,text=True)
        (OUT/'run.log').write_text(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
        report=json.loads(result.stdout);report['sourceUnchanged']=all((ROOT/name).read_bytes()==data for name,data in frozen.items())
        report['sourceHashes']={name:hashlib.sha256(data).hexdigest()for name,data in frozen.items()}
        report['referenceSHA256']=hashlib.sha256(REFERENCE.read_bytes()).hexdigest()
        report['reference']='https://github.com/openmultiplayer/open.mp/blob/2b4a69dd606dc2f93e98b0f1ffe8801cc01633f5/Shared/NetCode/core.hpp'
        report['referenceBoundary']='Unmodified published packet write methods; explicit byte collector, no replacement server or transport semantics.'
        assert report['sourceUnchanged'];(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

if __name__=='__main__':main()
