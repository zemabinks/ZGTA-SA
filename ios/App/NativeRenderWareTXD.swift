// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// CPU-only reader for little-endian PC RenderWare texture dictionaries.
///
/// This independently written reader does not load images, create Metal resources,
/// or execute native plugins. Chunk layouts were checked against owner-local PC
/// TXDs and librw's MIT-licensed D3D9 stream reader (file-format reference only):
/// https://github.com/aap/librw/blob/master/src/d3d/d3d9.cpp
/// Checked file blob SHA: 851397b675257b47ff1667d3125d966ba803c952.
/// BC layouts: https://learn.microsoft.com/en-us/windows/win32/direct3d10/d3d10-graphics-programming-guide-resources-block-compression
/// Raw formats: https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dformat
enum NativeRenderWareTXD {
    struct Limits {
        var maximumFileBytes = 64 * 1024 * 1024
        var maximumTextureCount = 2_048
        var maximumDimension = 4_096
        var maximumMipLevels = 13
        var maximumDecodedBytes = 128 * 1024 * 1024
        var maximumChunkCount = 16_384
        static let `default` = Limits()
    }

    enum DecodeError: Error, CustomStringConvertible {
        case malformed(String)
        case unsupported(String)
        case limitExceeded(String)

        var description: String {
            switch self {
            case .malformed(let reason): return "Malformed TXD: \(reason)"
            case .unsupported(let reason): return "Unsupported TXD: \(reason)"
            case .limitExceeded(let reason): return "TXD limit exceeded: \(reason)"
            }
        }
    }

    struct TextureDictionary {
        let version: UInt32
        let deviceID: UInt16
        let textures: [Texture]
        let decodedByteCount: Int
    }

    struct Texture {
        /// Original ASCII stream names, without NUL padding. Never used as paths.
        let name: String
        let maskName: String
        /// RenderWare texture lookup is case-insensitive.
        var lookupName: String { name.lowercased() }
        let filterAddressing: UInt32
        let rasterFormat: UInt32
        let d3dFormat: UInt32
        let depth: UInt8
        let nativeFlags: UInt8
        var declaresAlpha: Bool { nativeFlags & 1 != 0 }
        var usesAutomaticMipmaps: Bool { nativeFlags & 4 != 0 }
        let mipLevels: [MipLevel]
        var containsTransparentPixels: Bool { mipLevels.contains { $0.containsTransparentPixels } }
    }

    struct MipLevel {
        let width: Int
        let height: Int
        let encodedByteCount: Int
        /// Tightly packed, top-to-bottom, straight-alpha RGBA8; no row padding.
        /// Some original PC files have empty final sub-4x4 BC mip records. These
        /// remain nil, rather than inventing image data or uploading empty bytes.
        let rgba8: Data?
        let containsTransparentPixels: Bool
        var rowBytes: Int { width * 4 }
    }

    static func decode(_ data: Data, limits: Limits = .default) throws -> TextureDictionary {
        try Parser(data: data, limits: limits).decode()
    }

    private struct Chunk {
        let kind: UInt32
        let version: UInt32
        let body: Range<Int>
    }

    private enum Format {
        case dxt1, dxt3, dxt5, bgra, bgrx, rgb565, argb1555, xrgb1555, argb4444, xrgb4444, luminance8, alpha8

        var blockBytes: Int? {
            switch self {
            case .dxt1: return 8
            case .dxt3, .dxt5: return 16
            default: return nil
            }
        }
        var bitsPerPixel: Int {
            switch self {
            case .bgra, .bgrx: return 32
            case .luminance8, .alpha8: return 8
            default: return 16
            }
        }
        func encodedSize(width: Int, height: Int) -> Int {
            if let blockBytes { return ((width + 3) / 4) * ((height + 3) / 4) * blockBytes }
            return width * height * (bitsPerPixel / 8)
        }
    }

    private final class Parser {
        let bytes: [UInt8]
        let limits: Limits
        var chunkCount = 0
        var decodedBytes = 0

        init(data: Data, limits: Limits) throws {
            guard limits.maximumFileBytes > 0, limits.maximumTextureCount > 0,
                  limits.maximumDimension > 0, limits.maximumDimension <= 65_535,
                  limits.maximumMipLevels > 0, limits.maximumMipLevels <= 16,
                  limits.maximumDecodedBytes > 0, limits.maximumChunkCount > 0 else {
                throw DecodeError.limitExceeded("invalid decoder limits")
            }
            guard data.count <= limits.maximumFileBytes else { throw DecodeError.limitExceeded("encoded file bytes") }
            self.limits = limits
            // A normalized buffer also makes a Data slice's nonzero startIndex safe.
            self.bytes = Array(data)
        }

