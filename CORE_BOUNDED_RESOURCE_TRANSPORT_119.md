# Bounded prepared/development resource transport

`NativeResourceTransport.boundedDataTask(with:maximumBytes:completionHandler:)`
accepts either `URL` or `URLRequest` and returns a suspended
`NativeResourceTask`. Valid limits are 1 through 2,147,483,648 bytes. Resume and
cancel are idempotent. Completion runs exactly once on a background queue,
including cancellation before resume. Consumers retain the task, cancel obsolete
work and dispatch their own UI updates. A completed result is not revoked by a
later cancel.

The App atomically installs its ordinary factory, optional bounded factory and
local-file resolver. Existing unbounded APIs retain their behavior. Installing
an old factory without the bounded argument clears any prior bounded factory;
the new API then uses the Foundation-only streaming implementation in
`ServerAddress.swift`, rather than buffering through an old completion API.
This file still has no App-resource dependency.

The bounded App resolver uses the actual Store's admission, request-path/query,
origin, size and SHA checks. Static installed GET requests pass the caller's cap
into `localResource` before its data read. Installed HEAD also enforces the
declared size cap. Missing, corrupt, unverified or invalid installed resources
fail closed. Ordinary API requests continue to use the network. Development
cache-origin rules are unchanged.

Network transfers copy the supplied Foundation session configuration, including
its cookie policy/storage and existing credentials policy. The helper does not
discover browser cookies, introduce credentials or change resource-path policy.
It requests identity encoding, refuses compressed responses and every redirect,
checks HTTP status and declared length before admitting a body, and checks each
delegate chunk against the remaining cap before appending it. Unknown-length and
chunked bodies remain supported. Invalid, conflicting or excessive lengths and
truncated bodies fail without returning partial data. A dedicated serial delegate
queue and lock-protected terminal state fence response, cancellation and task
attachment races. Cancellation propagates through the App's generic task handle.

The bound concerns the logical retained application payload (`Data.count`). It
does not claim a maximum total process RSS or bound Foundation's HTTP parsing,
delegate chunk allocations, allocator capacity, TLS or kernel buffers. It does
not provide per-model concurrency or aggregate resource budgeting; consumers
must supply those separately.

Run `nice -n 15 python3 test_native_bounded_resources.py` on the supported host.
The authored test starts and closes ephemeral loopback HTTP fixtures and executes
the actual Swift transport, Store and Session. Its explicitly synthetic runtime
validator admits transport markers only; it does not establish engine, GPU,
gameplay or retail parity. Per-run source identities, compiler/runtime results,
request counts and qualifications are retained under
`local-only/research/bounded-resources-119`. No original game fixtures are used.

The Core119 host run passed 138 Swift checks and six HTTP request-count/isolation
checks. A separate existing installed-resource loader regression passed 20 checks
against the same transport sources. The Foundation-only standalone typecheck and
complete transport harness compilation also passed; this is not a full App SDK
or rendered-game acceptance result.

Two initial giant-declared-length fixture attempts remain failed in their
original reports: closing after zero or one body byte produced Foundation's
connection-lost error before its response delegate. Flushing a 16 KiB prefix
before closing let the unchanged, hash-verified executable observe and reject
the excessive declared length with the required limit error. The cap assertion
was retained. This is also an example of why the application payload cap must
not be described as a bound on Foundation's internal buffering.
