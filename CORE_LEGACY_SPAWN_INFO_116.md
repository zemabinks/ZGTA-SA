# Legacy next-spawn data ownership

RPC68 (`SetSpawnInfo`) previously reused the accepted-class callback. A valid update while already spawned therefore selected a new local appearance and opened SELECT CHARACTER even though the client remained spawned. Previous/Next and SPAWN could not perform their advertised operations because their protocol guards correctly rejected class selection and voluntary spawn in that state.

The client now reports spawn-data updates through a separate callback while retaining the latest cached spawn information. The adapter identifies whether the actual client is selecting or waiting for spawn authorization. A live update does not replace the live actor, change placement, reset input/vitals/weapons, open a menu or send a spawn acknowledgement.

An existing class choice can refresh its appearance and resource admission in place. Its SPAWN action reads the current owned skin, so an override cannot retain the old action's captured readiness. If another modal is still dismissing, a per-presentation UUID preserves the accepted class's pending presentation while reading its latest skin. A newer accepted class supersedes older pending presentations; cancelled selection remains cancelled.

RPC128 still owns accepted class selection. Authorized RPC129 and spectator-off spawning consume the latest cached information, including updates received after a voluntary spawn request. RPC68 does not clear the pending request guard. Existing actor-resource admission and source/request fencing remain responsible for model availability.

## Placement boundary

This change adds no class-preview teleport. Class spawn coordinates and an explicitly scripted preview placement are distinct: the official qawno template deliberately places its class preview in a different interior from its eventual spawn. Blindly applying every class response's future spawn coordinates could overwrite that server-owned preview. Existing explicit position, heading, camera and spawn placement paths remain unchanged. A transient missing preview was not established as a missing-body defect; later normal phone observation showed CJ.

## Focused verification

```sh
python3 smoke_samp_spawn_info.py
python3 smoke_native_actor_selection.py
```

The first carrier compiles the complete actual client, adapter, protocol and admission helpers plus the selected actual class-menu methods and event cases. Authored packets cover both supported profiles, live updates, pending overrides, resource admission, delayed dismissal, supersession/cancellation, authorized forced and spectator spawns, denial/retry, malformed data and reconnect cache reset. An optional historical Client input must compile and fail the same live-ownership assertion; an optional historical menu method reproduces the delayed-dismissal race.

The retained focused run passed 94 assertions across both profiles with unchanged scoped sources. The historical client compiled and failed the live-class assertion after 11 checks, while its unused callback declaration supplied API compatibility only. The literal historical presentation method separately reproduced the pending-dismissal failure inside the successful current run. An initial 180-second compilation timeout and an authored fixture argument-label error remain retained as separate attempts.

The existing actor-selection carrier also passed all 650 assertions. Its fixture needed only storage for the new presentation UUID; its original assertions were retained. The affected lifecycle carrier's RPC68 expectation now identifies spawn metadata rather than a class/placement event. Its later complete rerun passed all 110 client/adapter/NMP lifecycle assertions in 255.35 seconds with unchanged scoped sources. A private adapter changed only compiler scheduling to a single-job, whole-module, unoptimized build with a 900-second bound; the production runner and assertions were not replaced. This full carrier uses the actual transport archive with no socket or fake transport acceptance.

Transport queueing, UI presentation and resource readiness are explicit recording boundaries. No socket is opened or polled; unused HTTP fails immediately. The tests do not establish a live join, actual UIKit behavior, rendered model readiness, retail behavior or complete server compatibility. Full App builds and normal runtime acceptance remain separate. Private reports retain source hashes, compiler commands, the initial bounded compilation timeout and subsequent results.

## Primary references

Official [class network definitions](https://github.com/openmultiplayer/open.mp/blob/master/Shared/NetCode/class.hpp) distinguish class responses, spawn data and spawn authorization. The [Classes component](https://github.com/openmultiplayer/open.mp/blob/master/Server/Components/Classes/classes_main.cpp) sends their respective messages. These current source references corroborate ownership; they are not a pinned copy of the exact QA binary.

The official [GetSpawnInfo documentation](https://open.mp/docs/scripting/functions/GetSpawnInfo) describes future spawn data. The [qawno template](https://github.com/openmultiplayer/qawno/blob/master/gamemode.new) demonstrates separate preview placement. No original client implementation or game asset is redistributed by this correction.
