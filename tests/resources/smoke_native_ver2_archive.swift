// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

@main private enum ArchiveCheck {
    typealias Archive = NativeVER2Archive

    static func main() throws {
        let rows: [(UInt32, UInt16, UInt16, String)] = [
            (3, 1, 0, "SHAPE.BIN"), (1, 2, 0, "Cloth.ABC"), (4, 1, 0, "shape.bin")
        ]
        let table = fixture(rows)
        var requests: [Range<Int64>] = []
        let entries = try Archive.scan(byteCount: 5 * 2048) { offset, count in
            requests.append(offset..<(offset + Int64(count)))
            return table.subdata(in: Int(offset)..<(Int(offset) + count))
        }
        precondition(requests == [0..<8, 8..<104])
        precondition(entries.map(\.name) == ["shape.bin", "cloth.abc", "shape.bin"])
        precondition(entries.map(\.offset) == [6144, 2048, 8192])
        precondition(entries.map(\.allocatedBytes) == [2048, 4096, 2048])

        rejects(fixture([(1, 1, 0, "bad/name")]), .entryName(1))
        rejects(fixture([(1, 1, 1, "packed")]), .packedEntry(1))
        rejects(fixture([(1, 0, 0, "empty")]), .entryRange(1))
        rejects(fixture([(0, 1, 0, "directory")]), .entryRange(1))
        rejects(fixture([(5, 1, 0, "outside")]), .entryRange(1))
        rejects(fixture([(1, 2, 0, "a"), (2, 1, 0, "b")]), .overlappingRanges)
        rejects(Data(table.dropLast()), .shortRead(offset: 8, expected: 96, actual: 95))
        rejects(Data(repeating: 0, count: 8), .header)
        rejects(Data([0x56, 0x45, 0x52, 0x32, 0xff, 0xff, 0xff, 0xff]), .header)

        let count = 32_769
        let firstSector: UInt32 = 513
        let largeTable = fixture((0..<count).map { (firstSector + UInt32($0), 1, 0, "entry") })
        var readSizes: [Int] = []
        let scanned = try Archive.scan(byteCount: Int64(firstSector + UInt32(count)) * 2048) { offset, bytes in
            readSizes.append(bytes)
            return largeTable.subdata(in: Int(offset)..<(Int(offset) + bytes))
        }
        precondition(scanned.count == count && readSizes == [8, 1_048_576, 32])
        print("PASS VER2 names, physical order, bounds, exact reads, and directory-only chunking")

        if CommandLine.arguments.count == 2 {
            try inspect(URL(fileURLWithPath: CommandLine.arguments[1]))
        }
    }

    private static func fixture(_ entries: [(UInt32, UInt16, UInt16, String)]) -> Data {
        var data = Data("VER2".utf8)
        append(UInt32(entries.count), to: &data)
        for (sector, size, packed, name) in entries {
            append(sector, to: &data)
            append(size, to: &data)
            append(packed, to: &data)
            data.append(contentsOf: name.utf8)
            data.append(Data(repeating: 0, count: 24 - name.utf8.count))
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func rejects(_ data: Data, _ reason: Archive.Failure) {
        do {
            _ = try Archive.scan(byteCount: 5 * 2048) { offset, count in
                let start = Int(offset)
                return data.subdata(in: start..<min(start + count, data.count))
            }
            preconditionFailure("Invalid archive was accepted")
        } catch {
            precondition(error as? Archive.Failure == reason, "Wrong refusal: \(error)")
        }
    }

    private static func inspect(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let byteCount = Int64(try handle.seekToEnd())
        var bytesRead = 0
        let entries = try Archive.scan(byteCount: byteCount) { offset, count in
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: count) ?? Data()
            bytesRead += data.count
            return data
        }
        var rows = SHA256()
        for entry in entries {
            rows.update(data: Data("\(entry.name)\t\(entry.offset)\t\(entry.allocatedBytes)\n".utf8))
        }
        precondition(bytesRead == 8 + 32 * entries.count)
        let digest = rows.finalize().map { String(format: "%02x", $0) }.joined()
        print("ARCHIVE rows=\(entries.count) directoryBytes=\(bytesRead) rowsSHA256=\(digest)")
    }
}
