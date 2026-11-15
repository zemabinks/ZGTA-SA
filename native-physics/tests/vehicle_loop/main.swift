import AVFoundation
import Foundation
typealias Layer = NativeVehicleAudioDynamics.Layer
func wav(_ values: [Int16], rate: Int = 32_000, channels: Int = 1) -> Data {
    var bytes = Data("RIFF".utf8)
    func u32(_ value: Int) { var x = UInt32(value).littleEndian; withUnsafeBytes(of:&x) { bytes.append(contentsOf:$0) } }
    func u16(_ value: Int) { var x = UInt16(value).littleEndian; withUnsafeBytes(of:&x) { bytes.append(contentsOf:$0) } }
    u32(36+values.count*2);bytes.append(Data("WAVEfmt ".utf8));u32(16);u16(1);u16(channels)
    u32(rate);u32(rate*channels*2);u16(channels*2);u16(16);bytes.append(Data("data".utf8));u32(values.count*2)
    for value in values { var x = value.littleEndian; withUnsafeBytes(of:&x) { bytes.append(contentsOf:$0) } }
    return bytes
}
let format = AVAudioFormat(standardFormatWithSampleRate:32_000,channels:2)!
func make() throws -> (NativeVehicleLoopAudio,AVAudioEngine) {
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:4_096)
    return (NativeVehicleLoopAudio(engine:engine,sampleRate:32_000),engine)
}
func render(_ voice: NativeVehicleLoopAudio, _ count: Int) -> ([Float],[Float]) {
    var left = [Float](repeating:0,count:count), right = left
    left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in voice.render(frames:count,left:l.baseAddress!,right:r.baseAddress!) } }
    return (left,right)
}
let mono = (0..<16).map { Int16(($0+1)*1_000) }, bytes = wav(mono)
for rate in [0.02,0.3,1,4.5] {
    let (audio,_) = try make()
    precondition(audio.register(bytes,name:"tone",loopStart:4))
    precondition(audio.play(Layer(name:"engine",sound:"tone",rate:rate,gain:1),id:"engine"))
    let result = render(audio,1000)
    var position = 0.0
    for i in 0..<1000 {
        if position >= 16 { position = 4+(position-16).truncatingRemainder(dividingBy:12) }
        let at = Int(position), next = at+1 < 16 ? at+1:4
        let source = Double(mono[at])/32768+(Double(mono[next]-mono[at])/32768)*(position-Double(at))
        let gain = 1-exp(-Double(i)/(0.03*32_000))
        precondition(abs(Double(result.0[i])-source*gain) < 4e-8,"Loop/attack/pitch/smoothing mismatch at rate \(rate), frame \(i)")
        precondition(result.0[i] == result.1[i],"Mono duplication changed")
        position += rate
    }
    precondition(abs(audio.probe("engine")!.frame-position)<1e-11)
    audio.stopAll(immediate:true)
}
do {
    let (audio,_) = try make();precondition(audio.register(bytes,name:"tone",loopStart:4))
    audio.play(Layer(name:"engine",sound:"tone",rate:1,gain:1),id:"engine")
    _ = render(audio,960)
    precondition(abs(audio.probe("engine")!.gain-(1-exp(-1)))<1e-12)
    audio.play(Layer(name:"engine",sound:"tone",rate:2,gain:1),id:"engine")
    _ = render(audio,960)
    precondition(abs(audio.probe("engine")!.rate-(2-exp(-1)))<1e-12)
    audio.play(Layer(name:"engine",sound:"tone",rate:1,gain:1,restart:true,startFraction:0.5),id:"engine")
    precondition(audio.probe("engine")!.frame == 8 && audio.activeVoiceCount == 2,"Restart did not retain fading previous voice")
    _ = render(audio,5761)
    precondition(audio.activeVoiceCount == 1,"Original 180ms stop deadline did not expire")
    audio.stop("engine");_ = render(audio,5761)
    precondition(audio.activeVoiceCount == 0)
}
do {
    let (audio,_) = try make();audio.register(bytes,name:"one",loopStart:-1)
    audio.play(Layer(name:"fall",sound:"one",rate:1,gain:1),id:"one");_ = render(audio,17)
    precondition(audio.probe("one") == nil,"One-shot incorrectly loops")
    let long = wav(Array(repeating:Int16(10_000),count:3_200));audio.register(long,name:"fall",loopStart:-1)
    audio.apply(.init(layers:[Layer(name:"fall",sound:"fall",rate:1,gain:1)]))
    _ = render(audio,1)
    audio.apply(.init(layers:[],retain:["fall"]))
    precondition(audio.probe("mine:fall") != nil,"Original idle fall-retention lost")
    audio.apply(.init(layers:[]))
    precondition(audio.probe("mine:fall") == nil)
    audio.stopAll(immediate:true)
}
for angle in [-135.0,-90,-45,0,45,90,135] {
    let (audio,_) = try make()
    audio.register(wav(Array(repeating:Int16(16384),count:16)),name:"mono",loopStart:0)
    audio.play(Layer(name:"remote",sound:"mono",rate:1,gain:1),id:"remote",spatialAzimuth:angle)
    let output=render(audio,960),matrix=NativeVehicleAudioSpatial.matrix(azimuth:angle,mono:true)
    let gain=0.5*(1-exp(-959/(0.03*32_000)))
    precondition(abs(Double(output.0[959])-gain*matrix.x)<4e-8 && abs(Double(output.1[959])-gain*matrix.z)<4e-8)
}
do {
    typealias Spatial=NativeVehicleAudioSpatial
    var parameter=Spatial.VectorParameter(.zero,constant:0.05)
    let first=SIMD3<Double>(10,20,-30),second=SIMD3<Double>(-2,4,8)
    parameter.setTarget(first,at:0)
    precondition(simd_distance(parameter.value(at:0.05),first*(1-exp(-1)))<1e-13)
    let middle=first*(1-exp(-0.5))
    parameter.setTarget(second,at:0.025)
    precondition(simd_distance(parameter.value(at:0.075),second+(middle-second)*exp(-1))<1e-13)

    let (audio,_)=try make(),source=SIMD3<Double>(10,0,-20),destination=SIMD3<Double>(-10,4,-8)
    let listener=SIMD3<Double>(4,2,3),forward=SIMD3<Double>(1,0.2,-1),oldForward=SIMD3<Double>(0,0,-1)
    let panner=Spatial.panner(kind:.road)
    audio.register(wav(Array(repeating:Int16(16384),count:16)),name:"moving",loopStart:0)
    audio.listener(position:listener,forward:forward)
    let plan=NativeVehicleAudioDynamics.Plan(layers:[Layer(name:"engine",sound:"moving",rate:1,gain:1)])
    audio.apply(plan,prefix:"remote",spatialPosition:source,panner:panner)
    let a=render(audio,512)
    audio.apply(plan,prefix:"remote",spatialPosition:destination,panner:panner)
    let b=render(audio,1024)
    let left=a.0+b.0,right=a.1+b.1
    for i in 0..<1536 {
        let time=Double(i)/32_000,ease=1-exp(-time/0.03)
        let ear=listener*ease,look=forward+(oldForward-forward)*exp(-time/0.03)
        let place=i<512 ? source:destination+(source-destination)*exp(-(time-512.0/32_000)/0.05)
        let matrix=Spatial.matrix(azimuth:Spatial.azimuth(source:place,listener:ear,forward:look),mono:true)
        let gain=0.5*ease*panner.gain(distance:simd_distance(place,ear))
        precondition(abs(Double(left[i])-gain*matrix.x)<4e-8 && abs(Double(right[i])-gain*matrix.z)<4e-8,
                     "Source/listener audio-time smoothing mismatch at \(i)")
    }
    audio.stopAll(immediate:true)
}
// Actual native source-node output agrees with the same voice's direct render
// across arbitrary AudioUnit block boundaries, including stereo and loop wrap.
do {
    var values: [Int16] = []
    for i in 0..<320 { values.append(Int16((i%16+1)*1_000)); values.append(Int16(-(i%16+1)*900)) }
    let stereo = wav(values,channels:2)
    let (actual,engine) = try make(),(reference,_) = try make()
    for audio in [actual,reference] {
        audio.register(stereo,name:"stereo",loopStart:80)
        audio.play(Layer(name:"engine",sound:"stereo",rate:0.13,gain:0.7),id:"engine")
    }
    precondition(actual.start())
    let output = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4_096)!
    for count in [257,4096,17,1024] {
        let status = try engine.renderOffline(AVAudioFrameCount(count),to:output)
        precondition(status == .success)
        let expected = render(reference,count)
        for i in 0..<count {
            precondition(abs(output.floatChannelData![0][i]-expected.0[i])<1e-7 && abs(output.floatChannelData![1][i]-expected.1[i])<1e-7,"Native AudioUnit block changed PCM")
        }
    }
    actual.stopAll(immediate:true);reference.stopAll(immediate:true)
}
print("PASS: native source-node PCM, attacks/tail loops,0.02..4.5pitch,30ms gain/rate smoothing, fractional restart, fall retain, natural one-shots and original180ms stop lifecycle")
