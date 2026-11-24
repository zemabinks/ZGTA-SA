// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

#if !ZGTA_PLACEMENT_SUITE
@main
#endif
enum StreamPlacementCheck {
    static func main() throws {
        try fixtures()
        if let archive = CommandLine.arguments.dropFirst().first {
            try auditArchive(URL(fileURLWithPath: archive))
        }
    }

    static func fixtures() throws {
        var sample = Data(repeating: 0, count: 192)
        sample.replaceSubrange(0..<4, with: "bnry".utf8)
        func put(_ value: UInt32, _ offset: Int, in data: inout Data) {
            var encoded = value.littleEndian
            withUnsafeBytes(of: &encoded) { data.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        // Place the CARS block before INST to catch assumptions about order.
        put(1, 4, in: &sample); put(1, 20, in: &sample)
        put(144, 28, in: &sample); put(80, 60, in: &sample)
        put(Float(-12.25).bitPattern, 144, in: &sample)
        put(Float(0.5).bitPattern, 156, in: &sample)
        put(Float(-0.5).bitPattern, 168, in: &sample)
        put(1234, 172, in: &sample); put(0x807, 176, in: &sample); put(152, 180, in: &sample)
        let block = try NativeWorldStreamIPL.decode(sample)
        precondition(block.instances.count == 1 && block.carGeneratorCount == 1)
        let instance = block.instances[0]
        precondition(instance.modelID == 1234 && instance.modelName == nil)
        precondition(instance.position.x == -12.25 && instance.rotation == SIMD4(0.5, 0, 0, -0.5))
        precondition(instance.interiorFlags == 0x807 && instance.interior == 7 && instance.lodIndex == 152)
        func rejected(_ input: Data) {
            do { _ = try NativeWorldStreamIPL.decode(input); preconditionFailure("accepted malformed stream") }
            catch { }
        }
        rejected(Data(sample.prefix(72)))
        rejected(Data(sample.prefix(182)))
        for (offset, invalid): (Int, UInt32) in [(0, 0), (8, 1), (4, .max), (28, 4), (28, 145), (60, 148),
                                                 (28, .max), (144, Float.nan.bitPattern), (172, .max), (180, .max - 1)] {
            var data = sample
            put(invalid, offset, in: &data)
            rejected(data)
        }
        var empty = sample
        put(0, 4, in: &empty); put(0, 20, in: &empty)
        let emptyBlock = try NativeWorldStreamIPL.decode(empty)
        precondition(emptyBlock.instances.isEmpty && emptyBlock.carGeneratorCount == 0)
        print("Passed binary placement field, extent and overlap checks.")
    }

    private static func auditArchive(_ url: URL) throws {
        let archive = try FileHandle(forReadingFrom: url)
        defer { try? archive.close() }
        let size = try archive.seekToEnd()
        func read(_ offset: Int64, _ length: Int) throws -> Data {
            try archive.seek(toOffset: UInt64(offset))
            return try archive.read(upToCount: length) ?? Data()
        }
        let entries = try NativeVER2Archive.scan(byteCount: Int64(size), read: read)
        var streams = 0, instances = 0, generators = 0
        for entry in entries where entry.name.hasSuffix(".ipl") {
            guard entry.allocatedBytes <= 16 * 1024 * 1024 else { throw NativeWorldStreamIPL.Failure.header }
            let bytes = try read(entry.offset, Int(entry.allocatedBytes))
            guard bytes.count == Int(entry.allocatedBytes) else { throw NativeWorldStreamIPL.Failure.header }
            do {
                let block = try NativeWorldStreamIPL.decode(bytes)
                streams += 1
                instances += block.instances.count
                generators += block.carGeneratorCount
            } catch {
                print("Unexpected \(entry.name): \(error)")
                throw error
            }
        }
        precondition(streams > 0 && instances > 0)
        print("Verified \(streams) original IMG placement files, \(instances) instances, \(generators) car-generator records.")
    }
}
