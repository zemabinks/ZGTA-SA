#!/usr/bin/env python3
"""Official open.mp packet methods + isolated native HTTP artwork verification."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
REFERENCE=ROOT/'local-only/research/samp-artwork'
def balanced(source,marker):
 start=source.index(marker);opening=source.index('{',start);depth=0
 for index in range(opening,len(source)):
  if source[index]=='{':depth+=1
  elif source[index]=='}':
   depth-=1
   if depth==0:return source[start:index+1]
 raise ValueError(marker)
def reference_fixture(folder):
 network=(REFERENCE/'openmp-network-bitstream.hpp').read_text()
 methods=[balanced(network,m)for m in ['inline void writeUINT8(','inline void writeUINT32(','inline void writeINT32(','inline void writeDynStr8(']]
 methods=[('template<typename T>\n'+m)if'writeDynStr8'not in m else m for m in methods]
 write=balanced(network,'inline void NetworkBitStream::Write(templateType var)').replace('NetworkBitStream::','')
 (folder/'bitstream.hpp').write_text('''#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <string>
#include <string_view>
using String=std::string;using StringView=std::string_view;
struct NetworkBitStream {std::vector<uint8_t> bytes;
void WriteBits(unsigned char*p,int bits,bool){if(bits%8)throw 1;bytes.insert(bytes.end(),p,p+bits/8);}
void Write(const char*p,size_t n){bytes.insert(bytes.end(),p,p+n);}
template<class templateType>
'''+write+'\n'+'\n'.join(methods)+'''
bool readUINT32(uint32_t&v){if(bytes.size()<4)return false;std::memcpy(&v,bytes.data(),4);return true;}
};
''')
 (folder/'network.hpp').write_text('#pragma once\nenum class NetworkPacketType{RPC};constexpr int OrderingChannel_SyncRPC=0,OrderingChannel_DownloadRequest=1;\n')
 (folder/'packet.hpp').write_text('#pragma once\ntemplate<int ID,NetworkPacketType Type,int Channel>struct NetworkPacketBase{static constexpr int id=ID;};\n')
 (folder/'types.hpp').write_text('#pragma once\n#include "bitstream.hpp"\n')
 (folder/'custommodels.hpp').write_bytes((REFERENCE/'openmp-custommodels.hpp').read_bytes())
 (folder/'crc32.hpp').write_bytes((REFERENCE/'openmp-crc32.hpp').read_bytes())
 (folder/'reference.cpp').write_bytes((ROOT/'tests/network/smoke_samp_artwork.cpp').read_bytes())
 subprocess.run(['xcrun','clang++','-std=c++17','-O1','-I',str(folder),str(folder/'reference.cpp'),'-o',str(folder/'reference')],check=True)
 with(folder/'goldens.json').open('w')as output:subprocess.run([str(folder/'reference')],stdout=output,check=True)
def main():
 out=ROOT/'local-only/research/samp-artwork/tests';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/NativeSAMPArtwork.swift','tests/network/smoke_samp_artwork.py','tests/network/smoke_samp_artwork.cpp','tests/network/smoke_samp_artwork.js','tests/network/smoke_samp_artwork.swift']
 before={p:(ROOT/p).read_bytes()for p in paths}
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as temp:
  work=Path(temp);reference_fixture(work)
  (work/'main.swift').write_bytes(before['tests/network/smoke_samp_artwork.swift']);(work/'artwork.swift').write_bytes(before['ios/App/NativeSAMPArtwork.swift'])
  result=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),str(work/'artwork.swift'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run(['node',str(ROOT/'tests/network/smoke_samp_artwork.js'),str(work/'verify'),str(work/'goldens.json'),str(work/'cache')],capture_output=True,text=True,timeout=60)
  unchanged=all((ROOT/p).read_bytes()==b for p,b in before.items())
  report={'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(b).hexdigest()for p,b in before.items()},'referenceHashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in REFERENCE.glob('openmp-*')if p.is_file()},'output':result.stdout+result.stderr,'limits':['Actual unmodified official ModelRequest/ModelUrl and CRC32 methods plus official integer/string write bodies','Aligned bitstream backing is an explicit byte collector; transport/RakNet join is separate','Real URLSession HTTP over disposable localhost service and synthetic bytes only','DFF/TXD rendering, collision, materials and custom skin rig import remain required; download success is not model render acceptance','Protocol CRC32 is not an authentication or collision-resistant security hash; MD5 is a local receipt fingerprint only']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
