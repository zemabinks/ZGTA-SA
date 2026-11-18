# Mission vehicle restart persistence

The independent server now saves the admitted body pose and condition of an active mission vehicle. Restart restores that body as parked, with the same task/vehicle identity and factory model code, without restoring a driver, passenger, claim, coupling, velocity or queued action.

Previously only the task fields survived. `savedJob` reconstructed those task fields and `addMissionVehicle` recreated the vehicle from its initial task anchor, using its existing initial offsets and default condition. An admitted parked/driver body could therefore move and become repaired after restart even though the task's vehicle ID stayed the same. This is an independent-world persistence repair, not a claim about retail GTA save behavior.

## Saved record and validation

Each player may have an optional `missionVehicle` record:

```json
{
  "version":1,
  "job":"taxi",
  "id":"mission-0123456789abcdef",
  "code":"420.6.1.0.",
  "pose":[115.375,112.625,20.9,1.094,-0.005,0.125],
  "health":975,
  "damage":"authored-example",
  "work":731
}
```

This example is synthetic. Pose order is world body x/y/z, heading/pitch/roll, using the existing server row units. The server validates the version, exact current task and occurrence ID, factory code, six finite pose values, world coordinate bounds, health0–1000, damage length and work0–2500. Persisted angles use the same conservative numeric-domain cap as existing placement records; this is format validation, not a new retail rotation or steering constant. Unknown fields are stripped. The factory code is checked again against the current task/model before restoration, so a different model cannot borrow the prior model's body state.

The record is produced only from the registered body belonging to that player's active task. Existing entry/report authority checks remain in force. Driver reports, final parked exits, disconnect release and admitted unattended updates capture mission state; condition changes request a save immediately through the existing debounced writer. Repeated pose-only writes use a five-second scheduling throttle, and every normal `flushSync` captures the latest admitted registered body. Existing atomic temporary-file/rename behavior remains.

A saved pose is already a body origin. Restore copies it without reapplying task-anchor offsets or a guessed ground-height correction. Health zero remains zero. The occupied driver marker is always cleared, and no seat/driver authority is restored. The independently saved authoritative foot-placement and actor-health/inventory owners remain separate.

Cancelled, completed/removed or expired tasks cannot re-admit their old body snapshot. A replacement task has its own vehicle occurrence. Continuing taxi fares may legitimately retain the same cab occurrence, and their body remains associated with that cab rather than a particular fare's start time. Ordinary owned-garage persistence is unchanged.

## Older saves and remaining boundaries

Older saves contain no admitted body pose to recover. They retain the previous task-anchor factory fallback, including its existing offsets and default condition. Malformed or mismatched snapshot records are also ignored in favor of that existing fallback for a still-valid task. A malformed record cannot supply another model's pose, grant occupancy or revive an expired task. It is not possible to reconstruct a missing old body position from the task station alone.

Initial factory suspension/ground placement remains unverified; this change does not certify or retune the preexisting offsets. No ground query, collision hull, vehicle physics, safe-egress calculation or heading-unit convention changed. Restart resumes the body as a parked stand-in; it does not promise continuous motion or persisted coupling topology. Existing movement/admission trust rules remain, and a complete process crash before an outstanding debounced/throttled save can still lose the newest update. This is not a synchronous crash-durability guarantee.

No live accounts, QA snapshots, original resources or physical captures are used by the public regression. Actual running-server/phone acceptance is a separate Root-owned step.

## Regression

```sh
node smoke_selfhost_mission_persistence.js
node smoke_selfhost_position_resume.js
node smoke_selfhost_tp_units.js
```

The new gate passes **515 checks across eight scenarios**, executing the actual backend constructor, guest HTTP/Peer packet paths, job/entry actions and persistence. It covers all ten mission vehicle factories with both negotiated native and legacy browser-style reports, two restarts without extra offsets, flushed active-driver state, wreck0, unattended updates, wrong-account/unclaimed/malformed/stale reports, cancelled/replaced/expired tasks, owned garage and strict dead-health/foot independence, corrupted/mismatched snapshots and older-save fallback.

All files, sockets, clock, timers, catalogs and collision floors are independently authored/in-memory. There is no listener, service, device or live save. It reuses the existing authored `smoke_selfhost_position_resume.js` harness prefix rather than copying or simulating backend persistence logic.

An optional actual pre-change backend comparison is available:

```sh
node smoke_selfhost_mission_persistence.js --before /absolute/path/to/prechange/selfhost_backend.js
```

The preserved pre-change Core114 source reproduces pose, condition and work loss in **12 checks** while retaining the task/vehicle ID. The other required gates retain **737 placement checks** and **699 teleport-unit checks**. The new default gate is registered in the core runner and Linux Node source CI. Reports/hashes are private outputs under ignored `local-only/research/mission-vehicle-persistence-114/`; no original bytes are embedded in the test or documentation.
