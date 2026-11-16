// SPDX-License-Identifier: AGPL-3.0-only
// Packet write bodies are supplied read-only from the pinned local reference.
#include <cstdio>
#include <string>
#include "reference.hpp"
static std::string hex(const std::vector<uint8_t>& data) {
    std::string result;
    for (auto byte:data) { char value[3]; std::snprintf(value,3,"%02x",byte); result+=value; }
    return result;
}
int main() {
    std::printf("{\"aim\":[");
    const int modes[]={4,7,8,18,53,55};
    for (int i=0;i<320;i++) {
        PlayerAimSync p{};p.PlayerID=i+1;p.CamMode=modes[i%6];
        p.CamFrontVector={float(i%2 ? -1:1),0,0};
        p.CamPos={float(i*13-2000),float(1000-i*7),float(i%90)};
        p.AimZ=float(i%21-10)/10;p.CamZoom=i%64;p.WeaponState=(i/64)%4;p.AspectRatio=i%256;
        NetworkBitStream bs;p.write(bs);
        std::printf("%s\"%s\"",i ? ",":"",hex(bs.bytes).c_str());
    }
    std::printf("],\"bullet\":[");
    for (int i=0;i<320;i++) {
        PlayerBulletSync p{};p.PlayerID=i+1;p.HitType=i%5;p.HitID=p.HitType ? i%100:65535;
        p.Origin={float(i*13-2000),float(1000-i*7),float(i%90)};
        p.HitPos={p.Origin.x+8,p.Origin.y-5,p.Origin.z+1};
        p.Offset={float(i%9-4),float(i%7-3),float(i%5-2)};p.WeaponID=22+i%13;
        NetworkBitStream bs;p.write(bs);
        std::printf("%s\"%s\"",i ? ",":"",hex(bs.bytes).c_str());
    }
    std::printf("]}\n");
}
