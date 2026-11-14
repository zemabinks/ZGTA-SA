import Foundation
import Metal

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

    func frame(clip: String, elapsed: Double) -> MTLBuffer? {
        guard let options = frames[clip], !options.isEmpty else { return nil }
        let step = max(0, Int(elapsed * Double(framesPerSecond)))
        let index = clip == "jump_launch" ? min(options.count - 1, step) : step % options.count
        return options[index]
    }
}
