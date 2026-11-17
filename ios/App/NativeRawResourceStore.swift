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
    /// Receipt metadata only. No pack is opened/hashed and no verification or
    /// playable state is conferred. Consumers acquire requested files lazily.
    struct ReceiptDescriptor {
        let sourceID:String,contentID:String,generationID:String,selectionIdentity:String,sourceName:String
        let sourceBytes:Int64
        let resourcesByCasefoldedPath:[String:Resource]
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
    private let leaseWorker:OperationQueue={let queue=OperationQueue();queue.name="org.zgtasa.raw-resource-reads";queue.qualityOfService = .utility;queue.maxConcurrentOperationCount=2;return queue}()
    private var value=Snapshot.empty,busy=false,leaseRequests=0,liveLeaseStorages=0,receiptRequests=0
    private var snapshotRevision=UUID()
    init(root:URL,extractor:Extractor = .originalISO){
        self.root=root.standardizedFileURL.resolvingSymlinksInPath();self.extractor=extractor
        do{try prepareRoot();let catalogue=try loadCatalogue();value=try retained(catalogue)}
        catch{value.issues=[error.localizedDescription]}
    }
    var snapshot:Snapshot{lock.lock();defer{lock.unlock()};return value}
    private func set(_ snapshot:Snapshot){lock.lock();value=snapshot;snapshotRevision=UUID();lock.unlock()}
    private func prepareRoot()throws{
        for directory in [root,root.appendingPathComponent("staging"),root.appendingPathComponent("generations"),root.appendingPathComponent("lease-locks")]{
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
                    if UUID(uuidString:path.lastPathComponent) != nil,!referenced.contains(path.lastPathComponent){try self.removeUnleasedGeneration(path.lastPathComponent)}
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
            defer{try? self.files.removeItem(at:stage);if let moved{try? self.removeUnleasedGeneration(moved.lastPathComponent)}}
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
            if let prior,prior != id{try? self.removeUnleasedGeneration(prior)}
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
    /// Called only while the existing global exclusive operation lock is held.
    /// Persistent lock files are deliberately retained to avoid inode races.
    private func removeUnleasedGeneration(_ id:String)throws {
        guard let exclusive=try NativeRawResourceGenerationLock.acquire(root:root,generation:id,exclusive:true) else{return}
        defer{exclusive.close()}
        let path=try generation(id);try files.removeItem(at:path)
    }
    /// Whole-file verification runs on a bounded worker queue. Progress is
    /// immutable and synchronous on that worker; UI clients must marshal it.
    /// Completion is main-queue, and reading never verifies the whole source.
    @discardableResult func acquireLocalFile(path:String,expectedSourceID:String?=nil,expectedContentID:String?=nil,
        expectedGenerationID:String?=nil,maximumBytes:Int64=Int64(UInt32.max),
        verificationProgress:((NativeRawResourceLease.VerificationProgress)->Void)?=nil,
        completion:@escaping(Result<NativeRawResourceLease,Error>)->Void)->NativeRawResourceLease.Request {
        let request=NativeRawResourceLease.Request()
        lock.lock();let admitted=leaseRequests<16;if admitted{leaseRequests+=1};lock.unlock()
        guard admitted else{request.deliver(.failure(NativeRawResourceLease.Failure.invalid("Too many pending raw file acquisitions.")),fence:{},completion:completion);return request}
        leaseWorker.addOperation {
            var binding:NativeRawResourceLease.Binding?,catalogueStamp:NativeRawResourceFileStamp?,receiptStamp:NativeRawResourceFileStamp?
            self.lock.lock();let observationRevision=self.snapshotRevision;self.lock.unlock()
            let result=Result{()throws->NativeRawResourceLease in
                self.lock.lock();let reserved=self.liveLeaseStorages<16;if reserved{self.liveLeaseStorages+=1};self.lock.unlock()
                guard reserved else{throw NativeRawResourceLease.Failure.invalid("Too many live raw file leases.")}
                var slotOwned=true;defer{if slotOwned{self.releaseLeaseStorage()}}
                try request.check()
                guard Self.validPath(path),!path.contains(":"),!path.contains("\\"),maximumBytes>=0,maximumBytes<=Int64(UInt32.max),
                    expectedSourceID.map(Self.digest) ?? true,expectedContentID.map(Self.digest) ?? true,
                    expectedGenerationID.map({UUID(uuidString:$0) != nil}) ?? true else{throw NativeRawResourceLease.Failure.invalid("Invalid raw file lease request.")}
                try self.prepareRoot()
                let catalogueLock=try NativeRawResourceFileIO.operationReadLock(root:self.root)
                var shared:NativeRawResourceGenerationLock?,descriptor:Int32 = -1
                defer{catalogueLock.close();if descriptor>=0{Darwin.close(descriptor)};shared?.close()}
                let catalogue=try self.loadCatalogue()
                guard let source=catalogue.activeSourceID,let id=catalogue.sources[source] else{throw NativeRawResourceLease.Failure.invalid("No saved raw resource source is selected.")}
                guard expectedSourceID.map({$0==source}) ?? true,expectedGenerationID.map({$0==id}) ?? true else{throw NativeRawResourceLease.Failure.stale}
                guard let held=try NativeRawResourceGenerationLock.acquire(root:self.root,generation:id,exclusive:false) else{throw NativeRawResourceLease.Failure.busy};shared=held
                let stage=try self.generation(id),receipt=try self.receipt(at:stage,sourceID:source)
                guard expectedContentID.map({$0==receipt.contentID}) ?? true else{throw NativeRawResourceLease.Failure.stale}
                guard let item=try receipt.casefoldIndex()[path.lowercased()] else{throw NativeRawResourceLease.Failure.invalid("Requested file is absent from the selected raw receipt: "+path)}
                guard item.bytes<=maximumBytes else{throw NativeRawResourceLease.Failure.invalid("Raw file exceeds this reader's byte budget.")}
                let selected=NativeRawResourceLease.Binding(sourceID:source,contentID:receipt.contentID,generationID:id,selectionIdentity:receipt.selectionIdentity,path:item.path,bytes:item.bytes,sha256:item.sha256);binding=selected
                receiptStamp=try NativeRawResourceFileIO.metadataStamp(root:self.root,components:["generations",id],name:"raw-resources.json")
                descriptor=try NativeRawResourceFileIO.openResource(root:self.root,generation:id,path:item.path)
                let before=try NativeRawResourceFileStamp.read(descriptor)
                guard before.size==item.bytes else{throw NativeRawResourceLease.Failure.changed}
                // The generation lock pins immutable bytes while repair/source
                // replacement proceeds independently under operation.lock.
                catalogueLock.close()
                var hash=SHA256(),offset:Int64=0
                while offset<item.bytes {
                    try request.check()
                    let count=Int(min(Int64(NativeRawResourceLease.maximumReadBytes),item.bytes-offset))
                    var chunk=Data(count:count),done=0
                    while done<count {
                        try request.check()
                        let read=chunk.withUnsafeMutableBytes{buffer in Darwin.pread(descriptor,buffer.baseAddress!.advanced(by:done),count-done,off_t(offset+Int64(done)))}
                        if read<0{if errno==EINTR{continue};throw NativeRawResourceLease.Failure.io(errno)}
                        guard read>0 else{throw NativeRawResourceLease.Failure.changed};done+=read
                    }
                    hash.update(data:chunk);offset+=Int64(count)
                    verificationProgress?(.init(binding:selected,verifiedBytes:offset))
                }
                try request.check()
                guard try NativeRawResourceFileStamp.read(descriptor)==before else{throw NativeRawResourceLease.Failure.changed}
                guard hash.finalize().map({String(format:"%02x",$0)}).joined()==item.sha256 else{throw NativeRawResourceLease.Failure.checksum}
                let finalLock=try NativeRawResourceFileIO.operationReadLock(root:self.root);defer{finalLock.close()}
                let current=try self.loadCatalogue()
                guard current.activeSourceID==source,current.sources[source]==id,
                    try NativeRawResourceFileIO.metadataStamp(root:self.root,components:["generations",id],name:"raw-resources.json")==receiptStamp else{throw NativeRawResourceLease.Failure.stale}
                catalogueStamp=try NativeRawResourceFileIO.catalogueStamp(root:self.root)
                try request.check()
                finalLock.close()
                let storage=NativeRawResourceLease.Storage(binding:selected,fd:descriptor,generationLock:held,stamp:before,
                    fault:{[weak self] in self?.noteLeaseFault($0,revision:observationRevision)},released:{[weak self] in self?.releaseLeaseStorage()})
                descriptor = -1;shared=nil;slotOwned=false
                verificationProgress?(.init(binding:selected,verifiedBytes:item.bytes,stage:.verified))
                try request.check()
                return NativeRawResourceLease(storage:storage)
            }
            if case .failure(let error)=result,let binding {
                if let failure=error as? NativeRawResourceLease.Failure {
                    switch failure{case .changed,.checksum:self.noteLeaseFault(binding,revision:observationRevision);default:break}
                }
            }
            request.deliver(result,fence:{
                guard case .success=result,let binding,let catalogueStamp,let receiptStamp else{return}
                let current=try NativeRawResourceFileIO.operationReadLock(root:self.root);defer{current.close()}
                guard try NativeRawResourceFileIO.catalogueStamp(root:self.root)==catalogueStamp,
                    try NativeRawResourceFileIO.metadataStamp(root:self.root,components:["generations",binding.generationID],name:"raw-resources.json")==receiptStamp else{throw NativeRawResourceLease.Failure.stale}
            },completion:{value in
                self.lock.lock();self.leaseRequests-=1;self.lock.unlock();completion(value)
            })
        }
        return request
    }
    private func releaseLeaseStorage(){lock.lock();liveLeaseStorages-=1;lock.unlock()}
    @discardableResult func acquireLocalFile(path:String,matching descriptor:ReceiptDescriptor,maximumBytes:Int64=Int64(UInt32.max),
        verificationProgress:((NativeRawResourceLease.VerificationProgress)->Void)?=nil,
        completion:@escaping(Result<NativeRawResourceLease,Error>)->Void)->NativeRawResourceLease.Request {
        acquireLocalFile(path:path,expectedSourceID:descriptor.sourceID,expectedContentID:descriptor.contentID,
            expectedGenerationID:descriptor.generationID,maximumBytes:maximumBytes,
            verificationProgress:verificationProgress,completion:completion)
    }
    /// Lightweight immutable index for radio catalogue construction. Only the
    /// bounded receipt is decoded; stream/config bytes are verified on demand.
    @discardableResult func readReceiptDescriptor(expectedSourceID:String?=nil,expectedContentID:String?=nil,
        completion:@escaping(Result<ReceiptDescriptor,Error>)->Void)->NativeRawResourceLease.Request {
        let request=NativeRawResourceLease.Request()
        lock.lock();let admitted=receiptRequests<2;if admitted{receiptRequests+=1};lock.unlock()
        guard admitted else{request.deliverValue(.failure(NativeRawResourceLease.Failure.invalid("Too many pending raw receipt reads.")),fence:{},completion:completion);return request}
        leaseWorker.addOperation {
            var catalogueStamp:NativeRawResourceFileStamp?,receiptStamp:NativeRawResourceFileStamp?
            let result=Result{()throws->ReceiptDescriptor in
                try request.check()
                guard expectedSourceID.map(Self.digest) ?? true,expectedContentID.map(Self.digest) ?? true else{throw NativeRawResourceLease.Failure.invalid("Invalid expected raw receipt identity.")}
                try self.prepareRoot();let global=try NativeRawResourceFileIO.operationReadLock(root:self.root);defer{global.close()}
                let catalogue=try self.loadCatalogue()
                guard let source=catalogue.activeSourceID,let id=catalogue.sources[source] else{throw NativeRawResourceLease.Failure.invalid("No saved raw resource source is selected.")}
                guard expectedSourceID.map({$0==source}) ?? true else{throw NativeRawResourceLease.Failure.stale}
                guard let shared=try NativeRawResourceGenerationLock.acquire(root:self.root,generation:id,exclusive:false) else{throw NativeRawResourceLease.Failure.busy};defer{shared.close()}
                let before=try NativeRawResourceFileIO.metadataStamp(root:self.root,components:["generations",id],name:"raw-resources.json")
                let receipt=try self.receipt(at:self.generation(id),sourceID:source)
                guard expectedContentID.map({$0==receipt.contentID}) ?? true else{throw NativeRawResourceLease.Failure.stale}
                guard try NativeRawResourceFileIO.metadataStamp(root:self.root,components:["generations",id],name:"raw-resources.json")==before else{throw NativeRawResourceLease.Failure.stale}
                receiptStamp=before;catalogueStamp=try NativeRawResourceFileIO.catalogueStamp(root:self.root)
                try request.check()
                return ReceiptDescriptor(sourceID:source,contentID:receipt.contentID,generationID:id,selectionIdentity:receipt.selectionIdentity,
                    sourceName:receipt.sourceName,sourceBytes:receipt.sourceBytes,resourcesByCasefoldedPath:try receipt.casefoldIndex())
            }
            request.deliverValue(result,fence:{
                guard case .success(let descriptor)=result,let catalogueStamp,let receiptStamp else{return}
                let current=try NativeRawResourceFileIO.operationReadLock(root:self.root);defer{current.close()}
                guard try NativeRawResourceFileIO.catalogueStamp(root:self.root)==catalogueStamp,
                    try NativeRawResourceFileIO.metadataStamp(root:self.root,components:["generations",descriptor.generationID],name:"raw-resources.json")==receiptStamp else{throw NativeRawResourceLease.Failure.stale}
            },completion:{value in self.lock.lock();self.receiptRequests-=1;self.lock.unlock();completion(value)})
        }
        return request
    }
    private func noteLeaseFault(_ binding:NativeRawResourceLease.Binding,revision:UUID) {
        worker.async {
            do {
                let current=try NativeRawResourceFileIO.operationReadLock(root:self.root);defer{current.close()}
                let catalogue=try self.loadCatalogue()
                guard catalogue.activeSourceID==binding.sourceID,catalogue.sources[binding.sourceID]==binding.generationID else{return}
                self.lock.lock();defer{self.lock.unlock()}
                guard self.snapshotRevision==revision,self.value.sourceID==binding.sourceID,self.value.contentID==binding.contentID else{return}
                self.value.verified=false
                self.snapshotRevision=UUID()
                let message="Raw file changed; verify or repair: "+binding.path
                if !self.value.issues.contains(message){self.value.issues.append(message)}
            }catch{} // Stale/busy observations never revoke a newer generation.
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
