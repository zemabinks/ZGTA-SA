// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Object placements from classic PC streamed binary IPL members. Coordinates
/// and LOD indices remain in their source space, ready for the owning map group.
/// Format reference: plugin-sdk's tBinaryIplFile and CFileObjectInstance layouts.
enum NativeWorldStreamIPL {
    struct Contents {
        let instances: [NativeWorldPlacement.Instance]
        let carGeneratorCount: Int
    }

    enum Failure: LocalizedError {
        case header, section(String), instance(Int)
        var errorDescription: String? {
            switch self {
            case .header: return "Invalid or unsupported streamed IPL header."
            case .section(let name): return "Invalid streamed IPL \(name) section."
            case .instance(let row): return "Invalid object placement at streamed IPL row \(row)."
            }
        }
    }

    static func decode(_ data: Data) throws -> Contents {
        let headerSize = 76
        guard (headerSize...16 * 1024 * 1024).contains(data.count),
              data.prefix(4).elementsEqual([0x62, 0x6e, 0x72, 0x79]) else { throw Failure.header }

        return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            func word(_ offset: Int) -> UInt32 {
                UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
            func signed(_ offset: Int) -> Int { Int(Int32(bitPattern: word(offset))) }
            func scalar(_ offset: Int) -> Float { Float(bitPattern: word(offset)) }

            // Disc IPLs declare INST and CARS counts. Treat an unfamiliar active
            // section as unsupported instead of interpreting its storage as INST.
            guard [8, 12, 16, 24].allSatisfy({ word($0) == 0 }) else { throw Failure.header }
            func span(countAt: Int, offsetAt: Int, stride: Int, name: String) throws -> Range<Int> {
                let count = Int(word(countAt))
                guard count <= 65_535 else { throw Failure.section(name) }
                if count == 0 { return 0..<0 }
                let start = Int(word(offsetAt))
                guard start >= headerSize, start.isMultiple(of: 4), start <= bytes.count,
                      count <= (bytes.count - start) / stride else { throw Failure.section(name) }
                return start..<(start + stride * count)
            }
            let objects = try span(countAt: 4, offsetAt: 28, stride: 40, name: "INST")
            let generators = try span(countAt: 20, offsetAt: 60, stride: 48, name: "CARS")
            guard objects.isEmpty || generators.isEmpty || !objects.overlaps(generators) else {
                throw Failure.section("overlapping INST/CARS")
            }

            var instances = [NativeWorldPlacement.Instance]()
            instances.reserveCapacity(objects.count / 40)
            for at in stride(from: objects.lowerBound, to: objects.upperBound, by: 40) {
                let position = SIMD3(scalar(at), scalar(at + 4), scalar(at + 8))
                let rotation = SIMD4(scalar(at + 12), scalar(at + 16), scalar(at + 20), scalar(at + 24))
                let rotationLengthSquared = (rotation * rotation).sum()
                let id = signed(at + 28), lod = signed(at + 36)
                // Some LOD links refer to the parent text IPL. Bound them only
                // after all the pieces of that region are available together.
                guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
                      rotationLengthSquared.isFinite, rotationLengthSquared > 0,
                      id >= 0, lod >= -1 else { throw Failure.instance(instances.count) }
                instances.append(.init(modelID: id, modelName: nil, interiorFlags: word(at + 32),
                                       position: position, rotation: rotation, lodIndex: lod))
            }
            return Contents(instances: instances, carGeneratorCount: generators.count / 48)
        }
    }
}
