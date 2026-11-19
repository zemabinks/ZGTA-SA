`NativeStockAssetAccess` is an explicit snapshot of the current app's own LAN
join cookie. It never reads a cookie store itself. The caller chooses the own
app session and configured server origin; browser stores, original-game login
cookies and Discord cookies are not valid inputs for obtaining access.

```swift
let loader = try NativeSAMPStockAssetLoader(assetBaseURL: assetRoot,
    accessProvider: {
        let cookies = ownSessionCookieStore.cookies(for: ownServer.url) ?? []
        return NativeStockAssetAccess(assetOrigin: ownServer.url,
                                      sessionCookies: cookies)
    })
```

The optional provider runs on the main queue at each model/file submission.
Without it, stock loading remains credential-free. A returned snapshot only
produces `zgta_access=<64 lowercase hex characters>`, and only when
`cookieHeader(for:at:)` accepts the exact request origin and reserved stock path.
The same helper can authorize a bounded metadata request using the same own
session policy. It never produces an Authorization header or forwards other
cookie names/values.

Checks cover HTTP(S) scheme, exact host/effective port, absence of URL userinfo,
query and fragment, known metadata URLs or exact hash-addressed DFF/TXD/COL paths,
exact cookie host-domain, cookie directory boundary, expiry, Secure and explicit
Port restrictions. Parent/subdomain cookies are deliberately not promoted to
asset-host authority. Different eligible token values fail closed; identical
values are emitted once. Invalid token bytes cannot create header syntax.

Foundation returns an empty `portList` even for a cookie with no Port attribute.
Only a real Port attribute imposes that extra restriction; request origin ports
are always checked. Foundation also discards the constructor's OriginURL cookie
metadata. It cannot reconstruct historical cookie-source ports/schemes from a
cookie object. The caller's explicit current own-session origin is therefore
the provenance policy; this helper does not infer it from incomplete metadata.

URLSession cookie handling, cookie storage, credential storage and URL cache
remain disabled. Only the validated manual Cookie header is added. All redirects
are rejected, including same-origin redirects; neither stock access nor another
cookie can reach a redirect target. Snapshots are immutable, expiry is checked
again before each file request, and existing loader cancel/reset generation
rules still apply. Account/session changes must invalidate the caller's active
asset owner rather than keeping old work alive.

Run `python3 tests/resources/test_stock_asset_access.py`. Pure checks exercise origin/path/domain,
expiry, Secure, Port, token and ambiguity boundaries. Real HTTP cases include
gated stock resources with default 401 and explicit own-cookie success, expired
and wrong-origin refusal, same/cross-origin redirect rejection, and unrelated
paths receiving no cookie despite explicit opt-in. Peer profile, Discord and
original-origin cookies coexist in the fixture snapshot to prove filtering.
The prior loader cases and all 109 actual stock-server checks remain in the run,
followed by an arm64 iOS 15 SDK typecheck. Reports and fake fixture tokens stay
under `local-only/research/stock-asset-access`; no real session tokens are logged.
