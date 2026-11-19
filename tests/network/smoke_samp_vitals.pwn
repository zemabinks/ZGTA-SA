// SPDX-License-Identifier: AGPL-3.0-only
// Independent disposable local-vitals fixture. No game assets or health ACK.
#include <open.mp>
new QA_Phase[MAX_PLAYERS][32];
new QA_Seen[MAX_PLAYERS],QA_Car;
stock QA_Record(playerid,const event[],Float:amount=0.0,WEAPON:weapon=WEAPON_FIST,source=INVALID_PLAYER_ID,body=3)
{
    new name[MAX_PLAYER_NAME+1];new Float:hp,Float:ap;
    GetPlayerName(playerid,name,sizeof name);GetPlayerHealth(playerid,hp);GetPlayerArmour(playerid,ap);
    printf("ZGTA_VITALS {\"name\":\"%s\",\"phase\":\"%s\",\"event\":\"%s\",\"amount\":%f,\"weapon\":%d,\"source\":%d,\"body\":%d,\"health\":%f,\"armour\":%f,\"state\":%d}",name,QA_Phase[playerid],event,amount,_:weapon,source,body,hp,ap,_:GetPlayerState(playerid));
    return 1;
}
main(){}
public OnGameModeInit()
{
    AddPlayerClass(287,1510.0,-1720.0,13.5,0.0,WEAPON_DEAGLE,50,WEAPON_FIST,0,WEAPON_FIST,0);
    QA_Car=AddStaticVehicle(411,1515.0,-1720.0,13.5,0.0,1,1);return 1;
}
public OnPlayerConnect(playerid){QA_Phase[playerid]="joining";return 1;}
public OnPlayerSpawn(playerid){SetPlayerHealth(playerid,100.0);SetPlayerArmour(playerid,25.0);QA_Record(playerid,"spawn");return 1;}
public OnPlayerCommandText(playerid,cmdtext[])
{
    if(!strcmp(cmdtext,"/qa_seed")){SetPlayerHealth(playerid,35.75);SetPlayerArmour(playerid,12.5);return 1;}
    if(!strcmp(cmdtext,"/qa_armour")){SetPlayerHealth(playerid,80.75);SetPlayerArmour(playerid,25.5);return 1;}
    if(!strcmp(cmdtext,"/qa_high")){SetPlayerHealth(playerid,1000.5);SetPlayerArmour(playerid,1000.25);return 1;}
    if(!strcmp(cmdtext,"/qa_fatal")){SetPlayerHealth(playerid,1.125);SetPlayerArmour(playerid,12.5);return 1;}
    if(!strcmp(cmdtext,"/qa_freeze")){TogglePlayerControllable(playerid,false);return 1;}
    if(!strcmp(cmdtext,"/qa_unfreeze")){TogglePlayerControllable(playerid,true);return 1;}
    if(strfind(cmdtext,"/qa ")!=0)return 0;
    strmid(QA_Phase[playerid],cmdtext,4,strlen(cmdtext),32);QA_Seen[playerid]=0;
    SendClientMessage(playerid,0xFFFFFFFF,"VITALS:%s",QA_Phase[playerid]);return 1;
}
public OnPlayerTakeDamage(playerid,issuerid,Float:amount,WEAPON:weaponid,bodypart)
{
    QA_Record(playerid,"taking",amount,weaponid,issuerid,bodypart);return 1;
}
public OnPlayerDeath(playerid,killerid,WEAPON:reason){QA_Record(playerid,"death",0.0,reason,killerid);return 1;}
public OnPlayerUpdate(playerid)
{
    if(++QA_Seen[playerid]<=3){QA_Record(playerid,"update");}return 1;
}
