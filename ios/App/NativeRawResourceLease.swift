// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
import Darwin

/// Verified original bytes only. No URL, playable status, PCM export or network
/// access is provided. Each live storage/descriptor owner pins its generation.
final class NativeRawResourceLease {
    struct Binding:Equatable {
        let sourceID:String,contentID:String,generationID:String,selectionIdentity:String
        let path:String,bytes:Int64,sha256:String
    }
    struct VerificationProgress {
        enum Stage {case hashing,verified}
        let binding:Binding,verifiedBytes:Int64,stage:Stage
        init(binding:Binding,verifiedBytes:Int64,stage:Stage = .hashing){self.binding=binding;self.verifiedBytes=verifiedBytes;self.stage=stage}
    }
    enum Failure:Swift.Error,LocalizedError {
        case invalid(String),busy,stale,cancelled,closed,changed,checksum,io(Int32)
        var errorDescription:String? {switch self {
        case .invalid(let s):return s
        case .busy:return "Raw storage is busy; retry this read after its current operation."
        case .stale:return "The selected raw resource generation changed before this read was delivered."
        case .cancelled:return "Raw resource read cancelled."
        case .closed:return "Raw resource lease is closed."
        case .changed:return "The leased raw file changed; verify or repair the saved raw resources."
        case .checksum:return "The requested raw file does not match its saved checksum."
        case .io(let code):return "Raw resource file I/O failed (\(code))."
        }}
    }
    final class Request {
        private let lock=NSLock();private var cancelled=false,delivered=false
        func cancel(){lock.lock();if !delivered{cancelled=true};lock.unlock()}
        var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
        func check()throws{if isCancelled{throw Failure.cancelled}}
        /// The final fence is a bounded metadata check, never hashing/decoding.
        func deliver(_ result:Result<NativeRawResourceLease,Swift.Error>,fence:@escaping()throws->Void,
                     completion:@escaping(Result<NativeRawResourceLease,Swift.Error>)->Void){
            deliverValue(result,discard:{$0.close()},fence:fence,completion:completion)
        }
        func deliverValue<T>(_ result:Result<T,Swift.Error>,discard:@escaping(T)->Void={_ in},fence:@escaping()throws->Void,
                             completion:@escaping(Result<T,Swift.Error>)->Void){
            DispatchQueue.main.async {
                self.lock.lock();let stop=self.cancelled;self.delivered=true;self.lock.unlock()
                if stop {if case .success(let value)=result{discard(value)};completion(.failure(Failure.cancelled));return}
                do {try fence();completion(result)}catch{if case .success(let value)=result{discard(value)};completion(.failure(error))}
            }
        }
    }
    /// Own this handle for as long as a C decoder needs generation protection.
    /// The borrowed FD must not be closed or retained by the closure. A C API
    /// taking FD ownership must duplicate it, while retaining this handle.
    final class Descriptor {
        private let lock=NSRecursiveLock();private var storage:Storage?,fd:Int32
        fileprivate init(storage:Storage,fd:Int32){self.storage=storage;self.fd=fd}
        deinit{close()}
        var binding:Binding?{lock.lock();defer{lock.unlock()};return storage?.binding}
        func withFileDescriptor<T>(_ body:(Int32)throws->T)throws->T {
            lock.lock();defer{lock.unlock()}
            guard let storage,fd>=0 else{throw Failure.closed}
            return try storage.borrow(fd:fd,body)
        }
        func close(){
            lock.lock();let old=fd,held=storage;fd = -1;storage=nil
            if old>=0{Darwin.close(old)};lock.unlock()
            if old>=0{held?.releaseDescriptor()}
        }
    }
    static let maximumReadBytes=1_048_576,maximumDescriptorHandles=8
    private let lock=NSRecursiveLock();private var storage:Storage?
    let binding:Binding
    init(storage:Storage){self.storage=storage;binding=storage.binding}
    deinit{close()}
    func close(){lock.lock();storage=nil;lock.unlock()}
    func read(atOffset offset:Int64,maximumBytes:Int)throws->Data {
        lock.lock();defer{lock.unlock()};guard let storage else{throw Failure.closed}
        return try storage.read(atOffset:offset,maximumBytes:maximumBytes)
    }
    /// Borrowed read-only FD, serialized with read/dup/close and mutation checks.
    /// The closure must not close or retain it; prefer an owned Descriptor when
    /// decoder lifetime extends beyond construction.
    func withFileDescriptor<T>(_ body:(Int32)throws->T)throws->T {
        lock.lock();defer{lock.unlock()};guard let storage else{throw Failure.closed}
        return try storage.borrow(fd:storage.fd,body)
    }
    func duplicateFileDescriptor()throws->Descriptor {
        lock.lock();defer{lock.unlock()};guard let storage else{throw Failure.closed}
        return try storage.duplicate()
    }

