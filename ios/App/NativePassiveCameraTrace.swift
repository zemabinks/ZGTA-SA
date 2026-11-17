// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Opt-in, device-local diagnostics. Submission never encodes JSON or touches
/// disk. A bounded serial writer owns the file and reports discarded records.
final class NativePassiveCameraTrace {
    struct Ray: Codable {
        let origin, direction: [Float]
        let requestedDistance: Float
        let groups: UInt32
        let vehiclePolicyApplied: Bool
        var result: String
        var resultDistance: Float?
        var collider, body: UInt64?
        var bodyKind: String?
        var nativeMaterial: Int?
        var point, normal: [Float]?
        var originalOtherMember: Bool?
        var originalMaterialMember: Bool?
        var legacyObject: Bool?
        let excludedDynamicOtherCount, excludedLegacyCount, excludedOwnCount: Int
        let excludedDynamicOtherSample: [UInt64]
    }
    struct Draw: Codable {
        let monotonicMilliseconds: Double
        let eye, target: [Float]
        let nearPlane, farPlane, verticalFov, aspect: Float
        let legacyCameraOverride: Bool
        var subjectTransform: [Float]? = nil
    }
    struct Record: Codable {
        let camera: NativeGameCamera.VehicleObservation?
        let ray: Ray?
        let draw: Draw?
    }
    struct Limits {
        var records=1800
        var bytes=2*1024*1024
        var pending=32
        fileprivate var bounded: Self {
            Self(records:min(7200,max(1,records)),bytes:min(8*1024*1024,max(8192,bytes)),pending:min(64,max(1,pending)))
        }
    }
    struct Summary: Codable {
        let file: URL
        let submitted, written, droppedQueue, droppedLimit, droppedBytes, droppedEncoding, droppedIO: Int
        let bytes: Int
        let error: String?
        private enum CodingKeys:String,CodingKey {
            case file,submitted,written,droppedQueue,droppedLimit,droppedBytes,droppedEncoding,droppedIO,bytes,error
        }
        func encode(to encoder:Encoder)throws {
            var values=encoder.container(keyedBy:CodingKeys.self)
            // The callback retains the usable local URL. The diagnostic file
            // itself does not record a user's filesystem account/path.
            try values.encode(file.lastPathComponent,forKey:.file)
            try values.encode(submitted,forKey:.submitted);try values.encode(written,forKey:.written)
            try values.encode(droppedQueue,forKey:.droppedQueue);try values.encode(droppedLimit,forKey:.droppedLimit)
            try values.encode(droppedBytes,forKey:.droppedBytes);try values.encode(droppedEncoding,forKey:.droppedEncoding)
            try values.encode(droppedIO,forKey:.droppedIO);try values.encode(bytes,forKey:.bytes)
            try values.encodeIfPresent(error,forKey:.error)
        }
    }
    private struct Envelope: Encodable {let sequence:Int;let observation:Record}
    private let limits: Limits
    private let directory: URL
    private let file: URL
    private let queue: DispatchQueue
    private let lock=NSLock()
    private var accepting=true,pending=0,submitted=0,queueDrops=0,limitDrops=0
    // The fields below are used exclusively by the writer queue.
    private var handle:FileHandle?,written=0,bytes=0,byteDrops=0,encodingDrops=0
    private var failure:String?,finished:Summary?
    private static func errorCode(_ error:Error)->String {
        let value=error as NSError
        // Describing/localizing a filesystem error can perform slow ancillary
        // work and include a user's absolute path. Keep diagnostics bounded.
        return String(value.domain.prefix(80))+":"+String(value.code)
    }

