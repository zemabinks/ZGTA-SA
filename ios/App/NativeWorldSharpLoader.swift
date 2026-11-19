// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import MetalKit

/// One active decode/upload and one replaceable pending image. Caller retires
/// its ticket on intent/source changes and fences publication on the main queue.
final class NativeWorldSharpLoader {
    enum Failure:Error {case unavailable,image}
    private let work=NativeWorldSharpWork()
    deinit{work.close()}
    func load(url:URL,layout:NativeWorldSharpLayout,device:MTLDevice,queue:MTLCommandQueue,
              ticket:NativeWorldSharpTicket,completion:@escaping(Result<NativeWorldSharpTextures,Error>)->Void) {
        var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30)
        request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        let task=NativeResourceTransport.boundedDataTask(with:request,maximumBytes:64*1024*1024){[weak self] data,response,error in
            ticket.finishTransfer()
            guard let self,!ticket.isCancelled else{return}
            guard error==nil,let http=response as?HTTPURLResponse,http.statusCode==200,http.url==url,let data else {
                DispatchQueue.main.async{if !ticket.isCancelled{completion(.failure(error ?? Failure.unavailable))}};return
            }
            self.work.submit {
                guard !ticket.isCancelled else{return}
                let result:Result<NativeWorldSharpTextures,Error>=Result {
                    guard layout.acceptsPNG(data) else{throw Failure.image}
                    let atlas=try MTKTextureLoader(device:device).newTexture(data:data,options:[.SRGB:false,.generateMipmaps:false])
                    guard !ticket.isCancelled else{throw Failure.unavailable}
                    let textures=try NativeWorldSharpTextures(device:device,queue:queue,atlas:atlas,layout:layout)
                    try textures.finishUpload()
                    return textures
                }
                guard !ticket.isCancelled else{return}
                DispatchQueue.main.async{if !ticket.isCancelled{completion(result)}}
            }
        }
        ticket.attachCancellation{task.cancel()}
        if !ticket.isCancelled{task.resume()}
    }
}
