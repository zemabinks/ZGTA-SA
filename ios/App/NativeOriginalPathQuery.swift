// SPDX-License-Identifier: AGPL-3.0-only
// Native exterior SA DAT profile only; no game bytes, original AI or spawning.
import Foundation

enum NativeOriginalPathFailure: Error, Equatable {
    case malformed(String)
    case unloadedArea(UInt16)
    case invalidAddress(UInt16, UInt16)
    case kindMismatch
    case queryBudget
}

struct NativeOriginalPathAddress: Hashable, Comparable, Sendable {
    let area: UInt16
    let node: UInt16
    static func < (a: Self, b: Self) -> Bool {
        a.area == b.area ? a.node < b.node : a.area < b.area
    }
}

struct NativeOriginalPathArea: Sendable {
    enum Kind: Equatable, Sendable { case vehicle, ped }
    struct Node: Sendable {
        let address: NativeOriginalPathAddress
        let kind: Kind
        let position: SIMD3<Double>
        let firstLink: Int
        let linkCount: Int
        let widthRaw: UInt8
        let floodRaw: UInt8
        let flagsRaw: UInt32
    }
    struct NaviAddress: Sendable {
        let packed: UInt16
        var area: UInt16 { packed >> 10 }
        var index: Int { Int(packed & 1023) }
    }
    struct Navi: Sendable {
        let position: SIMD2<Double>
        let target: NativeOriginalPathAddress
        let direction: SIMD2<Double>
        let flagsRaw: UInt32
        var leftLanes: Int { Int((flagsRaw >> 8) & 7) }
        var rightLanes: Int { Int((flagsRaw >> 11) & 7) }
        var signalCycleRaw: Int { Int((flagsRaw >> 16) & 3) }
    }
    struct Link: Sendable {
        let target: NativeOriginalPathAddress
        let navi: NaviAddress
        let lengthRaw: UInt8
        let intersectionRaw: UInt8
        var crossesRoad: Bool { intersectionRaw & 1 != 0 }
        var hasPedSignal: Bool { intersectionRaw & 2 != 0 }
    }
    let area: UInt16
    let vehicleCount: Int
    let pedCount: Int
    let nodes: [Node]
    let naviNodes: [Navi]
    let links: [Link]

    // This bound matches NativeRawResourceLease.maximumReadBytes. Acquire a
    // source/content/generation-bound lease before decoding; this pure parser
    // neither opens a path nor verifies provenance/receipt hashes itself.
    static let maximumBytes = 1_048_576
    static let maximumRecords = 65_535