        func decode() throws -> TextureDictionary {
            let roots = try chunks(in: 0..<bytes.count)
            guard roots.count == 1, let root = roots.first, root.kind == 0x16 else {
                throw DecodeError.malformed("expected one texture-dictionary root")
            }
            let children = try chunks(in: root.body)
            let structures = children.filter { $0.kind == 1 }
            guard structures.count == 1, let info = structures.first, info.body.count == 4 else {
                throw DecodeError.malformed("dictionary struct must contain count and device ID")
            }
            let declaredCount = Int(u16(info.body.lowerBound))
            let deviceID = u16(info.body.lowerBound + 2)
            guard deviceID == 0 || deviceID == 2 else {
                throw DecodeError.unsupported("dictionary device ID \(deviceID); only PC D3D9 is supported")
            }
            guard declaredCount <= limits.maximumTextureCount else { throw DecodeError.limitExceeded("texture count") }
            let natives = children.filter { $0.kind == 0x15 }
            guard natives.count == declaredCount else { throw DecodeError.malformed("dictionary texture count does not match native chunks") }
            var textures: [Texture] = []
            var names = Set<String>()
            textures.reserveCapacity(declaredCount)
            for native in natives {
                let texture = try texture(native)
                guard names.insert(texture.lookupName).inserted else { throw DecodeError.malformed("duplicate texture name \(texture.name)") }
                textures.append(texture)
            }
            return TextureDictionary(version: root.version, deviceID: deviceID, textures: textures, decodedByteCount: decodedBytes)
        }

        func chunks(in range: Range<Int>) throws -> [Chunk] {
            var result: [Chunk] = []
            var offset = range.lowerBound
            while offset < range.upperBound {
                guard range.upperBound - offset >= 12 else { throw DecodeError.malformed("truncated chunk header at \(offset)") }
                chunkCount += 1
                guard chunkCount <= limits.maximumChunkCount else { throw DecodeError.limitExceeded("chunk count") }
                let length = Int(u32(offset + 4))
                let start = offset + 12
                guard length <= range.upperBound - start else { throw DecodeError.malformed("chunk exceeds its parent at \(offset)") }
                let end = start + length
                result.append(Chunk(kind: u32(offset), version: u32(offset + 8), body: start..<end))
                offset = end
            }
            return result
        }

