// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CZGTANativeAudio

/// Verified raw-generation radio access. All catalogue reads, lease hashing,
/// descriptor use and codec calls run outside main. One serial owner controls
/// the C handles; only the ABI's thread-safe cancel may overlap a decode.
final class NativeLocalRadioProvider:NativeRadioWindowSource {
    enum Availability {case absent;case available(stations:Set<Int>)}
    enum Failure:Error {case invalidCatalogue,unavailable,busy,format,cancelled,codec(Int32)}
    struct Statistics {let packs,decoders,preparations,windows:Int;let workerIsMain:Bool}
    private struct Catalogue {
        let receipt:NativeRawResourceStore.ReceiptDescriptor
        let archive:NativeRadioArchive.Catalogue
        let records:[Int:NativeRadioArchive.Record]
        let resources:[String:NativeRawResourceStore.Resource]
    }
    private struct Pack {
        let lease:NativeRawResourceLease
        var used:UInt64
    }
    private struct Decoder {
        let handle:OpaquePointer
        let descriptor:NativeRawResourceLease.Descriptor
        let record:NativeRadioArchive.Record
        let info:zgta_radio_info
        var used:UInt64
    }
    private let worker=DispatchQueue(label:"ZGTA.local-radio-decoder",qos:.utility)
    private let lock=NSLock()
    private let storeFactory:()->NativeRawResourceStore
    private var epoch:UInt64=0
    private var requests:[UUID:NativeRawResourceLease.Request]=[:]
    private var reservedRequests=Set<UUID>()
    private var activeHandle:OpaquePointer?
    private var admittedRead:UUID?
    private var publicIDs=Set<Int>()
    // Serial worker state only.
    private var store:NativeRawResourceStore?
    private var catalogue:Catalogue?
    private var packs:[String:Pack]=[:],decoders:[String:Decoder]=[:]
    private var used:UInt64=0
    private var pending:UUID?
    private var preparations=0,windows=0

