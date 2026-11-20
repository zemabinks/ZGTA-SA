# Stock resource source lifetimes (149)

Changing the configured asset source previously left the stock catalog, loader,
GPU meshes and physical collision registrations attached to the preceding
source. A same-URL resource repair had the same problem. The old loader could
then reject the new source's URLs or leave the old world props visible.

The renderer now retires these stock resources when the existing resource
binding identity changes. It cancels bootstrap/model/dictionary work, clears
old retry suppression and pending counters, removes the retired stock GPU and
physical registrations, and starts a fresh bootstrap on demand. Server-defined
object instances, movement, attachments and independently downloaded DL artwork
remain separate. Normal same-source frames retain their ready resources.

The metadata and model callbacks check their captured source, generation and
request owner before publication. The model pump also checks its captured
catalog/loader source between iterations: a reentrant status callback cannot
make it continue loading an old catalog under the new source's identity.
Raw material-dictionary requests use the existing bounded transport with a
64 MiB encoded limit, cancellation handles and per-request tokens. An old
completion cannot clear a replacement request or install an old texture.

Stock texture keys can overlap custom artwork's base-model keys. The renderer
retains the independently registered artwork bindings and restores surviving
bindings when stock resources retire or are evicted. Differing surviving
artwork checksums remain explicit conflicts. No texture is chosen by filename
similarity, and no model or collision geometry is fabricated.

## Evidence boundaries

The authored Foundation carrier executes the literal renderer source/reset,
texture-retirement and server-setter statements. Download, mesh, collider and
material owners are explicit spies in this gate. The separate stock-runtime
carrier executes the actual extracted callbacks with real loopback HTTP,
RenderWare decoding, Metal uploads/readbacks and Rapier collider registration.
It retains its original retail-prop fixtures and existing assertions, and adds
origin changes, same-content resource-generation repairs, bootstrap CPU work
finishing after retirement, a reentrant source switch and dictionary-request
replacement. The last dictionary callback-order fixture controls transport
delivery; its decoder and Metal upload remain real.

Preserved failures include the old 148 renderer retaining its GPU registration,
an initial unsupported URL-path fixture, a run rejected because its input source
changed during validation, and the pre-reentry-fix pump. The final authored owner gate passes 23 checks. The actual HTTP/RW/Metal/Rapier
carrier passes 291 checks with 11 GPU readbacks; all five added source-transition
scenarios pass. The full selected Core149 chain with required Metal, physics,
audio and transport passes in 774.0 seconds, with 226 app/build inputs and five
changed test sources held. Host/project/layout gates pass. SDK and installed-app
acceptance remain separate pending gates.

This is a resource-lifetime correctness repair. It does not complete ordinary
stock-ped importing, timed-object activity, ambient AI, traffic, police, full
original resources, physical-device acceptance or original-PC gameplay parity.
Original resources, fixture bytes, recordings and private histories stay local.

```sh
python3 tests/resources/smoke_native_stock_source.py
python3 tests/core/smoke_core_149.py --require-gpu --with-physics --with-audio --with-transport
# Optional owner-resource integration gate, with prepared local references:
python3 tests/network/test_samp_stock_runtime.py --source-transitions
```
