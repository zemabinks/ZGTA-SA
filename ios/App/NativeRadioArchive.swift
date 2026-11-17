// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Darwin

/// Independent bounded catalogue/XOR reader for owner PC radio resources.
/// No path discovery, network, codec, game audio or authentication is supplied.
/// An integration must provide verified immutable raw-generation descriptors.
enum NativeRadioArchive {
    static let headerBytes:UInt64=8068
    static let maximumPayloadBytes:UInt64=64*1024*1024
    static let maximumReadBytes=65536
    static let stationPacks=["AA","CH","CO","CR","DS","HC","MH","MR","NJ","RE","RG","TK"]
    private static let xorKey:[UInt8]=[234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241]
    struct Limits {
        var maximumPacks=256
        var maximumLookupRecords=20000
        var maximumPackBytes:UInt64=4*1024*1024*1024
        var maximumRecordBytes:UInt64=headerBytes+maximumPayloadBytes
    }
    struct Pack:Equatable {let index:Int,name:String,bytes:UInt64?}
    struct Record:Equatable {
        let id:Int,packIndex:Int,pack:String,offset:UInt64,byteCount:UInt64
        var payloadBytes:UInt64{byteCount-headerBytes}
    }
    struct Catalogue {
        let packs:[Pack]
        let records:[Record]
        let stations:[[Record]]
        let adverts:[Record]
        let absentPackRecords:Int
        let emptyLookupRecords:Int
        let excludedPackRecords:Int
        func record(id:Int)->Record?{records.first{$0.id==id}}
    }
    enum Failure:Error,Equatable,CustomStringConvertible {
        case limits,table,packIdentity,range,overlap,descriptor,sourceChanged,io,cancelled,closed
        var description:String {
            switch self {
            case .limits:return "Radio resource limit exceeded"
            case .table:return "Invalid radio lookup table"
            case .packIdentity:return "Ambiguous or unavailable radio pack identity"
            case .range:return "Invalid radio record/read range"
            case .overlap:return "Overlapping radio record bounds"
            case .descriptor:return "A readable regular radio file descriptor is required"
            case .sourceChanged:return "Original radio source changed"
            case .io:return "Radio source read failed"
            case .cancelled:return "Radio read cancelled"
            case .closed:return "Radio descriptor is closed"
            }
        }
    }
    private static func name(_ text:String)throws->String {
        let upper=text.uppercased()
        guard !upper.isEmpty,upper.utf8.count<=16,upper.utf8.allSatisfy({(65...90).contains($0)}) else{throw Failure.packIdentity}
        return upper
    }
    static func catalogue(packNames:Data,lookup:Data,availablePacks:[String:UInt64],limits:Limits=Limits())throws->Catalogue {
        guard (1...256).contains(limits.maximumPacks),(1...20000).contains(limits.maximumLookupRecords),
              limits.maximumPackBytes>0,limits.maximumPackBytes<=4*1024*1024*1024,
              limits.maximumRecordBytes>headerBytes,limits.maximumRecordBytes<=headerBytes+maximumPayloadBytes else{throw Failure.limits}
        guard !packNames.isEmpty,packNames.count%16==0,packNames.count/16<=limits.maximumPacks,
              !lookup.isEmpty,lookup.count%12==0,lookup.count/12<=limits.maximumLookupRecords else{throw Failure.table}
        var available=[String:UInt64]()
        for (raw,bytes) in availablePacks {
            let normalized=try name(raw)
            guard available[normalized]==nil,bytes>0,bytes<=limits.maximumPackBytes else{throw Failure.packIdentity}
            available[normalized]=bytes
        }
        let names=[UInt8](packNames),rows=[UInt8](lookup)
        var packs=[Pack](),seen=Set<String>()
        for index in 0..<names.count/16 {
            let bytes=Array(names[index*16..<index*16+16]),end=bytes.firstIndex(of:0) ?? 16
            // Bytes after the first NUL are padding, not filename characters.
            let raw=String(bytes:bytes.prefix(end),encoding:.ascii)?.trimmingCharacters(in:.whitespacesAndNewlines)
            guard let raw else{throw Failure.packIdentity}
            let normalized=raw.isEmpty ? "":try name(raw)
            guard normalized.isEmpty || seen.insert(normalized).inserted else{throw Failure.packIdentity}
            packs.append(Pack(index:index,name:normalized,bytes:available[normalized]))
        }
        guard Set(available.keys).isSubset(of:seen) else{throw Failure.packIdentity}
        func u32(_ at:Int)->UInt64 {UInt64(rows[at])|UInt64(rows[at+1])<<8|UInt64(rows[at+2])<<16|UInt64(rows[at+3])<<24}
        struct Pending {let id:Int,pack:Pack,offset:UInt64,lookupBytes:UInt64}
        var pending=[Pending](),absent=0,empty=0,excluded=0
        let eligible=Set(stationPacks+["ADVERTS"])
        for id in 0..<rows.count/12 {
            let at=id*12,packIndex=Int(rows[at]),offset=u32(at+4),size=u32(at+8)
            // Three bytes after the index are unused PC padding (the owner
            // fixture contains CD CD CD); they are not a 32-bit pack index.
            guard packs.indices.contains(packIndex) else{throw Failure.table}
            let pack=packs[packIndex]
            guard size>headerBytes else{empty+=1;continue}
            guard eligible.contains(pack.name) else{excluded+=1;continue}
            guard let bytes=pack.bytes else{absent+=1;continue}
            guard offset<=bytes,size<=bytes-offset,size<=limits.maximumRecordBytes else{throw Failure.range}
            pending.append(Pending(id:id,pack:pack,offset:offset,lookupBytes:size))
        }
        var boundaries=[Int:[UInt64:UInt64]]()
        for pack in packs where pack.bytes != nil {
            let offsets=Set(pending.filter{$0.pack.index==pack.index}.map(\.offset)).sorted()
            var ends=[UInt64:UInt64]()
            for (i,offset) in offsets.enumerated(){ends[offset]=i+1<offsets.count ? offsets[i+1]:pack.bytes!}
            boundaries[pack.index]=ends
        }
        var records=[Record](),aliases=[String:UInt64]()
        for row in pending {
            let end=boundaries[row.pack.index]![row.offset]!,span=end-row.offset
            let expanded=row.lookupBytes+headerBytes
            let physical=span==expanded ? expanded:row.lookupBytes
            guard physical<=span else{throw Failure.overlap}
            guard physical>headerBytes,physical<=limits.maximumRecordBytes else{throw Failure.range}
            let identity="\(row.pack.index):\(row.offset)"
            if let prior=aliases[identity],prior != physical{throw Failure.overlap}
            aliases[identity]=physical
            records.append(Record(id:row.id,packIndex:row.pack.index,pack:row.pack.name,offset:row.offset,byteCount:physical))
        }
        guard records.contains(where:{stationPacks.contains($0.pack)}) else{throw Failure.packIdentity}
        return Catalogue(packs:packs,records:records,stations:stationPacks.map{pack in records.filter{$0.pack==pack}},
                         adverts:records.filter{$0.pack=="ADVERTS"},absentPackRecords:absent,emptyLookupRecords:empty,excludedPackRecords:excluded)
    }
    /// Thread-safe bounded raw reads, duplicated FD, sticky cancellation. This
    /// lower-layer handle never authenticates a path or changes caller FD offset.
    final class Substream {
        private struct Identity:Equatable {
            let device:dev_t,inode:ino_t,bytes:off_t,modifiedSeconds:Int,modifiedNanos:Int,changedSeconds:Int,changedNanos:Int
            init(_ s:stat){device=s.st_dev;inode=s.st_ino;bytes=s.st_size;modifiedSeconds=s.st_mtimespec.tv_sec;modifiedNanos=s.st_mtimespec.tv_nsec;changedSeconds=s.st_ctimespec.tv_sec;changedNanos=s.st_ctimespec.tv_nsec}
        }
        private let lock=NSLock(),identity:Identity,record:Record
        private var descriptor:Int32,cancelled=false
        init(fileDescriptor:Int32,record:Record)throws {
            var s=stat();let flags=fcntl(fileDescriptor,F_GETFL)
            guard fileDescriptor>=0,flags>=0,(flags&O_ACCMODE) != O_WRONLY,
                  fstat(fileDescriptor,&s)==0,s.st_mode&S_IFMT==S_IFREG,s.st_size>=0 else{throw Failure.descriptor}
            let size=UInt64(s.st_size)
            guard record.offset<=size,record.byteCount>headerBytes,record.byteCount-headerBytes<=maximumPayloadBytes,
                  record.byteCount<=size-record.offset,record.offset<=UInt64(Int64.max),record.byteCount<=UInt64(Int64.max)-record.offset else{throw Failure.range}
            let copy=fcntl(fileDescriptor,F_DUPFD_CLOEXEC,0)
            guard copy>=0 else{throw Failure.io}
            descriptor=copy;identity=Identity(s);self.record=record
        }
        deinit{if descriptor>=0{Darwin.close(descriptor)}}
        func cancel(){lock.lock();cancelled=true;lock.unlock()}
        func close(){lock.lock();defer{lock.unlock()};if descriptor>=0{Darwin.close(descriptor);descriptor = -1}}
        func read(at relativeOffset:UInt64,maximumBytes:Int)throws->Data {
            lock.lock();defer{lock.unlock()}
            guard descriptor>=0 else{throw Failure.closed}
            guard !cancelled else{throw Failure.cancelled}
            guard (0...NativeRadioArchive.maximumReadBytes).contains(maximumBytes),relativeOffset<=record.payloadBytes else{throw Failure.range}
            var current=stat();guard fstat(descriptor,&current)==0,identity==Identity(current) else{throw Failure.sourceChanged}
            let count=min(maximumBytes,Int(record.payloadBytes-relativeOffset)),at=record.offset+headerBytes+relativeOffset
            var result=Data(count:count)
            try result.withUnsafeMutableBytes{(raw:UnsafeMutableRawBufferPointer)in
                var done=0
                while done<count {
                    let read=pread(descriptor,raw.baseAddress!.advanced(by:done),count-done,off_t(at)+off_t(done))
                    if read<0,errno==EINTR{continue}
                    guard read>0 else{throw Failure.io};done+=read
                }
                for i in 0..<count{raw[i]^=xorKey[Int((at+UInt64(i))&15)]}
            }
            guard fstat(descriptor,&current)==0,identity==Identity(current) else{throw Failure.sourceChanged}
            return result
        }
    }
}
