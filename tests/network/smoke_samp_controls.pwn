// SPDX-License-Identifier: AGPL-3.0-only
// Independent, disposable open.mp control/state fixture. No game assets.
#include <open.mp>

new QA_Vehicle;
new QA_Phase[MAX_PLAYERS][32];
new QA_Seen[MAX_PLAYERS];
new KEY:QA_Keys[MAX_PLAYERS];
new QA_LR[MAX_PLAYERS], QA_UD[MAX_PLAYERS];
new QA_State[MAX_PLAYERS], QA_Weapon[MAX_PLAYERS];

stock QA_Record(playerid, const event[])
{
    new name[MAX_PLAYER_NAME + 1], KEY:keys, lr, ud;
    new Float:x, Float:y, Float:z;
    new Float:cx,Float:cy,Float:cz,Float:chp;
    GetPlayerName(playerid, name, sizeof name);
    GetPlayerKeys(playerid, keys, ud, lr);
    GetPlayerPos(playerid, x, y, z);
    GetVehiclePos(QA_Vehicle,cx,cy,cz);GetVehicleHealth(QA_Vehicle,chp);
    printf("ZGTA_QA {\"name\":\"%s\",\"event\":\"%s\",\"phase\":\"%s\",\"state\":%d,\"vehicle\":%d,\"keys\":%d,\"lr\":%d,\"ud\":%d,\"weapon\":%d,\"x\":%f,\"y\":%f,\"z\":%f,\"carX\":%f,\"carY\":%f,\"carZ\":%f,\"carHP\":%f}",
        name, event, QA_Phase[playerid], _:GetPlayerState(playerid), GetPlayerVehicleID(playerid), keys, lr, ud, _:GetPlayerWeapon(playerid), x, y, z,cx,cy,cz,chp);
    return 1;
}
main() {}
public OnGameModeInit()
{
    SetGameModeText("ZGTA owned control QA");
    AddPlayerClass(287, 1510.0, -1720.0, 13.5, 90.0, WEAPON_DEAGLE, 500, WEAPON_UZI, 500, WEAPON_FIST, 0);
    QA_Vehicle = AddStaticVehicle(411, 1515.0, -1720.0, 13.5, 90.0, 1, 1);
    printf("ZGTA_QA_VEHICLE %d", QA_Vehicle);
    return 1;
}
public OnPlayerConnect(playerid)
{
    QA_Phase[playerid] = "connected";
    QA_Seen[playerid] = 0;
    QA_Record(playerid, "connect");
    return 1;
}
public OnPlayerRequestClass(playerid, classid)
{
    #pragma unused classid
    SetPlayerPos(playerid, 1510.0, -1720.0, 13.5);
    SetPlayerCameraPos(playerid, 1507.0, -1720.0, 15.0);
    SetPlayerCameraLookAt(playerid, 1510.0, -1720.0, 13.5);
    return 1;
}
public OnPlayerSpawn(playerid)
{
    SetPlayerInterior(playerid, 0);
    SetPlayerHealth(playerid, 100.0);
    SetPlayerArmour(playerid, 25.0);
    GivePlayerWeapon(playerid, WEAPON_DEAGLE, 500);
    GivePlayerWeapon(playerid, WEAPON_UZI, 500);
    SetPlayerArmedWeapon(playerid, WEAPON_DEAGLE);
    QA_Record(playerid, "spawn");
    return 1;
}
public OnPlayerCommandText(playerid, cmdtext[])
{
    if (!strcmp(cmdtext, "/qa_freeze")) {TogglePlayerControllable(playerid, false);return 1;}
    if (!strcmp(cmdtext, "/qa_unfreeze")) {TogglePlayerControllable(playerid, true);return 1;}
    if (!strcmp(cmdtext, "/qa_camera"))
    {
        SetPlayerCameraPos(playerid, 1500.0, -1700.0, 30.0);
        SetPlayerCameraLookAt(playerid, 1510.0, -1720.0, 15.0, CAMERA_CUT);
        return 1;
    }
    if (!strcmp(cmdtext, "/qa_interpolate"))
    {
        InterpolateCameraPos(playerid, 1500.0, -1700.0, 30.0, 1504.0, -1704.0, 32.0, 1500, CAMERA_MOVE);
        InterpolateCameraLookAt(playerid, 1510.0, -1720.0, 15.0, 1512.0, -1722.0, 16.0, 1600, CAMERA_MOVE);
        return 1;
    }
    if (!strcmp(cmdtext, "/qa_camera_behind")) {SetCameraBehindPlayer(playerid);return 1;}
    if (!strcmp(cmdtext, "/qa_spec_player"))
    {
        for (new target = 0; target < MAX_PLAYERS; target++)
        {
            if (target != playerid && IsPlayerConnected(target))
            {
                TogglePlayerSpectating(playerid, true);
                PlayerSpectatePlayer(playerid, target, SPECTATE_MODE_FIXED);
                return 1;
            }
        }
        return 1;
    }
    if (!strcmp(cmdtext, "/qa_spec_vehicle")) {PlayerSpectateVehicle(playerid, QA_Vehicle, SPECTATE_MODE_SIDE);return 1;}
    // No explicit SpawnPlayer call: client must complete the server-authorized
    // normal PlayerSpawn52 transaction when124 disables spectating.
    if (!strcmp(cmdtext, "/qa_spec_off")) {TogglePlayerSpectating(playerid, false);return 1;}
    if (!strcmp(cmdtext, "/qa_passenger"))
    {
        PutPlayerInVehicle(playerid, QA_Vehicle, 1);
        return 1;
    }
    if (!strcmp(cmdtext, "/qa_unseat"))
    {
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (!strcmp(cmdtext, "/qa_far"))
    {
        SetPlayerPos(playerid, 2500.0, -1720.0, 13.5);
        return 1;
    }
    if (!strcmp(cmdtext, "/qa_home"))
    {
        SetPlayerPos(playerid, 1510.0, -1720.0, 13.5);
        return 1;
    }
    if (strfind(cmdtext, "/qa ") != 0) return 0;
    strmid(QA_Phase[playerid], cmdtext, 4, strlen(cmdtext), 32);
    QA_Seen[playerid] = 0;
    SendClientMessage(playerid, 0xFFFFFFFF, "QA:%s", QA_Phase[playerid]);
    return 1;
}
public OnPlayerEnterVehicle(playerid, vehicleid, ispassenger)
{
    #pragma unused vehicleid, ispassenger
    QA_Record(playerid, "enter_rpc");
    return 1;
}
public OnPlayerExitVehicle(playerid, vehicleid)
{
    #pragma unused vehicleid
    QA_Record(playerid, "exit_rpc");
    return 1;
}
public OnPlayerStateChange(playerid, PLAYER_STATE:newstate, PLAYER_STATE:oldstate)
{
    #pragma unused newstate, oldstate
    QA_Record(playerid, "state");
    return 1;
}
public OnPlayerUpdate(playerid)
{
    new KEY:keys, lr, ud, playerState = _:GetPlayerState(playerid), weapon = _:GetPlayerWeapon(playerid);
    GetPlayerKeys(playerid, keys, ud, lr);
    if (!QA_Seen[playerid] || keys != QA_Keys[playerid] || lr != QA_LR[playerid] || ud != QA_UD[playerid]
        || playerState != QA_State[playerid] || weapon != QA_Weapon[playerid])
    {
        QA_Record(playerid, "update");
        QA_Seen[playerid] = 1;
        QA_Keys[playerid] = keys; QA_LR[playerid] = lr; QA_UD[playerid] = ud;
        QA_State[playerid] = playerState; QA_Weapon[playerid] = weapon;
    }
    return 1;
}
