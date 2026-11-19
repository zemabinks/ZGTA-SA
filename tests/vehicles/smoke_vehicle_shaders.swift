import Foundation
import Metal

@main enum VehicleShaderSmoke {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),device=MTLCreateSystemDefaultDevice()!
        let world=try String(contentsOf:root.appendingPathComponent("ios/App/WorldShaders.metal"),encoding:.utf8)
        let vehicle=try String(contentsOf:root.appendingPathComponent("ios/App/VehicleShaders.metal"),encoding:.utf8)
        guard let start=vehicle.range(of:"fragment half4 vehicleFragment") else{fatalError("Missing vehicle fragment")}
        // Both actual translation units have the same Uniforms/Raster layouts;
        // share the world's declarations for this runtime pipeline check.
        let library=try device.makeLibrary(source:world+"\n"+vehicle[start.lowerBound...],options:nil)
        let descriptor=MTLRenderPipelineDescriptor()
        descriptor.vertexFunction=library.makeFunction(name:"worldVertex")
        descriptor.fragmentFunction=library.makeFunction(name:"vehicleFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        _=try device.makeRenderPipelineState(descriptor:descriptor)
        descriptor.fragmentFunction=library.makeFunction(name:"worldFragment")
        descriptor.colorAttachments[0].writeMask=[]
        _=try device.makeRenderPipelineState(descriptor:descriptor)
        print("PASS: actual native vehicle-material and depth-only hull Metal pipeline layouts")
    }
}
