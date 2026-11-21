// SPDX-License-Identifier: AGPL-3.0-only
import AVFoundation
import Foundation
import simd

@main enum ShotAttackTests {
    static var checks=0
    static func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
    static func wave(frames:Int)->Data {
        var data=Data()
        func text(_ value:String){data.append(contentsOf:value.utf8)}
        func u16(_ value:Int){var v=UInt16(value).littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
        func u32(_ value:Int){var v=UInt32(value).littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
        text("RIFF");u32(36+frames*2);text("WAVEfmt ");u32(16);u16(1);u16(1);u32(48000);u32(96000);u16(2);u16(16);text("data");u32(frames*2)
        for _ in 0..<frames{u16(16384)}
        return data
    }
    static func mixer()->NativeVehicleLoopAudio {
        let engine=AVAudioEngine(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        try! engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:4096)
        return NativeVehicleLoopAudio(engine:engine)
    }
    static func render(_ mixer:NativeVehicleLoopAudio,_ frames:Int)->([Float],[Float]) {
        var left=[Float](repeating:0,count:frames),right=left
        left.withUnsafeMutableBufferPointer{a in right.withUnsafeMutableBufferPointer{b in
            mixer.render(frames:frames,left:a.baseAddress!,right:b.baseAddress!)
        }}
        return(left,right)
    }
    static func main() {
        let immediate=mixer(),ordinary=mixer(),pcm=wave(frames:2048)
        for owner in [immediate,ordinary]{check(owner.register(pcm,name:"authored",loopStart:-1),"Actual PCM registration")}
        let layer=NativeVehicleAudioDynamics.Layer(name:"attack",sound:"authored",rate:1,gain:0.7)
        check(immediate.play(layer,id:"shot",immediateGain:true),"Immediate shot voice")
        check(ordinary.play(layer,id:"loop"),"Existing default voice")
        let shot=render(immediate,256),loop=render(ordinary,256)
        check(shot.0.allSatisfy{abs($0-0.35)<1e-7} && shot.1==shot.0,"Gun attack acquired a loop fade-in or changed PCM")
        check(loop.0[0]==0 && loop.0[255]>0 && loop.0[255]<0.35,"Existing loop attack smoothing changed")
        immediate.stopAll(immediate:true);ordinary.stopAll(immediate:true)
        for distance in [14.0,28,400] {
            let owner=mixer();check(owner.register(pcm,name:"authored",loopStart:-1),"Positioned PCM registration")
            owner.apply(.init(layers:[layer]),prefix:"shot",spatialPosition:SIMD3(0,0,-distance),
                panner:.init(reference:14,maximum:260,rolloff:1.6),immediateGain:true)
            let output=render(owner,64),attenuation=14/(14+1.6*(max(14,distance)-14))
            let expected=Float(0.35*sqrt(0.5)*attenuation)
            check(output.0.allSatisfy{abs($0-expected)<1e-7} && output.1==output.0,"Positioned shot gain/panner/first sample differs")
            owner.outputGain=0.25
            let quiet=render(owner,64)
            check(quiet.0.allSatisfy{abs($0-expected*0.25)<1e-7},"Effects setting applied twice or changed shot phase")
            owner.stopAll(immediate:true)
        }
        let short=mixer();check(short.register(wave(frames:8),name:"short",loopStart:-1),"Short one-shot PCM")
        check(short.play(.init(name:"attack",sound:"short",rate:1,gain:1),id:"short",immediateGain:true),"Short voice")
        let output=render(short,16)
        check(output.0.prefix(8).allSatisfy{$0==0.5} && output.0.suffix(8).allSatisfy{$0==0},"Shot attack was delayed or sample repeated")
        check(short.activeVoiceCount==0,"Finished shot retained an active mixer voice")
        short.stopAll(immediate:true)
        let swept=mixer();check(swept.register(wave(frames:24000),name:"swept",loopStart:-1),"Sweep PCM")
        let curve=NativeAudioPanSweep(values:[-1,1,-1],seconds:0.4)
        check(swept.play(.init(name:"whizz",sound:"swept",rate:1,gain:1),id:"whizz",immediateGain:true,panSweep:curve),"Atomic one-shot sweep scheduling")
        let pan=render(swept,20000)
        for index in 0..<20000 {
            let value=index<=9600 ? -1+Double(index)/4800:1-Double(min(19200,index)-9600)/4800
            let angle=(value+1)*Double.pi/4
            check(abs(pan.0[index]-Float(0.5*cos(angle)))<1e-6 && abs(pan.1[index]-Float(0.5*sin(angle)))<1e-6,"Mono sweep did not interpolate at audio sample time")
        }
        swept.stopAll(immediate:true)
        print("PASS actual offline shot attack: \(checks) gates; authored PCM, default loop smoothing and positioned immediate attacks. No output device, original sound, audible or retail acceptance")
    }
}
