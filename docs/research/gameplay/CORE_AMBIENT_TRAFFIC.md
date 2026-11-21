# Native ambient traffic implementation scope

The native client has a separate compact-traffic store and scene. It decodes
traffic records, predicts road/free movement, loads matching original road and
vehicle resources, and retires state when connections or asset sources change.
Registered vehicles suppress their corresponding compact replica.

Nearby traffic can supply bounded server-owned contact bodies. The client can
request materialization of an original traffic vehicle, but that request alone
does not grant driving authority. A compatible server must register the vehicle
and publish the resulting control state.

Optional owner-provided traffic occupant metadata selects original character
resources and seated poses. These actors remain separate from human player
rosters. Missing metadata or unavailable resources do not produce substitute
characters. Astride death/fall-off, driver gun/look/voice behavior, traffic combat
and authoritative jacking remain incomplete.

Main lamp selection uses time, weather and actor identity. Brake inputs use the
same selected motion sample as vehicle presentation. Typed compact audio sources
retain their own identity and stable candidate ordering through the common
vehicle-audio path. This does not establish audible playback or complete
headlight beams and model-specific emergency effects.

Traffic AI, original spawn density, signals, routes, police and server decisions
are separate systems. A server must publish compatible traffic records; this
client work does not create the original service's server implementation.

The regression gates use authored records and geometry. Optional reference
inputs and all original game data remain local. Selected application cases use
controlled records through the independent backend and original owner resources.
Those cases do not establish original traffic AI, live original-server driving,
physical-iPhone performance or original-PC gameplay parity.

The current source regression set, both unsigned SDK builds and controlled
retained-resource Simulator cases pass. Reviewed original-resource captures
establish the stated presentation scope. The current full source regression
chain completed uninterrupted; application and original-resource checks are
recorded separately. Actual Taxi material metadata confirms day/night and
rear-only brake selection, while GPU brightness and audible output still need
separate verification. No original assets, private fixtures or captured gameplay
are distributed here.
