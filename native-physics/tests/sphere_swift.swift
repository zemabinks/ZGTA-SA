import Foundation
import simd

@main enum SphereSwiftABI {
 static func main() {
  let world=SwiftRapierWorld()!
  var ids:[UInt64]=[],checks=0
  func check(_ value:Bool,_ label:String){checks += 1;precondition(value,label)}
  for i in 0..<150 {
   let collider=world.addSphere(radius:0.2)!
   check(world.setColliderGroups(collider,collision:i%2==0 ? 0x00010001:0x00020002,solver:0xffffffff),"groups")
   check(world.setColliderQueryMetadata(collider,surface:2,material:i%3==0 ? 62:0),"PED metadata")
   ids.append(collider)
  }
  check(world.sphereIntersections(center:.zero,radius:0.3).count==150,"buffer grows beyond64/128")
  check(world.sphereIntersections(center:.zero,radius:0.3,groups:0).isEmpty,"explicit empty groups")
  check(world.sphereIntersections(center:.zero,radius:0.3,groups:0x00010001).count==75,"one membership/filter mask")
  check(world.sphereIntersections(center:.zero,radius:0.3).filter{$0.material != 62}.count==100,"caller PED predicate preserved")
  let excluded=Set(ids.prefix(7))
  check(world.sphereIntersections(center:.zero,radius:0.3,excludingColliders:excluded).count==143,"explicit collider exclusion")
  let body=world.addBody(position:.zero)!
  _=world.addSphere(radius:0.2,body:body)!;_=world.addSphere(radius:0.2,body:body)!
  check(world.sphereIntersections(center:.zero,radius:0.3).count==152,"attached bodies included")
  check(world.sphereIntersections(center:.zero,radius:0.3,excludingBodies:[body]).count==150,"body exclusions remove every attached shape")
  check(world.sphereIntersections(center:.zero,radius:0.3,flags:1).count==2,"exclude fixed")
  check(world.sphereIntersections(center:.zero,radius:0.3,flags:4).count==150,"exclude dynamic")
  check(world.sphereIntersections(center:.zero,radius:0.3,flags:16).isEmpty,"exclude solids")
  check(world.setCollider(ids[0],enabled:false),"disable")
  check(world.sphereIntersections(center:.zero,radius:0.3).count==151,"disabled shape omitted")
  check(world.sphereIntersections(center:.zero,radius:0).isEmpty,"zero radius safely rejected")
  check(world.sphereIntersections(center:SIMD3(.nan,0,0),radius:0.3).isEmpty,"invalid origin safely rejected")
  let sphere=Set(world.sphereIntersections(center:.zero,radius:0.3).map(\.id))
  let capsule=Set(world.intersections(center:.zero,halfHeight:0,radius:0.3).map(\.id))
  check(sphere==capsule,"deep-overlap filtering compatibility")
  print("PASS literal sphere Swift ABI:",checks,"checks, dynamic buffer growth, groups, PED predicate, disabled/body/collider exclusions and invalid inputs")
 }
}
