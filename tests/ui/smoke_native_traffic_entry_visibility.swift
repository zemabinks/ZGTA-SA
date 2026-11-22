// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

// Authored positions and capability boundaries around literal controller
// source. These spies do not stand in for real UIKit or server consent.
enum NativeAmbientTrafficScene {
    struct Frame {let id:Int;let body:Body;struct Body {let position:SIMD3<Double>}}
}
struct Vehicle {let position:SIMD3<Float>}
final class Network {var canRequestTrafficVehicle=false;var orderedVehicles:[Vehicle]=[]}
final class Renderer {
    var position=SIMD3<Float>.zero
    var presentedAmbientTraffic:[NativeAmbientTrafficScene.Frame]=[]
    func predictedVehicle(_ v:Vehicle)->Vehicle{v}
}
final class Button {var isHidden=false}
final class Harness {
    let network=Network();var renderer:Renderer?=Renderer();let vehicleButton=Button()
    // ACTUAL_TRAFFIC_CANDIDATE
    func update(climbing:Bool=false,dropping:Bool=false){
        let renderer=renderer!
        // ACTUAL_VISIBILITY
    }
}
@main enum VisibilityTests {
    static var checks=0
    static func check(_ value:Bool,_ text:String){checks+=1;if !value{fputs("FAIL "+text+"\n",stderr);exit(1)}}
    static func frame(_ id:Int,_ position:SIMD3<Double>)->NativeAmbientTrafficScene.Frame{.init(id:id,body:.init(position:position))}
    static func main(){
        let h=Harness();h.update();check(h.vehicleButton.isHidden,"Empty foot context exposes a vehicle")
        h.network.orderedVehicles=[.init(position:SIMD3(2,0,0))];h.update();check(!h.vehicleButton.isHidden,"Existing registered entry disappeared")
        h.network.orderedVehicles=[];h.network.canRequestTrafficVehicle=true
        h.renderer!.presentedAmbientTraffic=[frame(17,SIMD3(2,0,0))];h.update()
        check(!h.vehicleButton.isHidden,"Traffic-only foot target has no touch entry control")
        check(h.nearbyTrafficVehicleForEntry?.id==17,"Displayed traffic target cannot reach the action selector")
        h.network.canRequestTrafficVehicle=false;h.update();check(h.vehicleButton.isHidden,"Unsupported/revoked traffic capability exposes an action")
        check(h.nearbyTrafficVehicleForEntry==nil,"Unsupported traffic reaches the tap selector")
        h.network.canRequestTrafficVehicle=true
        for (gap,visible) in [(0.0,true),(7.999,true),(8.0,true),(8.001,false),(20.0,false)]{
            h.renderer!.presentedAmbientTraffic=[frame(17,SIMD3(gap,0,0))];h.update();check(h.vehicleButton.isHidden != visible,"Traffic reach boundary disagrees with touch action")
        }
        h.renderer!.position=SIMD3(100,200,5);h.renderer!.presentedAmbientTraffic=[frame(80,SIMD3(102,200,5)),frame(2,SIMD3(101,200,5))];h.update()
        check(!h.vehicleButton.isHidden&&h.nearbyTrafficVehicleForEntry?.id==2,"Candidate is not the nearest actual world-space car")
        h.renderer!.presentedAmbientTraffic=[frame(10,SIMD3(.nan,0,0)),frame(11,SIMD3(100,200,6))];h.update()
        check(h.nearbyTrafficVehicleForEntry?.id==11,"Invalid candidate hid a valid nearby traffic car")
        h.renderer!.presentedAmbientTraffic=[frame(10,SIMD3(.infinity,0,0))];h.update();check(h.vehicleButton.isHidden,"Nonfinite traffic exposes an action")
        for enabled in [false,true]{
            h.network.canRequestTrafficVehicle=enabled;h.renderer!.presentedAmbientTraffic=[]
            h.update(climbing:true);check(!h.vehicleButton.isHidden,"Climb release lost its existing control")
            h.update(dropping:true);check(!h.vehicleButton.isHidden,"Jetpack removal lost its existing control")
        }
        h.network.canRequestTrafficVehicle=false;h.network.orderedVehicles=[.init(position:SIMD3(100,200,7))];h.update();check(!h.vehicleButton.isHidden,"Traffic capability broke ordinary registered entry")
        h.renderer=nil;check(h.nearbyTrafficVehicleForEntry==nil,"Missing scene retained a traffic action")
        print("PASS native traffic touch visibility \(checks) checks; literal controller source and authored boundaries, not UIKit, server entry or retail acceptance")
    }
}
