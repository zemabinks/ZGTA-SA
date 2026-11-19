// SPDX-License-Identifier: AGPL-3.0-only
// Independently authored DAT fixtures; no original resource bytes.
import Foundation

@main
struct NativeOriginalPathQueryTests {
    typealias Area = NativeOriginalPathArea
    typealias Graph = NativeOriginalPathGraph
    typealias Address = NativeOriginalPathAddress
    typealias Failure = NativeOriginalPathFailure

    static func put16(_ data: inout Data, _ at: Int, _ value: UInt16) {
        data[at] = UInt8(truncatingIfNeeded: value)
        data[at + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    static func put32(_ data: inout Data, _ at: Int, _ value: UInt32) {
        for i in 0..<4 { data[at + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }
    static func append16(_ data: inout Data, _ value: UInt16) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }
    static func fixture(area: UInt16 = 0, vehicles: UInt32 = 0) -> Data {
        var data = Data(count: 20)
        for (index, count) in [UInt32(2), vehicles, 2 - vehicles, 1, 2].enumerated() {
            put32(&data, index * 4, count)
        }
        for index in 0..<2 {
            var node = Data(count: 28)
            put16(&node, 8, UInt16(index * 8)); put16(&node, 10, 16)
            put16(&node, 12, UInt16(bitPattern: -8)); put16(&node, 14, 32766)
            put16(&node, 16, UInt16(index)); put16(&node, 18, area); put16(&node, 20, UInt16(index))
            node[22] = 4; node[23] = 1; put32(&node, 24, 1)
            data.append(node)
        }
        var navi = Data(count: 14)
        put16(&navi, 0, 4); put16(&navi, 2, 16); put16(&navi, 4, area)
        navi[8] = 100; put32(&navi, 10, (2 << 8) | (1 << 11) | (2 << 16))
        data.append(navi)
        append16(&data, area); append16(&data, 1)
        append16(&data, area); append16(&data, 0)
        data.append(Data(count: 192 * 4))
        append16(&data, area << 10); append16(&data, area << 10)
        data.append(contentsOf: [2, 2]); data.append(Data(count: 192))
        data.append(contentsOf: [1, 3]); data.append(Data(count: 192))
        return data
    }
    static func expectFailure(_ label: String, expected: Failure? = nil, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: \(label)") }
        catch {
            if let expected { precondition((error as? Failure) == expected, "Wrong rejection: \(label): \(error)") }
        }
    }
    static func main() throws {
        let data = fixture(), area = try Area(data: data, expectedArea: 0)
        precondition(area.pedCount == 2 && area.vehicleCount == 0)
        precondition(area.nodes[1].position == SIMD3<Double>(1, 2, -1))
        precondition(area.links.map(\.intersectionRaw) == [1, 3]) // Catches a missing 192-byte length reserve.
        precondition(area.links[0].target == Address(area: 0, node: 1))
        precondition(area.nodes[1].kind == .ped && area.nodes[1].widthRaw == 4)
        let empty = try Area(data: Data(count: 20), expectedArea: 1)
        precondition(empty.nodes.isEmpty && empty.links.isEmpty)

        expectFailure("short header") { _ = try Area(data: Data(count: 19), expectedArea: 0) }
        expectFailure("truncated section") { _ = try Area(data: Data(data.dropLast()), expectedArea: 0) }
        expectFailure("unexpected suffix") { _ = try Area(data: data + Data([0]), expectedArea: 0) }
        expectFailure("unsupported area") { _ = try Area(data: data, expectedArea: 64) }
        expectFailure("byte ceiling") { _ = try Area(data: Data(count: Area.maximumBytes + 1), expectedArea: 0) }
        for (offset, value) in [(0, UInt32.max), (0, UInt32(3)), (12, UInt32(1025))] {
            var malformed = data; put32(&malformed, offset, value)
            expectFailure("bad header count") { _ = try Area(data: malformed, expectedArea: 0) }
        }
        for (offset, value) in [(20 + 18, UInt16(1)), (20 + 20, UInt16(7)), (20 + 16, UInt16(2))] {
            var malformed = data; put16(&malformed, offset, value)
            expectFailure("bad node identity/range") { _ = try Area(data: malformed, expectedArea: 0) }
        }

        let graph = try Graph(areas: [area]), start = Address(area: 0, node: 0), goal = Address(area: 0, node: 1)
        let nearest = try graph.nearest(to: SIMD3<Double>(0, 2, -1), kind: .ped, maximumDistance: 1)
        precondition(nearest?.address == start)
        let absent = try graph.nearest(to: SIMD3<Double>(0, 200, 0), kind: .ped, maximumDistance: 1)
        precondition(absent == nil)
        let route = try graph.route(from: start, to: goal, kind: .ped)
        precondition(route?.addresses == [start, goal])
        let links = try graph.resolvedLinks(from: start)
        precondition(links.count == 1 && links[0].target.address == goal && links[0].navi == nil)
        expectFailure("duplicate area") { _ = try Graph(areas: [area, area]) }
        expectFailure("wrong route kind", expected: .kindMismatch) { _ = try graph.route(from: start, to: goal, kind: .vehicle) }
        expectFailure("nearest work ceiling", expected: .queryBudget) {
            _ = try graph.nearest(to: .zero, kind: .ped, maximumDistance: 100, maximumScannedNodes: 1)
        }
        expectFailure("nonfinite nearest point", expected: .queryBudget) {
            _ = try graph.nearest(to: SIMD3<Double>(.nan, 0, 0), kind: .ped, maximumDistance: 100)
        }
        expectFailure("invalid route budget", expected: .queryBudget) {
            _ = try graph.route(from: start, to: goal, kind: .ped, maximumExpandedNodes: 0)
        }
        expectFailure("return length ceiling", expected: .queryBudget) {
            _ = try graph.route(from: start, to: goal, kind: .ped, maximumReturnedNodes: 1)
        }
        let addressOffset = 20 + 2 * 28 + 14
        var outside = data; put16(&outside, addressOffset, 1)
        let outsideArea = try Area(data: outside, expectedArea: 0), incomplete = try Graph(areas: [outsideArea])
        expectFailure("unloaded link is not skipped", expected: .unloadedArea(1)) { _ = try incomplete.resolvedLinks(from: start) }
        let otherArea = try Area(data: fixture(area: 1), expectedArea: 1)
        let complete = try Graph(areas: [outsideArea, otherArea])
        let crossArea = try complete.resolvedLinks(from: start)
        precondition(crossArea[0].target.address == Address(area: 1, node: 1))
        var badTarget = data; put16(&badTarget, addressOffset + 2, 99)
        let badArea = try Area(data: badTarget, expectedArea: 0), badGraph = try Graph(areas: [badArea])
        expectFailure("node reference bound", expected: .invalidAddress(0, 99)) { _ = try badGraph.resolvedLinks(from: start) }

        let cars = try Area(data: fixture(vehicles: 2), expectedArea: 0), carGraph = try Graph(areas: [cars])
        let carLinks = try carGraph.resolvedLinks(from: start)
        precondition(carLinks[0].navi?.leftLanes == 2 && carLinks[0].navi?.rightLanes == 1)
        precondition(carLinks[0].navi?.signalCycleRaw == 2 && carLinks[0].original.crossesRoad)
        var badNavi = fixture(vehicles: 2)
        let naviLinkOffset = addressOffset + (2 + 192) * 4
        put16(&badNavi, naviLinkOffset, 1)
        let badNaviArea = try Area(data: badNavi, expectedArea: 0), badNaviGraph = try Graph(areas: [badNaviArea])
        expectFailure("navi reference bound") { _ = try badNaviGraph.resolvedLinks(from: start) }
        print("PASS authored native path decoding/query checks; original AI remains separate.")
    }
}
