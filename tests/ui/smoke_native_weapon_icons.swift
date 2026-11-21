// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
// Explicit decoding/presentation boundary: these are authored image tokens,
// not UIKit decoding or original weapon artwork.
private final class UIImage:NSObject {
 let value:String
 init?(data:Data){guard let s=String(data:data,encoding:.utf8),s.hasPrefix("img:")else{return nil};value=String(s.dropFirst(4));super.init()}
}
private final class IconView {var image:UIImage?}
private struct ServerAddress {
 let url:URL
 init(_ value:String){url=URL(string:value)!}
 var display:String{url.absoluteString}
 func path(_ value:String)->URL{url.appendingPathComponent(value)}
}
private final class NativeResourceStore {
 enum Mode:String{case development,installed}
 struct Binding{var generation=UUID(),mode=Mode.development,contentID:String?="authored-1",developmentOrigin:String?=nil,playable=true}
 static let shared=NativeResourceStore()
 var runtimeBinding=Binding()
}
private protocol NativeResourceTask {func resume();func cancel()}
private final class Task:NativeResourceTask {
 let url:URL,completion:(Data?,URLResponse?,Error?)->Void
 var resumed=false,cancelled=false
 init(_ url:URL,_ completion:@escaping(Data?,URLResponse?,Error?)->Void){self.url=url;self.completion=completion}
 func resume(){resumed=true}
 func cancel(){cancelled=true}
 // Deliberately permit completion after cancellation: a callback may already
 // be queued at the owner's boundary. The actual loader must reject it.
 func finish(_ image:String?,status:Int=200){completion(image.map{Data(("img:"+$0).utf8)},HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:nil),nil)}
}
private enum NativeResourceTransport {
 static var requests:[Task]=[]
 static func dataTask(with url:URL,completionHandler:@escaping(Data?,URLResponse?,Error?)->Void)->Task {
  let task=Task(url,completionHandler);requests.append(task);return task
 }
}
private final class HUD {
 let weaponIcon=IconView()
 // ACTUAL_FIELDS
 // ACTUAL_METHODS
}
@main private enum Main {
 static func main(){
  var checks=0
  func check(_ ok:Bool,_ why:String){checks+=1;if !ok{print("FAIL \(why)");exit(1)}}
  func drain(_ seconds:Double=0.04){
   let timer=Timer(timeInterval:0.005,repeats:true){_ in};RunLoop.current.add(timer,forMode:.default);defer{timer.invalidate()}
   let end=Date().addingTimeInterval(seconds)
   while Date()<end{_ = RunLoop.current.run(mode:.default,before:min(end,Date().addingTimeInterval(0.01)))}
  }
  let server=ServerAddress("http://127.0.0.1:18001"),other=ServerAddress("http://127.0.0.1:18002"),hud=HUD()
  hud.loadWeaponIcon(server:server,weapon:22);let pistol=NativeResourceTransport.requests.last!;pistol.finish("pistol");drain()
  check(hud.weaponIcon.image?.value=="pistol","Initial requested image was not presented")
  hud.loadWeaponIcon(server:server,weapon:25)
  check(hud.weaponIcon.image==nil,"Weapon switch retained the preceding weapon icon")
  let shotgun=NativeResourceTransport.requests.last!,pending=NativeResourceTransport.requests.count
  hud.loadWeaponIcon(server:server,weapon:25)
  check(NativeResourceTransport.requests.count==pending,"Repeated inventory state duplicated an in-flight image request")
  shotgun.finish(nil,status:404);drain()
  check(hud.weaponIcon.image==nil,"Missing weapon artwork revealed an unrelated previous image")
  hud.loadWeaponIcon(server:server,weapon:25)
  check(NativeResourceTransport.requests.count==pending,"Failed resource retried before its monotonic interval")
  drain(2.05);hud.loadWeaponIcon(server:server,weapon:25)
  check(NativeResourceTransport.requests.count==pending+1,"A later update could not retry the missing image")
  NativeResourceTransport.requests.last!.finish("shotgun");drain()
  check(hud.weaponIcon.image?.value=="shotgun","Successful retry did not replace missing artwork")
  let loaded=NativeResourceTransport.requests.count;hud.loadWeaponIcon(server:server,weapon:25)
  check(NativeResourceTransport.requests.count==loaded,"Ammunition update refetched an already loaded icon")
  hud.loadWeaponIcon(server:server,weapon:22);let old=NativeResourceTransport.requests.last!
  hud.loadWeaponIcon(server:server,weapon:25);let interim=NativeResourceTransport.requests.last!
  hud.loadWeaponIcon(server:server,weapon:22);let fresh=NativeResourceTransport.requests.last!
  check(old.cancelled&&interim.cancelled,"Switching weapons retained superseded transfers")
  old.finish("stale-same-weapon");drain();check(hud.weaponIcon.image==nil,"Old same-ID completion escaped its request incarnation")
  fresh.finish("fresh-pistol");drain();interim.finish("late-shotgun");drain()
  check(hud.weaponIcon.image?.value=="fresh-pistol","Late superseded weapon replaced the current image")
  hud.loadWeaponIcon(server:server,weapon:34);let oldSource=NativeResourceTransport.requests.last!
  NativeResourceStore.shared.runtimeBinding.generation=UUID();oldSource.finish("retired-install");drain()
  check(hud.weaponIcon.image==nil,"Retired installed-source callback became current artwork")
  hud.loadWeaponIcon(server:server,weapon:34);let newSource=NativeResourceTransport.requests.last!
  check(newSource !== oldSource,"Resource generation did not obtain a new request")
  newSource.finish("current-install");drain();check(hud.weaponIcon.image?.value=="current-install","New source did not present its own image")
  hud.loadWeaponIcon(server:other,weapon:34);check(hud.weaponIcon.image==nil,"Another server inherited the previous server's image")
  NativeResourceTransport.requests.last!.finish("other-server");drain();check(hud.weaponIcon.image?.value=="other-server","Current server image was rejected")
  var temporary:HUD?=HUD();temporary!.loadWeaponIcon(server:server,weapon:31);let orphan=NativeResourceTransport.requests.last!;temporary=nil
  check(orphan.cancelled,"Retiring the HUD retained its image transfer")
  print("PASS \(checks) actual icon-loader lifecycle, source/request races, missing-image retry and request deduplication; explicit image/transport/store/server boundaries, no UIKit/App/pixel claim")
 }
}
