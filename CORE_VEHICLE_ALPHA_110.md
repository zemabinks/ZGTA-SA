# Vehicle material ordering and remote appearance · Core110

Two separate rendering defects were found. Transparent vehicle parts were drawn
in each vehicle's instance order, between an earlier own passenger and a later
remote driver. A depth-writing window could therefore reject every driver
fragment. Separately, remote appearance was classified by the optional registry
vehicle ID: supported ID-less driver rows incorrectly entered the foot branch
and never appended a driver.

The renderer now draws opaque vehicle parts normally, completes opaque actors,
then draws captured transparent vehicle packets in stable far-to-near order.
Every packet retains its own mesh, atlas, model/part transform, paint, emissive,
scorched and alpha-test state. Opaque hull occlusion and the original transparent
**depthWrite=true** policy remain. No hull, pose, camera near plane or vehicle
visibility change is involved. Opacity is already baked into vertex alpha and
is not multiplied a second time.

The existing cached rig metadata supplies `glass`, `opacity` and `alphaTest`.
The classifier `glass == true || opacity < 1 || alphaTest > 0` matched all
15,422 material groups across 212 available archived-browser vehicle factories,
including 2,854 transparent groups. This is archived-browser factory evidence,
not retail-runtime verification. Missing optional fields retain old defaults;
texture-alpha parts with opacity1 remain included through alphaTest. Adjacent
parts merge only when their transparency state also agrees.

Sort anchors use each node's indexed local bounds centre, transformed through
its actual instance/part view-projection matrix. Equal depths preserve insertion
order, including duplicate model instances. This approximates conventional
object-centre transparency sorting; intersecting transparent geometry and
unused source vertices can require a more detailed policy. Original material
source order, alpha testing, depth testing and shader output remain intact.

Remote rendering roles now follow the same `s` appearance prefix as the packet
client, with the explicit passenger relation taking precedence. ID-less car and
bike rows retain rider/bike caches and append the normal driver. Foot and
passenger rows retain their own branches. Private rig animation cache keys can
use player identity when the registry ID is absent. No registry ID is created,
no authority is granted, and shared-ID parked-car exclusions remain unchanged.

Run independent authored checks on macOS with Xcode:

```sh
python3 smoke_native_vehicle_transparency.py
python3 smoke_native_remote_appearance.py
python3 smoke_native_vehicle_alpha.py
```

The last command requires actual offscreen desktop Metal access. It discovers
an already-installed Metal compiler or accepts `--metal /path/to/metal` /
`ZGTA_METAL_COMPILER`; it does not install tools. `--compile-only` explicitly
reports compilation only and is not runtime acceptance.

Focused results: **27** actual Rig/encoder state checks; **17** actual packet,
role and cache assertions; **80** actual Metal checks using unchanged production
shaders/pipeline and the new extracted deferred encoder. Historical draw orders,
opaque hulls, alpha-test discard, texture alpha, depth-write controls and
multiple overlapping windows are retained as positive/negative controls. Merely
disabling window depth writes fails correct compositing; disabling hull depth
writes leaks riders through opaque geometry. Proper phase/order works while
retaining depth writes.

All geometry and textures in the public regressions are independently authored.
Original factory probes, vehicle resources and outputs stay private. Full App
SDK builds, actual iOS views, live driver visibility and wheel acceptance remain
separate checks; no retail 1:1 or phone performance claim follows from these tests.
