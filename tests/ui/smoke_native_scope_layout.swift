// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreGraphics
var checks=0
func require(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError(message)}}
final class RecordedContext {
 func saveGState(){};func restoreGState(){};func translateBy(x:CGFloat,y:CGFloat){};func scaleBy(x:CGFloat,y:CGFloat){}
}
let recordingContext=RecordedContext()
func UIGraphicsGetCurrentContext()->RecordedContext?{recordingContext}
final class UIColor {
 static let black=UIColor(),white=UIColor()
 func setFill(){};func setStroke(){}
}
final class UIBezierPath {
 static var fills:[UIBezierPath]=[]
 let rectangle:CGRect?,oval:CGRect?
 var children:[UIBezierPath]=[],usesEvenOddFillRule=false,lineWidth:CGFloat=0
 init(){rectangle=nil;oval=nil}
 init(rect:CGRect){rectangle=rect;oval=nil}
 init(ovalIn:CGRect){rectangle=nil;oval=ovalIn}
 func append(_ path:UIBezierPath){children.append(path)}
 func fill(){Self.fills.append(self)};func stroke(){}
 func move(to:CGPoint){};func addLine(to:CGPoint){}
}
final class RecordedImage {func draw(in:CGRect){}}
final class NativeHUDResources {
 static let shared=NativeHUDResources();var sprites:[String:RecordedImage]=[:]
}
final class Window {var bounds:CGRect;init(_ bounds:CGRect){self.bounds=bounds}}
final class Sight {
 var frame=CGRect.zero
 var bounds:CGRect{CGRect(origin:.zero,size:frame.size)}
 var aimPoint:CGPoint?,scoped=false
 func draw(_ rect:CGRect){
/* ACTUAL_SIGHT_DRAW */
 }
}
final class HUD {
 var bounds=CGRect.zero,offset=CGPoint.zero,window:Window?
 let aim=Sight()
 func convert(_ rect:CGRect,from:Window)->CGRect{CGRect(x:rect.minX-offset.x,y:rect.minY-offset.y,width:rect.width,height:rect.height)}
 func convert(_ point:CGPoint,from:Window)->CGPoint{CGPoint(x:point.x-offset.x,y:point.y-offset.y)}
 func layout(){
/* ACTUAL_VIEWPORT_LAYOUT */
 }
}
let drawOnly=/* DRAW_ONLY */
let sizes=[CGSize(width:667,height:375),CGSize(width:844,height:390),CGSize(width:852,height:393),CGSize(width:1366,height:1024),CGSize(width:390,height:844)]
for size in sizes {
 for offset in [CGPoint.zero,CGPoint(x:58,y:60),CGPoint(x:10,y:100)] {
  let window=Window(CGRect(origin:.zero,size:size)),hud=HUD();hud.window=window;hud.offset=offset
  hud.bounds=CGRect(x:0,y:0,width:size.width-offset.x-20,height:size.height-offset.y-12)
  if !drawOnly {
   hud.layout();let view=hud.aim.frame.offsetBy(dx:offset.x,dy:offset.y)
   require(view==window.bounds,"Scope mask follows shortened HUD instead of full window")
   let centre=hud.aim.aimPoint!
   require(abs(view.minX+centre.x-window.bounds.midX)<0.001 && abs(view.minY+centre.y-window.bounds.midY)<0.001,"Sight centre uses the wrong view coordinates")
  }else{hud.aim.frame=window.bounds;hud.aim.aimPoint=CGPoint(x:size.width/2,y:size.height/2)}
  let viewport=hud.aim.bounds
  let dirty=[viewport,CGRect(x:4,y:3,width:8,height:12),CGRect(x:size.width/3,y:size.height/4,width:19,height:22)]
  var reference:CGRect?
  for area in dirty {
   hud.aim.scoped=true;UIBezierPath.fills=[];hud.aim.draw(area)
   require(UIBezierPath.fills.first?.rectangle==viewport,"Dirty rectangle changed full-window scope coverage")
   let mask=UIBezierPath.fills[0];require(mask.usesEvenOddFillRule,"Scope aperture lost even-odd transparency")
   require(mask.children.count==1,"Unexpected scope aperture count")
   let hole=mask.children[0].oval!
   require(hole.minX>=viewport.minX && hole.maxX<=viewport.maxX && hole.minY>=viewport.minY && hole.maxY<=viewport.maxY,"Aperture escaped the game window")
   require(abs(hole.midX-viewport.midX)<0.001 && abs(hole.midY-viewport.midY)<0.001,"Aperture left the actual camera centre")
   if let reference{require(reference==hole,"Dirty rectangle changed scope aperture size")}else{reference=hole}
   hud.aim.scoped=false;UIBezierPath.fills=[];hud.aim.draw(area)
   require(!UIBezierPath.fills.contains{$0.rectangle != nil},"Ordinary aim blacked out the game window")
  }
  if !drawOnly {
   hud.window=nil;hud.layout()
   require(hud.aim.frame==hud.bounds,"Detached HUD lost its local fallback")
   require(hud.aim.aimPoint==CGPoint(x:hud.aim.bounds.midX,y:hud.aim.bounds.midY),"Detached sight retained a stale window coordinate")
  }
 }
}
print("PASS actual scoped viewport/draw geometry: \(checks) checks; five authored screen sizes and dirty regions; UIKit pixels/retail remain separate")
