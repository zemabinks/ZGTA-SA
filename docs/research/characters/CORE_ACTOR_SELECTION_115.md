# Character model selection ownership

Deferred character loading now belongs to one typed request with a source identity and a unique token. A newer native or SA-MP request supersedes the older request across both ID namespaces. Catalogue, CJ and custom-model arrivals resume the current request; they do not create a fresh selection that can override newer input. Disconnect, stop and resource-source changes revoke deferred publication.

This fixes a concrete race: requesting CJ while its resources load, then receiving a newer SA-MP class before its catalogue arrives, could leave two pending flags. The old CJ completion could replace the newer class. The asset-free regression executes the actual selection methods and class-menu handlers; its optional historical control reproduces that older failure.

Server-authoritative character IDs retain their existing wire behavior. Model-resource admission is reported separately. The existing class SPAWN action requires admission of the currently offered class and the existing server-model download barrier. It checks again when activated; Previous, Next and Back remain available while loading or unavailable. A new explicit CJ selection can retry a failed resource request immediately; asynchronous resource arrivals and remote demand retain the normal retry backoff and in-flight deduplication. A conflicting skin0 catalogue reports unavailable instead of waiting for an impossible admission.

For ordinary converted characters, applied means validated catalogue mapping and renderer identity selection. It does not certify that the GPU mesh has completed loading. CJ additionally requires its verified runtime model. The optional fixed vest/denim profile is a limited appearance; it does not implement the complete original wardrobe or body morphs.

Run `python3 tests/resources/smoke_native_actor_selection.py` or the focused `python3 tests/core/smoke_core_115.py` on macOS with Xcode Swift. These are authored source regressions. Physical rendering, main-game transitions, multiplayer appearance and original-game accuracy require separate acceptance; passing these checks does not establish a complete 1:1 port.
