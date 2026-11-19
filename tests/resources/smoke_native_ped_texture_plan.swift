// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

private enum FixtureError:Error {case check(String)}
private var checks=0
private func check(_ value:Bool,_ message:String)throws {checks+=1;if !value{throw FixtureError.check(message)}}
private func rejects(_ message:String,_ action:()throws->Void)throws {
    do {try action();throw FixtureError.check("accepted "+message)}
    catch is NativePedAtlasLayout.Invalid {checks+=1}
}
private func binary(layers:Int,faces:[Int])->Data {
    var data=Data()
    func u32(_ value:UInt32){var value=value.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
    func u16(_ value:UInt16){var value=value.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
    func f32(_ value:Float){u32(value.bitPattern)}
    let vertices=faces.count*3
    for value in [UInt32(0x324c5257),UInt32(vertices),UInt32(vertices),UInt32(layers)]{u32(value)}
    for _ in faces {for point:[Float] in [[-0.8,-0.8,0.5],[0.8,-0.8,0.5],[0,0.8,0.5]]{point.forEach(f32)}}
    for _ in 0..<vertices{f32(0.5);f32(0.5)}
    for index in 0..<vertices{u32(UInt32(index))}
    data.append(Data(repeating:255,count:vertices*4))
    for slot in faces{for _ in 0..<3{u16(UInt16(slot))}}
    if vertices%2 != 0{u16(0)}
    data.append(Data(repeating:128,count:vertices*4));data.append(Data(count:layers*2))
    return data
}
@main private struct TexturePlanSmoke {
    static func main()throws {
        typealias Plan=NativePedAtlasLayout.HardwarePlan
        let world=try WorldBinary(data:binary(layers:2,faces:[0,1,0,1]))
        let rects=[[0,0,1,1],[1,0,2,2]]
        let plan=try Plan(world:world,rects:rects,width:4,height:4,maximumBytes:64)
        try check(plan.groups.count==2 && plan.entries==[SIMD2(0,0),SIMD2(1,0)],"different original dimensions remain separate")
        try check(plan.draws.map(\.group)==[0,1,0,1] && plan.draws.map(\.indexOffset)==[0,3,6,9],"original index order/offsets preserved")
        try check(plan.draws.allSatisfy{$0.indexCount==3} && plan.copiedTexelBytes==20,"exact runs and pixel accounting")
        let same=try Plan(world:world,rects:[[0,0,2,2],[2,0,2,2]],width:4,height:2,maximumBytes:32)
        try check(same.groups.count==1 && same.groups[0].copies.map(\.slot)==[0,1],"matching dimensions share one array")
        try check(same.entries==[SIMD2(0,0),SIMD2(0,1)] && same.draws.count==1 && same.draws[0].indexCount==12,"array slices preserve individual textures without extra group draws")
        let many=try WorldBinary(data:binary(layers:512,faces:[0,255,256,511,0]))
        let small=(0..<512).map{[$0%8,$0/8,1,1]}
        let split=try Plan(world:many,rects:small,width:8,height:64,maximumBytes:2048)
        try check(split.groups.count==2 && split.groups.allSatisfy{$0.copies.count==256},"bounded array slice count")
        try check(split.entries[255]==SIMD2(0,255) && split.entries[256]==SIMD2(1,0) && split.entries[511]==SIMD2(1,255),"slice limit mapping")
        try check(split.draws.map(\.group)==[0,1,0] && split.draws.map(\.indexCount)==[6,6,3],"contiguous group runs preserve repeats")
        try rejects("missing material"){_=try Plan(world:world,rects:Array(rects.prefix(1)),width:4,height:4,maximumBytes:64)}
        try rejects("copy byte budget"){_=try Plan(world:world,rects:rects,width:4,height:4,maximumBytes:19)}
        for bad in [[-1,0,1,1],[0,0,0,1],[3,3,2,2],[Int.max,0,1,1],[0,Int.max,1,1]] {
            try rejects("out-of-bounds rectangle"){_=try Plan(world:world,rects:[bad,rects[1]],width:4,height:4,maximumBytes:64)}
        }
        var mixed=binary(layers:2,faces:[0])
        let slotOffset=16+3*12+3*8+3*4+3*4
        mixed[slotOffset+2]=1
        let ambiguous=try WorldBinary(data:mixed)
        try rejects("mixed material in one triangle"){_=try Plan(world:ambiguous,rects:rects,width:4,height:4,maximumBytes:64)}
        let excessive=try WorldBinary(data:binary(layers:2,faces:(0..<4097).map{$0%2}))
        try rejects("excessive material runs"){_=try Plan(world:excessive,rects:rects,width:4,height:4,maximumBytes:64)}
        print("PASS native texture plan: \(checks) authored grouping, index, slice and bounds checks")
    }
}
