// SPDX-License-Identifier: AGPL-3.0-only
// Independent owned DL visual fixture; original model bytes remain local-only.
#include <open.mp>
new QA_Object, QA_Car;
new Float:QA_Home[3] = {2296.5663, 2451.6270, 10.8203};
stock QA_Log(playerid, const event[])
{
    new name[MAX_PLAYER_NAME+1], Float:x, Float:y, Float:z, KEY:keys, ud, lr;
    GetPlayerName(playerid,name,sizeof name);GetPlayerPos(playerid,x,y,z);GetPlayerKeys(playerid,keys,ud,lr);
    printf("ZGTA_VISUAL {\"name\":\"%s\",\"event\":\"%s\",\"state\":%d,\"vehicle\":%d,\"skin\":%d,\"customSkin\":%d,\"keys\":%d,\"lr\":%d,\"ud\":%d,\"x\":%f,\"y\":%f,\"z\":%f}",
        name,event,_:GetPlayerState(playerid),GetPlayerVehicleID(playerid),GetPlayerSkin(playerid),GetPlayerCustomSkin(playerid),keys,lr,ud,x,y,z);
    return 1;
}
main() {}
public OnGameModeInit()
{
    SetGameModeText("ZGTA owned DL visual QA");SetWorldTime(12);SetWeather(0);
    AddPlayerClass(20001,QA_Home[0],QA_Home[1],QA_Home[2],0.0,WEAPON_DEAGLE,100,WEAPON_UZI,100,WEAPON_FIST,0);
    QA_Car=AddStaticVehicle(411,2301.5,2451.6,10.82,0.0,1,1);
    QA_Object=CreateObject(-1000,2296.5,2459.0,10.2,0.0,0.0,0.0,300.0);
    SetObjectMaterialText(QA_Object,"ZGTA SA QA",0,OBJECT_MATERIAL_SIZE_512x256,"Arial",32,false,0xFFFFFFFF,0xFF102030,OBJECT_MATERIAL_TEXT_ALIGN_CENTER);
    printf("ZGTA_VISUAL_MODELS ped=20001 object=-1000 instance=%d car=%d",QA_Object,QA_Car);
    return 1;
}
public OnPlayerConnect(playerid){QA_Log(playerid,"connect");return 1;}
public OnPlayerRequestClass(playerid,classid)
{
    #pragma unused classid
    SetPlayerPos(playerid,QA_Home[0],QA_Home[1],QA_Home[2]);SetPlayerFacingAngle(playerid,0.0);
    SetPlayerCameraPos(playerid,2296.5,2446.0,13.2);SetPlayerCameraLookAt(playerid,2296.5,2452.0,11.5,CAMERA_CUT);
    QA_Log(playerid,"class");return 1;
}
public OnPlayerSpawn(playerid)
{
    SetPlayerInterior(playerid,0);SetPlayerHealth(playerid,100.0);SetPlayerArmour(playerid,25.0);
    SetPlayerSkin(playerid,20001);SetPlayerPos(playerid,QA_Home[0],QA_Home[1],QA_Home[2]);SetPlayerFacingAngle(playerid,0.0);
    GivePlayerWeapon(playerid,WEAPON_DEAGLE,100);SetPlayerArmedWeapon(playerid,WEAPON_DEAGLE);
    SetCameraBehindPlayer(playerid);SendClientMessage(playerid,0xFFFFFFFF,"Owned DL QA: /qa_help");QA_Log(playerid,"spawn");return 1;
}
public OnPlayerFinishedDownloading(playerid,virtualworld)
{
    #pragma unused virtualworld
    QA_Log(playerid,"download_ready");return 1;}
public OnPlayerRequestDownload(playerid,DOWNLOAD_REQUEST:type,crc)
{
    #pragma unused type,crc
    QA_Log(playerid,"download_request");return 1;}
public OnPlayerCommandText(playerid,cmdtext[])
{
    if(!strcmp(cmdtext,"/qa_help")){ShowPlayerDialog(playerid,27,DIALOG_STYLE_MSGBOX,"Owned DL QA","/qa_move /qa_reset /qa_freeze /qa_unfreeze\n/qa_camera /qa_behind /qa_driver /qa_spec /qa_unspec","Close","");return 1;}
    if(!strcmp(cmdtext,"/qa_move")){MoveObject(QA_Object,2300.5,2459.0,10.2,1.0);QA_Log(playerid,"object_move");return 1;}
    if(!strcmp(cmdtext,"/qa_reset")){StopObject(QA_Object);SetObjectPos(QA_Object,2296.5,2459.0,10.2);return 1;}
    if(!strcmp(cmdtext,"/qa_freeze")){TogglePlayerControllable(playerid,false);QA_Log(playerid,"freeze");return 1;}
    if(!strcmp(cmdtext,"/qa_unfreeze")){TogglePlayerControllable(playerid,true);QA_Log(playerid,"unfreeze");return 1;}
    if(!strcmp(cmdtext,"/qa_camera")){SetPlayerCameraPos(playerid,2296.5,2445.0,14.0);SetPlayerCameraLookAt(playerid,2296.5,2458.0,11.3,CAMERA_CUT);QA_Log(playerid,"camera");return 1;}
    if(!strcmp(cmdtext,"/qa_behind")){SetCameraBehindPlayer(playerid);return 1;}
    if(!strcmp(cmdtext,"/qa_driver")){PutPlayerInVehicle(playerid,QA_Car,0);QA_Log(playerid,"forced_driver");return 1;}
    if(!strcmp(cmdtext,"/qa_spec")){TogglePlayerSpectating(playerid,true);PlayerSpectateVehicle(playerid,QA_Car,SPECTATE_MODE_NORMAL);QA_Log(playerid,"spectate");return 1;}
    if(!strcmp(cmdtext,"/qa_unspec")){TogglePlayerSpectating(playerid,false);QA_Log(playerid,"unspectate");return 1;}
    return 0;
}
public OnObjectMoved(objectid){if(objectid==QA_Object){printf("ZGTA_VISUAL_OBJECT_MOVED %d",objectid);}return 1;}
public OnPlayerEnterVehicle(playerid,vehicleid,ispassenger)
{
    #pragma unused vehicleid,ispassenger
    QA_Log(playerid,"enter_rpc");return 1;}
public OnPlayerExitVehicle(playerid,vehicleid)
{
    #pragma unused vehicleid
    QA_Log(playerid,"exit_rpc");return 1;}
public OnPlayerStateChange(playerid,PLAYER_STATE:newstate,PLAYER_STATE:oldstate)
{
    #pragma unused newstate,oldstate
    QA_Log(playerid,"state");return 1;}
public OnPlayerUpdate(playerid)
{
    // Bound actual authority evidence to4Hz per player.
    static last[MAX_PLAYERS];new now=GetTickCount();if(now-last[playerid]>=250){last[playerid]=now;QA_Log(playerid,"update");}
    return 1;
}
