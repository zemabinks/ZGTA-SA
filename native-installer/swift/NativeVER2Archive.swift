// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Inspects an ordinary little-endian VER2 archive through a bounded reader.
/// The scan returns physical directory rows in source order. Duplicate names
/// remain distinct rows, so a caller must resolve ambiguity before using a name.
enum NativeVER2Archive {
    struct Entry: Equatable, Sendable {
        let name: String
        let offset: Int64
        let allocatedBytes: Int64
    }

    enum Failure: LocalizedError, Equatable {
        case archiveSize
        case header
        case shortRead(offset: Int64, expected: Int, actual: Int)
        case entryName(Int)
        case packedEntry(Int)
        case entryRange(Int)
        case overlappingRanges

        var errorDescription: String? {
            switch self {
            case .archiveSize: return "The archive exceeds the size or sector alignment limits."
            case .header: return "The VER2 directory header or entry count is invalid."
            case .shortRead(let offset, let expected, let actual):
                return "The archive read at byte \(offset) returned \(actual) of \(expected) requested bytes."
            case .entryName(let row): return "Archive directory entry \(row) has an invalid name."
            case .packedEntry(let row): return "Archive directory entry \(row) uses an unsupported packed range."
            case .entryRange(let row): return "Archive directory entry \(row) has an invalid sector range."
            case .overlappingRanges: return "Archive directory entries have overlapping sector ranges."
            }
        }
    }

    private static let sectorBytes: Int64 = 2_048
    private static let maximumArchiveBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
    private static let maximumEntries = 100_000
    private static let maximumReadBytes = 1_024 * 1_024
    private static let headerBytes = 8
    private static let entryBytes = 32

    static func scan(byteCount: Int64, read: (Int64, Int) throws -> Data) throws -> [Entry] {
        guard (sectorBytes...maximumArchiveBytes).contains(byteCount),
              byteCount.isMultiple(of: sectorBytes) else { throw Failure.archiveSize }

        func exact(_ offset: Int64, _ count: Int) throws -> Data {
            let data = try read(offset, count)
            guard data.count == count else {
                throw Failure.shortRead(offset: offset, expected: count, actual: data.count)
            }
            return data
        }

        let header = try exact(0, headerBytes)
        let count = try header.withUnsafeBytes { bytes -> Int in
            guard bytes.prefix(4).elementsEqual([0x56, 0x45, 0x52, 0x32]) else { throw Failure.header }
            return Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
        }
        guard count <= maximumEntries else { throw Failure.header }
        let directoryEnd = Int64(headerBytes + count * entryBytes)
        guard directoryEnd <= byteCount else { throw Failure.header }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        let entriesPerRead = maximumReadBytes / entryBytes
        for first in stride(from: 0, to: count, by: entriesPerRead) {
            let rows = min(count - first, entriesPerRead)
            let table = try exact(Int64(headerBytes + first * entryBytes), rows * entryBytes)
            try table.withUnsafeBytes { bytes in
                for index in 0..<rows {
                    let row = first + index + 1
                    let start = index * entryBytes
                    let sector = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: start, as: UInt32.self))
                    let sectors = UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: start + 4, as: UInt16.self))
                    let packed = UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: start + 6, as: UInt16.self))
                    guard packed == 0 else { throw Failure.packedEntry(row) }
                    let offset = Int64(sector) * sectorBytes
                    let allocatedBytes = Int64(sectors) * sectorBytes
                    guard allocatedBytes > 0, offset >= directoryEnd,
                          offset + allocatedBytes <= byteCount else { throw Failure.entryRange(row) }
                    let name = try normalizedName(bytes[(start + 8)..<(start + entryBytes)], row: row)
                    entries.append(Entry(name: name, offset: offset, allocatedBytes: allocatedBytes))
                }
            }
        }

        var previousEnd = directoryEnd
        for entry in entries.sorted(by: { $0.offset < $1.offset }) {
            guard entry.offset >= previousEnd else { throw Failure.overlappingRanges }
            previousEnd = entry.offset + entry.allocatedBytes
        }
        return entries
    }

    private static func normalizedName(_ field: UnsafeRawBufferPointer.SubSequence, row: Int) throws -> String {
        var ascii: [UInt8] = []
        for byte in field.prefix(while: { $0 != 0 }) {
            switch byte {
            case 65...90: ascii.append(byte + 32)
            case 97...122, 48...57, 35, 40, 41, 43, 45, 46, 95: ascii.append(byte)
            default: throw Failure.entryName(row)
            }
        }
        guard !ascii.isEmpty else { throw Failure.entryName(row) }
        return String(decoding: ascii, as: UTF8.self)
    }
}