    init(data: Data, expectedArea: UInt16) throws {
        guard expectedArea < 64, (20...Self.maximumBytes).contains(data.count) else {
            throw NativeOriginalPathFailure.malformed("area or byte limit")
        }
        let b = Array(data) // Normalizes Data slice indices; bounded to 1 MiB.
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        func i16(_ i: Int) -> Int16 { Int16(bitPattern: u16(i)) }
        func u32(_ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
        let counts = stride(from: 0, to: 20, by: 4).map { Int(u32($0)) }
        guard counts.allSatisfy({ $0 <= Self.maximumRecords }), counts[3] <= 1024,
              counts[0] == counts[1] + counts[2] else {
            throw NativeOriginalPathFailure.malformed("native header counts")
        }
        let total = counts[0], vehicles = counts[1], peds = counts[2], navis = counts[3], addresses = counts[4]
        let reserve = addresses > 0 ? 192 : 0
        let naviOffset = 20 + total * 28
        let addressOffset = naviOffset + navis * 14
        let packedOffset = addressOffset + (addresses + reserve) * 4
        let lengthOffset = packedOffset + addresses * 2
        let intersectionOffset = lengthOffset + addresses + reserve
        let end = intersectionOffset + addresses + reserve
        guard end == b.count else { throw NativeOriginalPathFailure.malformed("native section length") }
        // Every read below is within one prevalidated fixed-stride section.
        var decodedNodes: [Node] = []; decodedNodes.reserveCapacity(total)
        for index in 0..<total {
            let at = 20 + index * 28, first = Int(u16(at + 16)), flags = u32(at + 24)
            let degree = Int(flags & 15), fileArea = u16(at + 18), fileIndex = u16(at + 20)
            guard fileArea == expectedArea, Int(fileIndex) == index, first + degree <= addresses else {
                throw NativeOriginalPathFailure.malformed("node identity or adjacency range")
            }
            decodedNodes.append(Node(address: .init(area: fileArea, node: fileIndex),
                                     kind: index < vehicles ? .vehicle : .ped,
                                     position: SIMD3(Double(i16(at + 8)) / 8, Double(i16(at + 10)) / 8, Double(i16(at + 12)) / 8),
                                     firstLink: first, linkCount: degree, widthRaw: b[at + 22],
                                     floodRaw: b[at + 23], flagsRaw: flags))
        }
        var decodedNavi: [Navi] = []; decodedNavi.reserveCapacity(navis)
        for index in 0..<navis {
            let at = naviOffset + index * 14
            decodedNavi.append(Navi(position: SIMD2(Double(i16(at)) / 8, Double(i16(at + 2)) / 8),
                                   target: .init(area: u16(at + 4), node: u16(at + 6)),
                                   direction: SIMD2(Double(Int8(bitPattern: b[at + 8])) / 100,
                                                    Double(Int8(bitPattern: b[at + 9])) / 100),
                                   flagsRaw: u32(at + 10)))
        }
        var decodedLinks: [Link] = []; decodedLinks.reserveCapacity(addresses)
        for index in 0..<addresses {
            let at = addressOffset + index * 4
            decodedLinks.append(Link(target: .init(area: u16(at), node: u16(at + 2)),
                                     navi: .init(packed: u16(packedOffset + index * 2)),
                                     lengthRaw: b[lengthOffset + index], intersectionRaw: b[intersectionOffset + index]))
        }
        area = expectedArea; vehicleCount = vehicles; pedCount = peds
        nodes = decodedNodes; naviNodes = decodedNavi; links = decodedLinks
    }
}

struct NativeOriginalPathGraph: Sendable {
    typealias Address = NativeOriginalPathAddress
    typealias Area = NativeOriginalPathArea
    struct Edge: Sendable {
        let target: Area.Node
        let original: Area.Link
        let navi: Area.Navi?
    }
    struct Nearest: Sendable { let address: Address; let distance: Double }
    struct Route: Sendable {
        let addresses: [Address]
        let distance: Double
        let expandedNodes: Int
    }
    private let areas: [UInt16: Area]
    var loadedAreas: [UInt16] { areas.keys.sorted() }

    init(areas: [Area]) throws {
        guard areas.count <= 64 else { throw NativeOriginalPathFailure.malformed("area count") }
        var index: [UInt16: Area] = [:]
        for area in areas {
            guard index.updateValue(area, forKey: area.area) == nil else {
                throw NativeOriginalPathFailure.malformed("duplicate area")
            }
        }
        self.areas = index
    }
    func node(_ address: Address) throws -> Area.Node {
        guard address.area < 64 else { throw NativeOriginalPathFailure.invalidAddress(address.area, address.node) }
        guard let area = areas[address.area] else { throw NativeOriginalPathFailure.unloadedArea(address.area) }
        guard Int(address.node) < area.nodes.count else { throw NativeOriginalPathFailure.invalidAddress(address.area, address.node) }
        return area.nodes[Int(address.node)]
    }
    func resolvedLinks(from address: Address) throws -> [Edge] {
        let node = try node(address), area = areas[address.area]!
        return try (node.firstLink..<(node.firstLink + node.linkCount)).map { index in
            let link = area.links[index], target = try self.node(link.target)
            guard target.kind == node.kind else { throw NativeOriginalPathFailure.kindMismatch }
            var navi: Area.Navi?
            if node.kind == .vehicle {
                guard let naviArea = areas[link.navi.area] else { throw NativeOriginalPathFailure.unloadedArea(link.navi.area) }
                guard link.navi.index < naviArea.naviNodes.count else {
                    throw NativeOriginalPathFailure.malformed("navi reference outside loaded table")
                }
                navi = naviArea.naviNodes[link.navi.index]
            }
            return Edge(target: target, original: link, navi: navi)
        }
    }
    private static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }

