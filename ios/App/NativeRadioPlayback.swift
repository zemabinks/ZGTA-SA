import AVFoundation
import CryptoKit
import Foundation

/// Native PCM scheduling follows the shared station clock, including joins in
/// the middle of songs and sample-contiguous intro/outro/DJ transitions.
final class NativeRadioPlayback {
    private let program: NativeRadioProgram
    private let tracks: [Int: URL]
    private let clock: () -> Double
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var timer: Timer?
    private var cursor: NativeRadioProgram.Cursor?
    private var offset = 0
    private var scheduled = 0
    private var started = 0.0
    private var generation = 0
    private var request: URLSessionDownloadTask?
    private var loading: Int?
    private var failed: Set<Int> = []
    private var files: [Int: URL] = [:]
    private var openFile: (id: Int, file: AVAudioFile)?
    private var cache: URL?
    private var station = 13
    private var fadeFrames = 960
    var onFailure: (() -> Void)?
    var volume: Float = 0.6 { didSet { engine.mainMixerNode.outputVolume = max(0, min(1, volume)) } }

    init(program: NativeRadioProgram, tracks: [Int: URL], clock: @escaping () -> Double) {
        self.program = program; self.tracks = tracks; self.clock = clock
        format = AVAudioFormat(standardFormatWithSampleRate: Double(program.rate), channels: 2)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        if let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = root.appendingPathComponent("ZGTA-SA-radio", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            cache = directory
        }
    }
    deinit { timer?.invalidate(); request?.cancel(); node.stop(); engine.stop() }

    func start(station: Int) throws {
        stop()
        guard let cursor = program.at(station: station, milliseconds: clock() + 60) else { return }
        self.station = station; self.cursor = cursor; offset = cursor.into
        fadeFrames = Int(Double(program.rate) * 0.03)
        started = ProcessInfo.processInfo.systemUptime + 0.06
        try engine.start()
        node.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.06)))
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.pump() }
        pump()
    }
    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        request?.cancel(); request = nil; loading = nil
        node.stop(); engine.stop()
        cursor = nil; openFile = nil; scheduled = 0; failed.removeAll()
    }

    private func advance(_ frames: Int) {
        offset += frames
        while let value = cursor, offset >= value.piece.plays {
            offset -= value.piece.plays
            cursor = program.after(value)
        }
    }
    private func pump() {
        guard cursor != nil else { return }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - started)
        // Decoding/network stalls consume station time, just as the browser's
        // streaming scheduler skips late frames instead of restarting a song.
        let late = Int(ceil((elapsed + 0.005) * Double(program.rate))) - scheduled
        if late > 0 { advance(late); scheduled += late }
        var iterations = 0
        while Double(scheduled) / Double(program.rate) - elapsed < 12, let value = cursor, iterations < 1000 {
            iterations += 1
            let id = value.piece.id, remaining = value.piece.plays - offset
            if remaining <= 0 { advance(0); continue }
            if tracks[id] != nil && files[id] == nil && !failed.contains(id) {
                download(id)
                return
            }
            let count = min(8_000, remaining)
            var file: AVAudioFile?
            if let url = files[id] {
                do {
                    if openFile?.id != id { openFile = (id, try AVAudioFile(forReading: url)) }
                    file = openFile?.file
                } catch { failed.insert(id); onFailure?() }
            }
            let buffer: AVAudioPCMBuffer
            do { buffer = try Self.buffer(file: file, offset: offset, frames: count, format: format) }
            catch { failed.insert(id); onFailure?(); return }
            if file != nil, fadeFrames > 0, let channels = buffer.floatChannelData {
                let total = Double(program.rate) * 0.03
                for frame in 0..<min(count, fadeFrames) {
                    let level = Float(1 - Double(fadeFrames) / total)
                    channels[0][frame] *= level; channels[1][frame] *= level
                    fadeFrames -= 1
                }
            }
            node.scheduleBuffer(buffer)
            advance(count); scheduled += count
        }
    }
    private enum AudioFailure: Error { case invalidPCM }
    /// The browser duplicates mono and pads missing decoded samples with
    /// silence while retaining the program's exact sample count.
    static func buffer(file: AVAudioFile?, offset: Int, frames: Int, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard frames > 0, frames <= 8_000, offset >= 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = output.floatChannelData, format.channelCount == 2 else { throw AudioFailure.invalidPCM }
        output.frameLength = AVAudioFrameCount(frames)
        channels[0].initialize(repeating: 0, count: frames)
        channels[1].initialize(repeating: 0, count: frames)
        guard let file else { return output }
        guard file.processingFormat.sampleRate == format.sampleRate,
              (1...2).contains(file.processingFormat.channelCount) else { throw AudioFailure.invalidPCM }
        if offset < file.length {
            file.framePosition = AVAudioFramePosition(offset)
            if let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)) {
                try file.read(into: input, frameCount: AVAudioFrameCount(frames))
                if let source = input.floatChannelData {
                    channels[0].update(from: source[0], count: Int(input.frameLength))
                    channels[1].update(from: source[file.processingFormat.channelCount > 1 ? 1 : 0], count: Int(input.frameLength))
                }
            }
        }
        return output
    }
    private func download(_ id: Int) {
        guard loading == nil, let url = tracks[id], let cache else { return }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = cache.appendingPathComponent(digest + ".wav")
        if FileManager.default.fileExists(atPath: destination.path) {
            files[id] = destination
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return
        }
        loading = id
        let token = generation
        request = URLSession.shared.downloadTask(with: url) { [weak self] temporary, response, _ in
            var saved: URL?
            if let temporary, (response as? HTTPURLResponse)?.statusCode == 200 {
                do {
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    saved = destination
                } catch {}
            }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.loading = nil; self.request = nil
                if let saved { self.files[id] = saved; self.pruneCache(except: saved) }
                else { self.failed.insert(id); self.onFailure?() }
                self.pump()
            }
        }
        request?.resume()
    }
    private func pruneCache(except retained: URL) {
        guard let cache, let files = try? FileManager.default.contentsOfDirectory(at: cache,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where size > 256 * 1_024 * 1_024 && entry.0 != retained {
            try? FileManager.default.removeItem(at: entry.0)
            self.files = self.files.filter { $0.value != entry.0 }
            size -= entry.1
        }
    }
}
