#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual remote packet/cache role regression; no transport, assets or UI."""
from pathlib import Path
import hashlib,json,subprocess,time
from smoke_native_vehicle_transparency import block
ROOT=Path(__file__).resolve().parent

def main():
 out=ROOT/'local-only/research/remote-appearance-110'/str(time.time_ns());out.mkdir(parents=True)
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text();network=(ROOT/'ios/App/NativeMultiplayerClient.swift').read_text()
 files=[ROOT/'ios/App'/p for p in ['NativeWorldRenderer.swift','NativeMultiplayerClient.swift','NativeRemoteBikeAnimation.swift']]+[Path(__file__)]
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 assert 'let driving = !code.hasPrefix("s")'in network
 assert 'if Self.remoteAppearanceIsFoot(code:player.code,ridingVehicleID:player.ridingVehicleID)'in renderer
 assert 'let drivenVehicleIDs = Set(remotePlayers.compactMap(\\.vehicleID))'in renderer
 assert 'let player=remotePlayers.first{Self.remoteAppearanceIsDriver'in renderer
 source='''import Foundation
import simd
// ACTUAL_REMOTE_PLAYER
final class Carrier {
 var remotePlayers:[RemotePlayer]=[]
 var remoteServerTimeOffsetMilliseconds:Double?
 var remoteBikeSamples:[String:(NativeRemoteBikeAnimation.Sample,NativeRemoteBikeAnimation.Sample?)]=[:]
 HELPERS
 RECORD
 func ids()->(Set<String>,Set<String>){RIDERIDS;FOOTIDS;return(riderIDs,footIDs)}
 func run(){
  var checks=0
  func check(_ value:Bool){checks+=1;precondition(value)}
  func p(_ id:String,_ code:String,_ vehicle:String?=nil,_ ride:String?=nil)->RemotePlayer{
   var v=RemotePlayer(id:id,name:"Authored",position:.zero,code:code,heading:0,pitch:0,roll:0,speed:3,steer:0,skin:7,animation:"",animationStarted:0,weapon:0,vehicleID:vehicle)
   v.ridingVehicleID=ride;v.ridingSeat=ride==nil ? 0:1;v.packetReceivedAt=5;v.packetClockMilliseconds=1000;return v
  }
  let car=p("car","420"),bike=p("bike","522"),registered=p("registered","420","owned"),foot=p("foot","s7"),passenger=p("passenger","s7",nil,"owned")
  remotePlayers=[car,bike,registered,foot,passenger]
  check(Self.remoteAppearanceIsDriver(code:car.code,ridingVehicleID:nil))
  check(Self.remoteAppearanceIsDriver(code:bike.code,ridingVehicleID:nil))
  check(!Self.remoteAppearanceIsFoot(code:car.code,ridingVehicleID:nil))
  check(Self.remoteAppearanceIsFoot(code:foot.code,ridingVehicleID:nil))
  check(!Self.remoteAppearanceIsDriver(code:passenger.code,ridingVehicleID:passenger.ridingVehicleID))
  check(!Self.remoteAppearanceIsFoot(code:passenger.code,ridingVehicleID:passenger.ridingVehicleID))
  check(ids().0==["car","bike","registered","passenger"] && ids().1==["foot"])
  recordRemoteAnimationPackets()
  check(Set(remoteBikeSamples.keys)==["car","bike","registered"])
  check(remoteBikeSamples["bike"]!.0.speed==3 && remoteBikeSamples["bike"]!.0.serial==1000 && remoteBikeSamples["bike"]!.0.time==5)
  recordRemoteAnimationPackets();check(remoteBikeSamples["bike"]!.1==nil)
  check(Self.remoteDriverRenderKey(playerID:"car",vehicleID:nil) != Self.remoteDriverRenderKey(playerID:"bike",vehicleID:nil))
  check(Self.remoteDriverRenderKey(playerID:"registered",vehicleID:"owned")=="owned")
  check(car.vehicleID==nil && bike.vehicleID==nil && passenger.vehicleID==nil)
  remotePlayers=[p("car","s7"),passenger]
  recordRemoteAnimationPackets();check(remoteBikeSamples.isEmpty)
  check(ids().0==["passenger"] && ids().1==["car"])
  remotePlayers=[car,bike];recordRemoteAnimationPackets()
  check(Set(remoteBikeSamples.keys)==["car","bike"])
  remotePlayers=[];recordRemoteAnimationPackets();check(remoteBikeSamples.isEmpty)
  print("REMOTE_APPEARANCE_PASS \(checks) actual packet/cache/role assertions")
 }
}
Carrier().run()
'''
 source=source.replace('// ACTUAL_REMOTE_PLAYER',block(network,'struct RemotePlayer {'))
 source=source.replace('HELPERS','\n'.join(block(renderer,m)for m in ['    private static func remoteAppearanceIsDriver(','    private static func remoteAppearanceIsFoot(','    private static func remoteDriverRenderKey(']))
 source=source.replace('RECORD',block(renderer,'    private func recordRemoteAnimationPackets('))
 for token,name in [('RIDERIDS','let riderIDs = '),('FOOTIDS','let footIDs = ')]:source=source.replace(token,next(line.strip()for line in renderer.splitlines()if line.strip().startswith(name)))
 (out/'main.swift').write_text(source);(out/'NativeRemoteBikeAnimation.swift').write_bytes((ROOT/'ios/App/NativeRemoteBikeAnimation.swift').read_bytes())
 with(out/'compile.log').open('w')as log:subprocess.run(['xcrun','swiftc','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),str(out/'NativeRemoteBikeAnimation.swift'),str(out/'main.swift'),'-o',str(out/'verify')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=600)
 r=subprocess.run([str(out/'verify')],capture_output=True,text=True,check=True,timeout=30);(out/'runtime.log').write_text(r.stdout+r.stderr)
 assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in hashes.items())
 report={'status':'PASS','sourceHashes':hashes,'sourceUnchanged':True,'output':r.stdout.strip(),'originalDataUsed':False,'networkOrUIUsed':False,'registryIDsManufactured':False}
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
