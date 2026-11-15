import Foundation
import simd

@main enum ShotOcclusionSmoke {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks += 1;precondition(condition,message)}
        let start=SIMD3<Float>(-1,-1,14),finish=SIMD3<Float>(1,1,14)
        let cells=NativeShotOcclusion.cells(from:start,to:finish)!
        check(cells.contains("c119") && cells.contains("c136"),"Ray crosses both diagonal city cells")
        check(NativeShotOcclusion.cells(from:finish,to:start)==cells,"Coverage is direction independent")
        for missing in cells {
            var traced=false
            check(!NativeShotOcclusion.clear(from:start,to:finish,loaded:{$0 != missing},trace:{_,_,_ in traced=true;return nil}),"Unloaded crossed cell fails closed")
            check(!traced,"No empty-world visibility inference before collision is ready")
        }
        let world=SwiftRapierWorld(gravity:.zero)!
        func trace(_ origin:SIMD3<Float>,_ direction:SIMD3<Float>,_ distance:Float)->Float? {
            world.raycast(origin:SwiftRapierWorld.gtaToRapier(origin),direction:SwiftRapierWorld.gtaToRapier(direction),distance:distance,groups:0xffff0083)?.distance
        }
        check(NativeShotOcclusion.clear(from:start,to:finish,loaded:{_ in true},trace:trace),"Installed empty cells permit a clear shot")
        let wall=world.addBox(halfExtents:SIMD3(0.1,2,2),position:SwiftRapierWorld.gtaToRapier(SIMD3(0,0,14)))!
        check(!NativeShotOcclusion.clear(from:start,to:finish,loaded:{_ in true},trace:trace),"Native wall blocks the exact muzzle-target segment across cells")
        check(!NativeShotOcclusion.clear(from:finish,to:start,loaded:{_ in true},trace:trace),"Wall also blocks the reverse ray")
        world.removeCollider(wall)
        check(NativeShotOcclusion.clear(from:start,to:finish,loaded:{_ in true},trace:trace),"Removed collision immediately restores visibility")
        for hz in [15,30,60,120] {
            for frame in 0..<hz {
                let y=Float(frame)/Float(hz)*2-1
                let a=SIMD3<Float>(-1,y,14),b=SIMD3<Float>(1,y,15)
                check(NativeShotOcclusion.clear(from:a,to:b,loaded:{_ in true},trace:trace),"Changing aim keeps clear streamed segments valid")
            }
        }
        for bad in [SIMD3<Float>(.nan,0,13),SIMD3<Float>(.infinity,0,13),SIMD3<Float>(3000,0,13)] {
            check(NativeShotOcclusion.cells(from:start,to:bad)==nil,"Invalid/outside world cannot claim loaded geometry")
        }
        check(NativeShotOcclusion.cells(from:start,to:SIMD3(1,1,701))==nil,"Cross-interior shot cannot claim contiguous coverage")
        check(!NativeShotOcclusion.clear(from:start,to:start,loaded:{_ in true},trace:trace),"Zero-length shot rejected")
        check(!NativeShotOcclusion.clear(from:start,to:finish,loaded:{_ in true},trace:{_,_,_ in .nan}),"Invalid physics result fails closed")
        check(NativeShotOcclusion.cells(from:SIMD3(-2999,0,14),to:SIMD3(2999,0,14))?.count==16,"Long segment visits every column")
        print("PASS shot occlusion: \(checks) checks; actual native wall, streamed-cell coverage, missing cells and invalid inputs")
    }
}