    // Nearest within the explicitly loaded graph. This does not assert that
    // all geographic areas touching the query radius have been loaded.
    func nearest(to position: SIMD3<Double>, kind: Area.Kind, maximumDistance: Double,
                 maximumScannedNodes: Int = 100_000) throws -> Nearest? {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              maximumDistance.isFinite, maximumDistance > 0, maximumDistance <= 1000,
              (1...100_000).contains(maximumScannedNodes) else { throw NativeOriginalPathFailure.queryBudget }
        var best: Nearest?, scanned = 0
        for area in loadedAreas {
            for node in areas[area]!.nodes where node.kind == kind {
                scanned += 1
                guard scanned <= maximumScannedNodes else { throw NativeOriginalPathFailure.queryBudget }
                let distance = Self.distance(position, node.position)
                if distance <= maximumDistance, best == nil || distance < best!.distance {
                    best = Nearest(address: node.address, distance: distance)
                }
            }
        }
        return best
    }

    // Independent A* using geometric edge costs, not original GTA route
    // selection. Missing linked areas throw; they are never silently skipped.
    // No spawning restrictions, dynamic node switches, steering or AI behavior.
    func route(from start: Address, to goal: Address, kind: Area.Kind,
               maximumExpandedNodes: Int = 4096, maximumReturnedNodes: Int = 2048) throws -> Route? {
        guard (1...50_000).contains(maximumExpandedNodes), (1...50_000).contains(maximumReturnedNodes) else {
            throw NativeOriginalPathFailure.queryBudget
        }
        let source = try node(start), target = try node(goal)
        guard source.kind == kind, target.kind == kind else { throw NativeOriginalPathFailure.kindMismatch }
        var heap = PathHeap(), costs: [Address: Double] = [start: 0], previous: [Address: Address] = [:], expanded = 0
        heap.push(.init(priority: Self.distance(source.position, target.position), cost: 0, address: start))
        while let item = heap.pop() {
            guard costs[item.address] == item.cost else { continue }
            if item.address == goal {
                var path = [goal]
                while path.last! != start {
                    guard path.count < maximumReturnedNodes, let before = previous[path.last!] else {
                        throw NativeOriginalPathFailure.queryBudget
                    }
                    path.append(before)
                }
                return Route(addresses: Array(path.reversed()), distance: item.cost, expandedNodes: expanded)
            }
            guard expanded < maximumExpandedNodes else { throw NativeOriginalPathFailure.queryBudget }
            expanded += 1
            let current = try node(item.address)
            for edge in try resolvedLinks(from: item.address) {
                let cost = item.cost + max(0.001, Self.distance(current.position, edge.target.position))
                if cost >= costs[edge.target.address, default: .infinity] { continue }
                costs[edge.target.address] = cost; previous[edge.target.address] = item.address
                heap.push(.init(priority: cost + Self.distance(edge.target.position, target.position), cost: cost, address: edge.target.address))
            }
        }
        return nil // Unreachable in the loaded graph; no linked area was omitted.
    }
}

private struct PathHeap {
    struct Item {
        let priority: Double
        let cost: Double
        let address: NativeOriginalPathAddress
        func before(_ other: Self) -> Bool {
            priority == other.priority ? address < other.address : priority < other.priority
        }
    }
    private var values: [Item] = []
    mutating func push(_ item: Item) {
        values.append(item); var index = values.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard values[index].before(values[parent]) else { break }
            values.swapAt(index, parent); index = parent
        }
    }
    mutating func pop() -> Item? {
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return values.removeLast() }
        let result = values[0], last = values.removeLast(); values[0] = last; var index = 0
        while index * 2 + 1 < values.count {
            let left = index * 2 + 1, right = left + 1
            let child = right < values.count && values[right].before(values[left]) ? right : left
            guard values[child].before(values[index]) else { break }
            values.swapAt(index, child); index = child
        }
        return result
    }
}
