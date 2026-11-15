# Native settings

`NativeAppSettings.shared` stores a validated `Snapshot` in the device's UserDefaults under `native.app.settings.v1`. Use `update { ... }` or `reset()`; `didChange` notifications identify the changed store in `notification.object`. Preferences apply when a game loads, when they change, and when the game becomes visible again. Server accounts, inventory and gameplay controls are separate.

| Preference | Default | Supported values / owner |
|---|---|---|
| Resolution scale | 100% | 50–100%; Renderer recalculates actual MTK drawable pixels from point bounds and display scale on layout. |
| Frame-rate cap | 60 | 30–120, limited to the current screen maximum; both MTKView and CADisplayLink request the same cap. OS/power/thermal limits may lower actual rate. |
| Camera sensitivity / invert Y | 1× / off | 0.25–3×; both native on-foot and vehicle camera look calls. One global setting covers touch and controller camera input; vehicle steering/pitch controls retain their bindings. |
| Foot / vehicle camera | Middle / middle | Three foot views, six vehicle views; existing camera-cycle controls save the same values. |
| Radar | Shown, circular, 400m, markers on | Range200–1200m; applies to the minimap. Full map, navigation targets and waypoints remain available. |
| Master / effects / radio levels | 100% each | 0–100%; normalized multipliers preserve the existing effects0.7 and radio0.6 mix at defaults. |
| Regional weather | Off | Server weather by default; existing regional-weather override toggle is synchronized. |
| Reduce menu motion | Off | Menu transitions also respect iOS Reduce Motion. |

First load preserves previous `world.view.foot`, `world.view.car` and `world.weather.auto` values. Reset persists the real defaults, including those legacy keys, and updates the running game. It does not erase the local account, garage, server address or saved radio station.

`NativeOptionsViewController(settings:)` uses the common DE panel for touch, keyboard and controller navigation. In-game Options is presented over the game; the existing presentation override cancels held inputs. The multiplayer world remains live. Unsupported shadow/lighting-quality, voice, character-creation and control-remapping options are omitted.

Validation: `python3 smoke_native_settings.py` checks persistence/migration/corruption, bounds/defaults/reset, actual camera look at30/60/120Hz, and extracted Renderer/VC owner application. It does not measure physical iPhone frame rate or controller hardware. Audio waveform and active-voice gain tests are maintained separately. The iPhone high-refresh request additionally requires Apple's `CADisableMinimumFrameDurationOnPhone` Info.plist opt-in; see [Apple's key reference](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone).
