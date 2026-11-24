// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main struct WorldPlacementSmoke {
    static func main() throws {
        func source(_ text: String) -> Data { Data(text.utf8) }
        func rejected(_ test: () throws -> Void) {
            do { try test(); fatalError("Expected rejection") } catch {}
        }
        var definitions: [Int: NativeWorldPlacement.Definition] = [:], parents: [String: String] = [:]
        try NativeWorldPlacement.readDefinitions(source("""
            objs
            123, model_a, base_a, 125, 4
            456, far_a, base_a, 2, 200, 400, 0
            end
            tobj
            789, night_a, base_n, 200, 1, 22, 6
            end
            anim
            840, model_b, base_b, move_b, 80, 0
            end
            txdp
            base_a, common
            common, extras
            end
            """), path: "fixture.ide", into: &definitions, parents: &parents)
        precondition(definitions.count == 4 && definitions[456]?.drawDistances == [200, 400])
        precondition(definitions[789]?.timeOn == 22 && definitions[789]?.timeOff == 6)
        precondition(definitions[840]?.animation == "move_b")
        let row = "123, model_a, 1025, -30, 5.25, 12, 0, 0, -0.5, 0.8660254, 1"
        let lod = "456, far_a, 0, -30, 5.25, 12, 0, 0, 0, 1, -1"
        let instances = try NativeWorldPlacement.readInstances(source("inst\n\(row)\n\(lod)\nend\n"), path: "fixture.ipl")
        precondition(instances.count == 2 && instances[0].interiorFlags == 1025 && instances[0].interior == 1)
        precondition(instances[0].rotation.z == -0.5 && instances[0].lodIndex == 1)
        precondition(instances[1].lodIndex == -1)
        let placed = try instances[0].worldTransform()
        let placedX = placed * SIMD4<Float>(1, 0, 0, 0)
        precondition(abs(placedX.x - 0.5) < 0.0001 && abs(placedX.y - sqrt(0.75)) < 0.0001)
        precondition(placed.columns.3 == SIMD4(-30, 5.25, 12, 1))
        let tilt = NativeWorldPlacement.Instance(modelID: 123, modelName: nil, interiorFlags: 0,
                        position: .zero, rotation: SIMD4(sqrt(0.5), 0, 0, sqrt(0.5)), lodIndex: -1)
        let tiltMatrix = try tilt.worldTransform()
        precondition(simd_distance(tiltMatrix * SIMD4(0,1,0,0), SIMD4(0,0,-1,0)) < 0.0001)
        var fixtureRegion = NativeWorldPlacement.Region(placementPath: "data/maps/fixture.ipl", definitions: definitions, instances: instances, textureParents: parents)
        let chain = try fixtureRegion.parentTextureNames(for: "BASE_A")
        precondition(chain == ["common", "extras"])
        fixtureRegion.textureParents["extras"] = "base_a"
        rejected { _ = try fixtureRegion.parentTextureNames(for: "base_a") }
        let named = try fixtureRegion.resolvedStream(named: "fixture_stream0.ipl", instances: [tilt])
        precondition(named.count == 1 && named[0].modelName == "model_a" && named[0].rotation == tilt.rotation)
        rejected { _ = try fixtureRegion.resolvedStream(named: "other_stream0.ipl", instances: [tilt]) }
        rejected { _ = try NativeWorldPlacement.readInstances(source("inst\n\(row)\nend"), path: "outside.ipl") }
        rejected { _ = try NativeWorldPlacement.readInstances(source("inst\n\(lod.replacingOccurrences(of: "-1", with: "0"))\nend"), path: "self.ipl") }
        rejected { _ = try NativeWorldPlacement.readInstances(source("inst\n\(lod.replacingOccurrences(of: "-30", with: "NaN"))\nend"), path: "finite.ipl") }
        rejected { _ = try NativeWorldPlacement.readInstances(source("inst\n\(lod)"), path: "incomplete.ipl") }
        rejected { try NativeWorldPlacement.readDefinitions(source("objs\n123, model_a, other, 20, 0\nend"), path: "duplicate.ide", into: &definitions, parents: &parents) }
        print("PASS text IDE/IPL bounds, timed definitions, signed rotation, interior flags and LOD integrity")
        try StreamPlacementCheck.fixtures()
    }
}