    init(storeFactory:@escaping()->NativeRawResourceStore={NativeRawResourceStore.shared}) {
        self.storeFactory=storeFactory
    }
    deinit {
        requests.values.forEach{$0.cancel()}
        let oldDecoders=decoders,oldPacks=packs,guardLock=lock
        worker.async {
            for value in oldDecoders.values{guardLock.lock();zgta_radio_destroy(value.handle);guardLock.unlock();value.descriptor.close()}
            for value in oldPacks.values{value.lease.close()}
        }
    }
    func contains(_ id:Int)->Bool{lock.lock();defer{lock.unlock()};return publicIDs.contains(id)}
    private func current()->UInt64{lock.lock();defer{lock.unlock()};return epoch}
    private func valid(_ token:UInt64)->Bool{lock.lock();defer{lock.unlock()};return token==epoch}
    /// Reserve before invoking an API that may deliver on another queue before
    /// it returns its Request. A completed reservation is never reinserted.
    private func reserveRequest(_ id:UUID,token:UInt64)->Bool {
        lock.lock();defer{lock.unlock()}
        guard token==epoch else{return false}
        reservedRequests.insert(id);return true
    }
    private func track(_ request:NativeRawResourceLease.Request,id:UUID,token:UInt64) {
        lock.lock()
        let reserved=reservedRequests.remove(id) != nil
        let admitted=token==epoch && reserved
        if admitted{requests[id]=request}
        lock.unlock()
        if !admitted{request.cancel()}
    }
    private func untrack(_ id:UUID) {
        lock.lock();reservedRequests.remove(id);requests.removeValue(forKey:id);lock.unlock()
    }
    /// Also suppresses callbacks that were already waiting on main. Catalogue
    /// metadata may be retained, but every new session re-admits its receipt.
    func cancel() {
        lock.lock();epoch &+= 1;admittedRead=nil
        let old=Array(requests.values);requests.removeAll();reservedRequests.removeAll()
        if let activeHandle{zgta_radio_cancel(activeHandle)}
        lock.unlock()
        old.forEach{$0.cancel()}
        worker.async{[self] in closeAll();pending=nil}
    }
    private func close(_ decoder:Decoder) {
        lock.lock();zgta_radio_destroy(decoder.handle);lock.unlock()
        decoder.descriptor.close()
    }
    private func closeAll() {
        for value in decoders.values{close(value)};decoders.removeAll()
        for value in packs.values{value.lease.close()};packs.removeAll()
    }
    private func deliver<T>(_ result:Result<T,Error>,token:UInt64,completion:@escaping(Result<T,Error>)->Void) {
        DispatchQueue.main.async{[weak self] in guard self?.valid(token)==true else{return};completion(result)}
    }
    private func finishRead(_ result:Result<NativeRadioPCMWindow,Error>,token:UInt64,ticket:UUID,
                            completion:@escaping(Result<NativeRadioPCMWindow,Error>)->Void) {
        lock.lock();if admittedRead==ticket{admittedRead=nil};lock.unlock()
        deliver(result,token:token,completion:completion)
    }
    func statistics(completion:@escaping(Statistics)->Void) {
        worker.async{[self] in
            let value=Statistics(packs:packs.count,decoders:decoders.count,preparations:preparations,windows:windows,workerIsMain:Thread.isMainThread)
            DispatchQueue.main.async{completion(value)}
        }
    }
    func loadCatalogue(completion:@escaping(Result<Availability,Error>)->Void) {
        cancel();let token=current()
        worker.async{[self] in
            guard valid(token)else{return}
            catalogue=nil;lock.lock();publicIDs=[];lock.unlock()
            let source=store ?? storeFactory();store=source
            let snapshot=source.snapshot
            if snapshot.sourceID==nil {
                deliver(snapshot.issues.isEmpty ? .success(.absent):.failure(Failure.invalidCatalogue),token:token,completion:completion)
                return
            }
            let id=UUID()
            guard reserveRequest(id,token:token)else{return}
            let request=source.readReceiptDescriptor{[weak self] result in
                guard let self else{return};self.untrack(id)
                self.worker.async{[self] in
                    guard self.valid(token)else{return}
                    switch result {
                    case .failure(let error):self.deliver(.failure(error),token:token,completion:completion)
                    case .success(let receipt):self.loadTables(receipt,store:source,token:token,completion:completion)
                    }
                }
            }
            track(request,id:id,token:token)
        }
    }
    private func loadTables(_ receipt:NativeRawResourceStore.ReceiptDescriptor,store:NativeRawResourceStore,
                            token:UInt64,completion:@escaping(Result<Availability,Error>)->Void) {
        let entries=receipt.resourcesByCasefoldedPath
        let first="audio/config/strmpaks.dat",second="audio/config/traklkup.dat"
        var resources:[String:NativeRawResourceStore.Resource]=[:]
        for name in NativeRadioArchive.stationPacks+["ADVERTS"] {
            if let item=entries["audio/streams/"+name.lowercased()]{resources[name]=item}
        }
        if entries[first]==nil && entries[second]==nil && resources.isEmpty {
            deliver(.success(.absent),token:token,completion:completion);return
        }
        guard let names=entries[first],let lookup=entries[second],names.bytes>0,names.bytes<=4096,
              lookup.bytes>0,lookup.bytes<=240000,!resources.isEmpty else {
            deliver(.failure(Failure.invalidCatalogue),token:token,completion:completion);return
        }
        acquireTable(names,receipt:receipt,store:store,maximum:4096,token:token){[self] result in
            switch result {
            case .failure(let error):deliver(.failure(error),token:token,completion:completion)
            case .success(let nameData):
                acquireTable(lookup,receipt:receipt,store:store,maximum:240000,token:token){[self] result in
                    let parsed=Result{()throws->Availability in
                        let lookupData=try result.get()
                        var available:[String:UInt64]=[:]
                        for (name,item) in resources {
                            guard item.bytes>0,item.bytes<=Int64(UInt32.max)else{throw Failure.invalidCatalogue}
                            available[name]=UInt64(item.bytes)
                        }
                        let archive=try NativeRadioArchive.catalogue(packNames:nameData,lookup:lookupData,availablePacks:available)
                        guard valid(token)else{throw Failure.cancelled}
                        catalogue=Catalogue(receipt:receipt,archive:archive,records:Dictionary(uniqueKeysWithValues:archive.records.map{($0.id,$0)}),resources:resources)
                        lock.lock();publicIDs=Set(archive.records.map(\.id));lock.unlock()
                        return .available(stations:Set(archive.stations.indices.filter{!archive.stations[$0].isEmpty}))
                    }
                    deliver(parsed,token:token,completion:completion)
                }
            }
        }
    }
    /// Completion is internal and always runs on the serial decoder owner.
    private func acquireTable(_ resource:NativeRawResourceStore.Resource,receipt:NativeRawResourceStore.ReceiptDescriptor,
                              store:NativeRawResourceStore,maximum:Int64,token:UInt64,
                              completion:@escaping(Result<Data,Error>)->Void) {
        let id=UUID()
        guard reserveRequest(id,token:token)else{return}
        let request=store.acquireLocalFile(path:resource.path,matching:receipt,maximumBytes:maximum){[weak self] result in
            guard let self else{if case .success(let value)=result{value.close()};return};self.untrack(id)
            self.worker.async{[self] in
                guard self.valid(token)else{if case .success(let value)=result{value.close()};return}
                let data=Result{()throws->Data in
                    let lease=try result.get();defer{lease.close()}
                    return try lease.read(atOffset:0,maximumBytes:Int(resource.bytes))
                }
                completion(data)
            }
        }
        track(request,id:id,token:token)
    }
    func read(id:Int,offset:Int,frames:Int,completion:@escaping(Result<NativeRadioPCMWindow,Error>)->Void) {
        let ticket=UUID()
        lock.lock();let token=epoch
        guard admittedRead==nil else{lock.unlock();deliver(.failure(Failure.busy),token:token,completion:completion);return}
        admittedRead=ticket;lock.unlock()
        worker.async{[self] in
            guard valid(token)else{return}
            guard pending==nil else{finishRead(.failure(Failure.busy),token:token,ticket:ticket,completion:completion);return}
            guard offset>=0,(1...8000).contains(frames),let catalogue,let record=catalogue.records[id],let store else {
                finishRead(.failure(Failure.unavailable),token:token,ticket:ticket,completion:completion);return
            }
            pending=ticket
            if packs[record.pack] != nil {decode(record,offset:offset,frames:frames,token:token,ticket:ticket,completion:completion);return}
            // At most two pinned packs, including descriptors retained by C.
            if packs.count>=2,let victim=packs.min(by:{$0.value.used<$1.value.used})?.key {
                let keys=decoders.compactMap{$0.value.record.pack==victim ? $0.key:nil}
                for key in keys{if let value=decoders.removeValue(forKey:key){close(value)}}
                packs.removeValue(forKey:victim)?.lease.close()
            }
            guard let resource=catalogue.resources[record.pack]else{pending=nil;finishRead(.failure(Failure.invalidCatalogue),token:token,ticket:ticket,completion:completion);return}
            let requestID=UUID()
            guard reserveRequest(requestID,token:token)else{return}
            let request=store.acquireLocalFile(path:resource.path,matching:catalogue.receipt,maximumBytes:resource.bytes){[weak self] result in
                guard let self else{if case .success(let value)=result{value.close()};return};self.untrack(requestID)
                self.worker.async{[self] in
                    guard self.valid(token),self.pending==ticket else{if case .success(let value)=result{value.close()};return}
                    switch result {
                    case .failure(let error):self.pending=nil;self.finishRead(.failure(error),token:token,ticket:ticket,completion:completion)
                    case .success(let lease):
                        self.used &+= 1;self.packs[record.pack]=Pack(lease:lease,used:self.used)
                        self.decode(record,offset:offset,frames:frames,token:token,ticket:ticket,completion:completion)
                    }
                }
            }
            track(request,id:requestID,token:token)
        }
    }
    private func call<T>(_ handle:OpaquePointer,descriptor:NativeRawResourceLease.Descriptor,token:UInt64,
                         body:()throws->T)throws->T {
        lock.lock()
        guard token==epoch else{lock.unlock();throw Failure.cancelled}
        activeHandle=handle;lock.unlock()
        defer{lock.lock();activeHandle=nil;lock.unlock()}
        return try descriptor.withFileDescriptor{_ in try body()}
    }
    private func decode(_ record:NativeRadioArchive.Record,offset:Int,frames:Int,token:UInt64,ticket:UUID,
                        completion:@escaping(Result<NativeRadioPCMWindow,Error>)->Void) {
        let result=Result{()throws->NativeRadioPCMWindow in
            guard valid(token),pending==ticket,let pack=packs[record.pack]else{throw Failure.cancelled}
            used &+= 1;packs[record.pack]?.used=used
            let key="\(record.pack):\(record.offset):\(record.byteCount)"
            if decoders[key]==nil {
                if decoders.count>=2,let victim=decoders.min(by:{$0.value.used<$1.value.used})?.key,
                   let old=decoders.removeValue(forKey:victim){close(old)}
                let descriptor=try pack.lease.duplicateFileDescriptor()
                var pointer:OpaquePointer?
                do {
                    let status=try descriptor.withFileDescriptor{fd in zgta_radio_create(fd,record.offset,record.byteCount,&pointer)}
                    guard status==ZGTA_RADIO_OK,let handle=pointer else{throw Failure.codec(Int32(status.rawValue))}
                    var info=zgta_radio_info()
                    let prepared=try call(handle,descriptor:descriptor,token:token){zgta_radio_prepare(handle,&info)}
                    preparations &+= 1
                    guard prepared==ZGTA_RADIO_OK else{throw Failure.codec(Int32(prepared.rawValue))}
                    guard info.abi_version==1,info.sample_rate==32000,info.output_channels==2 else{throw Failure.format}
                    decoders[key]=Decoder(handle:handle,descriptor:descriptor,record:record,info:info,used:used)
                    pointer=nil
                }catch {
                    if let pointer{lock.lock();zgta_radio_destroy(pointer);lock.unlock()};descriptor.close();throw error
                }
            }
            guard var decoder=decoders[key]else{throw Failure.unavailable}
            decoder.used=used;decoders[key]=decoder
            if UInt64(offset)>=decoder.info.frames{return NativeRadioPCMWindow(rate:32000,requestedFrames:frames,decodedFrames:0,samples:[])}
            let count=min(frames,Int(decoder.info.frames-UInt64(offset)))
            var samples=[Float](repeating:0,count:count*2),written:UInt32=0
            let status=try call(decoder.handle,descriptor:decoder.descriptor,token:token){
                samples.withUnsafeMutableBufferPointer{zgta_radio_read(decoder.handle,UInt64(offset),UInt32(count),$0.baseAddress,$0.count,&written)}
            }
            windows &+= 1
            guard status==ZGTA_RADIO_OK else{throw Failure.codec(Int32(status.rawValue))}
            guard written<=count,samples.prefix(Int(written)*2).allSatisfy(\.isFinite)else{throw Failure.format}
            return NativeRadioPCMWindow(rate:32000,requestedFrames:frames,decodedFrames:Int(written),samples:Array(samples.prefix(Int(written)*2)))
        }
        if pending==ticket{pending=nil}
        if case .failure=result {
            // A poisoned/cancelled handle must never stay in the seek cache.
            for value in decoders.values{close(value)};decoders.removeAll()
        }
        finishRead(result,token:token,ticket:ticket,completion:completion)
    }
}
