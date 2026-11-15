import Foundation

/// Native boarding policy: retain passive solver data while drive controls
/// belong to no seated driver. Camera input remains separately owned.
enum NativeVehicleInputOwnership {
    static func gated(_ input:NativeVehicleDynamics.Input,enabled:Bool)->NativeVehicleDynamics.Input {
        guard !enabled else{return input}
        var value=input
        value.throttle=0;value.steer=0;value.lean=0
        value.pitch=0;value.roll=0;value.yaw=0;value.jets=0
        value.hop=false;value.handbrake=true
        value.accelerate=nil;value.brake=nil;value.pedals=nil
        if value.drive != nil {value.drive = .init(throttle:0,steer:0,handbrake:true)}
        return value
    }
}
