# Consistent browser landing and jump policies

The self-host can apply the independently authored landing-completion and
jump-selection policies to an owner's locally archived browser controller.
This matches the bounded native124/126 task changes while retaining the
browser's existing movement, pose sampling, physics and transport.

The adapter requires an explicitly enabled private plan. The complete source,
factory range and each edit span must match their declared identities. Six
known edit kinds supply per-controller Float32 gait weights, per-action landing
completion ownership and the launch selector. Logical gait rows stay separate
when they share a prepared clip. A landing's current root displacement finishes
before its owner can restart the gait clock.

Original scripts, fingerprints, offsets and symbol bindings are absent from
the public adapter. Keep the locally verified plan at
`local-only/browser-task-policy.json`, or select it with
`ZGTA_BROWSER_TASK_POLICY_PLAN`. A plan is trusted code configuration: identity
checks do not establish its semantic correctness. Validate it against the
actual owned controller before enabling it. Unrecognized revisions need a new
local audit and pin plan; there is no best-effort replacement.

Only self-hosted mode uses this adapter. The existing Host, Origin and join-code
checks run first. The selected script is returned as a complete, no-store
response; GET and HEAD are supported, and byte-range requests cannot expose
partially transformed code. Source drift fails closed. Other assets retain
their existing paths. Serving never rewrites the owner's archived script.

```sh
node smoke_browser_task_policy_http.js
```

This runs authored controller/plan fixtures and the real isolated HTTP server.
It covers cold/idle/active gait selection, Float thresholds, phase wrap, missing
prepared handles, ordinary completion, callback replacement, death, root-motion
ordering, source/plan drift and request boundaries. Existing host and recovery
regressions remain separate checks.

Actual owned-controller evidence and transformed assets stay local. Missing
launch-clip timing fallback, external abort callers, live browser/native scenes,
physical-device behavior and original-retail equality remain separate
acceptance requirements. This is not a full browser-game or engine parity claim.
