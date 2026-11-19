// Actual mixers render only into memory; no output device is started.
func wave(frames:Int)->Data {
 var b=Data()
 func str(_ s:String){b.append(contentsOf:s.utf8)}
 func u16(_ n:Int){var v=UInt16(n).littleEndian;withUnsafeBytes(of:&v){b.append(contentsOf:$0)}}
 func u32(_ n:Int){var v=UInt32(n).littleEndian;withUnsafeBytes(of:&v){b.append(contentsOf:$0)}}
 str("RIFF");u32(36+frames*2);str("WAVEfmt ");u32(16);u16(1);u16(1);u32(48000);u32(96000);u16(2);u16(16);str("data");u32(frames*2)
 for _ in 0..<frames {u16(16384)}
 return b
}
var checks=0
func check(_ condition:Bool,_ label:String){precondition(condition,label);checks+=1}
let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
func mixer()->NativeVehicleLoopAudio {
 let engine=AVAudioEngine();try! engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:4096)
 return NativeVehicleLoopAudio(engine:engine)
}
let reference=mixer(),controlled=mixer(),pcm=wave(frames:131)
for mix in [reference,controlled] {
 check(mix.register(pcm,name:"synthetic",loopStart:7),"Register actual PCM")
 check(mix.play(.init(name:"held",sound:"synthetic",rate:1.03,gain:0.7),id:"held",forceLoop:true),"Schedule real held voice")
}
var referenceLeft=Array(repeating:Float(0),count:256),referenceRight=referenceLeft,left=referenceLeft,right=referenceLeft
for block in 0..<100 {
 let gain:Float=block<20 ? 1:block<40 ? 0:block<70 ? 0.25:1
 controlled.outputGain=gain
 referenceLeft.withUnsafeMutableBufferPointer{a in referenceRight.withUnsafeMutableBufferPointer{b in reference.render(frames:256,left:a.baseAddress!,right:b.baseAddress!)}}
 left.withUnsafeMutableBufferPointer{a in right.withUnsafeMutableBufferPointer{b in controlled.render(frames:256,left:a.baseAddress!,right:b.baseAddress!)}}
 for i in 0..<256 {check(left[i]==referenceLeft[i]*gain&&right[i]==referenceRight[i]*gain,"PCM mute/gain/restore differs")}
 let a=reference.probe("held")!,b=controlled.probe("held")!
 check(a.frame==b.frame&&a.rate==b.rate&&a.gain==b.gain,"Preferences changed loop phase or source smoothing")
 if block==30 {for mix in [reference,controlled] {check(mix.play(.init(name:"future",sound:"synthetic",rate:0.8,gain:0.2),id:"future",forceLoop:true),"Schedule voice while muted")}}
}
check(controlled.activeVoiceCount==2,"Mute did not discard held/future voices")
let engine=AVAudioEngine();try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:4096)
let rate=NativeRateAudio(engine:engine)
check(rate.play(wave(frames:96000),name:"constant",rate:0.4,gain:1,pan:0),"Actual low-rate voice")
let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096)!
func render()->[Float] {
 for _ in 0..<100 {
  if try! engine.renderOffline(4096,to:output) == .success {return Array(UnsafeBufferPointer(start:output.floatChannelData![0],count:Int(output.frameLength)))}
 }
 fatalError("Offline rate engine stalled")
}
_ = render()
let baseline=render(),start=engine.manualRenderingSampleTime
check(baseline.map{abs($0)}.max()!>0.49,"Offline rate voice produced no PCM")
rate.outputGain=0;_ = render();check(render().allSatisfy{abs($0)<0.000001},"Active low-rate voice did not mute")
rate.outputGain=0.25;_ = render();let quiet=render()
check(quiet.allSatisfy{abs($0-0.125)<0.002},"Active low-rate voice did not use one quarter gain")
rate.outputGain=1;_ = render();let restored=render()
check(restored.allSatisfy{abs($0-0.5)<0.002},"Low-rate voice did not restore without restarting")
check(engine.manualRenderingSampleTime>start,"Mute/restore reset engine clock")
rate.stop()
print("PASS actual offline audio gain: \(checks) PCM/phase checks, active/future held voices and low-rate node mute/restore")
