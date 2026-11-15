# Native Definitive Edition menu

The native title screen uses **MULTIPLAYER**, **GAME** and **OPTIONS**. Multiplayer
opens the actual self-hosted server connection and restores that server's saved
guest. Discord membership is not required. Leaving the connection screen cancels
pending work; delayed authentication cannot launch a hidden game.

Game provides the current local profile/name, saved statistics, server status,
contextual controls and credits. These are existing server capabilities, not a
character-slot creator or story campaign. Opening offline help/credits or public
server information does not create an account. Profile/statistics pages explicitly
restore or create the same guest used to play. A server requiring a join code must
first be joined through Multiplayer.

Options changes the actual native renderer, camera, radar and audio owners. See
[NATIVE_SETTINGS.md](NATIVE_SETTINGS.md). It is also accessible from the in-game
pause menu; the multiplayer simulation continues while input is suppressed behind
it. Only supported settings are shown. Voice chat, arbitrary graphics-quality
presets, shadows and a touch-layout editor are not represented by fake switches.

## Private presentation resources

Original artwork, font files and frontend sounds are never part of the source
release. An owner's local import is an optional `OwnerMenu` folder, built into the
app from ignored `local-only/menu-bundle/OwnerMenu`. The importer and its usage are
documented in [OWNER_MENU_IMPORT.md](OWNER_MENU_IMPORT.md). Regenerate the Xcode project after importing, or use
`build_native.sh`, which regenerates it automatically. An asset-free checkout can
still open the functional menu using plain text/color fallbacks; that fallback is
not the Definitive Edition presentation.

`NativeDEMenuAssets` reads `manifest.json` with image key-to-basename mappings,
fonts with `file` and `postScriptName`, and sound key-to-basename mappings. It
rejects nested/parent paths, registers the fonts in the app process and preserves
original image alpha. It can also read the same folder under the app's Application
Support directory. This is a local resource loader, not an asset downloader.

The supplied DE1.86.44544238 resources establish a1920x1080 design canvas, left
logo/button-panel anchors, bottom-aligned character art, PricedownGTAVInt menu
labels at design size50,65-unit rows,20/12 text margins and normal/hover shadow
positions. Selected backgrounds are the actual Resume/Game/Options textures;
serialized linear colors are converted to UIKit sRGB. Frontend start/back/
highlight/tab sounds resolve to S000/004/009/006. Their Microsoft ADPCM WAVE data
is decoded to native-playable PCM by independently written bounded code.

Compact screens retain the logo/portrait proportions and menu anchors, while
button hit rows expand to at least44points. MULTIPLAYER keeps the original left
edge and has a wider selection rectangle because it is longer than START. These
are deliberate touchscreen adaptations. Keyboard and controller navigation use
release edges and preserve handler ownership across menu/game transitions.

## Evidence and limits

The source of presentation facts is static parsing of the owner's IPA: verified
ZIP members, unencrypted Pakv11 indexes/selected payloads, tagged UMG properties,
resolved texture/font imports, actual SFNT names and raw cooked texture pixels.
The local investigation retained hashes, property byte offsets and independent
parser corroboration. No original executable was installed or run, and no
protected resource was decrypted. Static resources can be changed by runtime
Blueprint/native code; their presence does not prove the final runtime layout.

No selected menu resource contained a serialized WidgetAnimation or MovieScene
export. That does not establish the absence of runtime animation. The native
250ms entrance fades are independently chosen and respect Reduce Motion; they
are not claimed as verified original timings. Physical iPhone/controller feel,
all localization fallbacks and exact original runtime presentation still require
side-by-side testing. No1:1 accuracy claim follows from a build or geometry test.

A functional story Singleplayer mode is not practical as a menu integration: our
renderer/network client does not implement the original campaign scripts, mission
VM, story AI, cutscene and save-game runtime. The supplied IPA is a separate app,
not an embeddable campaign engine. The three-entry option preserves multiplayer
priority without advertising an unavailable story mode.

Final Core85 validation includes60 core/menu/network gates,61 responder checks,
optimized universal Simulator and unsigned iPhone builds, real guest world entry
and repeated Pause/resume, compact iPhone SE3 title/settings navigation, and
large iPhone17 Pro Max landscape title/options presentation.
The source-only/owner-resource project-generation matrix is checked separately.
Physical device/controller and exact retail menu animation remain unverified.
