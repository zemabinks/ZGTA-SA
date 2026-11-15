# Bicycle input and control ownership

Braking and bunny hopping use separate native inputs. `vehicleHandbrake` controls the brake; `vehicleHop` represents a held hop gesture. Holding the hop charges it, and normal release launches when both wheel groups have ground contact. Braking no longer charges a hop or launches one on release.

The current native controller scheme uses A/Cross for bunny hop and X/Square for braking. The touch attack/horn position becomes the contextual bunny-hop control on a bicycle. The [official PS3 manual's bicycle controls](https://media.rockstargames.com/rockstargames-newsite/img/manuals/en_us/GTA_SA_PS3_MANUAL_ENG.pdf) separate those actions. The archived browser uses its vehicle-fire binding for hop: primary mouse or standard-gamepad Pad1/B. These are different control schemes; the browser mapping is not evidence that a brake should also request a hop.

## Cancellation and ownership

`NativeGroundVehicle.cancelPendingInput()` forwards to `NativeBikeDynamics.cancelPendingHop()`. It discards an unlaunched charge while retaining an already launched hop's timer and physical momentum. It leaves pedal counters, crank, lean and stamina state intact. The renderer calls this when gameplay input is cancelled and before stepping without an enabled seated driver; the vehicle manager also calls it before zero-health/wreck stepping. Exit and solver recreation create a fresh charge state.

`NativeVehicleInputOwnership.gated(_:enabled:)` neutralizes throttle, steering, lean, pitch, roll, yaw, jets and hop while no seated living driver owns the controls. It holds the brake and removes explicit accelerator/brake/pedal overrides, including an optional drive override. Passive solver inputs such as controller mode, wetness and suspension offsets remain available. Camera look has its own input owner.

This is an explicit native boarding policy. In the public browser, the digital-action helper suppresses inputs during boarding/busy states, the brake is held and hop is disabled. Some analog terms remain available and can first cancel boarding. The native port does not claim to reproduce that entire analog boarding-cancellation path.

## Shared stamina

The owned bicycle uses the same player's budget as foot/swim sprinting through optional `NativeGroundVehicle` callbacks:

```swift
vehicle.staminaLeft = { stamina.left }
vehicle.takeStamina = { amount in stamina.take(amount) }
vehicle.restStamina = { amount in stamina.rest(amount) }
```

The callbacks receive the original 50 Hz effort amounts. `NativeStamina.take(_:)` already divides the debit by three internally; the binding must not divide it again. Available stamina refreshes at each fixed physics step. Re-entering or rebuilding a bike solver does not replace the player's budget. Nil callbacks preserve the existing standalone solver defaults, and unattended vehicles do not consume the player's pool.

The public browser passes `c6.breath` into its bicycle wrapper. Native pedal tapping, effort decay, breathing costs and rest calculations remain unchanged; only the missing connection to the shared budget was added.

## Regression scope

```sh
python3 smoke_bicycle_input.py
zsh smoke_vehicle_lifecycle.sh
```

The bicycle runner extracts and compiles the actual renderer-to-physics mapping, including its final ownership gate, with the production Swift helpers and native physics library. It uses owner-local model metadata and a synthetic flat collision surface. It checks independent braking/hopping, grounded charge/release, cancellation before and after launch, boarding loss, wreck and fresh entry, 30/60/120 Hz trajectories, preserved passive inputs, shared-budget debit/rest and handoff.

The stamina ledger is compared step by step with the existing independently translated bike sprint profile. Cancelling an absent hop repeatedly must leave that profile's pedal costs unchanged. Original model metadata and runtime traces remain under ignored `local-only/`; the runners contain no original asset tables.

These are native integration and public-client behavior checks. The manual supports the input distinction; it does not verify retail/iOS hop physics. Physical controller/touch usability, retail runtime timing and the unported analog boarding-cancellation behavior require separate runtime evidence. No acceleration or high-speed suspension tuning was changed.
