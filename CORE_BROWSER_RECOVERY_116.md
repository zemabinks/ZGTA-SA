# Self-host browser recovery admission

Core116 adds an independently authored, explicitly negotiated browser recovery adapter. This addresses a demonstrated reconnect divergence: an archived client can retain its active car after the server has revoked the registered claim, then legitimately serialize that car as ID-less freeplay. Accepting genuine freeplay is intentional; retaining the previous driving mode through reconnect is the separate defect. The retained observation normalizes missing properties to null and is not evidence of a literal `vehicle:null` packet.

This is an independent self-host policy. It is not evidence of original GTA save/reconnect behavior or complete game parity. Bounded live acceptance is described below; source tests and rendered gameplay remain separate evidence.

## Boundaries

- `browser_recovery.js` wraps only the normal same-origin `/api/world/live` WebSocket. It neither creates a replacement/replay socket nor injects input, pose, vehicle identity, account state, or engine callbacks.
- `browser_recovery_hook.js` verifies three bounded, uniquely occurring callback fingerprints in an owner-supplied archived bundle. It adds a completion witness to normal teleport and generation guards to the two normal entry callbacks. The original file is unchanged; no original implementation is included in public source. A mismatched served callback returns503 with a useful error. An unregistered client cannot negotiate this capability and retains explicit legacy behavior.
- `serve_local.js` loads the adapter before the archived asynchronous scripts and serves the adapter/transformed response without caching. Existing Host, Origin and join gates run first.
- `player_placement.js.createBrowser` is separate from the existing native factory. It does not satisfy or relax native inventory, health or position ACK prerequisites. Genuine unnegotiated legacy clients retain their existing protocol.

## Wire contract

An instrumented ordinary browser advertises `hi.browserRecovery:1`. A fresh server peer returns `hello.browserRecovery:1` and `browserPlacement:{connection,revision}`. The connection is a fresh24-character base64url namespace; revision is a nonnegative safe integer. Native ACK clients do not enter this browser path.

The server sends its normal `tp`, then the normal full baseline. The TP carries the same `browserPlacement` envelope. This order lets the normal callback release the old registered controller before baseline reconciliation can demote it to local freeplay. A pre-baseline callback still cannot unlock client admission: a subsequent genuine report requests the same normal TP again after the baseline. If gameplay is not active yet, that first callback is simply ignored and the same real-report retry path applies. Teleport heading remains degrees; saved positions remain radians. The target is the server's admitted foot checkpoint or existing placement-selection fallback, never a cached car claim or guessed safe egress.

The client requires all three steps:

1. A valid fresh baseline and completion of the currently delivered matching normal teleport callback. A returned-early callback, direct unrelated callback, stale namespace or replaced transport cannot provide this witness.
2. A subsequent genuine alive foot `me` report from the archived serializer. The adapter adds the applied envelope centrally. It does not manufacture a position or foot report. If the character is not active yet, real reports may request a bounded resend with `browserPlacementRequest`; there is no timer-generated gameplay or report replay.
3. An explicit server `browserPlacement` response with `accepted:true` and the same envelope, after normal foot admission.

Until admission, previous role/position/shot/exit writes are discarded rather than queued. This includes the old park/exit message that normal teleport cleanup can emit. Subsequent server teleports increment the revision, revoke old roles and fence queued old reports. A duplicate hello cannot rewind a newer placement. Admission creates no vehicle authority: a later ordinary entry is still required. Genuine ID-less freeplay remains supported after admission.

The bounded arrival check requires a grounded foot report within2 horizontal units and3 vertical units of the server target. These are independent admission tolerances, not inferred retail constants. Missing collision coverage, no viable foot report, a refused callback or server death fails closed. No position, health, ammunition, job, inventory or vehicle ownership is restored from the adapter's cached role. A character dead at reconnect requires a server-authorized recovery; this change does not introduce a new browser respawn protocol or heal it.

## Input lifecycle

A true close of the previously established active game connection may call only ordinary `document.exitPointerLock()`, and only when that same canvas was observed owning the lock during a real nonpaused game report. Fresh join, a same-peer live teleport, a duplicate close, an old socket or a lock owned elsewhere does not pause the new owner. The browser's normal pause/reactivation path remains responsible for input release and user resumption. Paused real foot reports may complete placement.

A private scalar probe of the actual archived normal pointer-lock-loss branch observes keyboard/fire/aim/hop clearing and normal pause. Its fullscreen exception retains intent. A bounded live ordinary-keyboard case also observes pause and stable foot placement through a real reconnect. Touch, gamepad, fullscreen exceptions and other browser focus orderings remain unverified. A WebSocket fence must not be described as universal held-input cancellation. No synthetic release/event, key-set mutation or automatic lock request is used by the recovery adapter.

## Authored F6 HTTP actions

Only the authored `local_gameplay.js` action producer uses the current applied grant. It sends `X-ZGTA-Browser-Connection` and `X-ZGTA-Browser-Revision`; there is no global fetch patch. Pending actions are not sent or replayed. A stale response cannot overwrite the panel after a grant changes.

The server checks the exact current live, admitted browser owner before reading a POST body and again before mutation. Wrong, malformed, unknown, stale, dead, non-ready and mixed-native tags return409. Explicitly tagged old requests also fail before any new hello after process restart. A negotiated current browser cannot bypass this with a cookie-only action. Native HTTP headers/policy remain separate.

