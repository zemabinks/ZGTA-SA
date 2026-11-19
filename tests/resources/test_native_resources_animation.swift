// SPDX-License-Identifier: AGPL-3.0-only
// Real, unchanged native CLP1/SKN1 readers over authored carriers. This target
// checks parser admission and one finite pose; it does not render a game/world.
import Foundation
import Metal
import simd

@main private struct ResourceAnimationReaderOracle {
    static func main() throws {
        guard CommandLine.arguments.count == 2,
              let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain:"ResourceAnimationReaderOracle",code:1,
                          userInfo:[NSLocalizedDescriptionKey:"Actual Metal device required for native SKN1 allocation"])
        }
        let configuration = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
        let cases = configuration["cases"] as! [[String:Any]]
        var checks = 0, failures = [String](), rows = [[String:Any]]()
        func check(_ actual:Bool,_ label:String){checks += 1; if !actual {failures.append(label)}}
        for item in cases {
            let label = item["label"] as! String
            let library = (item["library"] as? String).flatMap {try? Data(contentsOf:URL(fileURLWithPath:$0))}.flatMap {NativeSkeletalAnimationLibrary(data:$0)}
            let actor = (item["skeleton"] as? String).flatMap {try? Data(contentsOf:URL(fileURLWithPath:$0))}.flatMap {NativeSkeletalActor(data:$0,vertexCount:item["vertexCount"] as! Int,device:device)}
            check((library != nil) == (item["libraryValid"] as! Bool),label+" actual CLP1 admission")
            check((actor != nil) == (item["skeletonValid"] as! Bool),label+" actual SKN1 admission")
            if label == "valid-paired-skeletal-family",let library,let actor {
                let pose=actor.pose(clip:"ped/idle_stance",elapsed:0.17,library:library)
                check(library.clipCount == 1 && library.hasRoot("ped/idle_stance"),"authored real idle/root clip")
                check(pose != nil && pose!.palette.allSatisfy {matrix in
                    [matrix.columns.0,matrix.columns.1,matrix.columns.2,matrix.columns.3].allSatisfy {v in v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite}
                },"actual SKN1 produces a finite native palette")
                check(pose != nil && actor.positions(pose:pose!).allSatisfy {$0.x.isFinite && $0.y.isFinite && $0.z.isFinite},"actual native skin vertices remain finite")
            }
            rows.append(["label":label,"actualLibraryAccepted":library != nil,"actualSkeletonAccepted":actor != nil])
        }
        let report:[String:Any] = ["status":failures.isEmpty ? "PASS":"FAIL","checks":checks,"failures":failures,"cases":rows,
                                  "scope":"Actual unchanged native readers, authored CLP1/SKN1 bytes, actual Metal skin allocation and finite idle pose only; no game rendering, parity or full runtime admission claim"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:configuration["output"] as! String))
        print("RESOURCE_ANIMATION_READERS \(failures.isEmpty ? "PASS":"FAIL") \(checks)")
        if !failures.isEmpty {throw NSError(domain:"ResourceAnimationReaderOracle",code:2,userInfo:[NSLocalizedDescriptionKey:failures.joined(separator:"; ")])}
    }
}
