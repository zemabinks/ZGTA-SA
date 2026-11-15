import Foundation
import simd
import CoreFoundation

// The runner inserts the production prediction type here.
// HEALTH_PREDICTION

@main struct HealthCheck {
 static var checks=0
 static func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
 static func main() throws {
  for initial in 1...100 {
   for fall in 1...initial {
    var p=NativeHealthPrediction();p.begin(connection:"current",health:initial,armour:25,revision:0,processed:0)
    let request=p.hurt(to:initial-fall)!
    check(request.sequence==1 && request.damage==fall && p.health==initial-fall && p.armour==25,"local fall not predicted/bypassed armour")
    let serverLoss=min(7,initial)
    check(p.apply(health:initial-serverLoss,armour:17,connection:"current",processed:0,revision:1),"new server damage rejected")
    check(p.health==max(0,initial-serverLoss-fall) && p.armour==17,"server damage overwrote local loss or was charged twice")
    let final=max(0,initial-serverLoss-fall)
    check(p.apply(health:final,armour:17,connection:"current",processed:1,revision:2) && p.health==final,"acknowledged loss charged twice")
    check(!p.apply(health:initial,armour:25,connection:"current",processed:0,revision:0) && p.health==final,"stale HTTP healed predicted damage")
    check(p.apply(health:100,armour:50,connection:"current",processed:1,revision:3) && p.health==100 && p.armour==50,"actual server heal/armour upgrade lost")
   }
  }
  var p=NativeHealthPrediction();p.begin(connection:"A",health:100,armour:25,revision:0,processed:0)
  _=p.hurt(to:0);let pending=p.respawn()!
  check(p.health==0 && pending.sequence==2 && p.respawn()==nil,"respawn healed optimistically or duplicated pending request")
  check(p.apply(health:0,armour:25,connection:"A",processed:1,revision:1),"fatal ack rejected")
  check(p.apply(health:0,armour:25,connection:"A",processed:2,revision:2),"rejected respawn not acknowledged")
  let retry=p.respawn()!;check(retry.sequence==3,"rejected request prevented later respawn")
  check(p.apply(health:100,armour:0,connection:"A",processed:3,revision:3) && p.health==100,"real respawn not restored")
  _=p.hurt(to:70);p.disconnect();check(!p.active,"disconnect retained pending health namespace")
  p.begin(connection:"B",health:70,armour:0,revision:0,processed:0)
  check(p.health==70 && !p.apply(health:100,armour:100,connection:"A",processed:4,revision:99),"old peer response corrupted fresh baseline")
  check(p.hurt(to:65)!.sequence==1,"old unacknowledged request replayed after reconnect")
  check(!p.apply(health:100,armour:0,connection:"B",processed:2,revision:3),"future acknowledgement accepted")
  check(!p.apply(health:69,armour:0,connection:"B",processed:0,revision:0),"same revision changed authoritative value")
  for value:Any in [true,-1,0.5,Double.nan,Double.infinity,"1",9_007_199_254_740_992.0] {
   check(NativeHealthPrediction.integer(value)==nil,"invalid ACK integer accepted")
  }
  p.begin(connection:"limit",health:100,armour:0,revision:0,processed:9_007_199_254_740_991)
  check(p.hurt(to:90)==nil,"issued an unrepresentable JS request sequence")
  p.begin(connection:"limit",health:0,armour:0,revision:0,processed:9_007_199_254_740_991)
  check(p.respawn()==nil,"issued an unrepresentable respawn sequence")
  print("PASS health prediction: \(checks) actual production checks for concurrent server/local loss, armour, stale HTTP, heal, fatal/respawn and lost-ACK reconnect")
 }
}
