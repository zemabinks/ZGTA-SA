// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// The verified compact pedestrian graph shared with the browser. This is a
/// resource/query owner, separate from raw original area addresses and NPC AI.
struct NativeAmbientPedestrianPaths {
    enum Failure:Error {case malformed,limit,identity,invalidNode,queryBudget}
    struct Link:Equatable {
        let id:UInt16,kind:UInt8
        var crossesRoad:Bool{kind&1 != 0}
        var hasPedSignal:Bool{kind&2 != 0}
    }
    struct Nearest:Equatable {let id:UInt16,distance:Double}
    private struct Cell:Hashable {let x:Int,y:Int}
    let crc32:String
    let nodeCount:Int,linkCount:Int
    private let positions:[SIMD3<Double>],offsets:[Int],targets:[UInt16],kinds:[UInt8],widths:[UInt8]
    private let cells:[Cell:[UInt16]]
    static let maximumBytes=3*1_048_576

    static func crc32(_ data:Data)->String {
        var crc:UInt32=0xffffffff
        for value in data {
            crc ^= UInt32(value)
            for _ in 0..<8 {crc=(crc>>1)^((crc&1) != 0 ? 0xedb88320:0)}
        }
        return String(format:"%08x",crc^0xffffffff)
    }
    init(data:Data,expectedCRC:String)throws {
        guard (32...Self.maximumBytes).contains(data.count)else{throw Failure.limit}
        guard expectedCRC.utf8.count==8,expectedCRC.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})else{throw Failure.identity}
        let crc=Self.crc32(data)
        guard crc==expectedCRC else{throw Failure.identity}
        let bytes=Array(data)
        func u16(_ at:Int)->UInt16{UInt16(bytes[at])|UInt16(bytes[at+1])<<8}
        func u32(_ at:Int)->UInt32{UInt32(bytes[at])|UInt32(bytes[at+1])<<8|UInt32(bytes[at+2])<<16|UInt32(bytes[at+3])<<24}
        guard u32(0)==0x44504453,u32(4)==1 else{throw Failure.malformed}
        let nodes=Int(u32(8)),links=Int(u32(12))
        guard (1...65535).contains(nodes),links<=300000 else{throw Failure.limit}
        var cursor=32
        func section(_ count:Int,_ size:Int)throws->Int {
            let start=cursor;cursor+=count*size
            guard cursor<=bytes.count else{throw Failure.malformed}
            cursor = (cursor+3) & ~3
            guard cursor<=bytes.count else{throw Failure.malformed}
            return start
        }
        let xyz=try section(nodes*3,2),first=try section(nodes+1,4)
        _=try section(nodes,1) // No semantic use established for this byte.
        let width=try section(nodes,1),target=try section(links,2),kind=try section(links,1)
        guard cursor==bytes.count else{throw Failure.malformed}
        var nodeOffsets:[Int]=[];nodeOffsets.reserveCapacity(nodes+1)
        for id in 0...nodes {
            let value=Int(u32(first+id*4))
            guard value<=links,id==0 ? value==0:value>=nodeOffsets[id-1] && value-nodeOffsets[id-1]<=15 else{throw Failure.malformed}
            nodeOffsets.append(value)
        }
        guard nodeOffsets[nodes]==links else{throw Failure.malformed}
        var nodeTargets:[UInt16]=[];nodeTargets.reserveCapacity(links)
        for index in 0..<links {
            let id=u16(target+index*2)
            guard Int(id)<nodes else{throw Failure.invalidNode}
            nodeTargets.append(id)
        }
        var points:[SIMD3<Double>]=[];points.reserveCapacity(nodes)
        var grid:[Cell:[UInt16]]=[:]
        for id in 0..<nodes {
            let at=xyz+id*6
            let point=SIMD3(Double(Int16(bitPattern:u16(at)))/8,Double(Int16(bitPattern:u16(at+2)))/8,Double(Int16(bitPattern:u16(at+4)))/8)
            points.append(point);grid[Cell(x:Int(floor(point.x/64)),y:Int(floor(point.y/64))),default:[]].append(UInt16(id))
        }
        crc32=crc;nodeCount=nodes;linkCount=links;positions=points;offsets=nodeOffsets;targets=nodeTargets
        kinds=Array(bytes[kind..<kind+links]);widths=Array(bytes[width..<width+nodes]);cells=grid
    }
    func point(_ id:UInt16)throws->SIMD3<Double> {
        guard Int(id)<nodeCount else{throw Failure.invalidNode};return positions[Int(id)]
    }
    func widthRaw(_ id:UInt16)throws->UInt8 {
        guard Int(id)<nodeCount else{throw Failure.invalidNode};return widths[Int(id)]
    }
    func place(_ id:UInt16,seed:UInt8)throws->SIMD3<Double> {
        var result=try point(id)
        let width=Double(try widthRaw(id))*0.00775
        result.x+=width*Double(Int(seed&15)-7)
        result.y+=width*Double(Int(seed>>4)-7)
        return result
    }
    func neighbors(_ id:UInt16)throws->[Link] {
        guard Int(id)<nodeCount else{throw Failure.invalidNode}
        return (offsets[Int(id)]..<offsets[Int(id)+1]).map{.init(id:targets[$0],kind:kinds[$0])}
    }
    func nearest(to point:SIMD3<Double>,radius:Double,maximumScannedNodes:Int=100000)throws->Nearest? {
        guard point.x.isFinite,point.y.isFinite,point.z.isFinite,radius.isFinite,radius>0,radius<=500,
              (1...100000).contains(maximumScannedNodes),abs(point.x)<=1_000_000,abs(point.y)<=1_000_000 else{throw Failure.queryBudget}
        var result:Nearest?,best=radius*radius,scanned=0
        for x in Int(floor((point.x-radius)/64))...Int(floor((point.x+radius)/64)) {
            for y in Int(floor((point.y-radius)/64))...Int(floor((point.y+radius)/64)) {
                for id in cells[Cell(x:x,y:y)] ?? [] {
                    scanned+=1;guard scanned<=maximumScannedNodes else{throw Failure.queryBudget}
                    let delta=positions[Int(id)]-point,distance=simd_dot(delta,delta)
                    if distance<best || distance==best && (result==nil || id<result!.id) {
                        best=distance;result = .init(id:id,distance:sqrt(distance))
                    }
                }
            }
        }
        return result
    }
}