    final class Storage {
        let binding:Binding,fd:Int32
        private let generationLock:NativeRawResourceGenerationLock,stamp:NativeRawResourceFileStamp
        private let lock=NSRecursiveLock();private var descriptors=0,faultSent=false
        private let fault:(Binding)->Void
        private let released:()->Void
        init(binding:Binding,fd:Int32,generationLock:NativeRawResourceGenerationLock,
             stamp:NativeRawResourceFileStamp,fault:@escaping(Binding)->Void,released:@escaping()->Void){
            self.binding=binding;self.fd=fd;self.generationLock=generationLock;self.stamp=stamp;self.fault=fault;self.released=released
        }
        deinit{Darwin.close(fd);generationLock.close();released()}
        private func validate(_ descriptor:Int32)throws {
            guard try NativeRawResourceFileStamp.read(descriptor)==stamp else {
                if !faultSent{faultSent=true;fault(binding)};throw Failure.changed
            }
        }
        func read(atOffset offset:Int64,maximumBytes:Int)throws->Data {
            lock.lock();defer{lock.unlock()}
            guard offset>=0,offset<=binding.bytes,maximumBytes>=0,maximumBytes<=NativeRawResourceLease.maximumReadBytes else{throw Failure.invalid("Raw lease read exceeds its offset or chunk bound.")}
            try validate(fd)
            let count=Int(min(Int64(maximumBytes),binding.bytes-offset))
            var result=Data(count:count),done=0
            while done<count {
                let received=result.withUnsafeMutableBytes{buffer in Darwin.pread(fd,buffer.baseAddress!.advanced(by:done),count-done,off_t(offset+Int64(done)))}
                if received<0{if errno==EINTR{continue};throw Failure.io(errno)}
                guard received>0 else{if !faultSent{faultSent=true;fault(binding)};throw Failure.changed}
                done+=received
            }
            try validate(fd);return result
        }
        func borrow<T>(fd:Int32,_ body:(Int32)throws->T)throws->T {
            lock.lock();defer{lock.unlock()};try validate(fd)
            let result=Result{try body(fd)};try validate(fd);return try result.get()
        }
        func duplicate()throws->Descriptor {
            lock.lock();defer{lock.unlock()};try validate(fd)
            guard descriptors<NativeRawResourceLease.maximumDescriptorHandles else{throw Failure.invalid("Too many raw decoder descriptor handles.")}
            let duplicate=fcntl(fd,F_DUPFD_CLOEXEC,0)
            guard duplicate>=0 else{throw Failure.io(errno)}
            descriptors+=1;return Descriptor(storage:self,fd:duplicate)
        }
        func releaseDescriptor(){lock.lock();descriptors-=1;lock.unlock()}
    }
}

/// Nanosecond identity excludes atime because ordinary reads may update it.
struct NativeRawResourceFileStamp:Equatable {
    let device:UInt32,inode:UInt64,mode:UInt32,owner:UInt32,links:UInt64,size:Int64
    let modifiedSeconds:Int64,modifiedNanoseconds:Int64,changedSeconds:Int64,changedNanoseconds:Int64
    static func read(_ fd:Int32)throws->Self {
        var value=stat();guard fstat(fd,&value)==0 else{throw NativeRawResourceLease.Failure.io(errno)}
        guard UInt32(value.st_mode)&UInt32(S_IFMT)==UInt32(S_IFREG),value.st_uid==geteuid(),value.st_nlink==1,value.st_size>=0 else{throw NativeRawResourceLease.Failure.invalid("Raw reads require a regular file owned by this app, with one hard link.")}
        return Self(device:UInt32(bitPattern:value.st_dev),inode:UInt64(value.st_ino),mode:UInt32(value.st_mode),owner:value.st_uid,links:UInt64(value.st_nlink),size:Int64(value.st_size),modifiedSeconds:Int64(value.st_mtimespec.tv_sec),modifiedNanoseconds:Int64(value.st_mtimespec.tv_nsec),changedSeconds:Int64(value.st_ctimespec.tv_sec),changedNanoseconds:Int64(value.st_ctimespec.tv_nsec))
    }
}

