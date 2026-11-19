// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
import Darwin

private enum TestError:Error {case failed(String)}
private var checks=0
private func check(_ value:Bool,_ label:String)throws {checks+=1;if !value{throw TestError.failed(label)}}
private func wait(_ condition:()->Bool)throws {
    let limit=Date().addingTimeInterval(30)
    while !condition(),Date()<limit{RunLoop.main.run(until:Date().addingTimeInterval(0.003))}
    try check(condition(),"bounded callback completed")
}
private func rejects(_ label:String,_ body:()throws->Void)throws {do{try body()}catch{try check(true,label);return};try check(false,label)}
private let primary="AUDIO/STREAMS/AUTHORED",configuration="audio/CONFIG/Authored.dat"
private let members=[primary,configuration,"data/authored.dat"]+(1...12).map{"audio/streams/UNUSED\($0)"}
private func body(_ path:String,_ tag:UInt8)->Data {
    if path==primary{return Data(repeating:tag,count:2*1_048_576+19)}
    return Data(("authored:"+path+":"+String(tag)).utf8)
}
private func extractor()->NativeRawResourceStore.Extractor {
    .init(identity:"authored-raw-lease-fixtures-v1"){source,token in
        let tag=try Data(contentsOf:source).first!
        let entries=members.enumerated().map{NativeISOExtraction.Entry(index:$0.offset,path:$0.element,group:$0.element.components(separatedBy:"/")[0],bytes:UInt64(body($0.element,tag).count),source:.cabinet)}
        return .init(members:entries,extract:{folder,update in
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
            for (index,item)in entries.enumerated(){
                if token.isCancelled{throw NativeISOExtraction.Failure.cancelled}
                let target=folder.appendingPathComponent(item.path)
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try body(item.path,tag).write(to:target)
                update(.init(path:item.path,completedBytes:UInt64(index+1),totalBytes:UInt64(entries.count),completedFiles:UInt32(index+1),totalFiles:UInt32(entries.count)))
            }
        })
    }
}
private func extract(_ store:NativeRawResourceStore,_ source:URL)throws->NativeRawResourceStore.Snapshot {
    var result:Result<NativeRawResourceStore.Snapshot,Error>?
    store.extractISO(source,progress:{_ in}){result=$0};try wait{result != nil};return try result!.get()
}
private func verify(_ store:NativeRawResourceStore)throws->NativeRawResourceStore.Snapshot {
    var result:Result<NativeRawResourceStore.Snapshot,Error>?
    store.verifyRaw(progress:{_ in}){result=$0};try wait{result != nil};return try result!.get()
}
private func receipt(_ store:NativeRawResourceStore)throws->NativeRawResourceStore.ReceiptDescriptor {
    var result:Result<NativeRawResourceStore.ReceiptDescriptor,Error>?
    store.readReceiptDescriptor{result=$0};try wait{result != nil};return try result!.get()
}
private func acquire(_ store:NativeRawResourceStore,_ path:String,matching descriptor:NativeRawResourceStore.ReceiptDescriptor?=nil)throws->NativeRawResourceLease {
    var result:Result<NativeRawResourceLease,Error>?
    if let descriptor {store.acquireLocalFile(path:path,matching:descriptor){result=$0}}
    else{store.acquireLocalFile(path:path){result=$0}}
    try wait{result != nil};return try result!.get()
}
private func resource(_ root:URL,_ descriptor:NativeRawResourceStore.ReceiptDescriptor,_ path:String)->URL {
    root.appendingPathComponent("generations/"+descriptor.generationID+"/files/"+path)
}
private final class Gate {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock();private var used=false
    let stage:NativeRawResourceLease.VerificationProgress.Stage
    init(_ stage:NativeRawResourceLease.VerificationProgress.Stage = .hashing){self.stage=stage}
    func observe(_ value:NativeRawResourceLease.VerificationProgress){
        lock.lock();let pause = !used && value.stage==stage;if pause{used=true};lock.unlock()
        if pause{entered.signal();precondition(release.wait(timeout:.now()+20) == .success,"authored observer gate timed out")}
    }
    func waitEntered()throws {try check(entered.wait(timeout:.now()+10) == .success,"worker reached actual verification observer")}
}
private final class Flag:@unchecked Sendable {
    private let lock=NSLock();private var state=false
    func set(){lock.lock();state=true;lock.unlock()}
    var value:Bool{lock.lock();defer{lock.unlock()};return state}
}
@main private struct RawLeaseSmoke {
    static func main()throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true),files=FileManager.default
        try files.createDirectory(at:folder,withIntermediateDirectories:true)
        let source=folder.appendingPathComponent("authored-A.iso"),other=folder.appendingPathComponent("authored-B.iso")
        try Data([65,1,2,3]).write(to:source);try Data([66,1,2,3]).write(to:other)
        let root=folder.appendingPathComponent("store"),factory=extractor(),initial=NativeRawResourceStore(root:root,extractor:factory)
        let installed=try extract(initial,source);try check(installed.verified && installed.files==15,"actual authored extraction verified all raw fixtures")
        let store=NativeRawResourceStore(root:root,extractor:factory)
        try check(!store.snapshot.verified,"relaunch retains raw source without inventing verification")
        let index=try receipt(store)
        try check(index.resourcesByCasefoldedPath[primary.lowercased()]?.path==primary,"receipt descriptor preserves exact spelling and casefold index")
        try check(index.resourcesByCasefoldedPath.count==15 && !store.snapshot.verified,"metadata alone does not verify raw source")
        let lease=try acquire(store,primary.lowercased(),matching:index)
        try check(lease.binding.path==primary && lease.binding.sourceID==index.sourceID && lease.binding.contentID==index.contentID && lease.binding.generationID==index.generationID,"lease binds actual source/content/generation/path")
        try check(lease.binding.bytes==Int64(body(primary,65).count),"lease byte bound comes from actual receipt")
        try check(!store.snapshot.verified,"one-file checksum does not verify installation")
        let first=try lease.read(atOffset:0,maximumBytes:1_048_576),tail=try lease.read(atOffset:Int64(body(primary,65).count-19),maximumBytes:1_048_576)
        try check(first==Data(repeating:65,count:1_048_576)&&tail==Data(repeating:65,count:19),"bounded pread and EOF clamp")
        try check(try lease.read(atOffset:lease.binding.bytes,maximumBytes:1).isEmpty,"EOF read is empty")
        try rejects("negative offset rejected"){_ = try lease.read(atOffset:-1,maximumBytes:1)}
        try rejects("offset overflow rejected"){_ = try lease.read(atOffset:Int64.max,maximumBytes:1)}
        try rejects("unbounded read rejected"){_ = try lease.read(atOffset:0,maximumBytes:1_048_577)}
        try rejects("outside selection rejected"){_ = try acquire(store,"../outside")}
        try rejects("unknown entry rejected"){_ = try acquire(store,"audio/streams/ABSENT")}
        let decoder=try lease.duplicateFileDescriptor()
        try decoder.withFileDescriptor{fd in
            try check(fcntl(fd,F_GETFL)&O_ACCMODE==O_RDONLY,"decoder descriptor is read-only")
            try check(fcntl(fd,F_GETFD)&FD_CLOEXEC != 0,"decoder descriptor is close-on-exec")
            var bytes=[UInt8](repeating:0,count:8);let count=pread(fd,&bytes,bytes.count,7)
            try check(count==8 && bytes.allSatisfy{$0==65},"C construction seam reads verified original FD")
        }
        var duplicates:[NativeRawResourceLease.Descriptor]=[]
        for _ in 1..<NativeRawResourceLease.maximumDescriptorHandles{duplicates.append(try lease.duplicateFileDescriptor())}
        try rejects("descriptor quota enforced"){_ = try lease.duplicateFileDescriptor()}
        duplicates.forEach{$0.close()};duplicates=[]
        let generationPath=root.appendingPathComponent("generations/"+index.generationID)
        let lockPath=root.appendingPathComponent("lease-locks/"+index.generationID+".lock")
        let lockInode=(try files.attributesOfItem(atPath:lockPath.path)[.systemFileNumber]as!NSNumber).uint64Value
        // Repair another file. The valid opened pack/decoder must survive while
        // the old generation becomes obsolete and collection is attempted.
        try Data("damaged".utf8).write(to:resource(root,index,configuration))
        let repaired=try extract(store,source),afterRepair=try receipt(store)
        try check(repaired.verified && afterRepair.generationID != index.generationID && afterRepair.contentID==index.contentID,"repair publishes a new generation with the same exact content")
        try check(files.fileExists(atPath:generationPath.path),"repair skips leased old generation")
        try check(try lease.read(atOffset:0,maximumBytes:8)==Data(repeating:65,count:8),"old immutable lease survives repair")
        lease.close();try rejects("closed lease refuses reads"){_ = try lease.read(atOffset:0,maximumBytes:1)}
        try decoder.withFileDescriptor{fd in var byte:UInt8=0;try check(pread(fd,&byte,1,0)==1 && byte==65,"descriptor retains generation after public lease close")}
        _=try verify(NativeRawResourceStore(root:root,extractor:factory))
        try check(files.fileExists(atPath:generationPath.path),"other Store cleanup skips decoder-pinned generation")
        try rejects("stale receipt cannot silently acquire replacement"){_ = try acquire(store,primary,matching:index)}

        // Source swaps after actual final verification but before delivery must
        // fail at the delivery fence rather than publish an obsolete request.
        let ready=Gate(.verified);var stale:Result<NativeRawResourceLease,Error>?
        store.acquireLocalFile(path:primary,matching:afterRepair,verificationProgress:ready.observe){stale=$0}
        try ready.waitEntered();_ = try extract(store,other);let sourceB=try receipt(store)
        ready.release.signal();try wait{stale != nil}
        switch stale!{case .success(let value):value.close();try check(false,"obsolete delivery rejected");case .failure:try check(true,"obsolete delivery rejected")}
        try check(store.snapshot.sourceID==sourceB.sourceID&&store.snapshot.verified,"old result cannot revoke newer source state")
        try decoder.withFileDescriptor{fd in var byte:UInt8=0;try check(pread(fd,&byte,1,0)==1 && byte==65,"old decoder remains valid after source switch")}

        // A lightweight descriptor does not touch/hash even unreadable or
        // corrupt unrequested packs. Only the requested pack is checked later.
        let unrequested="audio/streams/UNUSED12",unrequestedURL=resource(root,sourceB,unrequested)
        let originalUnused=body(unrequested,66)
        try Data(repeating:0,count:originalUnused.count).write(to:unrequestedURL)
        try files.setAttributes([.posixPermissions:0],ofItemAtPath:unrequestedURL.path)
        let reopened=NativeRawResourceStore(root:root,extractor:factory),lightweight=try receipt(reopened)
        try check(lightweight.generationID==sourceB.generationID && !reopened.snapshot.verified,"descriptor stays metadata-only across all13 packs")
        try files.setAttributes([.posixPermissions:0o600],ofItemAtPath:unrequestedURL.path)
        try rejects("lazy pack acquire verifies actual whole checksum"){_ = try acquire(reopened,unrequested,matching:lightweight)}
        try originalUnused.write(to:unrequestedURL)
        _=try verify(store)

        let cancelGate=Gate();var cancelled:Result<NativeRawResourceLease,Error>?
        let cancel=store.acquireLocalFile(path:primary,matching:sourceB,verificationProgress:cancelGate.observe){cancelled=$0}
        try cancelGate.waitEntered();cancel.cancel();cancelGate.release.signal();try wait{cancelled != nil}
        switch cancelled!{case .success(let value):value.close();try check(false,"hash cancellation rejects result");case .failure:try check(true,"hash cancellation rejects result")}
        try check(store.snapshot.verified,"cancellation preserves full verification state")

        // An observation begun before a newer full verification must not revoke
        // it, even when content and generation IDs are unchanged.
        let mutationGate=Gate();var mutation:Result<NativeRawResourceLease,Error>?
        store.acquireLocalFile(path:primary,matching:sourceB,verificationProgress:mutationGate.observe){mutation=$0}
        try mutationGate.waitEntered()
        let pack=resource(root,sourceB,primary),writer=try FileHandle(forWritingTo:pack)
        try writer.seek(toOffset:UInt64(body(primary,66).count-1));try writer.write(contentsOf:Data([0]));try writer.seek(toOffset:UInt64(body(primary,66).count-1));try writer.write(contentsOf:Data([66]));try writer.close()
        _=try verify(store);mutationGate.release.signal();try wait{mutation != nil}
        switch mutation!{case .success(let value):value.close();try check(false,"file mutation during hash rejected");case .failure:try check(true,"file mutation during hash rejected")}
        try check(store.snapshot.verified,"stale mutation cannot revoke newer whole verification")

        let live=try acquire(store,primary,matching:sourceB),readGate=DispatchSemaphore(value:0),releaseRead=DispatchSemaphore(value:0),closing=Flag(),closed=Flag(),readDone=Flag()
        DispatchQueue.global().async {try! live.withFileDescriptor{fd in readGate.signal();precondition(releaseRead.wait(timeout:.now()+10) == .success);var byte:UInt8=0;precondition(pread(fd,&byte,1,0)==1 && byte==66)};readDone.set()}
        try check(readGate.wait(timeout:.now()+5) == .success,"decoder initialization entered owned FD seam")
        DispatchQueue.global().async {closing.set();live.close();closed.set()}
        try wait{closing.value}
        Thread.sleep(forTimeInterval:0.05);try check(!closed.value,"close waits for decoder initialization")
        releaseRead.signal();try wait{closed.value&&readDone.value}

        let tamper=try acquire(store,primary,matching:sourceB)
        let handle=try FileHandle(forWritingTo:pack);try handle.write(contentsOf:Data([0]));try handle.close()
        try rejects("post-acquire mutation detected"){_ = try tamper.read(atOffset:0,maximumBytes:8)}
        try wait{!store.snapshot.verified};tamper.close();_ = try extract(store,other)
        let final=try receipt(store)
        let external=folder.appendingPathComponent("outside-authored.dat");try body(configuration,66).write(to:external)
        let config=resource(root,final,configuration);try files.removeItem(at:config);try files.createSymbolicLink(at:config,withDestinationURL:external)
        try rejects("leaf symlink cannot be acquired"){_ = try acquire(store,configuration,matching:final)}
        _=try extract(store,other)
        let hard=try receipt(store),hardPath=resource(root,hard,configuration)
        try files.removeItem(at:hardPath);try files.linkItem(at:external,to:hardPath)
        try rejects("hardlinked external alias cannot be acquired"){_ = try acquire(store,configuration,matching:hard)}
        _=try extract(store,other);try check(files.fileExists(atPath:external.path),"cleanup never removes external alias target")

        decoder.close();_ = try verify(NativeRawResourceStore(root:root,extractor:factory))
        try check(!files.fileExists(atPath:generationPath.path),"unleased obsolete generation collected later")
        let retainedInode=(try files.attributesOfItem(atPath:lockPath.path)[.systemFileNumber]as!NSNumber).uint64Value
        try check(retainedInode==lockInode,"generation lock inode persists after collection")
        let report:[String:Any]=["status":"PASS","checks":checks,"fixtures":"Actual RawStore with independently authored extractor/source/raw bytes; no original assets or radio decoding.","limits":["No App/physical/Simulator/UI/network/playback acceptance.","One-file verification and metadata descriptors do not verify the entire raw source or activate gameplay.","Descriptor closures borrow FDs; retained decoder owners must honor that lifetime contract."]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("report.json"))
        print("RAW_LEASE_PASS checks=\(checks)")
    }
}
