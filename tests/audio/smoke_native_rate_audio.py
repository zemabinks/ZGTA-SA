#!/usr/bin/env python3
"""Verify original PCM decoding and actual offline low-rate audio rendering."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import json,math,struct,subprocess,tempfile,wave
ROOT=Path(__file__).resolve().parents[2]
SWIFT=r'''
let checks=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
for row in checks{
 let bytes=try Data(contentsOf:URL(fileURLWithPath:row["path"] as! String)),decoded=NativeRateAudio.pcm(bytes)!
 precondition(Int(decoded.frameLength)==row["frames"] as! Int)
 precondition(Int(decoded.format.channelCount)==row["channels"] as! Int)
 for item in row["samples"] as! [[Int]]{
  let actual=decoded.floatChannelData![item[0]][item[1]],expected=Float(item[2])/32768
  precondition(actual==expected,"PCM decoding changed archived sample")
 }
}
let source=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
for rate:Float in [0.302906,0.35636,0.4,0.46]{
 let engine=AVAudioEngine(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
 try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:4096)
 let player=NativeRateAudio(engine:engine)
 precondition(player.play(source,name:"sine",rate:rate,gain:1,pan:0),"low-rate voice failed")
 let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096)!
 var values:[Float]=[],retries=0
 while values.count<180000{
  let status=try engine.renderOffline(4096,to:output)
  if status == .success{values += Array(UnsafeBufferPointer(start:output.floatChannelData![0],count:Int(output.frameLength)))}
  else{retries += 1;precondition(retries<100,"offline rendering stalled")}
 }
 let last=values.lastIndex(where:{abs($0)>0.01})!
 let end=Double(last)/48000,expectedDuration=1/Double(rate)
 precondition(abs(end-expectedDuration)<0.08,"low-rate duration \(end) != \(expectedDuration)")
 let middle=Array(values[24000..<72000]);var crossings=0
 for i in 1..<middle.count where middle[i-1]<=0 && middle[i]>0{crossings += 1}
 precondition(abs(Double(crossings)-1000*Double(rate))<2,"pitch was clamped")
 print("Rendered rate \(rate): \(crossings)Hz, \(end)s")
 player.stop()
}
print("PASS: archived mono/stereo PCM samples and four actual native rates below0.5 preserve pitch and duration")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-rate-audio-') as temporary:
  work=Path(temporary);checks=[]
  for name in ['52_4','52_1','t167']:
   path=ROOT/f'local-only/site/game/sound/b{name}.wav'
   with wave.open(str(path)) as audio:
    frames,channels=audio.getnframes(),audio.getnchannels();raw=audio.readframes(frames)
   values=struct.unpack('<'+'h'*(len(raw)//2),raw);indices=sorted(set([0,1,frames//2,frames-1]+[i*frames//50 for i in range(50)]))
   samples=[[channel,index,values[index*channels+channel]] for channel in range(channels) for index in indices]
   checks.append({'path':str(path),'frames':frames,'channels':channels,'samples':samples})
  fixture=work/'samples.json';fixture.write_text(json.dumps(checks))
  sine=work/'sine.wav'
  with wave.open(str(sine),'wb') as audio:
   audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(27000)
   audio.writeframes(b''.join(struct.pack('<h',round(16384*math.sin(2*math.pi*1000*i/27000))) for i in range(27000)))
  swift=work/'verify.swift';swift.write_text((ROOT/'ios/App/NativeRateAudio.swift').read_text()+SWIFT)
  subprocess.run(['swift','-module-cache-path',str(work/'modules'),str(swift),str(fixture),str(sine)],check=True)
if __name__=='__main__':main()
