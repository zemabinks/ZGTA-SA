// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main private enum RegionCheck {
    private enum Failure: Error { case check(String) }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.check("Supply the original PC ISO and its models/gta3.img") }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        try ISOModelInstallCheck.run(source: source)
        try ArchiveModelCheck.run(archiveURL: URL(fileURLWithPath: CommandLine.arguments[2]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zgta-region-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeResourceStore(root: root)
        guard try NativeISORegionInstallation.load(from: store) == nil else { throw Failure.check("Unexpected previous map section") }
        let installed = try NativeISORegionInstallation.install(from: source, store: store, cancellation: .init()) { print($0) }
        let reopenedStore = NativeResourceStore(root: root)
        guard let reopened = try NativeISORegionInstallation.load(from: reopenedStore) else { throw Failure.check("Map section missing after reopen") }
        guard reopened.placementPath == "data/maps/la/lae.ipl", reopened.sourceSlots == [62, 64], reopened.instances == installed.instances,
              reopened.instances.map(\.modelID) == [5472, 5504], reopened.instances.map(\.lodIndex) == [119, 103],
              reopened.instances.allSatisfy({ $0.interior == 0 }), Set(reopened.collisions.keys) == Set([5472, 5504]), !reopenedStore.snapshot.hasPlayableInstallation else { throw Failure.check("Incorrect original placement or unexpected world admission") }
        for instance in reopened.instances {
            let matrix = try instance.worldTransform()
            guard let plan = reopened.models[instance.modelID], !plan.draws.isEmpty, !plan.textures.isEmpty,
                  matrix.columns.3.x == instance.position.x, matrix.columns.3.y == instance.position.y, matrix.columns.3.z == instance.position.z else { throw Failure.check("Missing textured plan or incorrect placement translation") }
        }
        let receipt = root.appendingPathComponent("installed-lae-section-v1.zgta")
        let original = try Data(contentsOf: receipt)
        var changed = original; changed[changed.count - 1] ^= 1
        try changed.write(to: receipt, options: .atomic)
        do { _ = try NativeISORegionInstallation.load(from: reopenedStore) }
        catch {
            print("PASS real ISO map region import, two authored exterior placements, original materials, atomic reopen and corruption rejection; \(original.count) installed bytes")
            return
        }
        throw Failure.check("Corrupt region payload accepted")
    }
}