        func texture(_ chunk: Chunk) throws -> Texture {
            let structures = try chunks(in: chunk.body).filter { $0.kind == 1 }
            guard structures.count == 1, let info = structures.first, info.body.count >= 92 else {
                throw DecodeError.malformed("native texture requires one complete D3D9 struct")
            }
            let start = info.body.lowerBound
            let platform = u32(start)
            guard platform == 9 else { throw DecodeError.unsupported("native platform \(platform); only D3D9 is supported") }
            let name = try self.name(at: start + 8, emptyAllowed: false)
            let mask = try self.name(at: start + 40, emptyAllowed: true)
            let raster = u32(start + 72), d3d = u32(start + 76)
            let width = Int(u16(start + 80)), height = Int(u16(start + 82))
            let depth = bytes[start + 84], mipCount = Int(bytes[start + 85])
            let rasterType = bytes[start + 86], flags = bytes[start + 87]
            guard width > 0, height > 0 else { throw DecodeError.malformed("zero texture dimension") }
            guard width <= limits.maximumDimension, height <= limits.maximumDimension else { throw DecodeError.limitExceeded("texture dimensions") }
            guard rasterType == 4 else { throw DecodeError.unsupported("raster type \(rasterType)") }
            guard flags & 2 == 0 else { throw DecodeError.unsupported("cube texture") }
            guard flags & 0xF0 == 0 else { throw DecodeError.unsupported("unknown native raster flags") }
            guard raster & 0x6000 == 0 else { throw DecodeError.unsupported("palettized raster; no verified palette fixture") }
            let format = try format(code: d3d)
            guard (flags & 8 != 0) == (format.blockBytes != nil) else { throw DecodeError.malformed("compression flag and D3D format disagree") }
            if format.blockBytes == nil {
                guard Int(depth) == format.bitsPerPixel else { throw DecodeError.malformed("raw pixel depth disagrees with D3D format") }
            } else {
                guard depth == 16 || depth == 32 else { throw DecodeError.unsupported("compressed raster depth \(depth)") }
            }
            var fullMipCount = 1, dimension = max(width, height)
            while dimension > 1 { fullMipCount += 1; dimension /= 2 }
            guard mipCount > 0, mipCount <= fullMipCount else { throw DecodeError.malformed("mip count exceeds complete chain or is zero") }
            guard mipCount <= limits.maximumMipLevels else { throw DecodeError.limitExceeded("mip level count") }
            guard mipCount == 1 || raster & 0x8000 != 0 else { throw DecodeError.malformed("multiple mip records without raster mipmap flag") }
            var offset = start + 88
            var mipLevels: [MipLevel] = []
            var missingTail = false
            for level in 0..<mipCount {
                guard info.body.upperBound - offset >= 4 else { throw DecodeError.malformed("missing mip byte count") }
                let size = Int(u32(offset)); offset += 4
                guard size <= info.body.upperBound - offset else { throw DecodeError.malformed("mip payload exceeds native struct") }
                let w = max(1, width >> level), h = max(1, height >> level)
                if size == 0 {
                    // Original PC dictionaries can omit a rectangular BC tail
                    // once either axis is smaller than one 4x4 block (e.g. 8x2).
                    // Keep it absent; never invent pixels or accept an empty base.
                    guard level > 0, format.blockBytes != nil, (w < 4 || h < 4) else { throw DecodeError.malformed("empty base or non-tail mip") }
                    missingTail = true
                    mipLevels.append(MipLevel(width: w, height: h, encodedByteCount: 0, rgba8: nil, containsTransparentPixels: false))
                    continue
                }
                guard !missingTail else { throw DecodeError.malformed("stored mip after an empty tail mip") }
                guard size == format.encodedSize(width: w, height: h) else { throw DecodeError.malformed("unexpected encoded mip size") }
                let rgbaSize = w * h * 4
                guard rgbaSize <= limits.maximumDecodedBytes - decodedBytes else { throw DecodeError.limitExceeded("total decoded RGBA bytes") }
                decodedBytes += rgbaSize
                let (pixels, transparent) = decodePixels(format, offset: offset, width: w, height: h, count: rgbaSize)
                mipLevels.append(MipLevel(width: w, height: h, encodedByteCount: size, rgba8: pixels, containsTransparentPixels: transparent))
                offset += size
            }
            guard offset == info.body.upperBound else { throw DecodeError.malformed("unexpected trailing native texture bytes") }
            return Texture(name: name, maskName: mask, filterAddressing: u32(start + 4), rasterFormat: raster, d3dFormat: d3d, depth: depth, nativeFlags: flags, mipLevels: mipLevels)
        }

        func name(at offset: Int, emptyAllowed: Bool) throws -> String {
            let end = (offset..<(offset + 32)).first { bytes[$0] == 0 } ?? (offset + 32)
            let name = bytes[offset..<end]
            guard emptyAllowed || !name.isEmpty else { throw DecodeError.malformed("empty texture name") }
            guard name.allSatisfy({ $0 >= 32 && $0 < 127 && $0 != 47 && $0 != 92 }) else {
                throw DecodeError.unsupported("texture names must be printable ASCII without path separators")
            }
            return String(decoding: name, as: UTF8.self)
        }

        func format(code: UInt32) throws -> Format {
            switch code {
            case 0x31545844: return .dxt1
            case 0x33545844: return .dxt3
            case 0x35545844: return .dxt5
            case 21: return .bgra
            case 22: return .bgrx
            case 23: return .rgb565
            case 24: return .xrgb1555
            case 25: return .argb1555
            case 26: return .argb4444
            case 30: return .xrgb4444
            case 50: return .luminance8
            case 28: return .alpha8
            default: throw DecodeError.unsupported("D3D format 0x\(String(code, radix: 16)); no verified decoder")
            }
        }

        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }

        struct Pixel {
            let r: Int, g: Int, b: Int, a: Int
            init(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
            static func mix(_ a: Pixel, _ b: Pixel, _ first: Int, _ second: Int, _ divisor: Int) -> Pixel {
                // Integer BC conversion matches Pillow's independent BC decoder.
                Pixel((a.r * first + b.r * second) / divisor, (a.g * first + b.g * second) / divisor, (a.b * first + b.b * second) / divisor)
            }
        }

        func rgb565(_ value: UInt16) -> Pixel {
            let r = Int(value >> 11), g = Int((value >> 5) & 63), b = Int(value & 31)
            return Pixel((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))
        }

