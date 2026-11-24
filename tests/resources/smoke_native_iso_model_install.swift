// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Invoke with a user-provided compatible PC installation ISO. All extracted and
/// converted data are confined to a fresh temporary store for this invocation.
#if !ZGTA_ISO_SUITE
@main
#endif
enum ISOModelInstallCheck {
    private enum Failure: Error { case check(String) }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.check("Supply the path of your compatible original PC disc image.") }
        try run(source: URL(fileURLWithPath: CommandLine.arguments[1]))
    }

    static func run(source: URL) throws {

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zgta-model-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeResourceStore(root: root)
        let oldBinding = store.runtimeBinding
        try require(try NativeISOModelInstallation.load(from: store) == nil, "Fresh store already had a model")
        let installed = try NativeISOModelInstallation.install(from: source, store: store, cancellation: .init())
        let reopenedStore = NativeResourceStore(root: root)
        guard let reopened = try NativeISOModelInstallation.load(from: reopenedStore) else { throw Failure.check("Lost receipt on reopen") }
        try require(reopened.manifest.modelPath == "models/grass/plant1.dff" && reopened.manifest.texturePath == "models/grass/plant1.txd", "Expected the selected pair")
        try require(reopened.dff == installed.dff && reopened.txd == installed.txd && !reopened.plan.draws.isEmpty, "Changed source bytes or missing draws on reopen")
        try require(!reopened.plan.textures.isEmpty && reopened.plan.textureByteCount > 0, "Missing textured draws")
        let reference = try NativeRenderWareTXD.decode(installed.txd)
        try require(reference.textures.count == reopened.textures.textures.count && reference.decodedByteCount == reopened.textures.decodedByteCount, "Converted dictionary mismatch")
        for (source, restored) in zip(reference.textures, reopened.textures.textures) {
            try require(source.name == restored.name && source.maskName == restored.maskName && source.filterAddressing == restored.filterAddressing && source.mipLevels.count == restored.mipLevels.count, "Restored texture metadata differs")
            for (expected, actual) in zip(source.mipLevels, restored.mipLevels) {
                try require(expected.rgba8 == actual.rgba8 && expected.width == actual.width && expected.height == actual.height && expected.containsTransparentPixels == actual.containsTransparentPixels, "Restored RGBA mip differs")
            }
        }
        try require(!reopenedStore.snapshot.hasPlayableInstallation && store.runtimeBinding == oldBinding && reopenedStore.snapshot.mode == oldBinding.mode, "A partial import changed world admission or the selected source")
        let receipt = root.appendingPathComponent("installed-static-model-v1.zgta")
        let saved = try Data(contentsOf: receipt)
        let cancellation = NativeISOExtraction.Cancellation()
        do {
            _ = try NativeISOModelInstallation.install(from: source, store: store, cancellation: cancellation) { status in
                if status.hasPrefix("Verifying") { cancellation.cancel() }
            }
            throw Failure.check("Cancelled replacement committed")
        } catch NativeISOExtraction.Failure.cancelled { }
        try require(try Data(contentsOf: receipt) == saved, "Cancelled replacement changed the previous installation")
        let stage = root.appendingPathComponent("staging")
        try require(try FileManager.default.contentsOfDirectory(atPath: stage.path).isEmpty, "Cancelled import leaked staging contents")
        var changed = saved
        changed[changed.count - 1] ^= 1
        for bytes in [changed, Data(saved.dropLast()), Data(saved.prefix(9))] {
            try bytes.write(to: receipt, options: .atomic)
            do {
                _ = try NativeISOModelInstallation.load(from: store)
            } catch { continue }
            throw Failure.check("Opened corrupted model receipt")
        }
        print("PASS real ISO extraction, verified native mip conversion, static textured draws, store reopen, cancellation rollback and corruption rejection")
    }
}
