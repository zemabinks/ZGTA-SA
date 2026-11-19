#include <cstdio>
#include <string>
#include <vector>
#include "custommodels.hpp"
#include "crc32.hpp"
static std::string hex(const std::vector<uint8_t>& bytes){std::string s;for(auto b:bytes){char v[3];std::snprintf(v,3,"%02x",b);s+=v;}return s;}
int main(){
 uint32_t seed=91207;auto rnd=[&](){seed=seed*1664525U+1013904223U;return seed;};
 std::printf("{\"models\":[");
 for(int i=0;i<256;++i){
  NetCode::RPC::ModelRequest r(i,256);r.type=i%2+1;r.virtualWorld=i%3 ? -1:73;r.baseId=i%2?19379:7;r.newId=i%2 ? -1000-i:20001+i;
  r.dffChecksum=rnd();r.txdChecksum=rnd();r.dffSize=rnd()%100000+1;r.txdSize=rnd()%100000+1;r.timeOn=i%24;r.timeOff=(i+7)%24;
  NetworkBitStream bs;r.write(bs);if(i)std::printf(",");
  std::printf("{\"hex\":\"%s\",\"pool\":%u,\"count\":%u,\"type\":%u,\"world\":%d,\"base\":%d,\"custom\":%d,\"dffCRC\":%u,\"txdCRC\":%u,\"dffSize\":%u,\"txdSize\":%u,\"on\":%u,\"off\":%u}",hex(bs.bytes).c_str(),r.poolID,r.Count,r.type,r.virtualWorld,r.baseId,r.newId,r.dffChecksum,r.txdChecksum,r.dffSize,r.txdSize,r.timeOn,r.timeOff);
 }
 std::printf("],\"urls\":[");
 for(int i=0;i<2;++i){NetCode::RPC::ModelUrl r("http://127.0.0.1:7789/synthetic.dff?test=1",i+1,0x1234abcd);NetworkBitStream bs;r.write(bs);if(i)std::printf(",");std::printf("\"%s\"",hex(bs.bytes).c_str());}
 std::printf("],\"crc\":[");
 for(int length: {0,1,7,1024,65536}){std::vector<uint8_t> data(length);for(auto&b:data)b=rnd()&255;auto crc=CRC32(0,data.data(),int(data.size()));static bool comma=false;if(comma)std::printf(",");comma=true;std::printf("{\"hex\":\"%s\",\"crc\":%u}",hex(data).c_str(),crc);}
 std::printf("],\"rpcIDs\":[%d,%d,%d,%d,%d,%d]}",NetCode::RPC::ModelRequest::id,NetCode::RPC::RequestDFF::id,NetCode::RPC::RequestTXD::id,NetCode::RPC::ModelUrl::id,NetCode::RPC::FinishDownload::id,NetCode::RPC::DownloadCompleted::id);
}
