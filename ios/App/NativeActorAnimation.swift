import Foundation
import Metal
import simd

/// Vertex frames baked from the archived DFF skin and ANP3 clips on the Mac.
/// The original game files and these generated frames stay outside the app.
struct NativeActorAnimation {
    private let frames: [String: [MTLBuffer]]
    private let framesPerSecond: Int

    init?(data: Data, vertexCount: Int, device: MTLDevice) {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 |
                Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 16, bytes[0...3].elementsEqual([65, 78, 77, 49]),
              u32(4) == vertexCount, vertexCount > 0, vertexCount < 100_000 else { return nil }
        let clipCount = u32(8)
        let fps = u32(12)
        guard clipCount > 0, clipCount <= 16, fps > 0, fps <= 120 else { return nil }
        var offset = 16
        var decoded: [String: [MTLBuffer]] = [:]
        for _ in 0..<clipCount {
            guard offset + 20 <= bytes.count else { return nil }
            let nameBytes = bytes[offset..<(offset + 16)].prefix { $0 != 0 }
            let name = String(bytes: nameBytes, encoding: .ascii) ?? ""
            let count = u32(offset + 16)
            offset += 20
            guard !name.isEmpty, count > 0, count <= 1000,
                  vertexCount <= Int.max / 12,
                  count <= (bytes.count - offset) / (vertexCount * 12) else { return nil }
            let frameLength = vertexCount * 12
            var buffers: [MTLBuffer] = []
            buffers.reserveCapacity(count)
            for _ in 0..<count {
                let buffer = data.withUnsafeBytes { raw -> MTLBuffer? in
                    guard let base = raw.baseAddress else { return nil }
                    return device.makeBuffer(bytes: base.advanced(by: offset),
                                             length: frameLength, options: .storageModeShared)
                }
                guard let buffer else { return nil }
                buffers.append(buffer)
                offset += frameLength
            }
            decoded[name] = buffers
        }
        guard offset == bytes.count else { return nil }
        frames = decoded
        framesPerSecond = fps
    }

    func sample(clip: String, elapsed: Double) -> (MTLBuffer, MTLBuffer, Float)? {
        guard let options = frames[clip], !options.isEmpty else { return nil }
        let phase = max(0, elapsed * Double(framesPerSecond))
        let step = min(Int(phase), 1_000_000_000)
        let last = options.count - 1
        let index = clip == "jump_launch" ? min(last, step) : step % options.count
        let next = clip == "jump_launch" ? min(last, index + 1) : (index + 1) % options.count
        return (options[index], options[next], Float(phase - floor(phase)))
    }
}

/// Per-frame right-hand transforms from the archived pedestrian skeleton.
/// Weapon vertices remain in their original RenderWare local coordinates.
struct NativeActorAttachment {
    private let frames: [String: [simd_float4x4]]
    private let framesPerSecond: Int

    init?(data: Data) {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
                UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 16, bytes[0...3].elementsEqual([72, 78, 68, 49]) else { return nil }
        let count = Int(u32(4)), fps = Int(u32(8))
        guard count > 0, count <= 16, fps > 0, fps <= 120 else { return nil }
        var offset = 16
        var decoded: [String: [simd_float4x4]] = [:]
        for _ in 0..<count {
            guard offset + 20 <= bytes.count else { return nil }
            let name = String(bytes: bytes[offset..<(offset + 16)].prefix { $0 != 0 },
                              encoding: .ascii) ?? ""
            let frameCount = Int(u32(offset + 16))
            offset += 20
            guard !name.isEmpty, frameCount > 0, frameCount <= 1000,
                  frameCount <= (bytes.count - offset) / 64 else { return nil }
            var matrices: [simd_float4x4] = []
            matrices.reserveCapacity(frameCount)
            for _ in 0..<frameCount {
                let values = (0..<16).map { Float(bitPattern: u32(offset + $0 * 4)) }
                guard values.allSatisfy(\.isFinite) else { return nil }
                matrices.append(simd_float4x4(columns: (
                    SIMD4(values[0], values[1], values[2], values[3]),
                    SIMD4(values[4], values[5], values[6], values[7]),
                    SIMD4(values[8], values[9], values[10], values[11]),
                    SIMD4(values[12], values[13], values[14], values[15]))))
                offset += 64
            }
            decoded[name] = matrices
        }
        guard offset == bytes.count else { return nil }
        frames = decoded
        framesPerSecond = fps
    }

    func frame(clip: String, elapsed: Double) -> simd_float4x4? {
        guard let options = frames[clip], !options.isEmpty else { return nil }
        let step = max(0, Int(elapsed * Double(framesPerSecond)))
        return options[clip == "jump_launch" ? min(options.count - 1, step) : step % options.count]
    }
}
