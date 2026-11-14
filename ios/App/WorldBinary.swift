import Foundation
import simd

/// The public browser client streams WRL2 geometry. This parser reads the same
/// local-only files into Metal-friendly vertices without including game data in
/// the app project or source repository.
struct NativeVertex {
    var position: SIMD4<Float>
    var uvLayer: SIMD4<Float>
    var tint: SIMD4<Float>
    var dusk: SIMD4<Float>
}

struct WorldBinary {
    let vertices: [NativeVertex]
    let indices: [UInt32]
    let layers: Int

    enum Error: Swift.Error { case invalidHeader, invalidLength, invalidIndex }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> UInt16 {
            UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
        }
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 |
                UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func f32(_ at: Int) -> Float { Float(bitPattern: u32(at)) }
        guard bytes.count >= 16, u32(0) == 0x324C5257 else { throw Error.invalidHeader }
        let count = Int(u32(4)), indexCount = Int(u32(8)), layerCount = Int(u32(12))
        guard count > 0, count < 1_000_000, indexCount > 0,
              indexCount < 3_000_000, indexCount % 3 == 0,
              layerCount > 0, layerCount <= 4096 else { throw Error.invalidHeader }
        let positions = 16
        let uvs = positions + count * 12
        let indexStart = uvs + count * 8
        let tintStart = indexStart + indexCount * 4
        let layerStart = tintStart + count * 4
        let duskStart = layerStart + (count + count % 2) * 2
        let sharpEnd = duskStart + count * 4 + layerCount * 2
        guard sharpEnd <= bytes.count else { throw Error.invalidLength }
        let unit: Float = 1 / 255
        var madeVertices: [NativeVertex] = []
        madeVertices.reserveCapacity(count)
        for n in 0..<count {
            let p = positions + n * 12, uv = uvs + n * 8
            let t = tintStart + n * 4, d = duskStart + n * 4
            let layer = Int(u16(layerStart + n * 2))
            guard layer < layerCount else { throw Error.invalidIndex }
            madeVertices.append(NativeVertex(
                position: SIMD4(f32(p), f32(p + 4), f32(p + 8), 1),
                uvLayer: SIMD4(f32(uv), f32(uv + 4), Float(layer), 0),
                tint: SIMD4(Float(bytes[t]) * unit, Float(bytes[t + 1]) * unit,
                            Float(bytes[t + 2]) * unit, Float(bytes[t + 3]) * unit),
                dusk: SIMD4(Float(bytes[d]) * unit, Float(bytes[d + 1]) * unit,
                            Float(bytes[d + 2]) * unit, Float(bytes[d + 3]) * unit)))
        }
        var madeIndices: [UInt32] = []
        madeIndices.reserveCapacity(indexCount)
        for n in 0..<indexCount {
            let value = u32(indexStart + n * 4)
            guard Int(value) < count else { throw Error.invalidIndex }
            madeIndices.append(value)
        }
        vertices = madeVertices
        indices = madeIndices
        layers = layerCount
    }
}
