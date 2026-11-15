import AVFoundation
import Foundation
import simd

/// One native source node renders vehicle voices at their actual source rate.
/// It avoids AVAudioPlayer's pitch clamp and keeps an attack distinct from its
/// repeating tail. No WebKit, audio files or audio session changes are involved.
final class NativeVehicleLoopAudio {
    private struct Sample {
        let left: [Float]
        let right: [Float]
        let rate: Double
        let loop: Int
        let mono: Bool
        var count: Int { left.count }
    }
    private final class Voice {
        let sample: Sample
        let sound: String
        var position: Double
        var rate: Double
        var targetRate: Double
        var gain = 0.0
        var targetGain: Double
        var pan: Double
        var azimuth: Double?
        var spatialGroup: String?
        var tau = 0.03
        var stopFrames: Int?
        let loop: Bool
        var finished = false
        init(sample: Sample, layer: NativeVehicleAudioDynamics.Layer, pan: Double, forceLoop: Bool, azimuth: Double?) {
            self.sample = sample; sound = layer.sound
            position = max(0,min(0.99,layer.startFraction))*Double(sample.count)
            rate = layer.rate; targetRate = layer.rate; targetGain = layer.gain
            self.pan = max(-1,min(1,pan)); loop = sample.loop >= 0 || forceLoop
            self.azimuth = azimuth
        }
    }
    private struct SpatialFrame {
        var mono = SIMD4<Double>.zero
        var stereo = SIMD4<Double>.zero
    }
    private final class SpatialState {
        var position: NativeVehicleAudioSpatial.VectorParameter
        var panner: NativeVehicleAudioSpatial.Panner
        var frames = Array(repeating:SpatialFrame(),count:4_096)
        init(position:SIMD3<Double>,panner:NativeVehicleAudioSpatial.Panner,time:Double) {
            self.position = .init(position,constant:0.05,time:time); self.panner = panner
        }
    }
    private let engine: AVAudioEngine
    private let format: AVAudioFormat
    private var source: AVAudioSourceNode?
    private let lock = NSLock()
    private var samples: [String: Sample] = [:]
    private var voices: [UUID: Voice] = [:]
    private var current: [String: UUID] = [:]
    private var spatialStates: [String:SpatialState] = [:]
    private var listenerPosition = NativeVehicleAudioSpatial.VectorParameter(.zero,constant:0.03)
    private var listenerForward = NativeVehicleAudioSpatial.VectorParameter(SIMD3(0,0,-1),constant:0.03)
    private var renderedFrames: UInt64 = 0
    private var keepsListening = false
    private var cleanup: Timer?
    private let outputRate: Double
    private var settingsGain:Float=1
    var outputGain:Float {
        get {lock.lock();defer{lock.unlock()};return settingsGain}
        set {lock.lock();settingsGain=newValue.isFinite ? min(1,max(0,newValue)):1;lock.unlock()}
    }
    var isRunning: Bool { engine.isRunning }

