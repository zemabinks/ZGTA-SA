// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
@main enum RiderFallMetadataTests {
 static var checks=0
 static func check(_ ok:Bool,_ text:String)throws{checks+=1;if !ok{throw NSError(domain:text,code:1)}}
 static func main()throws {
  let seat:[String:Any]=["at":[0,0,0],"side":-1,"rear":false,"opens":false]
  var group:[String:Any]=["open":[],"openRear":[],"getIn":[],"getInRear":[],"pullOut":[],"closeIn":[],"closeInRear":[],"getOut":[],"getOutRear":[],"closeOut":[],"closeOutRear":[],"getInTime":0,"getOutTime":0,"doorOpenOut":[],"doorCloseIn":[],"doorOpenIn":[],"doorCloseOut":[],"special":0,"shuffle":""]
  func definition(_ group:[String:Any])->NativeRiderDefinitions.Definition {
   let row:[String:Any]=["model":"authored","astride":true,"clips":["hit":"authored:hit"],"seats":[seat],"origin":0,"group":group]
   return try! JSONDecoder().decode(NativeRiderDefinitions.Definition.self,from:JSONSerialization.data(withJSONObject:row))
  }
  let known:Set<String>=["authored/left","authored/right","authored/hit"]
  var value=definition(group)
  try check(value.fallOffClip(contains:known.contains)==nil,"Older group without fallOff stopped decoding")
  group["fallOff"]=[NSNull(),"authored:right"];value=definition(group)
  try check(value.fallOffClip(contains:known.contains)=="authored/right","Null side did not use the available opposite")
  group["fallOff"]=["authored:missing","authored:right"];value=definition(group)
  try check(value.fallOffClip(contains:known.contains)=="authored/right","Missing library entry prevented side fallback")
  group["fallOff"]=["authored:left","authored:right"];value=definition(group)
  try check(value.fallOffClip(side:1,contains:known.contains)=="authored/left","Requested side overrode the seat side")
  value.seats[0].side=0
  try check(value.fallOffClip(side:1,contains:known.contains)=="authored/right","Neutral seat failed to use requested side")
  try check(value.fallOffClip(side:-1,contains:known.contains)=="authored/left","Neutral seat negative-side selection")
  try check(value.fallOffClip(seat:9,contains:known.contains)==nil,"Invalid seat invented a clip")
  try check(value.hitClip(contains:known.contains)=="authored/hit","Existing optional hit not normalized/admitted")
  try check(value.hitClip(contains:{_ in false})==nil,"Missing optional hit invented a replacement")
  value.clips.removeValue(forKey:"hit");value.astrideKind="authored"
  try check(value.hitClip(contains:{ $0=="authored/authored_hit" })=="authored/authored_hit","Older catalog family could not resolve available optional hit")
  value.astrideKind="wayfarer"
  try check(value.hitClip(contains:{$0=="wayfarer/wf_hit"})=="wayfarer/wf_hit","Declared family lost its original hit prefix")
  value.astrideKind="authored"
  try check(value.hitClip(contains:{_ in false})==nil,"Absent declared family clip invented a replacement")
  value.clips["hit"]="authored:explicit_missing"
  try check(value.hitClip(contains:{$0=="authored/authored_hit"})==nil,"Unavailable explicit role silently switched to inferred family")
  value.astride=false
  try check(value.hitClip(contains:known.contains)==nil && value.fallOffClip(contains:known.contains)==nil,"Ordinary seating entered the astride role")
  print("PASS rider fall metadata: \(checks) checks; authored JSON and library-presence seam only, no animation, transforms, renderer or retail acceptance")
 }
}
