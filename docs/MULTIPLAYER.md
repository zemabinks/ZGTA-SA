# Playing together in ZGTA:SA

ZGTA:SA has **three different multiplayer destinations**. They are **not one global lobby** and players on unrelated servers cannot automatically see each other.

| Destination | What it means | Current state |
| --- | --- | --- |
| **Your own ZGTA:SA server** | Native iOS and the archived browser client join your independent self-hosted world | Available for development; full shared vehicles, passengers and visual parity still need testing. |
| **SA-MP / open.mp server** | Native iOS talks to a compatible PC multiplayer server | Experimental client adapter; selected versions and scenarios tested, not every server/plugin. |
| **Original browser service** | Native iOS attempts to join the separate `play.samp.directory` world | Experimental adapter and sign-in; complete real-world gameplay has not been confirmed. |

## Option 1 — Host your own development lobby

### Step 1: Prepare the host

On a Mac/Linux computer, follow [Start here](START-HERE.md) to get the repository and run setup.

### Step 2: Start a LAN server

Find your Mac's **local Wi-Fi/LAN IP address**. Replace `192.168.1.20` below with **your actual computer address**:

```sh
python3 host.py serve --bind 0.0.0.0 --host 192.168.1.20:8766
```

Keep that Terminal window open. `--bind 0.0.0.0` lets other devices on your local network connect; it is **not** a public internet hosting setup.

### Step 3: Join from a Mac browser

On the host computer, open `http://127.0.0.1:8766/`. On another computer on the same LAN, open `http://192.168.1.20:8766/` using your actual address.

If a join code is required, find the server's `local-only/selfhost/join-code.txt` and give the code privately to your friend. Do not post it in a public screenshot or issue.

### Step 4: Join from the native iOS app

1. Connect the iPhone/iPad to the same network.
2. Open **ZGTA:SA → MULTIPLAYER**.
3. Enter your Mac's **LAN address**, such as `192.168.1.20:8766` (not `127.0.0.1`).
4. Enter the join code if required.
5. Choose **PLAY ON THIS SERVER**.

The native app also needs compatible prepared game resources; see [Game files](GAME-FILES.md). Both clients must join **the same independent server**.

**Important:** connecting successfully does not guarantee every animation, passenger seat, vehicle appearance or customization is correct yet. These are ongoing compatibility and real-device test targets.

## Option 2 — Try SA-MP / open.mp

In the native app's **MULTIPLAYER** screen, enter the address of a suitable **Mac asset origin** first if you are using development resources. Then choose **JOIN SA-MP / OPEN.MP**.

The dedicated form accepts a server address/port, nickname, optional server password and a protocol profile such as 0.3.7/open.mp or 0.3.DL. The *asset origin* supplies locally prepared models; the *game server* supplies multiplayer gameplay. Those are two different connections.

Some controlled open.mp joins and custom-asset scenarios are documented, but **arbitrary public SA-MP servers are not guaranteed**. Server-specific launchers, custom anti-cheat, voice/CEF plugins and other extensions may be unsupported. See the [technical compatibility report](../SERVER_COMPATIBILITY.md).

## Option 3 — Try the original browser world

From **MULTIPLAYER**, provide a valid Mac asset origin when required and choose **JOIN ORIGINAL BROWSER WORLD**. Use the service's own legitimate in-app Guest or Discord sign-in flow.

This is **not** the same as your ZGTA:SA independent server and is **not** automatically the same as ordinary SA-MP. A visible player roster does not mean every interaction, vehicle or custom asset works.

## What “crossplay” means here

**The goal:** when two supported clients join the **same** multiplayer server, they should show the same server-defined players, cars, seats, modifications and objects, subject to protocol capabilities and network delay. **Current limitation:** the project's real cross-platform behavior is not fully verified.

For progress and known boundaries, read [Project status](PROJECT-STATUS.md). If cars duplicate, drivers disappear or passengers get left behind, use the [bug reporting advice](TROUBLESHOOTING.md#report-a-problem).

[← All guides](README.md)