/// These lock files are persistent and must never be unlinked/recreated while
/// generations are collected. All catalogue/extraction writers use operation.lock.
final class NativeRawResourceGenerationLock {
    private var fd:Int32;private let lock=NSLock()
    init(fd:Int32){self.fd=fd}
    deinit{close()}
    func close(){lock.lock();let old=fd;fd = -1;lock.unlock();if old>=0{_ = flock(old,LOCK_UN);Darwin.close(old)}}
    static func acquire(root:URL,generation:String,exclusive:Bool)throws->NativeRawResourceGenerationLock? {
        guard UUID(uuidString:generation) != nil else{throw NativeRawResourceLease.Failure.invalid("Invalid raw generation lock identity.")}
        let directory=try NativeRawResourceFileIO.openDirectory(root:root,components:["lease-locks"]);defer{Darwin.close(directory)}
        let descriptor=openat(directory,generation+".lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard descriptor>=0 else{throw NativeRawResourceLease.Failure.io(errno)}
        do {
            let stamp=try NativeRawResourceFileStamp.read(descriptor)
            guard stamp.size==0,stamp.mode&0o077==0 else{throw NativeRawResourceLease.Failure.invalid("Unsafe raw generation lock file.")}
            guard flock(descriptor,(exclusive ? LOCK_EX:LOCK_SH)|LOCK_NB)==0 else{
                let code=errno
                if code==EWOULDBLOCK || code==EAGAIN{Darwin.close(descriptor);return nil};throw NativeRawResourceLease.Failure.io(code)
            }
            return .init(fd:descriptor)
        }catch{Darwin.close(descriptor);throw error}
    }
}

enum NativeRawResourceFileIO {
    private static func directory(_ fd:Int32)throws {
        var value=stat();guard fstat(fd,&value)==0 else{throw NativeRawResourceLease.Failure.io(errno)}
        guard UInt32(value.st_mode)&UInt32(S_IFMT)==UInt32(S_IFDIR),value.st_uid==geteuid() else{throw NativeRawResourceLease.Failure.invalid("Raw read directories must be owned directories.")}
    }
    static func openDirectory(root:URL,components:[String])throws->Int32 {
        var current=open(root.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard current>=0 else{throw NativeRawResourceLease.Failure.io(errno)}
        do {
            try directory(current)
            for component in components {
                guard !component.isEmpty,component != ".",component != "..",!component.contains("/"),!component.contains("\\") else{throw NativeRawResourceLease.Failure.invalid("Unsafe raw read directory component.")}
                let next=openat(current,component,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                guard next>=0 else{throw NativeRawResourceLease.Failure.io(errno)}
                do{try directory(next)}catch{Darwin.close(next);throw error}
                Darwin.close(current);current=next
            }
            return current
        }catch{Darwin.close(current);throw error}
    }
    static func openResource(root:URL,generation:String,path:String)throws->Int32 {
        let pieces=path.split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        guard UUID(uuidString:generation) != nil,!pieces.isEmpty,pieces.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":")}) else{throw NativeRawResourceLease.Failure.invalid("Unsafe raw lease path.")}
        let parent=try openDirectory(root:root,components:["generations",generation,"files"]+Array(pieces.dropLast()));defer{Darwin.close(parent)}
        let fd=openat(parent,pieces.last!,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else{throw NativeRawResourceLease.Failure.io(errno)}
        do{_ = try NativeRawResourceFileStamp.read(fd);return fd}catch{Darwin.close(fd);throw error}
    }
    static func catalogueStamp(root:URL)throws->NativeRawResourceFileStamp {
        try metadataStamp(root:root,components:[],name:"catalogue.json")
    }
    static func metadataStamp(root:URL,components:[String],name:String)throws->NativeRawResourceFileStamp {
        guard !name.isEmpty,!name.contains("/"),name != ".",name != ".." else{throw NativeRawResourceLease.Failure.invalid("Unsafe raw metadata filename.")}
        let parent=try openDirectory(root:root,components:components);defer{Darwin.close(parent)}
        let fd=openat(parent,name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else{throw NativeRawResourceLease.Failure.io(errno)}
        defer{Darwin.close(fd)};return try NativeRawResourceFileStamp.read(fd)
    }
    static func operationReadLock(root:URL)throws->NativeRawResourceGenerationLock {
        let parent=try openDirectory(root:root,components:[]);defer{Darwin.close(parent)}
        let fd=openat(parent,"operation.lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw NativeRawResourceLease.Failure.io(errno)}
        do {
            let stamp=try NativeRawResourceFileStamp.read(fd)
            guard stamp.size==0,stamp.mode&0o077==0 else{throw NativeRawResourceLease.Failure.invalid("Unsafe raw operation lock file.")}
            guard flock(fd,LOCK_SH|LOCK_NB)==0 else{throw NativeRawResourceLease.Failure.busy}
            return NativeRawResourceGenerationLock(fd:fd)
        }catch{Darwin.close(fd);throw error}
    }
}
