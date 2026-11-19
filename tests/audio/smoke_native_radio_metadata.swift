// SPDX-License-Identifier: AGPL-3.0-only
// Actual control/metadata methods; explicit resource and audio-sink boundaries.
import Foundation

final class NativeResourceTask {
    let completion:(Data?,URLResponse?,Error?)->Void
    var resumed=false,cancelled=false
    init(_ completion:@escaping(Data?,URLResponse?,Error?)->Void){self.completion=completion}
    func resume(){resumed=true}
    func cancel(){cancelled=true}
    func deliver(_ bytes:Data,status:Int=200){
        completion(bytes,HTTPURLResponse(url:URL(string:"https://assets.invalid/")!,statusCode:status,httpVersion:nil,headerFields:nil),nil)
    }
}
enum NativeResourceTransport {
    static var tasks:[String:NativeResourceTask]=[:]
    static func dataTask(with url:URL,completion:@escaping(Data?,URLResponse?,Error?)->Void)->NativeResourceTask {
        let task=NativeResourceTask(completion);tasks[url.path]=task;return task
    }
}
struct ServerAddress {
    let url=URL(string:"https://assets.invalid/")!
    func path(_ value:String)->URL{url.appendingPathComponent(value)}
}
final class QueuedWork {
    let body:()->Void
    var cancelled=false
    init(block:@escaping()->Void){body=block}
    func cancel(){cancelled=true}
    func alreadyDequeued(){body()}
}
enum DialScheduler {
    static var pending:[QueuedWork]=[]
    static func enqueue(deadline:DispatchTime,execute:QueuedWork){pending.append(execute)}
}
final class Radio {
    // ACTUAL_STATION
    // ACTUAL_TRACK
    // ACTUAL_SONG
    // ACTUAL_INDEX
    let server=ServerAddress()
    let stations=(0..<12).map{Station(name:"AUTHORED \($0)",file:"TEST\($0)")}
    var program:NativeRadioProgram?,tracks:[Int:URL]=[:],songs:[Song]=[],songOrder:[Int]=[]
    var vehicleModel:Int?,following=false,followedStation:Int?,vehicleStation:Int?,vehicleType=0,specialStation:Int?
    var index=0,wantsPlayback=false,interrupted=false,remembered:(station:Int,at:Double)?
    var dial:QueuedWork?,dialOwner:UUID?,programRequest:NativeResourceTask?,indexRequest:NativeResourceTask?
    var generation=0,tuned:[Int]=[],released=0
    var onStatus:((String)->Void)?
    var preferenceKey:String{"ZGTA.fixture.radio.metadata"}
    // ACTUAL_STATION_ID
    // ACTUAL_STATION_NAME
    // ACTUAL_CYCLE
    // ACTUAL_STOP
    // ACTUAL_RESUME
    // ACTUAL_ENTER
    // ACTUAL_REFRESH
    // ACTUAL_CONFIGURE
    // ACTUAL_CANCEL_DIAL
    // ACTUAL_LOAD_PROGRAM
    // ACTUAL_AUDIO_URL
    func releasePlayback(){generation+=1;released+=1}
    // This test observes control intent/tune calls, never starts an audio engine.
    func tune(){cancelDial();releasePlayback();if wantsPlayback && !interrupted && stationID != 13{tuned.append(stationID)}}
}

var checks=0,cases=0
func check(_ ok:Bool,_ message:String){
    guard ok else {fputs("FAIL: "+message+"\n",stderr);exit(23)};checks+=1
}
func flush(){RunLoop.current.run(until:Date().addingTimeInterval(0.025))}
func document()->Data {
    let station:[String:Any]=["songs":[[0,[1,1],[2,2]]],"idents":[1,1],"talk":[:],"noAdverts":[]]
    let value:[String:Any]=["rate":8000,"samples":[8000,1000,1000,1000],"stations":Array(repeating:station,count:12),
        "adverts":[3,3],"vehicleDefaults":["9001":[1,0],"9002":[2,0],"9003":[13,2],"9004":[7,1],"9005":[1,3]],
        "stationNames":Array(repeating:["name":"Authored","pack":"TEST"],count:13),"rain":[],"sun":[],"fog":[],
        "stationRegions":[:],"talkShowGroups":[[0]],"weather":["la":[1],"sf":[1],"desert":[1]]]
    return try! JSONSerialization.data(withJSONObject:value)
}
let bytes=document(),program=try NativeRadioProgram(data:bytes)
let indexBytes=try JSONSerialization.data(withJSONObject:["stations":[[["id":0,"url":"/game/radio/native/track/0.wav"]]],"adverts":[],"songs":[]])
func radio(known:Bool=false)->Radio {
    let value=Radio();if known{value.program=program};value.loadProgram();return value
}
func complete(_ task:NativeResourceTask?,_ bytes:Data){check(task?.resumed==true,"normal metadata task resumed");task!.deliver(bytes);flush()}

