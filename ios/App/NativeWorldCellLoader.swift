// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import MetalKit
import simd

/// One active cell pair/preparation, a bounded queue of descriptors and immutable
/// GPU products. The renderer alone publishes meshes and changes scene state.
final class NativeWorldCellLoader {
    enum Failure:Error {case pendingLimit,cancelled,unavailable,image,allocation,preparedLimit}
    struct Prepared {
        let vertices:MTLBuffer,indices:MTLBuffer,atlas:MTLTexture
        let indexCount:Int,layers:Int,sharpLayers:[UInt16],center:SIMD3<Float>?
        static func make(bin:Data,png:Data,cellSize:Int,device:MTLDevice,maximumBytes:Int,
                         cancelled:()->Bool={false})throws->Prepared {
            guard !cancelled()else{throw Failure.cancelled}
            let world=try WorldBinary(data:bin)
            guard [64,128].contains(cellSize),png.count>=24,
                  Array(png.prefix(8))==[137,80,78,71,13,10,26,10]else{throw Failure.image}
            func word(_ at:Int)->Int{(0..<4).reduce(0){($0<<8)|Int(png[at+$1])}}
            let width=word(16),height=word(20),columns=2048/cellSize
            guard width==2048,height>0,height<=32768,
                  height>=((world.layers+columns-1)/columns)*cellSize else{throw Failure.image}
            let geometry=world.vertices.count*MemoryLayout<NativeVertex>.stride+world.indices.count*4
            // PNG input is bounded separately. Reserve up to eight decoded
            // bytes/pixel, then account the actual Metal allocations as well.
            guard geometry<=maximumBytes,width*height*8<=maximumBytes-geometry else{throw Failure.preparedLimit}
            guard !cancelled()else{throw Failure.cancelled}
            // Use a worker-owned loader; foreground scene loads do not share
            // its mutable state. This synchronous API returns initialized data.
            let atlas=try MTKTextureLoader(device:device).newTexture(data:png,options:[.SRGB:false])
            guard atlas.width==width,atlas.height==height else{throw Failure.image}
            guard !cancelled()else{throw Failure.cancelled}
            guard let vertices=device.makeBuffer(bytes:world.vertices,length:world.vertices.count*MemoryLayout<NativeVertex>.stride),
                  let indices=device.makeBuffer(bytes:world.indices,length:world.indices.count*4)else{throw Failure.allocation}
            let bytes=vertices.allocatedSize+indices.allocatedSize+atlas.allocatedSize
            guard bytes<=maximumBytes else{throw Failure.preparedLimit}
            var center:SIMD3<Float>?
            if cellSize==128 {
                var low=SIMD3<Float>(repeating:.greatestFiniteMagnitude),high = -low
                for vertex in world.vertices{let p=SIMD3(vertex.position.x,vertex.position.y,vertex.position.z);low=simd_min(low,p);high=simd_max(high,p)}
                center=low*0.5+high*0.5
            }
            guard !cancelled()else{throw Failure.cancelled}
            return .init(vertices:vertices,indices:indices,atlas:atlas,indexCount:world.indices.count,
                         layers:world.layers,sharpLayers:world.sharpLayers,center:center)
        }
    }
    typealias Completion=(Result<Prepared,Error>)->Void
    private struct Pending {
        let id:UUID,name:String,bin:URL,png:URL,cellSize:Int,device:MTLDevice,completion:Completion
        var priority:Int
    }
    private struct Running {let item:Pending,job:Job}
    private static let cpu=DispatchQueue(label:"org.zgtasa.world-cell.prepare",qos:.utility)
    private let worker:DispatchQueue,maximumPending:Int,maximumFileBytes:Int,maximumPreparedBytes:Int
    private var pending:[Pending]=[],running:Running?,pumpScheduled=false
    var pendingCount:Int{main();return pending.count}
    var activeCount:Int{main();return running == nil ? 0:1}
    init(maximumPending:Int=32,maximumFileBytes:Int=64*1024*1024,
         maximumPreparedBytes:Int=192*1024*1024,worker:DispatchQueue?=nil) {
        precondition((1...64).contains(maximumPending) && (24...64*1024*1024).contains(maximumFileBytes) &&
                     (1...256*1024*1024).contains(maximumPreparedBytes))
        self.maximumPending=maximumPending;self.maximumFileBytes=maximumFileBytes
        self.maximumPreparedBytes=maximumPreparedBytes;self.worker=worker ?? Self.cpu
    }
    deinit{running?.job.cancel()}
    private func main(){dispatchPrecondition(condition:.onQueue(.main))}
    @discardableResult func load(name:String,bin:URL,png:URL,cellSize:Int,device:MTLDevice,priority:Int,
                                completion:@escaping Completion)->UUID {
        main();let id=UUID()
        guard pending.count<maximumPending else{DispatchQueue.main.async{completion(.failure(Failure.pendingLimit))};return id}
        pending.append(.init(id:id,name:name,bin:bin,png:png,cellSize:cellSize,device:device,completion:completion,priority:priority))
        schedulePump();return id
    }
    /// Update all priorities together before admitting a new frame's requests.
    /// Obsolete descriptors/transfers release their slots; active CPU work must
    /// exit before another preparation starts.
    func updateWanted(_ priorities:[String:Int]) {
        main();let retired=pending.filter{priorities[$0.name]==nil}
        pending=pending.compactMap{item in guard let priority=priorities[item.name]else{return nil};var item=item;item.priority=priority;return item}
        for item in retired{DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}}
        if let running,priorities[running.item.name]==nil{running.job.cancel()}
        schedulePump()
    }
    func cancel(_ id:UUID) {
        main()
        if let index=pending.firstIndex(where:{$0.id==id}){let item=pending.remove(at:index);DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}}
        if running?.item.id==id{running?.job.cancel()}
    }
    func reset() {
        main();let retired=pending;pending.removeAll();running?.job.cancel()
        for item in retired{DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}}
    }
    private func schedulePump() {
        guard !pumpScheduled else{return};pumpScheduled=true
        // Coalesce the detail/far batch instead of starting its first far cell
        // before the current detailed cell has had a chance to enter the queue.
        DispatchQueue.main.async{[weak self]in guard let self else{return};self.pumpScheduled=false;self.pump()}
    }
    private func pump() {
        main();guard running==nil,let priority=pending.map(\.priority).max(),
                     let index=pending.firstIndex(where:{$0.priority==priority})else{return}
        let item=pending.remove(at:index)
        let job=Job(item:item,maximumFileBytes:maximumFileBytes,maximumPreparedBytes:maximumPreparedBytes,worker:worker){[weak self]result in
            guard let self,self.running?.item.id==item.id else{return}
            self.running=nil;item.completion(result);self.schedulePump()
        }
        running = .init(item:item,job:job);job.start()
    }
    private final class Job {
        private let item:Pending,maximumFileBytes:Int,maximumPreparedBytes:Int,worker:DispatchQueue,completion:Completion
        private let lock=NSLock()
        private var cancelled=false,tasks:[Int:NativeResourceTask]=[:]
        // Main queue only:
        private var data:[Int:Data]=[:],preparing=false,finished=false
        init(item:Pending,maximumFileBytes:Int,maximumPreparedBytes:Int,worker:DispatchQueue,completion:@escaping Completion) {
            self.item=item;self.maximumFileBytes=maximumFileBytes;self.maximumPreparedBytes=maximumPreparedBytes
            self.worker=worker;self.completion=completion
        }
        private var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
        func cancel(){lock.lock();cancelled=true;let retired=Array(tasks.values);tasks.removeAll();lock.unlock();for task in retired{task.cancel()}}
        func start() {
            guard !isCancelled else{finish(.failure(Failure.cancelled));return}
            for (index,url)in [item.bin,item.png].enumerated() {
                var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30)
                request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
                let task=NativeResourceTransport.boundedDataTask(with:request,maximumBytes:maximumFileBytes){[weak self]data,response,error in
                    DispatchQueue.main.async{self?.receive(index:index,url:url,data:data,response:response,error:error)}
                }
                lock.lock();let stopped=cancelled;if !stopped{tasks[index]=task};lock.unlock()
                if stopped{task.cancel();finish(.failure(Failure.cancelled))}else{task.resume()}
            }
        }
        private func receive(index:Int,url:URL,data:Data?,response:URLResponse?,error:Error?) {
            lock.lock();tasks.removeValue(forKey:index);lock.unlock()
            guard !finished,!preparing else{return}
            guard !isCancelled else{finish(.failure(Failure.cancelled));return}
            guard error==nil,let http=response as?HTTPURLResponse,http.statusCode==200,http.url==url,
                  let data,data.count<=maximumFileBytes else{finish(.failure(error ?? Failure.unavailable));return}
            self.data[index]=data
            guard let bin=self.data[0],let png=self.data[1]else{return}
            preparing=true;self.data.removeAll()
            worker.async{[self]in autoreleasepool {
                let result=Result{try Prepared.make(bin:bin,png:png,cellSize:item.cellSize,device:item.device,
                                                   maximumBytes:maximumPreparedBytes,cancelled:{self.isCancelled})}
                finish(result)
            }}
        }
        private func finish(_ result:Result<Prepared,Error>) {
            DispatchQueue.main.async{[self]in
                guard !finished else{return};finished=true;data.removeAll()
                lock.lock();let retired=Array(tasks.values);tasks.removeAll();lock.unlock()
                for task in retired{task.cancel()}
                completion(isCancelled ? .failure(Failure.cancelled):result)
            }
        }
    }
}
