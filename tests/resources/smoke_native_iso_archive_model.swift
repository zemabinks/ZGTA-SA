// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Run against a privately extracted compatible PC archive. Only metadata is printed.
#if !ZGTA_ISO_SUITE
@main
#endif
enum ArchiveModelCheck {
    enum Failure: Error { case check(String) }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.check("Supply the path to the original models/gta3.img") }
        try run(archiveURL: URL(fileURLWithPath: CommandLine.arguments[1]))
    }

    static func run(archiveURL: URL) throws {
        let archive = try NativeISOArchiveModel(archive: archiveURL)
        let expected = ["lae_stream0.ipl", "lae_stream1.ipl", "lae_stream2.ipl", "lae_stream3.ipl", "lae_stream4.ipl", "lae_stream5.ipl"]
        let names = archive.streamedPlacementNames(for: "LAe")
        guard names == expected else { throw Failure.check("Unexpected LAe streamed-placement directory") }
        for name in names {
            let bytes = try archive.readPlacement(named: name)
            guard bytes.count.isMultiple(of: 2048), bytes.prefix(4) == Data("bnry".utf8) else { throw Failure.check("Invalid binary IPL member") }
        }
        for (name, dictionary) in [("frecrsbrid_LAE", "laeroads2s"), ("laeroad39", "laeroads2s"), ("laetraintunn03", "railtracklae")] {
            let asset = try archive.prepare(modelName: name, textureName: dictionary)
            guard !asset.plan.draws.isEmpty, asset.plan.textureByteCount > 0, !asset.plan.textures.isEmpty else { throw Failure.check("Missing textured draws") }
            print("PASS \(name): \(asset.dff.count) source bytes, \(asset.plan.draws.count) draws, \(asset.plan.textures.count) material textures")
        }
        for (model, texture, parents) in [("../laeroad39", "laeroads2s", [String]()), ("unknown", "laeroads2s", []), ("laeroad39", "laeroads2s", ["LAEROADS2S"])] {
            do { _ = try archive.prepare(modelName: model, textureName: texture, parentTextureNames: parents) }
            catch { continue }
            throw Failure.check("Invalid archive selection was accepted")
        }
        let stop = NativeISOExtraction.Cancellation()
        stop.cancel()
        do {
            _ = try archive.readPlacement(named: expected[0], cancellation: stop)
            throw Failure.check("Cancelled IPL read succeeded")
        } catch NativeISOExtraction.Failure.cancelled { }
        print("PASS exact streamed member names, bounded reads, cancellation, invalid names and cyclic texture ancestry")
    }
}
