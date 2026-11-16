// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// The native/browser vehicle body is below its authored model origin by the
/// prepared DFF offset. Legacy positions address that model origin. Apply the
/// offset in the complete vehicle rotation, once at the protocol boundary.
/// Metadata is owner-generated; no original model data is embedded here.
struct NativeSAMPVehicleCoordinates {
    enum Failure:Error{case metadata,missingModel(Int),invalidPose}
    private let origins:[Int:Float]
    init(metadata:Data)throws {
        guard metadata.count<=32*1024*1024,
              let document=try JSONSerialization.jsonObject(with:metadata)as?[String:Any],
              let models=document["models"]as?[String:[String:Any]],!models.isEmpty,models.count<=4096 else{throw Failure.metadata}
        var values:[Int:Float]=[:]
        for(key,row)in models {
            guard let id=Int(key),(400...611).contains(id),key==String(id),
                  let origin=row["origin"]as?NSNumber,CFGetTypeID(origin) != CFBooleanGetTypeID(),
                  origin.doubleValue.isFinite,abs(origin.doubleValue)<=100 else{throw Failure.metadata}
            values[id]=origin.floatValue
        }
        origins=values
    }
    var count:Int{origins.count}
    func offset(model:Int,rotation:SIMD4<Float>)throws->SIMD3<Float> {
        guard let origin=origins[model]else{throw Failure.missingModel(model)}
        guard rotation.x.isFinite,rotation.y.isFinite,rotation.z.isFinite,rotation.w.isFinite else{throw Failure.invalidPose}
        let q=simd_quatd(ix:Double(rotation.y),iy:Double(rotation.z),iz:Double(rotation.w),r:Double(rotation.x))
        let n=simd_length_squared(q.vector)
        guard n.isFinite,n>0.000001 else{throw Failure.invalidPose}
        return SIMD3<Float>(simd_quatd(vector:q.vector/sqrt(n)).act(SIMD3(0,0,Double(origin))))
    }
    func body(_ modelOrigin:SIMD3<Float>,model:Int,rotation:SIMD4<Float>)throws->SIMD3<Float> {
        try validate(modelOrigin);return try modelOrigin-offset(model:model,rotation:rotation)
    }
    func root(_ body:SIMD3<Float>,model:Int,rotation:SIMD4<Float>)throws->SIMD3<Float> {
        try validate(body);return try body+offset(model:model,rotation:rotation)
    }
    static func rotation(heading:Float,pitch:Float=0,roll:Float=0)throws->SIMD4<Float> {
        guard heading.isFinite,pitch.isFinite,roll.isFinite else{throw Failure.invalidPose}
        // Same YXZ/Double composition as the native vehicle owner; convert its
        // Y-up quaternion to the protocol's physical GTA Z-up (w,x,y,z).
        let y=simd_quatd(angle:-Double(heading),axis:SIMD3(0,1,0))
        let x=simd_quatd(angle:Double(pitch),axis:SIMD3(1,0,0))
        let z=simd_quatd(angle:-Double(roll),axis:SIMD3(0,0,1)),q=y*x*z
        return SIMD4(Float(q.real),Float(q.imag.x),Float(-q.imag.z),Float(q.imag.y))
    }
    private func validate(_ p:SIMD3<Float>)throws {
        guard p.x.isFinite,p.y.isFinite,p.z.isFinite else{throw Failure.invalidPose}
    }
}