        func decodePixels(_ format: Format, offset: Int, width: Int, height: Int, count: Int) -> (Data, Bool) {
            var output = Data(count: count)
            var transparent = false
            output.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                let out = raw.bindMemory(to: UInt8.self)
                if let blockBytes = format.blockBytes {
                    let blocksWide = (width + 3) / 4, blocksHigh = (height + 3) / 4
                    for by in 0..<blocksHigh {
                        for bx in 0..<blocksWide {
                            let block = offset + (by * blocksWide + bx) * blockBytes
                            let colorStart = block + (blockBytes == 8 ? 0 : 8)
                            let c0 = u16(colorStart), c1 = u16(colorStart + 2)
                            let a = rgb565(c0), b = rgb565(c1)
                            let fourColor = format != .dxt1 || c0 > c1
                            let colors = [a, b, fourColor ? Pixel.mix(a, b, 2, 1, 3) : Pixel.mix(a, b, 1, 1, 2), fourColor ? Pixel.mix(a, b, 1, 2, 3) : Pixel(0, 0, 0, 0)]
                            let colorIndices = u32(colorStart + 4)
                            var alphaValues = [Int](), alphaIndices: UInt64 = 0
                            if format == .dxt5 {
                                let a0 = Int(bytes[block]), a1 = Int(bytes[block + 1])
                                alphaValues = [a0, a1]
                                if a0 > a1 {
                                    for n in 1...6 { alphaValues.append(((7 - n) * a0 + n * a1) / 7) }
                                } else {
                                    for n in 1...4 { alphaValues.append(((5 - n) * a0 + n * a1) / 5) }
                                    alphaValues += [0, 255]
                                }
                                for byte in 0..<6 { alphaIndices |= UInt64(bytes[block + 2 + byte]) << (byte * 8) }
                            }
                            for y in 0..<min(4, height - by * 4) {
                                for x in 0..<min(4, width - bx * 4) {
                                    let pixel = y * 4 + x
                                    let color = colors[Int((colorIndices >> (pixel * 2)) & 3)]
                                    let alpha: Int
                                    if format == .dxt3 {
                                        alpha = Int((bytes[block + pixel / 2] >> ((pixel & 1) * 4)) & 15) * 17
                                    } else if format == .dxt5 {
                                        alpha = alphaValues[Int((alphaIndices >> (pixel * 3)) & 7)]
                                    } else { alpha = color.a }
                                    let destination = ((by * 4 + y) * width + bx * 4 + x) * 4
                                    out[destination] = UInt8(color.r); out[destination + 1] = UInt8(color.g)
                                    out[destination + 2] = UInt8(color.b); out[destination + 3] = UInt8(alpha)
                                    transparent = transparent || alpha != 255
                                }
                            }
                        }
                    }
                } else {
                    for pixel in 0..<(width * height) {
                        let source = offset + pixel * (format.bitsPerPixel / 8)
                        let color: Pixel
                        switch format {
                        case .bgra, .bgrx:
                            color = Pixel(Int(bytes[source + 2]), Int(bytes[source + 1]), Int(bytes[source]), format == .bgrx ? 255 : Int(bytes[source + 3]))
                        case .rgb565:
                            // Raw-format integer expansion follows Pillow's RGB
                            // raw oracle; BC endpoints use bit replication above.
                            let value = u16(source)
                            color = Pixel(Int(value >> 11) * 255 / 31, Int((value >> 5) & 63) * 255 / 63, Int(value & 31) * 255 / 31)
                        case .argb1555, .xrgb1555:
                            let value = u16(source)
                            let r = Int((value >> 10) & 31), g = Int((value >> 5) & 31), b = Int(value & 31)
                            color = Pixel((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2), format == .xrgb1555 || value & 0x8000 != 0 ? 255 : 0)
                        case .argb4444, .xrgb4444:
                            let value = u16(source)
                            color = Pixel(Int((value >> 8) & 15) * 17, Int((value >> 4) & 15) * 17, Int(value & 15) * 17, format == .xrgb4444 ? 255 : Int(value >> 12) * 17)
                        case .luminance8:
                            let value = Int(bytes[source]); color = Pixel(value, value, value)
                        case .alpha8: color = Pixel(255, 255, 255, Int(bytes[source]))
                        default: preconditionFailure("block format reached raw decoder")
                        }
                        let destination = pixel * 4
                        out[destination] = UInt8(color.r); out[destination + 1] = UInt8(color.g)
                        out[destination + 2] = UInt8(color.b); out[destination + 3] = UInt8(color.a)
                        transparent = transparent || color.a != 255
                    }
                }
            }
            return (output, transparent)
        }
    }
}
