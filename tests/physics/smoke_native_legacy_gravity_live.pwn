// SPDX-License-Identifier: AGPL-3.0-only
// Disposable, independently authored loopback fixture. No game assets.
#include <open.mp>
new QA_Phase[MAX_PLAYERS][16];
new QA_Updates[MAX_PLAYERS];
main() {}
stock QA_Record(playerid,const event[]) {
    new name[MAX_PLAYER_NAME+1],Float:x,Float:y,Float:z,Float:vx,Float:vy,Float:vz;
    GetPlayerName(playerid,name,sizeof name);GetPlayerPos(playerid,x,y,z);GetPlayerVelocity(playerid,vx,vy,vz);
    printf("GRAVITY_QA {\"name\":\"%s\",\"event\":\"%s\",\"phase\":\"%s\",\"gravity\":%f,\"global\":%f,\"z\":%f,\"vz\":%f}",name,event,QA_Phase[playerid],GetPlayerGravity(playerid),GetGravity(),z,vz);
}
public OnGameModeInit() {
    SetGameModeText("ZGTA isolated gravity QA");SetGravity(0.004);
    AddPlayerClass(7,0.0,0.0,300.0,0.0,WEAPON_FIST,0,WEAPON_FIST,0,WEAPON_FIST,0);
    return 1;
}
public OnPlayerConnect(playerid) {QA_Phase[playerid]="initial";QA_Updates[playerid]=0;return 1;}
public OnPlayerSpawn(playerid) {SetPlayerHealth(playerid,100.0);QA_Record(playerid,"spawn");return 1;}
public OnPlayerUpdate(playerid) {if(++QA_Updates[playerid]%4==0)QA_Record(playerid,"update");return 1;}
public OnPlayerCommandText(playerid,cmdtext[]) {
    #pragma unused playerid
    new phase[16];
    if(!strcmp(cmdtext,"/gravity_one",true)) phase="one";
    else if(!strcmp(cmdtext,"/gravity_global",true)) phase="global";
    else if(!strcmp(cmdtext,"/gravity_zero",true)) phase="zero";
    else if(!strcmp(cmdtext,"/gravity_invert",true)) phase="invert";
    else if(!strcmp(cmdtext,"/gravity_restore",true)) phase="restore";
    else return 0;
    if(!strcmp(phase,"global") || !strcmp(phase,"restore"))SetGravity(0.008);
    for(new id=0;id<MAX_PLAYERS;id++)if(IsPlayerConnected(id)) {
        new name[MAX_PLAYER_NAME+1];GetPlayerName(id,name,sizeof name);
        new bool:a=!strcmp(name,"ZGTA_Gravity037");
        if(!strcmp(phase,"one") && a)SetPlayerGravity(id,0.016);
        if(!strcmp(phase,"zero") && a)SetPlayerGravity(id,0.0);
        if(!strcmp(phase,"invert") && !a)SetPlayerGravity(id,-0.008);
        QA_Phase[id]=phase;QA_Record(id,"change");
    }
    new message[48];format(message,sizeof message,"GRAVITY:%s",phase);SendClientMessageToAll(0xffffffff,message);
    return 1;
}
