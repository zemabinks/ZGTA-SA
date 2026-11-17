import Foundation

/// Read-only ISO9660 metadata inspection. This does not extract InstallShield,
/// convert original assets, validate an edition or declare a playable install.
/// Layout fields follow ECMA-119 primary descriptors and directory records.
enum NativeGameSourceInspector {
    struct Entry:Equatable {let path:String;let bytes:Int64}
    struct Report:Equatable {
        let volume:String
        let files:[Entry]
        let installShieldCandidate:Bool
        var summary:String {
            installShieldCandidate ? "InstallShield-style disc layout found" : "ISO9660 image inspected"
        }
        var detail:String {
            let source=installShieldCandidate ? "The disc contains DATA1.HDR and DATA1–4.CAB. These Windows installer containers require extraction before native resource preparation." : "This image does not contain the expected DATA1.HDR and DATA1–4.CAB set."
            return "\(files.count) files indexed in \(volume). \(source) File names alone do not verify the game edition. This inspection has not installed playable resources."
        }
    }
    enum InspectionError:LocalizedError {
        case invalid(String),cancelled
        var errorDescription:String? {
            switch self {case .invalid(let message):return message;case .cancelled:return "Source inspection cancelled."}
        }
    }
    private struct Record {let extent:UInt64;let bytes:UInt64;let directory:Bool;let name:String}
    static func inspectISO(_ url:URL,cancelled:()->Bool={false}) throws ->Report {
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        let size=try handle.seekToEnd(),sector:UInt64=2048
        guard size>=sector*18 else{throw InspectionError.invalid("The selected file is too short to contain an ISO9660 volume.")}
        func read(_ offset:UInt64,_ count:Int)throws->[UInt8]{
            if cancelled(){throw InspectionError.cancelled}
            guard count>=0,offset<=size,UInt64(count)<=size-offset else{throw InspectionError.invalid("An ISO extent points outside the selected file.")}
            try handle.seek(toOffset:offset);let data=try handle.read(upToCount:count) ?? Data()
            guard data.count==count else{throw InspectionError.invalid("The ISO could not be read completely. Download cloud files before inspection.")}
            return Array(data)
        }
        func both32(_ data:[UInt8],_ at:Int)throws->UInt64 {
            guard at>=0,at+8<=data.count else{throw InspectionError.invalid("An ISO numeric field is truncated.")}
            let little=(0..<4).reduce(UInt64(0)){$0 | UInt64(data[at+$1]) << (8*$1)}
            let big=(0..<4).reduce(UInt64(0)){($0<<8) | UInt64(data[at+4+$1])}
            guard little==big else{throw InspectionError.invalid("The ISO has inconsistent byte-order fields.")};return little
        }
        var primary:[UInt8]?,terminated=false
        for number in 16..<80 {
            let bytes=try read(UInt64(number)*sector,Int(sector))
            guard Array(bytes[1..<6])==Array("CD001".utf8),bytes[6]==1 else{throw InspectionError.invalid("The selected file has no supported ISO9660 descriptor set.")}
            if bytes[0]==1 && primary==nil {primary=bytes}
            if bytes[0]==255 {terminated=true;break}
        }
        guard let descriptor=primary,terminated else{throw InspectionError.invalid("A complete primary ISO9660 descriptor set was not found.")}
        let block=UInt64(descriptor[128]) | UInt64(descriptor[129])<<8
        let blockBig=UInt64(descriptor[130])<<8 | UInt64(descriptor[131])
        guard block==sector,blockBig==sector else{throw InspectionError.invalid("This inspector supports 2048-byte ISO9660 logical blocks only.")}
        let blocks=try both32(descriptor,80)
        guard blocks>0,blocks<=size/sector else{throw InspectionError.invalid("The ISO volume size exceeds the selected file.")}
        let volumeBytes=blocks*sector
        func record(_ data:[UInt8],_ offset:Int)throws->Record {
            guard offset>=0,offset+34<=data.count else{throw InspectionError.invalid("An ISO directory record is truncated.")}
            let length=Int(data[offset]),nameLength=Int(data[offset+32])
            guard length>=34,offset+length<=data.count,nameLength>0,33+nameLength<=length,
                  data[offset+1]==0,data[offset+26]==0,data[offset+27]==0,data[offset+25]&0x80==0 else{
                throw InspectionError.invalid("The ISO contains an unsupported or malformed directory record.")
            }
            let extent=try both32(data,offset+2),bytes=try both32(data,offset+10)
            guard extent<=volumeBytes/sector,bytes<=volumeBytes-extent*sector else{throw InspectionError.invalid("An ISO directory or file extent exceeds the declared volume.")}
            let raw=Array(data[(offset+33)..<(offset+33+nameLength)])
            let name:String
            if raw==[0] || raw==[1] {name=""}else{
                guard raw.allSatisfy({$0>=32 && $0<127}),let decoded=String(bytes:raw,encoding:.ascii) else{throw InspectionError.invalid("The ISO uses unsupported file identifiers.")}
                name=decoded.components(separatedBy:";").first ?? decoded
                guard !name.isEmpty,name != ".",name != "..",!name.contains("/"),!name.contains("\\") else{throw InspectionError.invalid("The ISO contains an unsafe file identifier.")}
            }
            return Record(extent:extent,bytes:bytes,directory:data[offset+25]&2 != 0,name:name)
        }
        let root=try record(descriptor,156)
        guard root.directory else{throw InspectionError.invalid("The primary ISO root is not a directory.")}
        var queue:[(Record,String,Int)]=[(root,"",0)],index=0,visited=Set<UInt64>(),files:[Entry]=[],names=Set<String>(),metadataBytes:UInt64=0
        while index<queue.count {
            if cancelled(){throw InspectionError.cancelled}
            let(directory,parent,depth)=queue[index];index+=1
            guard depth<=12,queue.count<=4096,visited.insert(directory.extent).inserted else{throw InspectionError.invalid("ISO directory nesting, aliases or cycles exceed this bounded inspector.")}
            guard directory.bytes<=4*1024*1024,metadataBytes<=32*1024*1024-directory.bytes else{throw InspectionError.invalid("ISO directory metadata exceeds the inspection limit.")}
            metadataBytes+=directory.bytes
            let data=try read(directory.extent*sector,Int(directory.bytes));var offset=0
            while offset<data.count {
                if data[offset]==0 {offset=((offset/Int(sector))+1)*Int(sector);continue}
                let length=Int(data[offset]);guard length>0,offset%Int(sector)+length<=Int(sector) else{throw InspectionError.invalid("An ISO directory record crosses its logical block.")}
                let item=try record(data,offset);offset+=length
                if item.name.isEmpty {continue}
                let path=parent.isEmpty ? item.name:parent+"/"+item.name
                guard path.utf8.count<=1024,names.insert(path.uppercased()).inserted,names.count<=50000 else{throw InspectionError.invalid("ISO file identifiers are duplicated or exceed the inspection limit.")}
                if item.directory {queue.append((item,path,depth+1))}else{files.append(Entry(path:path,bytes:Int64(item.bytes)))}
            }
        }
        let required=Set(["DATA1.HDR","DATA1.CAB","DATA2.CAB","DATA3.CAB","DATA4.CAB"])
        let basenames=Set(files.map{($0.path as NSString).lastPathComponent.uppercased()})
        let volume=String(bytes:descriptor[40..<72],encoding:.ascii)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "Unnamed volume"
        return Report(volume:volume,files:files.sorted{$0.path<$1.path},installShieldCandidate:required.isSubset(of:basenames))
    }
}
