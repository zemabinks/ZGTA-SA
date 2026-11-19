# Static model material state

Untextured material draws now use a constant texture contribution. A bound
white fallback still satisfies the encoder's texture binding, but its sampler
address mode no longer changes an untextured surface outside the UV range.
Textured materials and explicit texture replacements still sample normally.

The geometry modulation flag controls the default material color, including
alpha. An explicit material-color replacement retains priority. The existing
raw material-alpha blend selection is independent of this flag and remains
unchanged, as do vertex colors, lighting and depth policy.

The static-model test uses authored files and offscreen Metal readback. It
checks textured and untextured materials, sampler configurations, modulation,
vertex color, alpha and explicit replacements. An alternate historical shader
can demonstrate the untextured border-sampling failure with current test and
runtime sources held constant.

```sh
python3 test_native_renderware_model.py --cpu-only
python3 test_native_renderware_model.py --require-metal
```

The GPU command requires a real Metal device and performs an explicit readback
blit. CPU mode does not establish rendered acceptance. Source checks retain the
current stock/custom resource-admission predicates; they do not execute those
transports. Missing named textures, incomplete resources and malformed assets
remain rejected. This change does not establish game-world, custom-pipeline,
physical-iPhone or retail-pixel parity.
