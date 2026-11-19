# Game files, ISO and local installation

ZGTA:SA needs game resources to display San Andreas. **Those copyrighted game files are not in this GitHub repository.** The native client can use prepared files in different ways, but **the original ISO is not currently a one-click playable installation**.

## Understand the three file types

| File/source | What it is | Can the native game play using it today? |
| --- | --- | --- |
| **Original GTA SA 1.0 US ISO** | Original PC installation media you supply | **Not by itself.** The app can inspect and extract raw resources, but native conversion is unfinished. |
| **Prepared ZGTA:SA package** | Converted resource files with `zgta-resources.json` and `blobs/<sha256>` | **Yes, if fully verified** by the native resource store; it provides local static resources, not a multiplayer server. |
| **Prepared resources served by your Mac** | The existing development asset server, optionally with an iPhone cache | **Yes for development**, subject to server and asset availability. |

**The app does not include GTA SA, a playable ISO, or a prepared commercial game download.**

## Find the file screen in the iOS app

1. Open ZGTA:SA.
2. Choose **GAME** on the main menu.
3. Choose **GAME FILES**.
4. Use the section that matches your resources below.

### Option A — Reuse Mac resources for development

Choose **USE DEVELOPMENT RESOURCES**. If you have already prepared a resource package on your Mac, enter that Mac's address in the development-resource field (for example `http://192.168.1.10:8766`) and choose **CACHE / REPAIR FROM MAC**.

The cache reuses verified unchanged files. A normal app rebuild or update should not require copying the entire game again. Deleting the app or resetting the Simulator can remove its app-owned cache.

The Mac must be accessible when resources not yet cached are requested. A resource server is **not necessarily the same** as the gameplay server you join.

For preparing the Mac's native resources, start with [Host a development server](../HOSTING.md) and [Build the app](development/BUILD-IOS.md).

### Option B — Use an already prepared installation

1. Choose **IMPORT / REPAIR PREPARED FOLDER**.
2. In Files, select a valid prepared ZGTA:SA folder containing `zgta-resources.json` and `blobs/<sha256>`.
3. Let the resource verifier finish.
4. Choose **VERIFY INSTALLED FILES** if you need to recheck it.
5. Select **USE INSTALLED RESOURCES** only after the app reports a verified playable resource installation.

Installed mode reads static assets locally and **does not silently fall back to Mac streaming** if a required file is missing. It still needs a reachable **gameplay server** for online multiplayer. A prepared package is not automatically the full original game; only declared and supported resources are verified.

### Option C — Inspect or extract your original ISO

1. In **GAME FILES**, choose **INSPECT ORIGINAL ISO** to examine the source, or **EXTRACT RAW RESOURCES FROM ISO** to save selected original resources.
2. Pick your own compatible ISO using the iOS Files picker.
3. Let the app read and extract it. The original ISO is kept unchanged.
4. Choose **VERIFY SAVED RAW RESOURCES** to check what was extracted.

**Stop here if your goal is to play from the ISO:** these are *raw* original game resources, **not yet converted into the runtime's verified native formats**. Extracting them does **not** activate installed mode. Future work must connect extraction to conversion, package verification and playable local loading. See [the technical extraction report](research/resources/CORE_NATIVE_RAW_ISO_108.md).

## Why can't I just select an ISO and press Play?

Selecting a file is straightforward. The hard part is making the native Metal game understand the original PC formats, their relationships, animations, collisions, game logic and the exact installer layout. The current code already supports raw extraction and some separately prepared original resources, but it has **not** demonstrated complete original-ISO-to-native conversion.

This is a development limitation, not a request for users to find another unofficial ISO.

## Keep your data safe

- Keep a backup of your original legally obtained game files and your prepared assets.
- Normal app updates can retain the installed/cached resources; deleting the app or resetting the Simulator can remove its local data.
- Do **not** publish the original ISO, derived proprietary assets, usernames, passwords or saved profiles to GitHub.
- When changing installations, verify the new package before removing a working one.

**Detailed technical notes:** [Native resource storage](research/resources/CORE_NATIVE_RESOURCES_107.md) · [ISO bridge](research/resources/CORE_NATIVE_INSTALLER_107.md) · [Runtime validation](research/resources/CORE_RESOURCE_TRANSPORT_109.md).

[← All guides](README.md)