// The old load-index callback re-entered9001, replacing user station2 with1.
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001);check(r.stationID==1,"authored model default")
    r.cycle(1);check(r.stationID==2,"ordinary cycle selects station2")
    let before=r.tuned.count
    complete(r.indexRequest,indexBytes)
    check(r.stationID==2,"late index replaces explicit station intent")
    check(r.tuned.count==before,"metadata must preserve pending tuning delay")
    r.stop()
}
for programFirst in [false,true] {
    cases+=1;let r=radio();r.enter(model:9001);r.cycle(1)
    if programFirst{complete(r.programRequest,bytes);complete(r.indexRequest,indexBytes)}
    else{complete(r.indexRequest,indexBytes);complete(r.programRequest,bytes)}
    check(r.stationID==2,"cold metadata order preserves explicit selection");check(r.dialOwner != nil,"metadata retains pending dial owner")
    r.stop()
}
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001);r.cycle(-1);check(r.stationID==13,"ordinary cycle reaches off")
    complete(r.indexRequest,indexBytes);check(r.stationID==13 && !r.wantsPlayback,"late index keeps deliberate radio off");r.stop()
}
for followed in [5,13] {
    cases+=1;let r=radio();r.enter(model:9001,followedStation:followed)
    complete(r.programRequest,bytes);complete(r.indexRequest,indexBytes)
    check(r.stationID==followed && r.following,"late metadata preserves following entry intent");r.stop()
}
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001,followedStation:5);r.cycle(1)
    complete(r.indexRequest,indexBytes);check(r.stationID==6 && r.following,"manual passenger choice remains current");r.stop()
}
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001);r.cycle(1);r.stop();let n=r.tuned.count
    complete(r.programRequest,bytes);complete(r.indexRequest,indexBytes)
    check(r.vehicleModel==nil && !r.wantsPlayback && r.tuned.count==n,"late source metadata cannot resume exited vehicle")
}
do {
    cases+=1;let r=radio();r.enter(model:9001);r.cycle(1);r.cycle(1);r.enter(model:9002)
    complete(r.programRequest,bytes);complete(r.indexRequest,indexBytes)
    check(r.stationID==2 && r.vehicleModel==9002,"metadata belongs to current entry, not previous selection")
    r.stop()
}
for model in [9003,9004,9005] {
    cases+=1;let r=radio();r.enter(model:model);r.cycle(1);complete(r.programRequest,bytes)
    let expected=model==9005 ? 0:model==9004 ? 13:2
    check(r.stationID==expected,"late classification retains ordinary/off-only/emergency rules");r.stop()
}
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001);r.cycle(1);let n=r.tuned.count
    r.indexRequest!.deliver(Data("invalid".utf8));flush()
    check(r.stationID==2 && r.tuned.count==n,"malformed metadata cannot overwrite current selection");r.stop()
}
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001);r.cycle(1);let owner=r.dialOwner
    let old=r.dial!;check(owner != nil,"dial is owned before stop");r.stop();check(r.dialOwner==nil,"exit retires queued dial")
    r.enter(model:9002);check(r.dialOwner==nil && r.stationID==2,"fresh entry uses existing current-model/remembered policy")
    let n=r.tuned.count;old.alreadyDequeued();check(r.tuned.count==n,"old queued dial cannot retune replacement vehicle")
    r.stop()
}
do {
    cases+=1;let r=radio(known:true);r.enter(model:9001);r.cycle(1);let old=r.dial!;r.cycle(1);let latest=r.dial!
    let n=r.tuned.count;old.alreadyDequeued();check(r.tuned.count==n && r.dial === latest,"superseded queued dial cannot consume latest intent")
    latest.alreadyDequeued();check(r.tuned.last==3 && r.dialOwner==nil,"current dial tunes current station exactly once")
    let m=r.tuned.count;latest.alreadyDequeued();check(r.tuned.count==m,"completed dial cannot replay")
    r.stop()
}
print("Radio metadata PASS \(checks) checks / \(cases) cases; no audio engine or network")
