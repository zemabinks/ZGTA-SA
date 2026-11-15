# Native parachute and jetpack

Movement is the native translation of public module 54205.$l. The fixed-step
character coordinator supplies the original ground height from feet + 0.1 m,
with a 400 m query, and passes movement/rising speed to the shared Rapier motor.
The separate 54205.ap presentation port retains parachute clip clocks,
opening/landing canopy, figure pitch/roll, jet nozzles and thigh pendulum.

On the independent Mac server, open the game menu, choose **Flight equipment**,
and equip a parachute or jetpack. The self-only `/parachute` and `/jetpack`
commands also work. These free equipment grants are a local server policy;
the publisher exposes them as staff commands. Discord is unnecessary.

- Parachute: a high fall starts diving; fire opens the canopy. The movement
  stick controls dive/steering/deceleration. Landing or swimming consumes an
  opened parachute. Fast uncovered landings can be fatal.
- Jetpack: run or move forward to lift, jump to descend, crouch to brake.
  The right stick/camera controls heading. Flight retains the original
  thrust, drag, bank, ground transition and height limit.
- Touch, keyboard and controller actions feed the same movement controller.
  Multiplayer uses the original 50–62 action range and rounded pitch/roll.

`prepare_native_flight_assets.js --archive-missing` retains the four public
original assets locally and exports the actual canopy/jetpack. Both Mac
launchers use the shared `prepare_native_runtime.sh`. Original assets,
converted meshes, rigs, fixture recordings and compiled applications remain
under ignored `local-only/` or a temporary build directory.

Checks:

- `python3 smoke_native_personal_flight.py`: 16,800 actual browser movement
  frames; 152,166 state, trajectory and landing comparisons; maximum error
  1.07e-14.
- `python3 smoke_native_flight_animation.py`: 5,400 original presentation
  frames; 49,722 checks, maximum error 1.11e-16.
- Full R6 replay includes 1,800 personal-flight frames among 12,080 frames;
  maximum native Float32 vertex difference 26.5 µm.
- Attachment replay covers 1,440 frames/40,860 canopy skin/world-vertex and
  nozzle-matrix comparisons; maximum Float32 difference 2.74 µm.
- `python3 smoke_native_wire.py`:actual Swift WebSocket client verifies
  flight fields, equipment, full pedestrian state and parked-car reports.
- `node smoke_native_server.js`:guest equipment grants, consumption,
  death restrictions and saved equipment alongside vehicle persistence.

The latest combined application still requires simulator/device acceptance.
Original jet exhaust particle emission/audio callbacks, aircraft bail-out
equipment routing and every private inventory rule remain separate gaps.
