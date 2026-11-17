// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
import Darwin

/// Persistent original bytes only. This store never activates native gameplay.
final class NativeRawResourceStore {
    struct Snapshot {
        var sourceID:String?,contentID:String?,sourceName:String?
        var files=0,bytes:Int64=0,verified=false,issues:[String]=[]
        static let empty=Snapshot()
    }
    struct Input {
        let members:[NativeISOExtraction.Entry]
        let extract:(URL,@escaping(NativeISOExtraction.Progress)->Void)throws->Void
    }
    struct Extractor {
        let identity:String
        let open:(URL,NativeISOExtraction.Cancellation)throws->Input
        static let originalISO=Extractor(identity:"zgta-original-raw-selection-v1"){url,cancellation in
            let reader=try NativeISOExtraction(source:url,cancellation:cancellation)
            let selected=try reader.gameResources()
            return Input(members:selected,extract:{stage,progress in
                try reader.extract(indices:selected.map(\.index),to:stage,progress:progress)
            })
        }
    }
    struct Resource:Codable {
        let path:String,bytes:Int64,sha256:String,group:String,source:Int
    }
    struct Receipt:Codable {
        let schema:Int,profile:String,selectionIdentity:String
        let sourceID:String,sourceBytes:Int64,sourceName:String,contentID:String
        let resources:[Resource]
        func casefoldIndex()throws->[String:Resource]{
            var result:[String:Resource]=[:]
            for item in resources {
                guard result.updateValue(item,forKey:item.path.lowercased())==nil else{throw Failure.invalid("Ambiguous Windows resource identity: "+item.path)}
            }
            return result
        }
    }
    private struct Catalogue:Codable {
        var schema=1,activeSourceID:String?,sources:[String:String]=[:]
    }
    final class Operation {
        let cancellation=NativeISOExtraction.Cancellation()
        func cancel(){cancellation.cancel()}
        fileprivate func check()throws{if cancellation.isCancelled{throw Failure.cancelled}}
    }
    enum Failure:LocalizedError {
        case invalid(String),cancelled
        var errorDescription:String? {switch self {
        case .invalid(let reason):return reason
        case .cancelled:return "Raw extraction cancelled. Previously saved raw and installed resources were preserved."
        }}
    }
    static let shared:NativeRawResourceStore={
        let parent=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        return NativeRawResourceStore(root:parent.appendingPathComponent("ZGTA-SA/RawResources-v1",isDirectory:true))
    }()
    let root:URL
    private let extractor:Extractor,files=FileManager.default,lock=NSLock()
    private let worker=DispatchQueue(label:"org.zgtasa.raw-resources",qos:.userInitiated)
    private var value=Snapshot.empty,busy=false
    init(root:URL,extractor:Extractor = .originalISO){
        self.root=root.standardizedFileURL.resolvingSymlinksInPath();self.extractor=extractor
        do{try prepareRoot();let catalogue=try loadCatalogue();value=try retained(catalogue)}
        catch{value.issues=[error.localizedDescription]}
    }
    var snapshot:Snapshot{lock.lock();defer{lock.unlock()};return value}
    private func set(_ snapshot:Snapshot){lock.lock();value=snapshot;lock.unlock()}
    private func prepareRoot()throws{
        for directory in [root,root.appendingPathComponent("staging"),root.appendingPathComponent("generations")]{
            try files.createDirectory(at:directory,withIntermediateDirectories:true)
            let info=try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard info.isDirectory==true,info.isSymbolicLink != true else{throw Failure.invalid("Raw resource storage is not an app-owned directory")}
        }
        var location=root;var flags=URLResourceValues();flags.isExcludedFromBackup=true;try? location.setResourceValues(flags)
    }
    private func loadCatalogue()throws->Catalogue{
        let path=root.appendingPathComponent("catalogue.json")
        guard files.fileExists(atPath:path.path) else{return Catalogue()}
        let info=try path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile==true,info.isSymbolicLink != true,(info.fileSize ?? Int.max)<=1_048_576 else{throw Failure.invalid("Invalid saved raw-resource catalogue")}
        let result=try JSONDecoder().decode(Catalogue.self,from:Data(contentsOf:path))
        guard result.schema==1,result.sources.count<=128,result.sources.allSatisfy({Self.digest($0.key)&&UUID(uuidString:$0.value) != nil}),
              result.activeSourceID.map({result.sources[$0] != nil}) ?? true else{throw Failure.invalid("Invalid raw-resource source identities")}
        return result
    }
    private static func digest(_ text:String)->Bool{text.utf8.count==64&&text.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    private static func validPath(_ path:String)->Bool{
        NativeRawResourceSelection.isGameResourcePath(path)&&path.utf8.count<=1024&&path.utf8.allSatisfy{(32...126).contains($0)}
    }
    private func generation(_ id:String)throws->URL{
        guard UUID(uuidString:id) != nil else{throw Failure.invalid("Invalid raw stage identity")}
        let path=root.appendingPathComponent("generations/"+id,isDirectory:true)
        let info=try path.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard info.isDirectory==true,info.isSymbolicLink != true else{throw Failure.invalid("Saved raw-resource stage is missing")}
        return path
    }
    private func resourceURL(_ path:String,at stage:URL)throws->URL{
        guard Self.validPath(path),!path.contains(":"),!path.contains("\\") else{throw Failure.invalid("Invalid saved raw-resource path")}
        var result=stage.appendingPathComponent("files",isDirectory:true)
        let components=path.split(separator:"/",omittingEmptySubsequences:false)
        for (index,component) in components.enumerated(){
            guard !component.isEmpty,component != ".",component != "..",component.utf8.count<=255 else{throw Failure.invalid("Unsafe saved raw-resource path")}
            let parent=try result.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard parent.isDirectory==true,parent.isSymbolicLink != true else{throw Failure.invalid("Raw resource directory was replaced or linked")}
            result.appendPathComponent(String(component))
            if index==components.count-1{
                let leaf=try result.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                guard leaf.isRegularFile==true,leaf.isSymbolicLink != true else{throw Failure.invalid("Raw resource is missing or linked: "+path)}
            }
        }
        return result
    }
    private func receipt(at stage:URL,sourceID:String)throws->Receipt{
        let path=stage.appendingPathComponent("raw-resources.json"),info=try path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile==true,info.isSymbolicLink != true,(info.fileSize ?? Int.max)<=32*1_048_576 else{throw Failure.invalid("Missing or oversized raw-resource receipt")}
        let receipt=try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:path))
        guard receipt.schema==1,receipt.profile=="zgta-raw-resources-v1",receipt.selectionIdentity==extractor.identity,
              receipt.sourceID==sourceID,Self.digest(sourceID),receipt.sourceBytes>0,receipt.sourceName.utf8.count<=1024,
              !receipt.resources.isEmpty,receipt.resources.count<=10000 else{throw Failure.invalid("Unsupported saved raw-resource receipt")}
        var seen=Set<String>(),total:Int64=0
        for item in receipt.resources{
            guard Self.validPath(item.path),Self.digest(item.sha256),item.bytes>=0,item.bytes<=Int64(UInt32.max),
                  seen.insert(item.path.lowercased()).inserted,[1,2].contains(item.source),item.group.utf8.count<=1024,
                  item.group.utf8.allSatisfy({(32...126).contains($0)}) else{throw Failure.invalid("Ambiguous or invalid raw-resource receipt entry")}
            total+=item.bytes;guard total<=32*1024*1024*1024 else{throw Failure.invalid("Raw resource receipt exceeds its byte bound")}
        }
        guard Self.contentID(receipt.resources)==receipt.contentID else{throw Failure.invalid("Raw resource receipt identity mismatch")}
        _=try receipt.casefoldIndex()
        return receipt
    }
    private static func contentID(_ items:[Resource])->String{
        var hash=SHA256();hash.update(data:Data("zgta-raw-resources-v1\n".utf8))
        for item in items.sorted(by:{$0.path<$1.path}){hash.update(data:Data("\(item.path)\0\(item.bytes)\0\(item.sha256)\0\(item.source)\0\(item.group)\n".utf8))}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    private func retained(_ catalogue:Catalogue)throws->Snapshot{
        guard let sourceID=catalogue.activeSourceID,let id=catalogue.sources[sourceID] else{return .empty}
        let stage=try generation(id),receipt=try receipt(at:stage,sourceID:sourceID)
        for item in receipt.resources{let path=try resourceURL(item.path,at:stage);guard try path.resourceValues(forKeys:[.fileSizeKey]).fileSize==Int(item.bytes) else{throw Failure.invalid("Saved raw resources need repair: "+item.path)}}
        return Snapshot(sourceID:sourceID,contentID:receipt.contentID,sourceName:receipt.sourceName,files:receipt.resources.count,bytes:receipt.resources.reduce(0){$0+$1.bytes},verified:false,issues:[])
    }
    private func hash(_ path:URL,operation:Operation,progress:((Int64)->Void)?=nil)throws->(Int64,String){
        let input=try FileHandle(forReadingFrom:path);defer{try? input.close()};var hash=SHA256(),count:Int64=0
        while true {
            let read=try autoreleasepool{()throws->Int in
                try operation.check()
                guard let part=try input.read(upToCount:1_048_576),!part.isEmpty else{return 0}
                count+=Int64(part.count);hash.update(data:part);progress?(count);return part.count
            }
            if read==0{break}
        }
        try operation.check();return(count,hash.finalize().map{String(format:"%02x",$0)}.joined())
    }
    private func verify(_ receipt:Receipt,at stage:URL,operation:Operation,update:(NativeResourceStore.Progress)->Void)throws{
        var done:Int64=0;let total=receipt.resources.reduce(Int64(0)){$0+$1.bytes}
        for (index,item) in receipt.resources.enumerated(){
            try operation.check();let path=try resourceURL(item.path,at:stage),actual=try hash(path,operation:operation)
            guard actual.0==item.bytes,actual.1==item.sha256 else{throw Failure.invalid("Raw resource checksum mismatch: "+item.path)}
            done+=item.bytes;update(.init(phase:"Verifying saved raw resources",completedFiles:index+1,totalFiles:receipt.resources.count,completedBytes:done,totalBytes:total,currentPath:item.path))
        }
    }
    private func perform(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<Snapshot,Error>)->Void,invalidateOnFailure:Bool=false,
                         work:@escaping(Operation,@escaping(NativeResourceStore.Progress)->Void)throws->Snapshot)->Operation{
        let operation=Operation();lock.lock();let alreadyBusy=busy;if !alreadyBusy{busy=true};lock.unlock()
        guard !alreadyBusy else{DispatchQueue.main.async{completion(.failure(Failure.invalid("A raw resource operation is already running")))};return operation}
        worker.async{
            var lastProgressTime = -Double.infinity,lastPhase=""
            let update:(NativeResourceStore.Progress)->Void={value in
                let now=ProcessInfo.processInfo.systemUptime
                guard value.phase != lastPhase || now-lastProgressTime>=0.1 || value.completedFiles==value.totalFiles else{return}
                lastProgressTime=now;lastPhase=value.phase
                DispatchQueue.main.async{progress(value)}
            }
            let result=Result{()throws->Snapshot in
                try self.prepareRoot();let descriptor=open(self.root.appendingPathComponent("operation.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
                guard descriptor>=0 else{throw Failure.invalid("Cannot lock app-owned raw resource storage")}
                defer{flock(descriptor,LOCK_UN);close(descriptor)}
                guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else{throw Failure.invalid("Another raw resource operation owns this storage")}
                try operation.check()
                for path in try self.files.contentsOfDirectory(at:self.root.appendingPathComponent("staging"),includingPropertiesForKeys:nil){
                    if path.pathExtension=="partial",UUID(uuidString:path.deletingPathExtension().lastPathComponent) != nil{try self.files.removeItem(at:path)}
                }
                let referenced=Set(try self.loadCatalogue().sources.values)
                for path in try self.files.contentsOfDirectory(at:self.root.appendingPathComponent("generations"),includingPropertiesForKeys:nil){
                    if UUID(uuidString:path.lastPathComponent) != nil,!referenced.contains(path.lastPathComponent){try self.files.removeItem(at:path)}
                }
                return try work(operation,update)
            }
            if case .success(let snapshot)=result{self.set(snapshot)}
            if case .failure(let error)=result,invalidateOnFailure{var snapshot=self.snapshot;snapshot.verified=false;snapshot.issues=[error.localizedDescription];self.set(snapshot)}
            self.lock.lock();self.busy=false;self.lock.unlock()
            DispatchQueue.main.async{completion(result)}
        };return operation
    }
    @discardableResult func extractISO(_ source:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<Snapshot,Error>)->Void)->Operation{
        perform(progress:progress,completion:completion){operation,update in
            guard source.isFileURL else{throw Failure.invalid("Choose your original local ISO in Files")}
            let source=source.resolvingSymlinksInPath(),before=try self.sourceStamp(source)
            guard before.size<=64*1024*1024*1024,source.lastPathComponent.utf8.count<=1024 else{throw Failure.invalid("The original source exceeds the supported bounded ISO size or name")}
            let identified=try self.hash(source,operation:operation){count in update(.init(phase:"Identifying original ISO",completedFiles:0,totalFiles:1,completedBytes:count,totalBytes:before.size,currentPath:source.lastPathComponent))}
            guard identified.0==before.size,try self.sourceStamp(source)==before else{throw Failure.invalid("The ISO changed while it was being identified")}
            var catalogue=try self.loadCatalogue();let sourceID=identified.1
            guard catalogue.sources[sourceID] != nil || catalogue.sources.count<128 else{throw Failure.invalid("Raw resource storage has reached its supported source count")}
            if let id=catalogue.sources[sourceID]{
                do{
                    let stage=try self.generation(id),receipt=try self.receipt(at:stage,sourceID:sourceID)
                    try self.verify(receipt,at:stage,operation:operation,update:update);try operation.check()
                    if catalogue.activeSourceID != sourceID{catalogue.activeSourceID=sourceID;try self.commit(catalogue)}
                    var snapshot=try self.retained(catalogue);snapshot.verified=true;return snapshot
                }catch{try operation.check()} // Re-extract a corrupt saved generation; never reuse it silently.
            }
            let input=try self.extractor.open(source,operation.cancellation)
            var seen=Set<String>();let members=input.members
            guard !members.isEmpty,members.count<=10000 else{throw Failure.invalid("No bounded raw game-resource selection was found")}
            for item in members{guard Self.validPath(item.path),seen.insert(item.path.lowercased()).inserted,item.bytes<=UInt64(UInt32.max) else{throw Failure.invalid("Ambiguous raw resource destination: "+item.path)}}
            let total=members.reduce(Int64(0)){$0+Int64($1.bytes)};guard total<=32*1024*1024*1024 else{throw Failure.invalid("Raw extraction exceeds its output byte bound")}
            let id=UUID().uuidString,stage=self.root.appendingPathComponent("staging/"+id+".partial",isDirectory:true)
            try self.files.createDirectory(at:stage,withIntermediateDirectories:false);var moved:URL?
            defer{try? self.files.removeItem(at:stage);if let moved{try? self.files.removeItem(at:moved)}}
            try input.extract(stage.appendingPathComponent("files",isDirectory:true)){value in
                update(.init(phase:"Extracting original raw resources",completedFiles:Int(value.completedFiles),totalFiles:Int(value.totalFiles),completedBytes:Int64(value.completedBytes),totalBytes:Int64(value.totalBytes),currentPath:value.path))
            }
            var resources:[Resource]=[],done:Int64=0
            for (index,item) in members.enumerated(){
                try operation.check();let path=try self.resourceURL(item.path,at:stage),actual=try self.hash(path,operation:operation)
                guard actual.0==Int64(item.bytes) else{throw Failure.invalid("Raw resource size mismatch: "+item.path)}
                resources.append(.init(path:item.path,bytes:actual.0,sha256:actual.1,group:item.group,source:Int(item.source.rawValue)))
                done+=actual.0;update(.init(phase:"Checking extracted raw resources",completedFiles:index+1,totalFiles:members.count,completedBytes:done,totalBytes:total,currentPath:item.path))
            }
            guard try self.sourceStamp(source)==before else{throw Failure.invalid("The original ISO changed during extraction; retry with an unchanged source")}
            let receipt=Receipt(schema:1,profile:"zgta-raw-resources-v1",selectionIdentity:self.extractor.identity,sourceID:sourceID,sourceBytes:before.size,sourceName:source.lastPathComponent,contentID:Self.contentID(resources),resources:resources)
            try JSONEncoder().encode(receipt).write(to:stage.appendingPathComponent("raw-resources.json"),options:.atomic)
            _=try self.receipt(at:stage,sourceID:sourceID);try operation.check()
            let destination=self.root.appendingPathComponent("generations/"+id,isDirectory:true)
            try self.files.moveItem(at:stage,to:destination);moved=destination
            let prior=catalogue.sources[sourceID];catalogue.sources[sourceID]=id;catalogue.activeSourceID=sourceID
            try operation.check();try self.commit(catalogue);moved=nil
            if let prior,prior != id,let previous=try? self.generation(prior){try? self.files.removeItem(at:previous)}
            var snapshot=try self.retained(catalogue);snapshot.verified=true;return snapshot
        }
    }
    @discardableResult func verifyRaw(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<Snapshot,Error>)->Void)->Operation{
        perform(progress:progress,completion:completion,invalidateOnFailure:true){operation,update in
            let catalogue=try self.loadCatalogue();guard let source=catalogue.activeSourceID,let id=catalogue.sources[source] else{throw Failure.invalid("No saved raw resources are selected")}
            let stage=try self.generation(id),receipt=try self.receipt(at:stage,sourceID:source)
            try self.verify(receipt,at:stage,operation:operation,update:update)
            var snapshot=try self.retained(catalogue);snapshot.verified=true;return snapshot
        }
    }
    private func commit(_ catalogue:Catalogue)throws{try JSONEncoder().encode(catalogue).write(to:root.appendingPathComponent("catalogue.json"),options:.atomic)}
    private struct Stamp:Equatable{let size:Int64,number:UInt64,date:Date}
    private func sourceStamp(_ url:URL)throws->Stamp{
        let info=try files.attributesOfItem(atPath:url.path)
        guard info[.type] as? FileAttributeType == .typeRegular,let size=info[.size] as? NSNumber,let number=info[.systemFileNumber] as? NSNumber,let date=info[.modificationDate] as? Date,size.int64Value>0 else{throw Failure.invalid("A readable regular original ISO file is required")}
        return Stamp(size:size.int64Value,number:number.uint64Value,date:date)
    }
}
