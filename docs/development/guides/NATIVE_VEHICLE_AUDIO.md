# Native vehicle audio

`NativeVehicleAudioDynamics` translates public module1061's sound planning as
pure Double calculations. Original bank mappings, PCM and loop metadata remain
in the ignored native audio manifest. The helper includes:

- The road engine's 20 ms accumulator and idle/rev/run-up/cruise/fall state
  machine, heard gearbox, hills, wheelspin, lean, nitro and single-gear cases.
- Aircraft rotor/pitch curves, front/rear/near/far layers and health variation.
- Boat throttle/turning, engine/skim attenuation, remote trend and slam timing.
- RC car/plane/helicopter, golf cart, hovercraft, train/tram and alternating
  braking layers; remote road-engine crossfades and reverse sound state.
- Original tyre surface/flat-tyre and damaged-engine sputter planning.

`RoadEngine.update(delta:input:runUpDuration:loopStart:)` takes the actual physics
state. Run-up duration and loop start come from the run-up bank's original PCM
frame metadata. `roadPlan` converts the returned mix into voice instructions.
Its `retain` set preserves a fall sample during idle; restart and fractional
offset distinguish original run-up/fall transitions from continuous loops.

`NativeVehicleLoopAudio` owns one native AVAudioSourceNode. Register each fetched
WAV with its original loop-start frame, then apply a plan under a vehicle prefix:

```swift
renderer.register(bytes, name: sampleName, loopStart: originalLoopFrame)
renderer.apply(plan, prefix: "mine", gain: masterGain)
```

It plays the attack once and repeats only the tail. Source-rate interpolation
supports rates below AVAudioPlayer's floor. Rate/gain changes follow the original
30 ms target smoothing. Stops use the original default 90 ms parameter: gain's
time constant is one third of that parameter and source removal occurs after
twice the parameter, 180 ms. Restarts preserve the previous fading voice. Audio
decoding occurs outside the render lock. PCM, node scheduling and output remain
native; no WebView or system/audio-session configuration is introduced.

Validation invokes the actual archived pure functions offline and retains all
raw traces under local-only:

```sh
zsh tests/audio/smoke_vehicle_audio.sh
zsh tests/vehicles/smoke_vehicle_loop.sh
```

The original planning replay covers 12,000 road frames and 21,600 aircraft,
boat, special, train, remote and reverse frames. Maximum observed difference is
2.23e-16. The loop renderer has separate synthetic PCM/lifecycle and actual
offline AudioUnit checks. Those checks establish native timing, pitch and loop
semantics; they do not claim that a platform resampler's output is bit-identical
to Chromium's Web Audio resampler or replace real-device listening tests.

`NativeVehicleAudioSpatial` preserves original nearest-five selection and
per-type panner profiles. Its selection/configuration fixture executes the
actual archived `hear` method against an AudioContext recorder: 60 scenes and
300 selected voices agree. The additional 800 spatial cases implement the
[W3C inverse distance model](https://www.w3.org/TR/webaudio/#dom-distancemodeltype-inverse)
and [equalpower mono/stereo algorithm](https://www.w3.org/TR/webaudio/#Spatialization-panning-algorithm).
Inverse attenuation continues past maxDistance; the game's 110/330 m selection
thresholds determine voice removal. Optional `spatialAzimuth:` in the native
loop renderer uses the actual decoded source channel count, including the mono
centre gain rather than treating duplicated mono as stereo. `listener` and
`apply(... spatialPosition:panner:)` evaluate the original 30 ms listener and
50 ms source AudioParam targets at each render sample. Distance gain is applied
after the voice's independent gain curve. An analytic moving-source test checks
all 1,536 samples across a control update, alongside native AudioUnit output.
