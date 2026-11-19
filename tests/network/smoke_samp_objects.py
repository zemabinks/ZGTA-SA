#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Official object RPC writers and movement method against native session owner."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
from tests.network.smoke_samp_artwork import balanced
ROOT=Path(__file__).resolve().parents[2]
REF=ROOT/'local-only/research/samp-objects'
def fixture(work):
    reference=(REF/'openmp-network-bitstream.hpp').read_text()
    markers=['inline void writeUINT8(','inline void writeUINT16(','inline void writeUINT32(','inline void writeINT32(','inline void writeFLOAT(','inline void writeDynStr8(']
    methods=[balanced(reference,m)for m in markers]
    methods=[('template<typename T>\n'+m)if'writeDynStr8'not in m and 'writeFLOAT'not in m else m for m in methods]
    write=balanced(reference,'inline void NetworkBitStream::Write(templateType var)').replace('NetworkBitStream::','')
    header='''#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <array>
#include <string>
#include <string_view>
#include <cmath>
#include <chrono>
#include <limits>
using String=std::string;using StringView=std::string_view;
template<class T,size_t N>using StaticArray=std::array<T,N>;
struct Vector3{float x=0,y=0,z=0;Vector3 operator-(const Vector3&o)const{return{x-o.x,y-o.y,z-o.z};}Vector3 operator/(float f)const{return{x/f,y/f,z/f};}Vector3&operator+=(const Vector3&o){x+=o.x;y+=o.y;z+=o.z;return*this;}};
namespace glm{float distance(const Vector3&a,const Vector3&b){auto d=a-b;return std::sqrt(d.x*d.x+d.y*d.y+d.z*d.z);}}
namespace Impl{}
struct NetworkBitStream{std::vector<uint8_t>bytes;
void WriteBits(unsigned char*p,int bits,bool){if(bits%8)throw 1;bytes.insert(bytes.end(),p,p+bits/8);}
void Write(const char*p,size_t n){bytes.insert(bytes.end(),p,p+n);}
template<class templateType>
'''+write+'\n'+'\n'.join(methods)+'''
void writeVEC3(Vector3 v){writeFLOAT(v.x);writeFLOAT(v.y);writeFLOAT(v.z);}
void writeBIT(bool){throw 2;}void WriteCompressedStr(StringView){throw 3;}
bool readBIT(bool&){return false;}template<class T>bool readUINT16(T&){return false;}template<class T>bool readUINT32(T&){return false;}bool readVEC3(Vector3&){return false;}
};
enum class NetworkPacketType{RPC};constexpr int OrderingChannel_SyncRPC=2;
template<int ID,NetworkPacketType Type,int Channel>struct NetworkPacketBase{static constexpr int id=ID;};
struct Colour{uint32_t value=0;uint32_t ABGR()const{return value;}uint32_t ARGB()const{return value;}static Colour FromARGB(uint32_t v){return{v};}};
constexpr int MAX_OBJECT_MATERIAL_SLOTS=16,INVALID_VEHICLE_ID=65535,INVALID_OBJECT_ID=65535,QUESTION_MARK_MODEL_ID=18631;
struct ObjectMaterialData{enum class Type{None,Default,Text};Type type=Type::None;bool used=false;uint16_t model=0;String textOrTXD,fontOrTexture;Colour materialColour,fontColour,backgroundColour;uint8_t materialSize=0,fontSize=0,bold=0,alignment=0;};
struct ObjectAttachmentData{enum class Type{None,Vehicle,Object,Player};Type type=Type::None;int ID=65535;Vector3 offset,rotation;bool syncRotation=false;};
struct ObjectMoveData{Vector3 targetPos,targetRot;float speed=0;};
struct ObjectAttachmentSlotData{uint32_t model=0,bone=0;Vector3 offset,rotation,scale;Colour colour1,colour2;};
'''
    (work/'support.hpp').write_text(header)
    for name in ['network.hpp','player.hpp','types.hpp']:(work/name).write_text('#include "support.hpp"\n')
    stub=work/'Server/Components/Objects/objects.hpp';stub.parent.mkdir(parents=True);stub.write_text('#include "support.hpp"\n')
    (work/'object.hpp').write_bytes((REF/'openmp-object.hpp').read_bytes())
    method=balanced((REF/'openmp-objects-impl.hpp').read_text(),'bool advanceMove(Microseconds elapsed)')
    (work/'movement.hpp').write_text('''#include "support.hpp"
using namespace std::chrono;using Microseconds=std::chrono::microseconds;using RealSeconds=std::chrono::duration<double>;
struct ReferenceMove{bool moving_=false;Vector3 pos_,rot_;ObjectMoveData moveData_;float rotSpeed_=0;
'''+method+'\n};\n')
    (work/'reference.cpp').write_bytes((ROOT/'tests/network/smoke_samp_objects.cpp').read_bytes())
    subprocess.run(['xcrun','clang++','-std=c++17','-O1','-I',str(work),str(work/'reference.cpp'),'-o',str(work/'reference')],check=True)
    with(work/'goldens.json').open('w')as out:subprocess.run([str(work/'reference')],stdout=out,check=True)
def main():
    out=REF/'tests';out.mkdir(parents=True,exist_ok=True)
    names=['ios/App/NativeSAMPProtocol.swift','ios/App/NativeSAMPTextCodec.swift','ios/App/NativeSAMPObjects.swift','ios/App/NativeSAMPObjectScene.swift','ios/App/NativeSAMPObjectSimulationClock.swift','tests/network/smoke_samp_objects.cpp','tests/network/smoke_samp_objects.py','tests/network/smoke_samp_objects.swift']
    before={n:(ROOT/n).read_bytes()for n in names}
    with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as temp:
        work=Path(temp);fixture(work);sources=[]
        for name in [n for n in names if n.startswith('ios/App/')]:
            path=work/Path(name).name;path.write_bytes(before[name]);sources.append(str(path))
        (work/'main.swift').write_bytes(before['tests/network/smoke_samp_objects.swift'])
        result=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*sources,str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
        (out/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(work/'goldens.json')],capture_output=True,text=True)
        unchanged=all((ROOT/n).read_bytes()==data for n,data in before.items())
        report={'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,'sourceHashes':{n:hashlib.sha256(data).hexdigest()for n,data in before.items()},'referenceHashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in REF.glob('openmp-*')},'output':result.stdout+result.stderr,'limits':['Actual official packet writers with aligned byte-collector backing; compressed material text is separately exercised via native codec fixtures','Actual official advanceMove with controlled vector/chrono backing, not server runtime/rendered gameplay','Attachment transform/render/collision and object edit interactions require separate acceptance']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