Cancellation or disconnect cannot undo an action already accepted by the server. Untagged requests with no negotiated browser peer remain indistinguishable from genuine legacy HTTP clients; their historical behavior is deliberately preserved. This is not a claim of universal HTTP cancellation or legacy generation fencing.

## Regressions

`node smoke_browser_recovery.js` runs asset-free authored coordinator/wrapper cases, actual full-backend handlers with virtual files/clock/framing, actual authored F6 action dispatch, and the actual serve handler with authored files. It opens no OS listener/socket and changes no real player data. It covers callback/baseline/admission barriers, malformed values, revision/nonce/reentrant ownership, cached claims/park cleanup, fresh entry, restart/death, HTTP generations, legacy compatibility and pointer-lock ownership. Existing disposable serve fixtures include the two new independent source dependencies; their assertions are unchanged.

`node smoke_browser_recovery.js --historical /path/to/Core115` retains the historical negative: the old server ignores the new capability and accepts the old ID-less driver report without restoring a registry claim. The archived close/demotion/serializer and exact callback witnesses are retained privately, not shipped in public tests.

The existing native placement and seven-producer teleport regressions are retained. No Swift/SDK compilation, browser, device, Simulator, service, real socket or live-state action is part of these source gates.

## Registered-body ordering follow-up

Root's first actual browser restart accepted foot placement, but normal later entry still selected the retained local body and omitted the vehicle property. The private actual registry/callback/entry A/B witness confirms that ordinary rows deliberately retain existing local bodies: all→TP localizes the active occurrence; TP→all releases it first and preserves the same registered parked occurrence. Normal F then asks the server for fresh entry rather than bypassing that request as freeplay. No registry ID, local flag, pose, claim or cached adopt packet is rewritten. An already-demoted historical tab is not repaired by this ordering; it needs an ordinary page reload before the new lifecycle can be tested. This does not reset the account, job or persistent vehicle. The old failed live observation and pre-order source/report are retained privately.

## Asynchronous entry ownership

The registered-body ordering correction alone does not cancel an already accepted entry task whose model is still loading. A private actual-source counterexample retains the full sequence: ordinary positive entry reply, deferred model, newer server teleport and foot admission, old model completion, stale local take, server refusal of its explicit claim, and later demotion to unintended ID-less driving. This is an authored closure/virtual-backend witness, not a claim that the later live test encountered the race.

The source adapter now also verifies unique fingerprints for the normal entry and spawned-entry callbacks. It captures the coordinator's ready connection/revision grant before the task can set its busy flag. Pending tasks return before loading or requesting entry. When a model completes, current grant ownership participates in the existing admission/disposal guard before registry take. Existing model failure, mode, death and body-identity checks, disposal and busy release remain in place. A subsequent new user request can retry; a stale task is not queued or replayed.

Registration is `normal-teleport-and-entry-v2`, emitted only after all three source fingerprints validate. A new coordinator does not negotiate from the older teleport-only registration. This requires a normal reload to adopt the matching no-store coordinator/transformed-source pair; it does not retrofit already-open older scripts. The wire capability remains `browserRecovery:1`. Unsupported/missing/duplicated source seams fail the whole transformation. No original callback implementation is stored in public source, and no registry identity, local flag, input, claim, health or engine callback is injected.

`node smoke_browser_entry_epochs.js` is an independently authored, asset-free regression over the actual transformer/coordinator. It retains an unfenced historical negative and tests both entry kinds across same-peer teleport, new connection, disconnect, death, body replacement, failed resource, reentrant disposal, busy serialization, fresh retry and legacy controls. The private gate additionally executes both actual archived callbacks and real virtual-backend admission. Spawned entry is an archived callback control; the current self-host backend does not emit `spawned.in:true`. These checks do not establish browser/GPU/physical gameplay acceptance.

## Bounded live acceptance

One isolated loopback QA world was exercised in a single existing Chrome tab using normal guest entry, the authored F6 Taxi action, ordinary F entry and actual server-process restarts. The corrected TP-before-baseline order recovered to foot; a later normal F entered the same registered Taxi with its explicit ID and a fresh server driver claim. The earlier failed all-before-TP observation is retained separately.

After an ordinary reload, passive response capture verified the exact current coordinator and transformed bundle bytes, with no-store headers. Normal F again claimed the registered Taxi. During another actual restart, ordinary W was held through disconnect and the new placement acknowledgement. The original pointer-lock-loss path paused gameplay; twelve subsequent actual foot reports showed zero horizontal displacement. W was then released normally. The Taxi had driven away before disconnect, so a later F at the foot checkpoint correctly remained on foot and is not counted as reentry acceptance. The separate stationary-restart case supplies that evidence.

The bounded held-input trace was not truncated; the longer rolling world observer was truncated and is not a complete session transcript. These tests do not establish exclusive human input, frame-rate invariance, other browsers, fullscreen/touch/controller cancellation, physical-device behavior, or retail-game accuracy. A warm already-visible stock Taxi reuses cached parsed resource promises; a genuine delayed model completion was not exercised live. Its cancellation coverage remains the explicitly deferred actual-source and authored regression cases above. No cache eviction, failed-resource injection, pose assignment or vehicle-identity rewrite was used to turn that limitation into a live pass.
