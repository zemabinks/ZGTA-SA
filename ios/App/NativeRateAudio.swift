import AVFoundation
import Foundation

/// PCM one-shots with true source-rate/pitch changes below AVAudioPlayer's
/// 0.5 floor. The original thunder layers require rates down to 0.302906.
final class NativeRateAudio {
    private struct Voice {
        let player: AVAudioPlayerNode
        let speed: AVAudioUnitVarispeed
        let started: Double
        let gain: Float
        let rise: Double
    }
    private let engine: AVAudioEngine
    private var buffers: [String:AVAudioPCMBuffer] = [:]
    private var voices: [UUID:Voice] = [:]
    private var timer: DispatchSourceTimer?
    init(engine: AVAudioEngine = AVAudioEngine()) { self.engine = engine }
    deinit { timer?.cancel();engine.stop() }

    static func pcm(_ bytes: Data) -> AVAudioPCMBuffer? {
        let raw = [UInt8](bytes)
        guard raw.count >= 44,Array(raw[0..<4]) == Array("RIFF".utf8),Array(raw[8..<12]) == Array("WAVE".utf8) else { return nil }
        func u16(_ offset: Int) -> Int { Int(raw[offset]) | Int(raw[offset+1])<<8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset+2)<<16 }
        var channels = 0,rate = 0,bits = 0,align = 0,pcm: Range<Int>?
        var offset = 12
        while offset+8 <= raw.count {
            let count = u32(offset+4),begin = offset+8
            guard count >= 0,begin+count <= raw.count else { return nil }
            let name = String(bytes:raw[offset..<offset+4],encoding:.ascii)
            if name == "fmt ",count >= 16 {
                guard u16(begin) == 1 else { return nil }
                channels = u16(begin+2);rate = u32(begin+4);align = u16(begin+12);bits = u16(begin+14)
            } else if name == "data" { pcm = begin..<begin+count }
            offset = begin+count+count%2
        }
        guard let pcm,(1...2).contains(channels),bits == 16,align == channels*2,
              rate > 0,pcm.count%align == 0,pcm.count/align > 0,pcm.count/align < 16_000_000,
              let format = AVAudioFormat(standardFormatWithSampleRate:Double(rate),channels:AVAudioChannelCount(channels)),
              let result = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(pcm.count/align)),
              let samples = result.floatChannelData else { return nil }
        result.frameLength = result.frameCapacity
        for frame in 0..<Int(result.frameLength) {
            for channel in 0..<channels {
                let index = pcm.lowerBound+frame*align+channel*2
                samples[channel][frame] = Float(Int16(bitPattern:UInt16(u16(index))))/32768
            }
        }
        return result
    }

    @discardableResult
    func play(_ bytes: Data,name: String,rate: Float,gain: Float,pan: Float,rise: Double = 0) -> Bool {
        guard rate.isFinite,(0.25...4).contains(rate),gain > 0 else { return false }
        let buffer: AVAudioPCMBuffer
        if let cached = buffers[name] { buffer = cached }
        else if let decoded = Self.pcm(bytes) { buffers[name] = decoded;buffer = decoded }
        else { return false }
        if voices.count >= 24,let oldest = voices.min(by:{ $0.value.started < $1.value.started }) { remove(oldest.key) }
        let player = AVAudioPlayerNode(),speed = AVAudioUnitVarispeed(),id = UUID()
        engine.attach(player);engine.attach(speed)
        engine.connect(player,to:speed,format:buffer.format)
        engine.connect(speed,to:engine.mainMixerNode,format:buffer.format)
        speed.rate = rate;player.pan = max(-1,min(1,pan))
        let gain = max(0,min(1,gain)),rise = max(0,rise)
        player.volume = rise > 0 ? 0 : gain
        voices[id] = Voice(player:player,speed:speed,started:ProcessInfo.processInfo.systemUptime,gain:gain,rise:rise)
        player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.remove(id) }
        }
        do { if !engine.isRunning { try engine.start() } }
        catch { remove(id);return false }
        player.play()
        if rise > 0 { startTimer() }
        return true
    }
    func stop() {
        engine.stop();timer?.cancel();timer = nil
        for voice in voices.values {
            voice.player.stop();engine.detach(voice.player);engine.detach(voice.speed)
        }
        voices.removeAll()
    }
    private func remove(_ id: UUID) {
        guard let voice = voices.removeValue(forKey:id) else { return }
        voice.player.stop();engine.detach(voice.player);engine.detach(voice.speed)
        if voices.isEmpty { timer?.cancel();timer = nil }
    }
    private func startTimer() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue:.main)
        source.schedule(deadline:.now(),repeating:1/60.0)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for voice in self.voices.values where voice.rise > 0 {
                voice.player.volume = voice.gain*Float(min(1,max(0,(now-voice.started)/voice.rise)))
            }
        }
        timer = source;source.resume()
    }
}