    init(engine: AVAudioEngine = AVAudioEngine(), sampleRate: Double = 48_000) {
        self.engine = engine; outputRate = sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, count, buffers in
            let output = UnsafeMutableAudioBufferListPointer(buffers)
            guard output.count >= 2, let left = output[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = output[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            if let self { self.render(frames: Int(count), left: left, right: right) }
            else { left.initialize(repeating:0,count:Int(count)); right.initialize(repeating:0,count:Int(count)) }
            return noErr
        }
        source = node; engine.attach(node); engine.connect(node,to:engine.mainMixerNode,format:format)
    }
    deinit { cleanup?.invalidate(); engine.stop() }

    @discardableResult func register(_ bytes: Data, name: String, loopStart: Int) -> Bool {
        guard let buffer = NativeRateAudio.pcm(bytes), let channels = buffer.floatChannelData else { return false }
        let count = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start:channels[0],count:count))
        let right = buffer.format.channelCount > 1 ? Array(UnsafeBufferPointer(start:channels[1],count:count)) : left
        let sample = Sample(left:left,right:right,rate:buffer.format.sampleRate,loop:loopStart < 0 ? -1:min(loopStart,count-1),mono:buffer.format.channelCount==1)
        lock.lock(); samples[name] = sample; lock.unlock()
        return true
    }
    @discardableResult func play(_ layer: NativeVehicleAudioDynamics.Layer, id: String,
                                 forceLoop: Bool = false, pan: Double = 0, spatialAzimuth: Double? = nil,
                                 spatialGroup: String? = nil) -> Bool {
        guard layer.rate.isFinite, layer.rate > 0, layer.gain.isFinite, layer.gain >= 0 else { return false }
        lock.lock(); defer { lock.unlock() }
        collect()
        guard let sample = samples[layer.sound] else { return false }
        if let key = current[id], let voice = voices[key], !voice.finished,
           voice.sound == layer.sound, !layer.restart {
            voice.targetRate = layer.rate; voice.targetGain = layer.gain; voice.pan = max(-1,min(1,pan))
            voice.azimuth = spatialAzimuth
            voice.spatialGroup = spatialGroup
        } else {
            if let key = current[id], let old = voices[key] { fade(old,seconds:0.09) }
            let key = UUID()
            voices[key] = Voice(sample:sample,layer:layer,pan:pan,forceLoop:forceLoop,azimuth:spatialAzimuth)
            voices[key]?.spatialGroup = spatialGroup
            current[id] = key
        }
        return true
    }
    /// Prefixes let the local car and up to five original remote vehicles share
    /// one source node while retaining independent voice lifecycles.
    func apply(_ plan: NativeVehicleAudioDynamics.Plan, prefix: String = "mine", gain: Double = 1, pan: Double = 0,
               spatialAzimuth: Double? = nil, spatialPosition: SIMD3<Double>? = nil,
               panner: NativeVehicleAudioSpatial.Panner? = nil) {
        var group: String?
        if let spatialPosition, let panner {
            lock.lock()
            let time = Double(renderedFrames)/outputRate
            if let state = spatialStates[prefix] { state.position.setTarget(spatialPosition,at:time); state.panner = panner }
            else { spatialStates[prefix] = SpatialState(position:spatialPosition,panner:panner,time:time) }
            group = prefix
            lock.unlock()
        }
        for original in plan.layers {
            var layer = original
            layer = NativeVehicleAudioDynamics.Layer(name:original.name,sound:original.sound,rate:original.rate,
                gain:original.gain*gain,restart:original.restart,startFraction:original.startFraction)
            play(layer,id:prefix+":"+layer.name,pan:pan,spatialAzimuth:spatialAzimuth,spatialGroup:group)
        }
        let wanted = Set(plan.layers.map { prefix+":"+$0.name }).union(plan.retain.map { prefix+":"+$0 })
        lock.lock()
        for (id,key) in current where id.hasPrefix(prefix+":") && !wanted.contains(id) {
            if let voice = voices[key] { fade(voice,seconds:0.09) }
            current.removeValue(forKey:id)
        }
        lock.unlock()
        start()
    }
    /// Source listener position/forward are AudioParams with a30ms target;
    /// rendering evaluates them at audio sample time, independently of FPS.
    func listener(position:SIMD3<Double>,forward:SIMD3<Double>) {
        guard (0..<3).allSatisfy({position[$0].isFinite && forward[$0].isFinite}) else { return }
        lock.lock()
        let time = Double(renderedFrames)/outputRate
        listenerPosition.setTarget(position,at:time); listenerForward.setTarget(forward,at:time)
        keepsListening = true
        lock.unlock()
        start(whileSilent:true)
    }
    @discardableResult func start(whileSilent:Bool = false) -> Bool {
        lock.lock(); let active = voices.values.contains { !$0.finished }; lock.unlock()
        guard active || whileSilent else { return false }
        do { if !engine.isRunning { try engine.start() } }
        catch { return false }
        if cleanup == nil {
            cleanup = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.collect(spatial:true); let empty = self.voices.isEmpty && !self.keepsListening; self.lock.unlock()
                if empty { self.engine.pause(); self.cleanup?.invalidate(); self.cleanup = nil }
            }
        }
        return true
    }
    func stop(_ id: String, fade: Double = 0.09) {
        lock.lock()
        if let key = current.removeValue(forKey:id), let voice = voices[key] { self.fade(voice,seconds:fade) }
        lock.unlock()
    }
    func stopAll(immediate: Bool = false) {
        lock.lock()
        for voice in voices.values { fade(voice,seconds:immediate ? 0:0.09) }
        current.removeAll(); if immediate { keepsListening = false }; collect(spatial:true); lock.unlock()
        if immediate { engine.pause(); cleanup?.invalidate(); cleanup = nil }
    }
    private func fade(_ voice: Voice, seconds: Double) {
        guard voice.stopFrames == nil else { return }
        voice.targetGain = 0; voice.tau = max(0.000001,seconds/3)
        voice.stopFrames = max(0,Int(ceil(2*seconds*outputRate)))
        if seconds <= 0 { voice.finished = true }
    }
    private func collect(spatial:Bool = false) {
        voices = voices.filter { !$0.value.finished }
        current = current.filter { voices[$0.value] != nil }
        if spatial {
            let groups = Set(voices.values.compactMap { $0.spatialGroup })
            spatialStates = spatialStates.filter { groups.contains($0.key) }
        }
    }
    /// Called only by the native render callback (or an offline synthetic gate).
    /// The lock protects short control updates; decoding/I/O happens outside it.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        left.initialize(repeating:0,count:frames); right.initialize(repeating:0,count:frames)
        lock.lock(); defer { lock.unlock() }
        for begin in stride(from:0,to:frames,by:4_096) {
            renderChunk(frames:min(4_096,frames-begin),left:left.advanced(by:begin),right:right.advanced(by:begin))
        }
    }
    private func renderChunk(frames:Int,left:UnsafeMutablePointer<Float>,right:UnsafeMutablePointer<Float>) {
        // Buffers are allocated on the control thread, reused across voices,
        // and bounded to4096 samples even if the device asks for a larger block.
        for state in spatialStates.values {
            for i in 0..<frames {
                let time = Double(renderedFrames+UInt64(i))/outputRate
                let listener = listenerPosition.value(at:time), forward = listenerForward.value(at:time)
                let source = state.position.value(at:time)
                let azimuth = NativeVehicleAudioSpatial.azimuth(source:source,listener:listener,forward:forward)
                let gain = state.panner.gain(distance:simd_distance(source,listener))
                state.frames[i].mono = NativeVehicleAudioSpatial.matrix(azimuth:azimuth,mono:true)*gain
                state.frames[i].stereo = NativeVehicleAudioSpatial.matrix(azimuth:azimuth,mono:false)*gain
            }
        }
        for voice in voices.values where !voice.finished {
            let sample = voice.sample
            let rateEase = 1-exp(-1/(0.03*outputRate)), gainEase = 1-exp(-1/(voice.tau*outputRate))
            // StereoPanner's equal-power law; centred stereo remains unchanged.
            let pan = voice.pan
            let panAngle = (pan <= 0 ? pan+1:pan)*Double.pi/2
            let panCos = cos(panAngle), panSin = sin(panAngle)
            let spatial = voice.azimuth.map { NativeVehicleAudioSpatial.matrix(azimuth:$0,mono:sample.mono) }
            let moving = voice.spatialGroup.flatMap { spatialStates[$0] }
            for i in 0..<frames {
                if let stop = voice.stopFrames {
                    if stop <= 0 { voice.finished = true; break }
                    voice.stopFrames = stop-1
                }
                if voice.position >= Double(sample.count) {
                    if voice.loop {
                        let loop = max(0,sample.loop), length = Double(sample.count-loop)
                        voice.position = Double(loop)+(voice.position-Double(sample.count)).truncatingRemainder(dividingBy:length)
                    } else { voice.finished = true; break }
                }
                guard voice.position.isFinite else { voice.finished = true; break }
                let at = Int(voice.position), share = voice.position-Double(at)
                let next = at+1 < sample.count ? at+1 : voice.loop ? max(0,sample.loop):at
                var l = Double(sample.left[at])+(Double(sample.left[next])-Double(sample.left[at]))*share
                var r = Double(sample.right[at])+(Double(sample.right[next])-Double(sample.right[at]))*share
                l *= voice.gain; r *= voice.gain
                if let moving {
                    let matrix = sample.mono ? moving.frames[i].mono:moving.frames[i].stereo
                    let original = l; l = l*matrix.x+r*matrix.y; r = original*matrix.z+r*matrix.w
                } else if let spatial { let original = l; l = l*spatial.x+r*spatial.y; r = original*spatial.z+r*spatial.w }
                else if pan < 0 { l += r*panCos; r *= panSin }
                else if pan > 0 { r += l*panSin; l *= panCos }
                left[i] += Float(l); right[i] += Float(r)
                voice.position += voice.rate*(sample.rate/outputRate)
                voice.gain += (voice.targetGain-voice.gain)*gainEase
                voice.rate += (voice.targetRate-voice.rate)*rateEase
            }
        }
        // Apply preferences after the original source/spatial mix, preserving
        // voice smoothing, phase, held loops and the exact default sample path.
        if settingsGain != 1 {for i in 0..<frames {left[i] *= settingsGain;right[i] *= settingsGain}}
        renderedFrames += UInt64(frames)
    }
    struct Probe { let sound: String; let frame: Double; let rate: Double; let gain: Double }
    var activeVoiceCount: Int { lock.lock(); defer { lock.unlock() }; return voices.values.filter { !$0.finished }.count }
    func probe(_ id: String) -> Probe? {
        lock.lock(); defer { lock.unlock() }
        guard let key = current[id], let voice = voices[key], !voice.finished else { return nil }
        return Probe(sound:voice.sound,frame:voice.position,rate:voice.rate,gain:voice.gain)
    }
}
