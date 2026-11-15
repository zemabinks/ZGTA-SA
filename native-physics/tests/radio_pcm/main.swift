import AVFoundation
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let format = AVAudioFormat(standardFormatWithSampleRate: 32_000, channels: 2)!
for channels: AVAudioChannelCount in [1, 2] {
    let fileFormat = AVAudioFormat(standardFormatWithSampleRate: 32_000, channels: channels)!
    let source = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: 16_000)!
    source.frameLength = 16_000
    for i in 0..<16_000 {
        source.floatChannelData![0][i] = i < 8_000 ? 0.125 : 0.25
        if channels == 2 { source.floatChannelData![1][i] = i < 8_000 ? -0.375 : -0.5 }
    }
    let url = directory.appendingPathComponent("\(channels).wav")
    do { let file = try AVAudioFile(forWriting: url, settings: fileFormat.settings); try file.write(from: source) }
    let file = try AVAudioFile(forReading: url)
    let first = try NativeRadioPlayback.buffer(file: file, offset: 0, frames: 8_000, format: format)
    let second = try NativeRadioPlayback.buffer(file: file, offset: 8_000, frames: 8_000, format: format)
    let tail = try NativeRadioPlayback.buffer(file: file, offset: 15_999, frames: 8_000, format: format)
    precondition(tail.floatChannelData![0][0] == 0.25)
    precondition((1..<8_000).allSatisfy { tail.floatChannelData![0][$0] == 0 && tail.floatChannelData![1][$0] == 0 })
    let engine = AVAudioEngine(), node = AVAudioPlayerNode()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
    node.scheduleBuffer(first); node.scheduleBuffer(second)
    try engine.start(); node.play()
    let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
    var at = 0
    while at < 16_000 {
        let count = min(4_096, 16_000 - at)
        let status = try engine.renderOffline(AVAudioFrameCount(count), to: output)
        precondition(status == .success, "Actual native PCM render stalled")
        for i in 0..<count {
            let expected: Float = at + i < 8_000 ? 0.125 : 0.25
            let right: Float = channels == 1 ? expected : (at + i < 8_000 ? -0.375 : -0.5)
            precondition(output.floatChannelData![0][i] == expected && output.floatChannelData![1][i] == right,
                         "Gap, sample shift or channel change at frame \(at+i)")
        }
        at += count
    }
    node.stop(); engine.stop()
}
print("PASS: actual native offline engine renders sample-contiguous mono/stereo program pieces; mono duplication and EOF silence preserve all 32,000 tested samples")
