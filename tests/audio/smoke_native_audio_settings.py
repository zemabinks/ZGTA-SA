#!/usr/bin/env python3
"""Actual live gain wiring and offline PCM mixing; no hardware output or mic.

The data fixtures are synthesized here. Optional owner menu recording checks
live in tests/audio/smoke_native_menu_sound.py and do not publish the supplied recordings.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile,json,hashlib
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/audio-settings'
def declaration(source,token):
 start=source.index(token);brace=source.index('{',start);depth=1;end=brace+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('private ','')+'\n'

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 game=(ROOT/'ios/App/NativeGameAudio.swift').read_text();radio=(ROOT/'ios/App/NativeVehicleRadio.swift').read_text();menu=(ROOT/'ios/App/NativeMenuAudio.swift').read_text()
 prefix='\n'.join((ROOT/'ios/App'/name).read_text() for name in ['NativeAppSettings.swift','NativeAudioEnvelope.swift'])
 source=prefix+r'''
final class Player {var volume:Float=1}
final class Graph {var outputGain:Float=1}
final class Game {
 var settingsGain:Float=1,volume:Float=0.7
 let rateAudio=Graph(),vehicleLoops=Graph()
 var oneShots:[ObjectIdentifier:Player]=[:],oneShotLevels:[ObjectIdentifier:NativeAudioEnvelope]=[:]
'''+declaration(game,'    func applySettings(')+declaration(game,'    private func refreshOneShotVolumes(')+r'''
}
final class Radio {
 var player:Player?=Player(),pcm:Player?=Player()
'''+declaration(radio,'    var volume: Float =')+declaration(radio,'    func applySettings(')+r'''
}
final class Menu {
 var gain:Float=0.7,players:[ObjectIdentifier:Player]=[:]
'''+declaration(menu,'    func applySettings(')+r'''
}
var checks=0
func check(_ ok:Bool,_ message:String){precondition(ok,message);checks+=1}
func near(_ a:Float,_ b:Float)->Bool {abs(a-b)<0.000001}
let game=Game(),radio=Radio(),menu=Menu(),voice=Player(),other=Player()
game.oneShots[ObjectIdentifier(voice)]=voice;game.oneShotLevels[ObjectIdentifier(voice)] = .init(gain:0.75,started:0,rise:0)
game.oneShots[ObjectIdentifier(other)]=other;game.oneShotLevels[ObjectIdentifier(other)] = .init(gain:2,started:0,rise:0)
menu.players[ObjectIdentifier(voice)]=Player()
for master in [0.0,0.25,0.5,1.0] {for effects in [0.0,0.25,1.0] {for station in [0.0,0.5,1.0] {
 var s=NativeAppSettings.Snapshot();s.masterVolume=master;s.effectsVolume=effects;s.radioVolume=station
 game.applySettings(s);radio.applySettings(s);menu.applySettings(s)
 let factor=Float(master*effects)
 check(near(game.rateAudio.outputGain,factor)&&near(game.vehicleLoops.outputGain,factor),"One gain per actual shared graph")
 check(near(voice.volume,0.525*factor)&&near(other.volume,factor),"Active one-shot levels rescale without losing original clipping")
 check(near(radio.player!.volume,s.effectiveRadioGain)&&near(radio.pcm!.volume,s.effectiveRadioGain),"Live AVPlayer and PCM radio gain")
 check(near(menu.players.values.first!.volume,s.effectiveEffectsGain),"Active menu voice gain")
}}}
for _ in 0..<20 {game.applySettings(.init())}
check(near(voice.volume,0.525)&&near(other.volume,1)&&game.oneShots.count==2,"Defaults restore without double scaling/replacing voices")
let rising=NativeAudioEnvelope(gain:0.5,started:10,rise:2)
check(near(rising.level(at:10,baseVolume:0.7,multiplier:1),0),"Rise begins silent")
check(near(rising.level(at:11,baseVolume:0.7,multiplier:1),0.175),"Rise midpoint")
check(near(rising.level(at:11,baseVolume:0.7,multiplier:0),0),"Mute active rise")
check(near(rising.level(at:11.5,baseVolume:0.7,multiplier:1),0.2625),"Restore advances same rise clock")
let fading=NativeAudioEnvelope(gain:1,started:0,rise:0,fade:.init(begins:10,ends:12,from:1,to:0.25))
check(near(fading.level(at:11,baseVolume:0.7,multiplier:1),0.35),"Original exponential fade midpoint")
check(near(fading.level(at:11,baseVolume:0.7,multiplier:0.5),0.175),"Preferences attenuate active fade once")
check(near(fading.level(at:15,baseVolume:0.7,multiplier:1),0.175) && !fading.animating(at:15),"Ended fade retains restore level without timer")
print("PASS actual audio settings dispatch/envelopes: \(checks) checks")
'''
 with tempfile.TemporaryDirectory(prefix='settings-',dir=OUT) as t:
  work=Path(t);(work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify')],check=True)
 # Real source mixer and rate node, with only synthetic PCM and offline engines.
 source='\n'.join((ROOT/'ios/App'/name).read_text() for name in ['NativeRateAudio.swift','NativeVehicleAudioDynamics.swift','NativeVehicleAudioSpatial.swift','NativeAudioPanSweep.swift','NativeVehicleLoopAudio.swift'])
 source+=(ROOT/'tests/audio/smoke_native_audio_settings.swift').read_text()
 with tempfile.TemporaryDirectory(prefix='pcm-',dir=OUT) as t:
  work=Path(t);(work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify')],check=True)
 files=['NativeAudioEnvelope.swift','NativeGameAudio.swift','NativeRateAudio.swift','NativeAudioPanSweep.swift','NativeVehicleLoopAudio.swift','NativeVehicleRadio.swift','NativeMenuAudio.swift','NativeMenuSoundData.swift']
 (OUT/'settings-report.json').write_text(json.dumps({'pass':True,'scope':'Actual extracted setting dispatch and real native offline PCM; no hardware output or microphone','sourceSHA256':{f:hashlib.sha256((ROOT/'ios/App'/f).read_bytes()).hexdigest() for f in files}},indent=2)+'\n')
if __name__=='__main__':main()
