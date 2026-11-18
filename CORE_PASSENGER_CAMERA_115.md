# Passenger camera frame correction

The native passenger camera previously used the fallback driver adapter. This selected the driver eye, reconstructed a level right/up basis, reconstructed velocity from forward speed, and supplied zero angular velocity. The attached passenger and visible vehicle already used a complete shared transform. Consequently the camera could disagree with its own seated actor during roll, sideslip and turns.

`NativeWorldRenderer.nativeCameraVehicle()` now handles passengers before the owned-driver branch. It uses the confirmed vehicle's shared model-root transform, its actual velocity and angular velocity, and the selected rider seat position (including its authored shift). Missing or mismatched passenger state returns no vehicle camera instead of consulting an unrelated owned body. Ordinary driver and other fallback paths are unchanged.

The shared transform uses GTA Z-up coordinates. Its translation already contains the rotated model-origin offset, once. Its first three columns are right, forward and up; the camera adapter applies no additional origin or axis conversion. A retained parked physics body supplies its current motion through the existing Rapier-to-GTA conversion. Remote driver and owned body motion retain their existing GTA units. Camera velocity and angular velocity are divided by 50, matching the existing driver and browser contracts.

## Verification

Run the asset-free focused gate:

```sh
python3 smoke_native_passenger_camera.py
```

The carrier compiles the literal production camera adapter, shared-frame method, coordinate functions, wire value types, rider definitions and `NativeGameCamera`. Metadata and poses are invented. Physics storage and prediction are explicit storage boundaries; unused HTTP calls fail immediately. The gate checks selected front/rear seats, shifted seats, roll/pitch/cardinal headings, three model origins, sideslip/spin, missing or wrong frames, missing definitions, missing seat eye, parked motion conversion and preserved owned-driver behavior. It compares actual camera outputs with the expected shared body/seat inputs at 15/30/60/120 Hz in middle, eye and bumper views.

The retained run passed 65,030 assertions over 24 configurations and 21,600 actual native camera output frames. The same carrier compiled the literal previous adapter and rejected it at the selected-seat eye assertion (exit 1); the corrected adapter exited 0. All scoped sources remained unchanged during execution. The complete actor draw method and 210 other frozen App/build inputs remained byte-identical. Private reports retain commands, source hashes and the historical negative.

Offline execution of the retained browser passenger component and camera independently confirmed the input contract. Invented examples produced an 0.8 m eye error from using the driver seat, a 0.2607 m error from omitted roll, and a 0.9318 m eye error from omitted sideslip/spin. Those are source-level numerical counterexamples, not observed retail-game or device measurements.

## Limits

The focused gate does not prove rendered pixels, collision queries, live multiplayer timing, retail feel, or cross-schedule camera trajectory equality. Full App SDK compilation and device/Simulator observation remain separate acceptance steps. Remote wheel contact counts are unavailable; the passenger adapter preserves the browser's four-wheel metadata convention. Non-passenger fallback behavior and existing smoothing curves remain unchanged. This correction does not establish 1:1 San Andreas parity.
