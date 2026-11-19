// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

final class NativeWorldSharpTicket {
    private let lock=NSLock()
    private var retired=false,transferFinished=false
    private var cancellation:(()->Void)?
    func cancel(){lock.lock();retired=true;let action=cancellation;cancellation=nil;lock.unlock();action?()}
    func attachCancellation(_ action:@escaping()->Void){
        lock.lock();let cancelled=retired;if !cancelled && !transferFinished{cancellation=action};lock.unlock()
        if cancelled{action()}
    }
    func finishTransfer(){lock.lock();transferFinished=true;let previous=cancellation;cancellation=nil;lock.unlock();withExtendedLifetime(previous){}}
    var isCancelled:Bool{lock.lock();defer{lock.unlock()};return retired}
}

/// At most one active decode and one pending payload. Replacing intent releases
/// a queued image immediately instead of accumulating cancelled large blocks.
final class NativeWorldSharpWork {
    private let lock=NSLock(),worker=DispatchQueue(label:"org.zgtasa.world-sharp.decode",qos:.utility)
    private var draining=false,closed=false,pending:(()->Void)?
    @discardableResult func submit(_ job:@escaping()->Void)->Bool {
        lock.lock()
        guard !closed else{lock.unlock();return false}
        let previous=pending;pending=job
        let start = !draining;draining=true;lock.unlock()
        withExtendedLifetime(previous){}
        if start{worker.async{[self] in drain()}}
        return true
    }
    func close(){lock.lock();closed=true;let previous=pending;pending=nil;lock.unlock();withExtendedLifetime(previous){}}
    private func drain(){
        while true {
            lock.lock();let job=pending;pending=nil
            if job==nil{draining=false;lock.unlock();return}
            lock.unlock();autoreleasepool{job?()}
        }
    }
}
