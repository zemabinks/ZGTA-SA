import Foundation
import CryptoKit
@main struct SplitVolumeProbe {
    static func main()throws{
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),stage=URL(fileURLWithPath:CommandLine.arguments[2])
        let expected=CommandLine.arguments[3].lowercased(),reader=try NativeISOExtraction(source:source)
        guard let member=reader.entries.first(where:{$0.path.uppercased()=="AUDIO/SFX/SPC_GA" && $0.source == .cabinet}) else{throw NativeISOExtraction.Failure.invalid("Split-volume original member unavailable")}
        try reader.extract(indices:[member.index],to:stage)
        let file=try FileHandle(forReadingFrom:stage.appendingPathComponent(member.path));defer{try? file.close()}
        var md5=Insecure.MD5(),sha=SHA256(),bytes:UInt64=0
        while let chunk=try file.read(upToCount:65536),!chunk.isEmpty{md5.update(data:chunk);sha.update(data:chunk);bytes+=UInt64(chunk.count)}
        let actual=md5.finalize().map{String(format:"%02x",$0)}.joined(),digest=sha.finalize().map{String(format:"%02x",$0)}.joined()
        guard bytes==member.bytes,actual==expected else{throw NativeISOExtraction.Failure.invalid("Split resource differs from original header checksum/size")}
        let statistics=reader.statistics
        let report:[String:Any]=["status":"PASS","scope":"Actual direct ISO split-CAB member extraction; streaming checksum against original HDR, not a separate accepted-file comparison or native conversion","path":member.path,"bytes":bytes,"headerMD5":expected,"sha256":digest,"isoBytesRead":statistics.isoBytesRead,"maximumReadRequest":statistics.maximumReadRequest,"outputBytes":statistics.outputBytesWritten]
        let output=stage.deletingLastPathComponent().appendingPathComponent("split-report.json")
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print("PASS actual split-CAB resource: \(bytes) bytes, original header MD5 verified, streamed SHA256 \(digest), max ISO read \(statistics.maximumReadRequest)")
    }
}
