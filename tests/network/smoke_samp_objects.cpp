// SPDX-License-Identifier: AGPL-3.0-only
// The test build supplies pinned, unmodified official packet classes and
// movement method from the ignored local research references.
#include <iostream>
#include <iomanip>
#include <sstream>
#include "object.hpp"
#include "movement.hpp"
using namespace NetCode::RPC;
static std::string hex(const std::vector<uint8_t>& b) {
    std::ostringstream out;for(auto v:b)out<<std::hex<<std::setfill('0')<<std::setw(2)<<int(v);return out.str();
}
template<class T>static void packet(T& value,const char* label) {
    NetworkBitStream bs;value.write(bs);
    std::cout<<"{\"id\":"<<T::id<<",\"label\":\""<<label<<"\",\"hex\":\""<<hex(bs.bytes)<<"\"},\n";
}
int main() {
    std::cout<<"{\"packets\":[\n";
    StaticArray<ObjectMaterialData,16> materials{};
    materials[3].used=true;materials[3].type=ObjectMaterialData::Type::Default;
    materials[3].model=19379;materials[3].textOrTXD="concrete";materials[3].fontOrTexture="wall_01";
    materials[3].materialColour.value=0x80332211;
    CreateObject create(materials,1,true);create.ObjectID=17;create.ModelID=-1001;
    create.Position={1.25f,-4.f,8.5f};create.Rotation={10.f,20.f,350.f};create.DrawDistance=300.f;create.CameraCollision=true;
    create.AttachmentData.type=ObjectAttachmentData::Type::None;packet(create,"custom");
    create.ObjectID=18;create.AttachmentData.type=ObjectAttachmentData::Type::Vehicle;create.AttachmentData.ID=4;
    create.AttachmentData.offset={1,2,3};create.AttachmentData.rotation={4,5,6};create.AttachmentData.syncRotation=true;packet(create,"attached");
    create.ObjectID=19;create.isDL=false;create.ModelID=19379;create.AttachmentData.type=ObjectAttachmentData::Type::Object;create.AttachmentData.ID=17;packet(create,"stock");
    SetObjectPosition pos;pos.ObjectID=17;pos.Position={40,50,60};packet(pos,"position");
    SetObjectRotation rot;rot.ObjectID=17;rot.Rotation={-10,360,720};packet(rot,"rotation");
    MoveObject move;move.ObjectID=17;move.CurrentPosition={1.25f,-4.f,8.5f};move.MoveData.targetPos={11.25f,16.f,18.5f};move.MoveData.targetRot={10,20,10};move.MoveData.speed=5;packet(move,"move");
    StopObject stop;stop.ObjectID=17;packet(stop,"stop");
    AttachObjectToPlayer attach;attach.ObjectID=17;attach.PlayerID=35;attach.Offset={0.1f,0.2f,0.3f};attach.Rotation={90,180,270};packet(attach,"player");
    SetPlayerObjectMaterial mat(materials[3]);mat.ObjectID=17;mat.MaterialID=3;packet(mat,"material");
    DestroyObject destroy;destroy.ObjectID=17;packet(destroy,"destroy");
    std::cout<<"null],\"motion\":[\n";
    for(int hz:{15,30,60,90,120,144}) {
        ReferenceMove body;body.pos_={1.25f,-4.f,8.5f};body.rot_={10,20,350};body.moveData_.targetPos={11.25f,16.f,18.5f};body.moveData_.targetRot={10,20,10};body.moveData_.speed=5;
        body.rotSpeed_=glm::distance(body.rot_,body.moveData_.targetRot)*5/glm::distance(body.pos_,body.moveData_.targetPos);body.moving_=true;
        int64_t micros=0;for(int step=1;step<=hz*6;++step) {
            int64_t next=int64_t(std::llround(double(step)*1000000.0/hz));body.advanceMove(Microseconds(next-micros));micros=next;
            if(step%(hz/3)==0 || step==hz*6)
                std::cout<<"{\"hz\":"<<hz<<",\"at\":"<<std::setprecision(12)<<double(micros)/1e6<<",\"point\":["<<body.pos_.x<<","<<body.pos_.y<<","<<body.pos_.z<<"],\"rotation\":["<<body.rot_.x<<","<<body.rot_.y<<","<<body.rot_.z<<"]},\n";
        }
    }
    std::cout<<"null]}\n";
}
