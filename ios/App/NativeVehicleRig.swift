import Foundation
import simd

/// Local geometry/joints exported from original88711/62540/39851. Every pose
/// remains in the original DFF/GTA frame until its final Metal matrix cast.
final class NativeVehicleRig {
    typealias V=SIMD3<Double>
    typealias Q=simd_quatd
    struct Input {
        var steering=0.0,rearSteering=0.0,frontSpin=0.0,rearSpin=0.0
        var offsets=[Double](),drop=[Double](),lean=0.0,crank:Double?
        var rotor=0.0,rotorSpin:Double?,nozzle=5000.0,gearUp=false
        var looks=[Int](),tyres=[Int](),brokenLights=[Int](),doorAngles=[Double](),doorAxes=[Int]()
        var lights=false,braking=false,scorched=false
        var extras:Set<Int>?
    }
    struct State { var gearShare=0.0;var rotorSpin=0.0 }
    struct Draw {
        let start:Int,count:Int,node:Int,transform:simd_float4x4
        let layerOverride:Float,emissive:Bool,scorched:Bool,alphaTest:Float
    }
    struct Frame {let matrices:[simd_double4x4];let visible:[Bool];let draws:[Draw]}
    struct Node:Decodable {
        let name:String,parent:Int,position:[Double],rotation:[Double],scale:[Double],matrix:[Double]
        let matrixAutoUpdate:Bool,visible:Bool,wheel:Bool,damaged:Bool,lowDetail:Bool
        let hub:String?,node:String?,extra:Int?
    }
    struct DrawDefinition:Decodable {let node:Int,start:Int,count:Int;let materialVisible:Bool;let lens:Int,texture:Int,litTexture:Int;let alphaTest:Double}
    struct DamageJoint:Decodable {let part:Int,node:Int,rest:[Double],hinge:[Double]}
    struct WheelJoint:Decodable {let node:Int,hub:String?;let home:[Double],rest:[Double],lean:[Double];let front:Bool,left:Bool,bogie:Bool}
    struct RotorJoint:Decodable {let node:Int,name:String,rest:[Double]}
    struct GearJoint:Decodable {let node:Int,frame:String,axis:[Double],angle:Double,over:[Double],at:[Double],undo:[Double]}
    struct NozzleJoint:Decodable {let node:Int}
    struct Hub:Decodable {let at:[Double],radius:Double}
    struct Bike:Decodable {
        let model:Int,front:Int,rear:Int,crank:Int?,parameters:[String:Double],hubs:[String:Hub],restDrop:Double
        let frontWheels:[Int],frontMudguards:[Int],rearWheels:[Int],pedals:[Int],pedalled:Bool,rearForkLength:Double,minimumZ:Double
    }
    struct Joints:Decodable {let damage:[DamageJoint],wheels:[WheelJoint],rotors:[RotorJoint],gear:[GearJoint],nozzles:[NozzleJoint],rearSteerOnly:Bool,bike:Bike?}
    struct WaterMask:Decodable {let node:Int,positions:[Float],indices:[UInt32]}
    struct Document:Decodable {let version:Int,id:Int,kind:String,nodes:[Node],draws:[DrawDefinition],joints:Joints,waterMasks:[WaterMask]?}
    let document:Document
    var damageHinges:[Int:SIMD3<Double>] {Dictionary(uniqueKeysWithValues:document.joints.damage.map{($0.part,Self.v($0.hinge))})}
    init?(data:Data) {
        guard let document=try? JSONDecoder().decode(Document.self,from:data),document.version==1,!document.nodes.isEmpty,
              document.nodes.count<4096,document.nodes.enumerated().allSatisfy({index,node in
                  node.parent<index && node.parent>=(-1) && node.position.count==3 && node.rotation.count==4 && node.scale.count==3 && node.matrix.count==16 &&
                  (node.position+node.rotation+node.scale+node.matrix).allSatisfy(\.isFinite)
              }),document.draws.allSatisfy({document.nodes.indices.contains($0.node)&&$0.start>=0&&$0.count>=0}),
              (document.waterMasks ?? []).allSatisfy({mask in document.nodes.indices.contains(mask.node)&&mask.positions.count%3==0&&mask.positions.allSatisfy(\.isFinite)&&mask.indices.allSatisfy{Int($0)<mask.positions.count/3}}) else{return nil}
        self.document=document
    }
    private static func v(_ values:[Double])->V {V(values[0],values[1],values[2])}
    private static func q(_ values:[Double])->Q {Q(ix:values[0],iy:values[1],iz:values[2],r:values[3])}
    private static func axis(_ vector:V,_ angle:Double)->Q {let sine=sin(angle/2);return Q(ix:vector.x*sine,iy:vector.y*sine,iz:vector.z*sine,r:cos(angle/2))}
    private static func multiply(_ a:Q,_ b:Q)->Q {
        Q(ix:a.imag.x*b.real+a.real*b.imag.x+a.imag.y*b.imag.z-a.imag.z*b.imag.y,
          iy:a.imag.y*b.real+a.real*b.imag.y+a.imag.z*b.imag.x-a.imag.x*b.imag.z,
          iz:a.imag.z*b.real+a.real*b.imag.z+a.imag.x*b.imag.y-a.imag.y*b.imag.x,
          r:a.real*b.real-a.imag.x*b.imag.x-a.imag.y*b.imag.y-a.imag.z*b.imag.z)
    }
    private static func matrix(_ values:[Double])->simd_double4x4 {
        .init(columns:(SIMD4(values[0],values[1],values[2],values[3]),SIMD4(values[4],values[5],values[6],values[7]),SIMD4(values[8],values[9],values[10],values[11]),SIMD4(values[12],values[13],values[14],values[15])))
    }
    private static func compose(_ p:V,_ q:Q,_ s:V)->simd_double4x4 {
        let x=q.imag.x,y=q.imag.y,z=q.imag.z,w=q.real,x2=x+x,y2=y+y,z2=z+z
        let xx=x*x2,xy=x*y2,xz=x*z2,yy=y*y2,yz=y*z2,zz=z*z2,wx=w*x2,wy=w*y2,wz=w*z2
        return .init(columns:(SIMD4((1-(yy+zz))*s.x,(xy+wz)*s.x,(xz-wy)*s.x,0),
            SIMD4((xy-wz)*s.y,(1-(xx+zz))*s.y,(yz+wx)*s.y,0),SIMD4((xz+wy)*s.z,(yz-wx)*s.z,(1-(xx+yy))*s.z,0),SIMD4(p,1)))
    }
    func pose(_ input:Input,state:inout State,delta:Double)->Frame {
        let nodes=document.nodes,joints=document.joints
        var positions=nodes.map{Self.v($0.position)},rotations=nodes.map{Self.q($0.rotation)}
        var locals=nodes.map{Self.matrix($0.matrix)},visible=nodes.map(\.visible)
        if let extras=input.extras {for node in nodes.indices {if let extra=nodes[node].extra {visible[node]=extras.contains(extra)}}}
        func tyre(_ index:Int)->Int {input.tyres.indices.contains(index) ? input.tyres[index]:0}
        for wheel in joints.wheels {
            let spin=wheel.front ? input.frontSpin:input.rearSpin,index=2*(wheel.left ? 0:1)+(wheel.front ? 0:1)
            let front=joints.rearSteerOnly ? 0:input.steering,rear=joints.rearSteerOnly ? -input.steering:input.rearSteering
            let wobble=tyre(index)==1 ? 0.3*sin(spin):0
            rotations[wheel.node]=Self.multiply(Self.multiply(Self.multiply(Self.axis(V(0,0,1),wobble-(wheel.front ? front:rear)),Self.q(wheel.lean)),Self.q(wheel.rest)),Self.axis(V(1,0,0),wheel.bogie ? 0:spin))
            if input.offsets.indices.contains(index) {positions[wheel.node].z=wheel.home[2]+input.offsets[index]}
            visible[wheel.node]=tyre(index)<2
        }
        if let bike=joints.bike {
            let fork=(bike.parameters["forkAngle"] ?? 0) * .pi/180
            let front=input.drop.indices.contains(0) ? input.drop[0]:bike.restDrop,rear=input.drop.indices.contains(1) ? input.drop[1]:bike.restDrop
            rotations[bike.front]=Self.axis(V(0,sin(fork),-cos(fork)),input.steering)
            for node in bike.frontWheels+bike.frontMudguards {
                let home=Self.v(nodes[node].position);positions[node]=V(home.x,home.y-front*tan(fork),home.z+front)
            }
            for node in bike.frontWheels {
                rotations[node]=Self.multiply(Self.multiply(Self.q(nodes[node].rotation),Self.axis(V(0,0,1),(tyre(0)==1 ? 0.05:0)*sin(input.frontSpin))),Self.axis(V(1,0,0),input.frontSpin))
            }
            rotations[bike.rear]=Self.axis(V(1,0,0),-asin(min(1,max(-1,rear/bike.rearForkLength))))
            for node in bike.rearWheels {
                rotations[node]=Self.multiply(Self.multiply(Self.q(nodes[node].rotation),Self.axis(V(0,0,1),(tyre(1)==1 ? 0.07:0)*sin(input.rearSpin))),Self.axis(V(1,0,0),input.rearSpin))
            }
            if let crank=bike.crank {
                let angle=input.crank.map { -$0 * .pi*2 } ?? input.rearSpin/2.5
                rotations[crank]=Self.axis(V(1,0,0),angle)
                for node in bike.pedals {rotations[node]=Self.axis(V(1,0,0),-angle)}
            }
            rotations[bike.model]=Self.multiply(Self.axis(V(0,1,0),input.lean),Self.axis(V(1,0,0),-0.05*abs(input.lean)))
            positions[bike.model].z=(1-cos(input.lean))*0.9*bike.minimumZ
        }
        if document.kind=="heli" || document.kind=="plane" {
            let elapsed=min(0.1,max(0,delta)),target=input.gearUp ? 1.0:0.0
            if state.gearShare != target {state.gearShare=min(1,max(0,state.gearShare+elapsed*(target>state.gearShare ? 1:-1)))}
            state.rotorSpin=input.rotorSpin ?? (state.rotorSpin+max(0,input.rotor)*elapsed*50).truncatingRemainder(dividingBy:100 * .pi)
            for rotor in joints.rotors where rotor.name.hasPrefix("static_") {
                let axis:V,rate:Double
                switch rotor.name {
                case "static_rotor":axis=V(0,0,1);rate = [447,469,487,488,497].contains(document.id) ? -1.66:-1
                case "static_rotor2":axis=V(1,0,0);rate = document.id==417 ? -2:-2.3
                case "static_prop":axis=V(0,1,0);rate=2
                default:axis=V(0,1,0);rate = -2
                }
                rotations[rotor.node]=Self.multiply(Self.q(rotor.rest),Self.axis(axis,state.rotorSpin*rate))
            }
            for nozzle in joints.nozzles {rotations[nozzle.node]=Self.axis(V(1,0,0),input.nozzle/5000 * .pi/2)}
            for joint in joints.gear {
                let transform=Self.compose(Self.v(joint.at),Self.axis(Self.v(joint.axis),joint.angle*state.gearShare),V(repeating:1))
                locals[joint.node]=Self.matrix(joint.over)*transform*Self.matrix(joint.undo)
            }
        }
        for joint in joints.damage {
            if input.doorAngles.indices.contains(joint.part) {
                let axis=input.doorAxes.indices.contains(joint.part) ? input.doorAxes[joint.part]:0
                rotations[joint.node]=Self.multiply(Self.q(joint.rest),Self.axis(axis==0 ? V(1,0,0):axis==1 ? V(0,1,0):V(0,0,1),input.doorAngles[joint.part]))
            }
            let look=input.looks.indices.contains(joint.part) ? input.looks[joint.part]:0
            let children=nodes.indices.filter{nodes[$0].parent==joint.node && nodes[$0].node != nil}
            let bent=children.contains{nodes[$0].damaged}
            for child in children {visible[child]=nodes[child].damaged ? look==1:(look==0 || look==1 && !bent)}
        }
        var matrices=[simd_double4x4](repeating:matrix_identity_double4x4,count:nodes.count)
        for index in nodes.indices {
            if nodes[index].matrixAutoUpdate {locals[index]=Self.compose(positions[index],rotations[index],Self.v(nodes[index].scale))}
            let parent=nodes[index].parent;matrices[index]=parent<0 ? locals[index]:matrices[parent]*locals[index]
            if parent>=0 {visible[index]=visible[index] && visible[parent]}
        }
        var draws:[Draw]=[]
        for draw in document.draws {
            guard visible[draw.node],draw.materialVisible else{continue}
            let lamp=[0,1,3,2].indices.contains(draw.lens) ? [0,1,3,2][draw.lens]:-1
            let broken=input.brokenLights.indices.contains(lamp) && input.brokenLights[lamp]==1
            let lit=draw.lens>=0 && draw.litTexture>0 && !broken && (draw.lens<2 ? input.lights:input.lights || input.braking)
            let m=matrices[draw.node],transform=simd_float4x4(columns:(SIMD4<Float>(m[0]),SIMD4<Float>(m[1]),SIMD4<Float>(m[2]),SIMD4<Float>(m[3])))
            let packet=Draw(start:draw.start,count:draw.count,node:draw.node,transform:transform,layerOverride:lit ? Float(draw.litTexture):-1,emissive:lit,scorched:input.scorched,alphaTest:Float(draw.alphaTest))
            // Preserve triangle order while joining adjacent groups with the
            // same actual draw state; texture/color stay in each vertex.
            if let previous=draws.last,previous.node==packet.node,previous.start+previous.count==packet.start,
               previous.layerOverride==packet.layerOverride,previous.emissive==packet.emissive,
               previous.scorched==packet.scorched,previous.alphaTest==packet.alphaTest {
                draws[draws.count-1]=Draw(start:previous.start,count:previous.count+packet.count,node:packet.node,transform:packet.transform,
                    layerOverride:packet.layerOverride,emissive:packet.emissive,scorched:packet.scorched,alphaTest:packet.alphaTest)
            } else {draws.append(packet)}
        }
        return Frame(matrices:matrices,visible:visible,draws:draws)
    }
}