    init(directory:URL,limits:Limits=Limits(),writerQueue:DispatchQueue?=nil) {
        self.directory=directory;self.limits=limits.bounded
        file=directory.appendingPathComponent("camera-\(UUID().uuidString.lowercased()).jsonl")
        queue=writerQueue ?? DispatchQueue(label:"ZGTA.passive-camera-writer",qos:.utility)
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                // Keep at most four bounded traces, including this new one.
                let old=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.creationDateKey,.isRegularFileKey,.isSymbolicLinkKey])
                    .filter { $0.lastPathComponent.hasPrefix("camera-") && $0.pathExtension=="jsonl" }
                    .filter { let v=try? $0.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]);return v?.isRegularFile==true && v?.isSymbolicLink != true }
                    .sorted {
                        let a=(try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast
                        let b=(try? $1.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast
                        return a>b
                    }
                for url in old.dropFirst(3){try FileManager.default.removeItem(at:url)}
                guard FileManager.default.createFile(atPath:file.path,contents:nil) else{throw CocoaError(.fileWriteUnknown)}
                handle=try FileHandle(forWritingTo:file)
                let header=Data("{\"schema\":\"zgta-passive-camera-v1\",\"maximumRecords\":\(self.limits.records),\"maximumBytes\":\(self.limits.bytes),\"maximumPending\":\(self.limits.pending)}\n".utf8)
                try handle?.write(contentsOf:header);bytes=header.count
            }catch{failure=Self.errorCode(error)}
        }
    }
    func submit(_ record:Record) {
        lock.lock()
        guard accepting else{lock.unlock();return}
        guard submitted<limits.records else{limitDrops += 1;lock.unlock();return}
        guard pending<limits.pending else{queueDrops += 1;lock.unlock();return}
        submitted += 1;pending += 1
        let sequence=submitted
        queue.async { [self] in
            defer{lock.lock();pending -= 1;lock.unlock()}
            guard failure==nil else{return}
            do {
                var data=try JSONEncoder().encode(Envelope(sequence:sequence,observation:record));data.append(10)
                // Reserve room for a final summary even when observation data
                // exhausts the configured disk budget.
                guard data.count<=32*1024,bytes+data.count<=limits.bytes-4096 else{byteDrops += 1;return}
                try handle?.write(contentsOf:data);bytes += data.count;written += 1
            }catch let error as EncodingError{encodingDrops += 1;_ = error}
            catch{failure=Self.errorCode(error)}
        }
        // Enqueue before releasing the admission lock, so stop cannot overtake
        // an accepted submission from another thread.
        lock.unlock()
    }
    /// The result is delivered on main after all accepted writes. Repeated
    /// stop calls return the same summary and never append another footer.
    func stop(completion:@escaping(Summary)->Void) {
        lock.lock();accepting=false;lock.unlock()
        queue.async { [self] in
            if let finished{DispatchQueue.main.async{completion(finished)};return}
            lock.lock();let counts=(submitted,queueDrops,limitDrops);lock.unlock()
            var summary=Summary(file:file,submitted:counts.0,written:written,droppedQueue:counts.1,
                droppedLimit:counts.2,droppedBytes:byteDrops,droppedEncoding:encodingDrops,
                droppedIO:counts.0-written-byteDrops-encodingDrops,bytes:bytes,error:failure)
            do {
                if failure==nil {
                    func footer(_ value:Summary)throws->Data {
                        var data=Data("{\"summary\":".utf8);data.append(try JSONEncoder().encode(value));data.append(contentsOf:Data("}\n".utf8));return data
                    }
                    var data=try footer(summary)
                    // Resolve the footer length so both the returned and
                    // persisted summaries account for the same complete file.
                    for _ in 0..<8 {
                        let total=bytes+data.count
                        summary=Summary(file:file,submitted:counts.0,written:written,droppedQueue:counts.1,
                            droppedLimit:counts.2,droppedBytes:byteDrops,droppedEncoding:encodingDrops,
                            droppedIO:counts.0-written-byteDrops-encodingDrops,bytes:total,error:nil)
                        let next=try footer(summary)
                        if next.count==data.count{data=next;break}
                        data=next
                    }
                    guard bytes+data.count<=limits.bytes else{throw CocoaError(.fileWriteOutOfSpace)}
                    try handle?.write(contentsOf:data);bytes += data.count
                    try handle?.synchronize()
                }
                try handle?.close()
            }catch{failure=Self.errorCode(error)}
            handle=nil
            summary=Summary(file:file,submitted:counts.0,written:written,droppedQueue:counts.1,
                droppedLimit:counts.2,droppedBytes:byteDrops,droppedEncoding:encodingDrops,
                droppedIO:counts.0-written-byteDrops-encodingDrops,bytes:bytes,error:failure)
            finished=summary
            let result=summary
            DispatchQueue.main.async{completion(result)}
        }
    }
}
