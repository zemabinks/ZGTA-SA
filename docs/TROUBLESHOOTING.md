# Troubleshooting ZGTA:SA

Use this page when setup or gameplay doesn't behave as expected. ZGTA:SA is an **experimental development project**, so an error can also mean that a feature has not been implemented yet.

## Common problems

| Problem | First thing to check |
| --- | --- |
| **Where is the iPhone IPA?** | There is **no published public IPA** yet. The repository contains source code. See [Start here](START-HERE.md). |
| **I selected my ISO but the game won't start** | **Raw ISO extraction is not a playable native installation.** Use prepared verified resources for current native testing. [Game files](GAME-FILES.md). |
| **The iPhone can't connect to my Mac** | Use the Mac's **LAN IP**, not `127.0.0.1`; keep the server running; connect both devices to the same network and check the firewall. |
| **The browser page doesn't load** | Keep `python3 host.py serve` running and visit `http://127.0.0.1:8766/` on the host computer. |
| **Setup reports missing files** | Run `python3 host.py doctor`; upstream public archive files might be unavailable. Source checkout alone has no game assets. |
| **Installed mode says resources are missing** | Return to **GAME → GAME FILES**, use **VERIFY INSTALLED FILES** and repair/import a compatible prepared package. It won't quietly load missing resources over the network. |
| **I rebuilt in Xcode and can't find resources** | Check **GAME → GAME FILES → USE DEVELOPMENT RESOURCES** or **CACHE / REPAIR FROM MAC**. If you deleted the app or reset Simulator, the private cache may be gone. |
| **I can join open.mp but some models/menus are wrong** | External-server compatibility is partial; a custom server may require unsupported extensions. See [Multiplayer](MULTIPLAYER.md). |
| **A ghost car appears, or the passenger doesn't follow** | This is a known class of multiplayer synchronization problem. Record which client drove, who entered which seat, the server version and what each screen showed. |
| **I updated and lost a local profile** | Check whether the same server, app installation and account identity are in use. Do not delete the old installation before backing up important app/server data. |

## Check the Mac development server

From the ZGTA-SA project folder in Terminal, run:

```sh
python3 host.py doctor
```

For a basic server start:

```sh
python3 host.py serve
```

If a command fails, copy the **actual final error message**. Do not guess at a fix, delete your game files or change project storage paths just to silence it.

## Check native game files

Open **ZGTA:SA → GAME → GAME FILES**. Read **RESOURCE STATUS**. If you are using installed resources, choose **VERIFY INSTALLED FILES**. If you're developing against your Mac, confirm the Mac address and cache status. ISO raw-resource verification is **not** proof the native game can play from that ISO.

## Report a problem

Create a GitHub issue in [ZGTA-SA Issues](https://github.com/zemabinks/ZGTA-SA/issues) and include:

1. **What you tried** in plain language, step by step.
2. **What you expected** and **what actually happened**.
3. Your platform (Mac/browser or iPhone/iPad), OS, and app/source revision if known.
4. For multiplayer: which server type, which device was driving, what each device displayed, and whether a reconnect changed the outcome.
5. A screenshot or short recording **only if it doesn't expose private information**.

Remove join codes, passwords, tokens, Apple IDs, personal paths, account cookies, private save data and copyrighted original game files before posting. Do **not** upload your GTA SA ISO or a private local archive.

[← All guides](README.md)
