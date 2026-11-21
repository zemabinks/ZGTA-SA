#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Typed compact audio sources and the literal production voice consumer.

Authored records/tables, deterministic clock and inert voice/preload sink.
No game audio, browser, audio device or playback backend is exercised.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def declaration(s,needle):
    begin=s.index(needle);at=s.index('{',begin);depth=1;end=at+1;quote=False;escape=False;line=False;comment=0
    while depth:
        c=s[end];pair=s[end:end+2]
        if line:
            if c=='\n':line=False
        elif comment:
            if pair=='/*':comment+=1;end+=1
            elif pair=='*/':comment-=1;end+=1
        elif quote:
            if escape:escape=False
            elif c=='\\':escape=True
            elif c=='"':quote=False
        elif pair=='//':line=True;end+=1
        elif pair=='/*':comment=1;end+=1
        elif c=='"':quote=True
        elif c=='{':depth+=1
        elif c=='}':depth-=1
        end+=1
    return s[begin:end]
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prepare-only',action='store_true');p.add_argument('--previous-controller',type=Path);a=p.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-audio-167'/str(time.time_ns());out.mkdir(parents=True)
    names=['ios/App/NativeVehicleAudioSpatial.swift','ios/App/NativeVehicleAudioDynamics.swift','ios/App/NativeGameAudio.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift','tests/audio/smoke_native_traffic_audio.swift','tests/audio/smoke_native_traffic_audio.py']
    frozen={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in names}
    game=(ROOT/names[2]).read_text();renderer=(ROOT/names[3]).read_text();controller=(ROOT/names[4]).read_text()
    previous=a.previous_controller.resolve()if a.previous_controller else None
    if previous:frozen[str(previous)]=hashlib.sha256(previous.read_bytes()).hexdigest()
    def call(source):
        start=source.index('            audio.updateRemoteVehicles(');end=start;depth=0;began=False
        while end<len(source):
            c=source[end]
            if c=='(':depth+=1;began=True
            elif c==')':
                depth-=1
                if began and depth==0:return source[start:end+1]
            end+=1
        raise ValueError('Unterminated actual audio handoff')
    statement=call(controller)
    method=declaration(game,'    func updateRemoteVehicles(')
    engine=declaration(game,'    private final class RemoteEngine {').replace('private final class','final class',1)
    production=declaration(renderer,'    var trafficVehicleAudioSources:')
    assert 'traffic:renderer.trafficVehicleAudioSources' in controller
    assert 'presentedAmbientTraffic.map' in production and 'listener:audioEar' in production
    assert 'RemotePlayer('not in production and 'RemotePlayer('not in method
    stub=r'''import Foundation
import simd
final class AudioClock {static let processInfo=AudioClock();var systemUptime=10.0}
enum SwiftRapierWorld {static func gtaToRapier(_ p:SIMD3<Float>)->SIMD3<Float>{SIMD3(p.x,p.z,-p.y)}}
struct RemotePlayer {
 var id:String,code:String
 var position=SIMD3<Float>.zero
 var heading:Float=0,pitch:Float=0,roll:Float=0,speed:Float=0
 var vehicleHealth=1000,horn=0
}
final class VoiceSink {
 var listenerCalls=0,cleared:[String]=[]
 func listener(position:SIMD3<Double>,forward:SIMD3<Double>){listenerCalls+=1}
 func apply(_ plan:NativeVehicleAudioDynamics.Plan,prefix:String){if plan.layers.isEmpty{cleared.append(prefix)}}
}
final class Audio {
 typealias ProcessInfo=AudioClock
 var suspended=false
 var road:[String:[NSNumber]]=["400":[10,20,1,0,3,1]]
 var aircraft:[String:[Any]]=[:],boats:[String:NSNumber]=[:],special:[String:[Any]]=[:],trains:[String:[NSNumber]]=[:]
 var sirens=["wail":"authored-wail","yelp":"authored-yelp"]
 let vehicleLoops=VoiceSink()
 var remoteEngines:[String:RemoteEngine]=[:],preloads:[Int]=[]
 var plans:[String:NativeVehicleAudioDynamics.Plan]=[:],positions:[String:SIMD3<Double>]=[:]
 func preloadVehicle(_ model:Int){preloads.append(model)}
 func applyVehiclePlan(_ plan:NativeVehicleAudioDynamics.Plan,prefix:String="mine",position:SIMD3<Double>?=nil,panner:NativeVehicleAudioSpatial.Panner?=nil){plans[prefix]=plan;positions[prefix]=position}
'''
    adapter='''
final class Renderer {
 var presentedAmbientTraffic:[NativeAmbientTrafficScene.Frame]=[]
 var audioEar=SIMD3<Float>.zero,audioForward=SIMD3<Float>(0,1,0)
 func remoteVehicleAudioTop(_ model:String)->Double?{45}
'''+production+'\n}\nfinal class Network {var orderedPlayers:[RemotePlayer]=[]}\n'
    carrier=out/'Audio.swift';carrier.write_text(stub+'\n'+engine+'\n'+method+'\n}\n'+adapter)
    def handoff(statement,name):
        f=out/name;f.write_text('func productionHandoff(_ audio:Audio,network:Network,renderer:Renderer){\n'+statement+'\n}\n');return f
    handoffFile=handoff(statement,'Handoff.swift')
    helperNames=['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientTrafficProtocol','NativeAmbientTrafficRoads','NativeAmbientTraffic','NativeAmbientTrafficMotion','NativeAmbientTrafficPresentation','NativeAmbientTrafficScene']
    for name in helperNames:
        n='ios/App/'+name+'.swift';frozen[n]=hashlib.sha256((ROOT/n).read_bytes()).hexdigest()
    sources=[]
    for n in [*names[:2],*['ios/App/'+n+'.swift'for n in helperNames]]:
        f=out/Path(n).name;f.write_bytes((ROOT/n).read_bytes());sources.append(f)
    test=out/'Gate.swift';test.write_bytes((ROOT/names[5]).read_bytes());sources += [carrier,test]
    report=dict(status='PREPARED',sourceHashes=frozen,literalConsumerSHA256=hashlib.sha256(method.encode()).hexdigest(),rendererAdapterSHA256=hashlib.sha256(production.encode()).hexdigest(),controllerStatementSHA256=hashlib.sha256(statement.encode()).hexdigest(),compilerInvoked=False,scope=__doc__,limits=['Authored sound tables, records and clock; inert voice/preload sink and GTA-axis boundary carrier','Actual spatial selection, sound dynamics and unchanged complete production consumer body','Literal renderer source property and GVC handoff execute with real typed frames; full tick, resource readiness, audio backend, GPU, network and audibility not executed','Existing130m native traffic scene admission still limits far candidates below the source150m allowance'])
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        if not a.prepare_only:
            report['compilerInvoked']=True
            variants=([('old-controller-statement',call(previous.read_text()))]if previous else[])+[('candidate',statement)]
            report['results']=[]
            for label,body in variants:
                selected=handoff(body,label+'-Handoff.swift');exe=out/(label+'-gate')
                command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,[*sources,selected]),'-o',str(exe)]
                with(out/(label+'-compile.log')).open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
                assert r.returncode==0,(out/(label+'-compile.log')).read_text()[-6000:]
                r=subprocess.run([str(exe)],capture_output=True,text=True,timeout=60)
                (out/(label+'-runtime.log')).write_text(r.stdout+r.stderr);row=dict(label=label,compileExit=0,exitCode=r.returncode,output=r.stdout+r.stderr);report['results'].append(row)
                if label=='old-controller-statement':
                    assert r.returncode!=0 and 'Actual GVC call omitted compact traffic sources'in row['output'],row
                    report['historicalScope']='Old GVC statement only, composed with current renderer adapter and audio consumer; not the complete old application'
                else:assert r.returncode==0,row
            report['status']='PASS'
    except BaseException as e:report.update(status='FAIL',error=repr(e));raise
    finally:
        report['sourceUnchanged']=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in frozen.items());save();print(json.dumps({k:v for k,v in report.items()if k not in ['sourceHashes']}))
    assert report['sourceUnchanged']
if __name__=='__main__':main()
