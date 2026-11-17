import AVFoundation
import CryptoKit
import Foundation

/// Native PCM scheduling follows the shared station clock, including joins in
/// the middle of songs and sample-contiguous intro/outro/DJ transitions.
final class NativeRadioPlayback {
    private let program: NativeRadioProgram
    private let tracks: [Int: URL]
    private let local:NativeRadioWindowSource?
    private let decoderWorker=DispatchQueue(label:"ZGTA.radio-file-decoder",qos:.utility)
    private final class FileState {var open:(id:Int,file:AVAudioFile)?}
    private let fileState=FileState()
    private struct Pending {let ticket:UUID,generation:Int,scheduled:Int,id:Int,offset:Int,frames:Int}
    private var pending:Pending?
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
    private var cache: URL?
    private var station = 13
    private var fadeFrames = 960
    var onFailure: (() -> Void)?
    var volume: Float = 0.6 { didSet { engine.mainMixerNode.outputVolume = max(0, min(1, volume)) } }

    init(program: NativeRadioProgram, tracks: [Int: URL],local:NativeRadioWindowSource?=nil, clock: @escaping () -> Double) {
        self.program = program; self.tracks = tracks; self.local=local;self.clock = clock
        format = AVAudioFormat(standardFormatWithSampleRate: Double(program.rate), channels: 2)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        if let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = root.appendingPathComponent("ZGTA-SA-radio", isDirectory: true)
            cache = directory
        }
    }
    deinit {
        timer?.invalidate();request?.cancel();local?.cancel();node.stop();engine.stop()
        let state=fileState;decoderWorker.async{state.open=nil}
    }

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
        pending=nil;local?.cancel()
        let state=fileState;decoderWorker.async{state.open=nil}
        node.stop(); engine.stop()
        cursor = nil; scheduled = 0; failed.removeAll()
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
        guard pending==nil else{return}
        var iterations = 0
        while Double(scheduled) / Double(program.rate) - elapsed < 12, let value = cursor, iterations < 1000 {
            iterations += 1
            let id = value.piece.id, remaining = value.piece.plays - offset
            if remaining <= 0 { advance(0); continue }
            let count = min(8_000, remaining)
            if let local,local.contains(id),!failed.contains(id) {
                let read=Pending(ticket:UUID(),generation:generation,scheduled:scheduled,id:id,offset:offset,frames:count)
                pending=read
                local.read(id:id,offset:offset,frames:count){[weak self] result in
                    guard let self,read.generation==self.generation,self.pending?.ticket==read.ticket else{return}
                    self.decoderWorker.async{[weak self] in
                        guard let self else{return}
                        let buffer=result.flatMap{window in Result{try Self.buffer(window:window,format:self.format)}}
                        DispatchQueue.main.async{[weak self] in self?.finish(read,buffer:buffer,fadeEligible:true)}
                    }
                }
                return
            }
            if local==nil,tracks[id] != nil && files[id] == nil && !failed.contains(id) {
                download(id)
                return
            }
            if local==nil,let url=files[id],!failed.contains(id) {
                let read=Pending(ticket:UUID(),generation:generation,scheduled:scheduled,id:id,offset:offset,frames:count)
                pending=read
                decoderWorker.async{[weak self] in
                    guard let self else{return}
                    let buffer=Result{()throws->AVAudioPCMBuffer in
                        if self.fileState.open?.id != id{self.fileState.open=(id,try AVAudioFile(forReading:url))}
                        return try Self.buffer(file:self.fileState.open?.file,offset:read.offset,frames:read.frames,format:self.format)
                    }
                    DispatchQueue.main.async{[weak self] in self?.finish(read,buffer:buffer,fadeEligible:true)}
                }
                return
            }
            let buffer: AVAudioPCMBuffer
            do { buffer = try Self.buffer(file: nil, offset: offset, frames: count, format: format) }
            catch { failed.insert(id); onFailure?(); return }
            node.scheduleBuffer(buffer)
            advance(count); scheduled += count
        }
    }
    private func finish(_ read:Pending,buffer:Result<AVAudioPCMBuffer,Error>,fadeEligible:Bool) {
        guard read.generation==generation,pending?.ticket==read.ticket,cursor != nil else{return}
        pending=nil
        let elapsed=max(0,ProcessInfo.processInfo.systemUptime-started)
        let late=Int(ceil((elapsed+0.005)*Double(program.rate)))-scheduled
        if late>0{advance(late);scheduled += late}
        switch buffer {
        case .failure:failed.insert(read.id);onFailure?()
        case .success(let value):
            guard let remaining=NativeRadioWindowReconciliation.remaining(planned:read.scheduled,scheduled:scheduled,
                readID:read.id,currentID:cursor?.piece.id,readOffset:read.offset,currentOffset:offset,frames:read.frames),
                  let channels=value.floatChannelData else{pump();return}
            let count=remaining.count
            if remaining.lowerBound>0 {
                for frame in 0..<count{channels[0][frame]=channels[0][frame+remaining.lowerBound];channels[1][frame]=channels[1][frame+remaining.lowerBound]}
                value.frameLength=AVAudioFrameCount(count)
            }
            if fadeEligible,fadeFrames>0 {
                let total=Double(program.rate)*0.03
                for frame in 0..<min(count,fadeFrames) {
                    let level=Float(1-Double(fadeFrames)/total)
                    channels[0][frame] *= level;channels[1][frame] *= level;fadeFrames -= 1
                }
            }
            node.scheduleBuffer(value);advance(count);scheduled += count
        }
        pump()
    }
    private enum AudioFailure: Error { case invalidPCM }
    static func buffer(window:NativeRadioPCMWindow,format:AVAudioFormat)throws->AVAudioPCMBuffer {
        guard window.rate==Int(format.sampleRate),(1...8000).contains(window.requestedFrames),
              window.decodedFrames>=0,window.decodedFrames<=window.requestedFrames,
              window.samples.count==window.decodedFrames*2,window.samples.allSatisfy(\.isFinite)else{throw AudioFailure.invalidPCM}
        let result=try buffer(file:nil,offset:0,frames:window.requestedFrames,format:format)
        guard let channels=result.floatChannelData else{throw AudioFailure.invalidPCM}
        for frame in 0..<window.decodedFrames{channels[0][frame]=window.samples[frame*2];channels[1][frame]=window.samples[frame*2+1]}
        return result
    }
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
        loading=id;let token=generation
        DispatchQueue.global(qos:.utility).async{[weak self] in
            let resolved=Result{()throws->URL? in
                let installed=try NativeResourceTransport.localFile(for:url)
                if installed==nil{try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)}
                return installed
            }
            DispatchQueue.main.async{[weak self] in
                guard let self,token==self.generation,self.loading==id else{return}
                switch resolved {
                case .failure:self.loading=nil;self.failed.insert(id);self.onFailure?();self.pump()
                case .success(let installed):
                    if let installed{self.files[id]=installed;self.loading=nil;self.pump()}
                    else{self.downloadRemote(id,url:url,cache:cache,token:token)}
                }
            }
        }
    }
    private func downloadRemote(_ id:Int,url:URL,cache:URL,token:Int){
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = cache.appendingPathComponent(digest + ".wav")
        if FileManager.default.fileExists(atPath: destination.path) {
            files[id] = destination;loading=nil
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            pump();return
        }
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
