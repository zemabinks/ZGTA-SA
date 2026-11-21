// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Verified compact SDRDv1 geometry, separate from original area addresses.
/// Link IDs describe directed navigation edges; they are not pedestrian nodes.
struct NativeAmbientTrafficRoads {
    enum Failure:Error {case malformed,limit,identity,invalidNode,invalidLink}
    let crc32:String
    let nodeCount:Int,linkCount:Int,naviCount:Int
    let linkFrom:[UInt16],linkTo:[UInt16]
    private let positions:[SIMD3<Double>],offsets:[Int],nodeFlags:[UInt32]
    private let navForLink:[Int],navPosition:[SIMD2<Double>],navNode:[UInt16]
    private let navDirection:[SIMD2<Double>],navFlags:[UInt32]
    static let maximumBytes=8*1_048_576

    init(data:Data,expectedCRC:String)throws {
        guard (32...Self.maximumBytes).contains(data.count)else{throw Failure.limit}
        guard expectedCRC.utf8.count==8,expectedCRC.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})else{throw Failure.identity}
        let crc=NativeAmbientPedestrianPaths.crc32(data)
        guard crc==expectedCRC else{throw Failure.identity}
        let bytes=Array(data)
        func u16(_ at:Int)->UInt16{UInt16(bytes[at])|UInt16(bytes[at+1])<<8}
        func u32(_ at:Int)->UInt32{UInt32(bytes[at])|UInt32(bytes[at+1])<<8|UInt32(bytes[at+2])<<16|UInt32(bytes[at+3])<<24}
        guard u32(0)==0x44524453,u32(4)==1 else{throw Failure.malformed}
        let nodes=Int(u32(8)),links=Int(u32(12)),navis=Int(u32(16))
        // The compact traffic channel carries16bit directed-link IDs, with
        //65535 reserved for an absent next edge. Bound every section first.
        guard (1...65535).contains(nodes),(1...65535).contains(links),(1...65535).contains(navis)else{throw Failure.limit}
        var cursor=32
        func section(_ count:Int,_ size:Int)throws->Int {
            let start=cursor;cursor+=count*size
            guard cursor<=bytes.count else{throw Failure.malformed}
            cursor=(cursor+3) & ~3
            guard cursor<=bytes.count else{throw Failure.malformed};return start
        }
        let xyz=try section(nodes*3,2),first=try section(nodes+1,4),flags=try section(nodes,4)
        _=try section(nodes,1) // Unused by the observed graph queries.
        let target=try section(links,4),navi=try section(links,4)
        let xy=try section(navis*2,2),attached=try section(navis,4)
        let direction=try section(navis*2,1),lanes=try section(navis,4)
        guard cursor==bytes.count else{throw Failure.malformed}
        var nodeOffsets:[Int]=[];nodeOffsets.reserveCapacity(nodes+1)
        for node in 0...nodes {
            let value=Int(u32(first+node*4))
            guard value<=links,node==0 ? value==0:value>=nodeOffsets[node-1]else{throw Failure.malformed}
            nodeOffsets.append(value)
        }
        guard nodeOffsets[nodes]==links else{throw Failure.malformed}
        var to:[UInt16]=[],from=Array(repeating:UInt16(0),count:links),navigation:[Int]=[]
        to.reserveCapacity(links);navigation.reserveCapacity(links)
        for link in 0..<links {
            let node=u32(target+link*4),nav=Int(u32(navi+link*4))
            guard node<UInt32(nodes),nav<navis else{throw Failure.invalidLink}
            to.append(UInt16(node));navigation.append(nav)
        }
        for node in 0..<nodes{for link in nodeOffsets[node]..<nodeOffsets[node+1]{from[link]=UInt16(node)}}
        var points:[SIMD3<Double>]=[],attributes:[UInt32]=[]
        for node in 0..<nodes {
            let at=xyz+node*6
            points.append(SIMD3(Double(Int16(bitPattern:u16(at)))/8,Double(Int16(bitPattern:u16(at+2)))/8,Double(Int16(bitPattern:u16(at+4)))/8))
            attributes.append(u32(flags+node*4))
        }
        var navigationPoints:[SIMD2<Double>]=[],navigationNodes:[UInt16]=[]
        var directions:[SIMD2<Double>]=[],laneFlags:[UInt32]=[]
        for nav in 0..<navis {
            let node=u32(attached+nav*4);guard node<UInt32(nodes)else{throw Failure.invalidNode}
            navigationNodes.append(UInt16(node))
            navigationPoints.append(SIMD2(Double(Int16(bitPattern:u16(xy+nav*4)))/8,Double(Int16(bitPattern:u16(xy+nav*4+2)))/8))
            directions.append(SIMD2(Double(Int8(bitPattern:bytes[direction+nav*2]))/100,Double(Int8(bitPattern:bytes[direction+nav*2+1]))/100))
            laneFlags.append(u32(lanes+nav*4))
        }
        crc32=crc;nodeCount=nodes;linkCount=links;naviCount=navis
        linkFrom=from;linkTo=to;positions=points;offsets=nodeOffsets;nodeFlags=attributes
        navForLink=navigation;navPosition=navigationPoints;navNode=navigationNodes
        navDirection=directions;navFlags=laneFlags
    }
    func point(_ node:UInt16)throws->SIMD3<Double> {
        guard Int(node)<nodeCount else{throw Failure.invalidNode};return positions[Int(node)]
    }
    func links(from node:UInt16)throws->Range<Int> {
        guard Int(node)<nodeCount else{throw Failure.invalidNode};return offsets[Int(node)]..<offsets[Int(node)+1]
    }
    func speedClass(_ node:UInt16)throws->UInt8 {
        guard Int(node)<nodeCount else{throw Failure.invalidNode};return UInt8(nodeFlags[Int(node)]>>12&3)
    }
    private func navigation(_ link:UInt16)throws->(Int,Bool) {
        guard Int(link)<linkCount else{throw Failure.invalidLink}
        let nav=navForLink[Int(link)];return(nav,navNode[nav]==linkTo[Int(link)])
    }
    /// Position and tangent remain GTA XY. The renderer owns Y-up conversion.
    func lanePoint(_ link:UInt16,lane:UInt8)throws->(position:SIMD2<Double>,direction:SIMD2<Double>) {
        let (nav,forward)=try navigation(link),flags=navFlags[nav]
        let fieldA=Double(flags>>8&7),fieldB=Double(flags>>11&7)
        let base=fieldA==0 ? 0.5-fieldB/2:fieldB==0 ? 0.5-fieldA/2:0.5+Double(flags&255)/16/5.4
        let offset=(Double(lane)+base)*5.4,direction=navDirection[nav]*(forward ? 1.0:-1.0)
        return(navPosition[nav]+SIMD2(direction.y,-direction.x)*offset,direction)
    }
    func against(_ link:UInt16)throws->Bool {
        let (nav,forward)=try navigation(link),flags=navFlags[nav]
        let fieldA=flags>>8&7,fieldB=flags>>11&7
        return forward ? fieldA==0 && fieldB>0:fieldB==0 && fieldA>0
    }
    func height(from first:UInt16,to second:UInt16,progress:Double)throws->Double {
        guard Int(first)<linkCount,Int(second)<linkCount,progress.isFinite,(0...1).contains(progress)else{throw Failure.invalidLink}
        let center=positions[Int(linkTo[Int(first)])].z
        if progress<0.5 {
            let start=(positions[Int(linkFrom[Int(first)])].z+center)/2
            return start+(center-start)*progress*2
        }
        let end=(center+positions[Int(linkTo[Int(second)])].z)/2
        return center+(end-center)*(progress-0.5)*2
    }
}
