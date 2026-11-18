# Start here — ZGTA:SA

This guide assumes you have **never used this project before**. You do not need to understand the source code to follow the explanations, but **building the iPhone app currently requires a Mac and Xcode**.

> **Before downloading:** ZGTA:SA has **no published public IPA or finished one-click installer** yet. The GitHub **Code → Download ZIP** button gives you the source code, **not** a ready-to-play game. The project does not include original GTA San Andreas files.

## Choose what you want to try

**A — Mac/browser development world:** available from source today. Follow the steps below.

**B — Native iPhone/iPad build:** for people with a Mac, Xcode and suitable original/prepared assets. Go to [Build for iPhone](development/BUILD-IOS.md).

**C — Install from your GTA SA 1.0 US ISO:** raw ISO extraction exists, but the automatic conversion into a playable native installation **is not finished**. See [Game files](GAME-FILES.md) before attempting this.

## A. Start the Mac/browser development world

### 1. Install the free prerequisites

You need a Mac (or a compatible Linux host), **Python 3.9 or newer**, **Node.js 22 or newer**, and a browser such as Chrome with working WebGL. You also need access to the required archived game content; source downloads may be incomplete if the upstream public resources are unavailable.

Terminal is the Mac app where you type commands. Open **Applications → Utilities → Terminal**.

### 2. Get the project

If Git is installed, copy and paste these commands **one line at a time**:

```sh
git clone https://github.com/zemabinks/ZGTA-SA.git
cd ZGTA-SA
```

The first command downloads the project code. The second enters its folder.

If you used **Code → Download ZIP** instead, unzip it, open Terminal in the extracted `ZGTA-SA` folder and continue below.

### 3. Prepare and check the files

```sh
python3 host.py setup --download
python3 host.py doctor
```

**Setup** prepares the local browser archive when its publicly discoverable source files are available. **Doctor** checks the setup and reports anything missing. If it reports a problem, see [Troubleshooting](TROUBLESHOOTING.md).

These commands do not create a native iPhone installation and do not run Rockstar's original Windows game.

### 4. Start the server

```sh
python3 host.py serve
```

Keep this Terminal window running. Open **http://127.0.0.1:8766/** in your browser.

The address `127.0.0.1` means **this computer**. It only works while the local server is running. To stop it, return to Terminal and press **Control + C**.

### 5. Let another device join

You and your friend must connect to the **same ZGTA:SA independent server**. To share it on your home Wi-Fi/LAN, see [Host or join a lobby](MULTIPLAYER.md) for the exact command and join-code explanation.

## B. Use the native iOS client

ZGTA:SA is being developed for **iPhone and iPad with iOS/iPadOS 16 or later**. This is the project's deployment target, not a promise that every device will run it well.

There is no verified public IPA in [GitHub Releases](https://github.com/zemabinks/ZGTA-SA/releases). Developers can build the app with Xcode by following [Build for iPhone / Simulator](development/BUILD-IOS.md).

The native app currently offers **MULTIPLAYER**, **GAME**, and **OPTIONS**. Open **GAME → GAME FILES** to manage development resources, a prepared installation, or raw ISO extraction.

## C. Know which game files are needed

**There are two different things:**

- **Original GTA SA PC files / ISO:** your source material. The app can currently inspect and extract selected raw ISO resources, but they still require native conversion.
- **Prepared native resources:** the files already converted into a format ZGTA:SA can load. Development can stream/cache them from your Mac, or the app can use a verified prepared package locally.

See [Game files and ISO](GAME-FILES.md). **Do not assume “ISO extraction finished” means “game ready to play.”**

## Next steps

If you want to **play with friends**, read [Multiplayer](MULTIPLAYER.md). If something doesn't work, start with [Troubleshooting](TROUBLESHOOTING.md). For feature availability, see [Project status](PROJECT-STATUS.md).

[← All guides](README.md)
