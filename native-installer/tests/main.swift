import Foundation
import CryptoKit
import CZGTAInstaller
private var checks=0
private func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
private func hash(_ url:URL)throws->String{SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()}
@main struct InstallerSmoke {
    static func main()throws{
        let root=URL(fileURLWithPath:CommandLine.arguments[1]).resolvingSymlinksInPath()
        for path in ["anim/ped.ifp","data/weapon.dat","data/maps/LA/LAe.ipl","models/gta3.img","models/player.img","models/coll/peds.col","text/american.gxt","audio/STREAMS/AA","AUDIO/STREAMS/ADVERTS","audio/CONFIG/BANKLKUP.DAT","movies/intro.mpg"]{check(NativeRawResourceSelection.isGameResourcePath(path),"Raw resource unnecessarily omitted: \(path)")}
        for path in ["GTA SA EXECUTABLE/gta_sa.exe","HOODLUM/GTA_SA.EXE","SETUP.EXE","DATA1.CAB","DATA1.HDR","ENGINE32.CAB","<Support>/runtime.dll","data/evil.EXE","models/evil.dll","data/evil.asi","audio/evil.cmd","data/../evil.dat","/data/test.dat","data//test.dat","data/C:/evil.dat","data\\weapon.dat","saves/save.b","README/ENU/README.TXT"]{check(!NativeRawResourceSelection.isGameResourcePath(path),"Non-resource/unsafe path admitted by default: \(path)")}
        for path in ["data/weapon.dat","models/coll/peds.col","audio/STREAMS/AA"]{check(path.withCString{zgta_installer_valid_relative_path($0)}==1,"Valid bridge path refused")}
        for path in ["","/data/test","data/../test","data//test","data\\test","data:C/test","data/./test","data/test/"]{check(path.withCString{zgta_installer_valid_relative_path($0)}==0,"Unsafe bridge path accepted")}
        let invalid=root.appendingPathComponent("invalid.iso");try Data(repeating:0,count:4096).write(to:invalid)
        do{_ = try NativeISOExtraction(source:invalid);preconditionFailure("Invalid ISO accepted")}catch{checks+=1}
        let token=NativeISOExtraction.Cancellation();token.cancel()
        do{_ = try NativeISOExtraction(source:invalid,cancellation:token);preconditionFailure("Pre-cancel ignored")}catch NativeISOExtraction.Failure.cancelled{checks+=1}
        catch{preconditionFailure("Pre-cancel returned another error")}
        if CommandLine.arguments.count>2 {
            let iso=URL(fileURLWithPath:CommandLine.arguments[2]),accepted=URL(fileURLWithPath:CommandLine.arguments[3])
            let before=try FileManager.default.attributesOfItem(atPath:iso.path)
            if FileManager.default.fileExists(atPath:root.appendingPathComponent("malformed-cases.json").path){
                let malformed=try JSONDecoder().decode([String].self,from:Data(contentsOf:root.appendingPathComponent("malformed-cases.json")))
                for name in malformed {
                    do{_ = try NativeISOExtraction(source:root.appendingPathComponent(name+".iso"));preconditionFailure("Malformed header accepted: \(name)")}catch{checks+=1}
                }
                let missing=try NativeISOExtraction(source:root.appendingPathComponent("truncated-cabinets.iso"))
                let entry=missing.entries.first{$0.path=="data/weapon.dat"}!,stage=root.appendingPathComponent("malformed-cabinet-stage")
                do{try missing.extract(indices:[entry.index],to:stage);preconditionFailure("Truncated cabinet data accepted")}catch{checks+=1}
                check(!FileManager.default.fileExists(atPath:stage.path),"Malformed cabinet left a partial stage")
            }
            let extraction=try NativeISOExtraction(source:iso),selection=try extraction.gameResources()
            check(extraction.entries.count==499,"Actual catalogue entries changed unexpectedly")
            check(selection.contains{$0.path=="models/gta3.img"},"Pending native model archive omitted")
            check(selection.contains{$0.path.uppercased()=="AUDIO/STREAMS/AA" && $0.source == .looseISO},"No-extension original radio stream omitted")
            check(selection.allSatisfy{!$0.path.lowercased().hasSuffix(".exe") && !$0.path.lowercased().hasSuffix(".dll") && !$0.path.lowercased().hasSuffix(".cab") && !$0.path.lowercased().hasPrefix("hoodlum/")},"Default selection includes Windows/installer/extras")
            let wanted=["anim/ped.ifp","data/gta.dat","data/handling.cfg","data/peds.ide","data/weapon.dat","audio/CONFIG/BankLkup.dat"]
            let entries=try wanted.map{path->NativeISOExtraction.Entry in guard let entry=extraction.entries.first(where:{$0.path==path && $0.source == .cabinet})else{throw NativeISOExtraction.Failure.invalid("Missing actual member \(path)")};return entry}
            let stage=root.appendingPathComponent("stage");var lastBytes:UInt64=0,lastFiles:UInt32=0,progressCalls=0
            try extraction.extract(indices:entries.map(\.index),to:stage){progress in
                check(progress.completedBytes>=lastBytes && progress.completedFiles>=lastFiles,"Progress rewound")
                check(progress.completedBytes<=progress.totalBytes && progress.completedFiles<=progress.totalFiles,"Progress exceeded bounds")
                lastBytes=progress.completedBytes;lastFiles=progress.completedFiles;progressCalls+=1
            }
            check(progressCalls>0 && lastFiles==UInt32(wanted.count),"Actual extraction did not complete progress")
            var matches:[[String:Any]]=[]
            for path in wanted {let extracted=stage.appendingPathComponent(path),reference=accepted.appendingPathComponent(path);let actual=try hash(extracted),expected=try hash(reference);check(actual==expected,"Original member byte/path mismatch: \(path)");matches.append(["path":path,"sha256":actual])}
            let radio=extraction.entries.first{$0.path.uppercased()=="AUDIO/STREAMS/AA" && $0.source == .looseISO}!
            let radioStage=root.appendingPathComponent("radio-stage")
            try extraction.extract(indices:[radio.index],to:radioStage)
            let radioHash=try hash(radioStage.appendingPathComponent(radio.path)),expectedRadio=try hash(root.appendingPathComponent("expected-radio-AA"))
            check(radioHash==expectedRadio,"Loose no-extension radio bytes/path differ from independent ISO fixture")
            matches.append(["path":radio.path,"sha256":radioHash,"source":"loose ISO; independently indexed private fixture"])
            // Existing destinations are never used as extraction stages.
            do{try extraction.extract(indices:entries.map(\.index),to:stage);preconditionFailure("Existing installation directory overwritten")}catch{checks+=1}
            let preserved=try hash(stage.appendingPathComponent(wanted[0])),original=try hash(accepted.appendingPathComponent(wanted[0]))
            check(preserved==original,"Existing resource changed after refusal")
            let duplicate=root.appendingPathComponent("duplicate")
            do{try extraction.extract(indices:[entries[0].index,entries[0].index],to:duplicate);preconditionFailure("Duplicate output accepted")}catch{checks+=1}
            check(!FileManager.default.fileExists(atPath:duplicate.path),"Invalid selection created stage")
            // C API rejects symlink parents; Swift resolves only a caller-owned
            // parent for legitimate Foundation /var aliases before entering it.
            let outside=root.appendingPathComponent("outside");try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
            let link=root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
            var error=[CChar](repeating:0,count:512),limits=zgta_installer_default_limits()
            let h=iso.path.withCString{zgta_installer_open_iso($0,&limits,nil,nil,&error,512)}!
            var index=UInt32(entries[0].index)
            let unsafe=link.appendingPathComponent("stage").path.withCString{zgta_installer_extract(h,&index,1,$0,nil,nil)}
            check(unsafe==ZGTA_INSTALLER_FAILED && !FileManager.default.fileExists(atPath:outside.appendingPathComponent("stage").path),"Symlink staging traversal escaped")
            zgta_installer_close(h)
            let cancelled=try NativeISOExtraction(source:iso),cancelStage=root.appendingPathComponent("cancelled")
            do{try cancelled.extract(indices:[entries[0].index],to:cancelStage){progress in if progress.completedBytes>0 {cancelled.cancel()}};preconditionFailure("Mid-file cancellation ignored")}catch NativeISOExtraction.Failure.cancelled{checks+=1}
            check(!FileManager.default.fileExists(atPath:cancelStage.path),"Cancelled raw stage retained partial files")
            limits=zgta_installer_default_limits();limits.max_output_bytes=10
            let bounded=try NativeISOExtraction(source:iso,limits:limits),limitStage=root.appendingPathComponent("limit")
            do{try bounded.extract(indices:[entries[0].index],to:limitStage);preconditionFailure("Output bound ignored")}catch{checks+=1}
            check(!FileManager.default.fileExists(atPath:limitStage.path),"Over-budget selection modified stage")
            let after=try FileManager.default.attributesOfItem(atPath:iso.path)
            check((before[.size] as? NSNumber)==(after[.size] as? NSNumber) && (before[.modificationDate] as? Date)==(after[.modificationDate] as? Date),"Original ISO metadata changed")
            let stats=extraction.statistics
            check(stats.isoBytesRead<10_000_000 && stats.maximumReadRequest<=32*1024*1024,"Extraction read/copied unbounded cabinet data")
            let report:[String:Any]=["scope":"Actual owner ISO direct-range raw extraction; not conversion or playable installation","catalogueEntries":extraction.entries.count,"defaultRawResources":selection.count,"defaultRawBytes":selection.reduce(UInt64(0)){$0+$1.bytes},"retainedRoots":Array(Set(selection.map{$0.path.split(separator:"/")[0].lowercased()})).sorted(),"matches":matches,"isoBytesRead":stats.isoBytesRead,"maximumReadRequest":stats.maximumReadRequest,"outputBytes":stats.outputBytesWritten,"progressCalls":progressCalls]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("owner-report.json"))
            print("Actual direct ISO: \(extraction.entries.count) entries, \(selection.count) default raw resources;6 accepted cabinet +1 original loose radio byte/path matches; read\(stats.isoBytesRead)B/max\(stats.maximumReadRequest)B")
        }
        print("PASS native installer bridge: \(checks) checks; raw-resource selection, path/cancel/limits/stage isolation")
    }
}
