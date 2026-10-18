# Installation

Transnote is an on-device transcription app for macOS 14 and later.

## ⚠️ Read this first: about the malware warning

Transnote is distributed without Apple's paid developer certification (code signing),
so macOS may show warnings like the following during installation or on first launch.

- "Apple could not verify “Transnote” is **free of malware** that may harm your Mac or compromise your privacy."
- "“インストール.command” Not Opened"

**This is not a malware or virus detection.** It is a notice from macOS's Gatekeeper
mechanism saying that it cannot perform its safety check on an unsigned app. Transnote
is not malware.

Note: this guidance applies **to Transnote only**. If another app shows a similar warning,
always confirm that its source is trustworthy.

| Possible warning (example) | Meaning | What to do |
| --- | --- | --- |
| "Apple could not verify … is free of malware" | Cannot be checked because it is unsigned (not a detection) | Close with "Done" and follow the [First launch](#first-launch) steps (right-click → Open) |
| "“インストール.command” Not Opened" | The install script is also unsigned | Do not press "Move to Trash"; close with "Done" and go to [Run from Terminal](#method-a-run-from-terminal-recommended) |

Do not press "Move to Trash". Doing so deletes the file.
Closing with "Done" is fine.

## Download

1. Open [GitHub Releases (latest)](https://github.com/T3pp31/Transnote/releases/latest).
2. Download `Transnote-<version>.dmg` or `Transnote.dmg`.
3. From the same Release, **always** download `Transnote.dmg.sha256` (or the versioned `.sha256`) too, and save it in the same folder as the DMG. The install script verifies this checksum by default.
4. If you were directed from the distribution page, [GitHub Pages](https://t3pp31.github.io/Transnote/) links to the same downloads.

## Verifying the SHA256 checksum

Because the app is distributed unsigned, verify before installing that the downloaded DMG has not been tampered with. **インストール.command** ("Install.command") automatically verifies the `.sha256` file in the same folder as the DMG.

### Method A: Verify with the `.sha256` file

Put the `.sha256` file in the same folder as the DMG and run the following in Terminal.

```bash
cd ~/Downloads
shasum -a 256 -c Transnote-0.1.0.dmg.sha256
```

If it prints `Transnote-0.1.0.dmg: OK`, the file is intact.

### Method B: Compare against the hash in the Release notes

Compare the SHA256 listed on the Release page with the value you compute locally.

```bash
shasum -a 256 ~/Downloads/Transnote-0.1.0.dmg
```

### Method C: Verify with the CHECKSUM environment variable (advanced)

Passing the SHA256 from the Release notes in the `CHECKSUM` environment variable lets the script verify the DMG before installing, even without a sidecar file.

```bash
CHECKSUM="<SHA256 from the Release>" bash "/Volumes/Transnote/インストール.command"
```

## Installation (recommended)

Because the app is distributed unsigned, **インストール.command** may not run when double-clicked. On newer versions of macOS, right-click → **Open** may also be blocked. **Running it from Terminal is the most reliable method.**

### Steps

1. Open the downloaded DMG.
2. Read **初めにお読みください.txt** ("Read Me First.txt") in the DMG.
3. Run **インストール.command** using one of the following methods.

#### Method A: Run from Terminal (recommended)

1. Open **Terminal** (search Spotlight for "Terminal").
2. Paste the following two lines **one at a time**, pressing Enter after each.

```bash
xattr -cr "/Volumes/Transnote/"
```

```bash
bash "/Volumes/Transnote/インストール.command"
```

If the DMG volume is named something like `Transnote 1`, change the path to match the name shown in the Finder sidebar.

```bash
xattr -cr "/Volumes/Transnote 1/"
bash "/Volumes/Transnote 1/インストール.command"
```

#### Method B: Right-click → Open

Right-click `インストール.command` → **Open** → **Open** in the confirmation dialog.

Recent versions of macOS may block Method B as well. If so, use Method A.

#### Method C: Allow it in System Settings

1. Close the warning dialog with **Done** (do not press **Move to Trash**).
2. Open **System Settings → Privacy & Security**.
3. Near the bottom, if there is an **Open Anyway** button for **インストール.command**, press it.

4. When installation finishes, Transnote launches.
5. **Eject** the DMG in Finder (if it stays mounted, multiple copies of the app appear).

The install script removes older versions from Applications (`Transnote.app`, the former name `LocalTranscriber.app`, `Transnote 2.app`, and so on) before placing the new version. If Transnote is running, it is quit automatically before being replaced.

## Installation (advanced: drag & drop)

If you place the app manually, follow these steps.

1. Quit Transnote if it is running.
2. Delete the existing `Transnote.app` in the Applications folder (and `LocalTranscriber.app`, if present).
3. Drag **Transnote** from the DMG to the **Applications** folder.

With this method, duplicates such as `Transnote 2.app` can be created if the app is running or an old version remains. **Using the install script above is normally recommended.**

## First launch

1. Launch Transnote from Applications.
2. Because the build is unsigned, macOS Gatekeeper may show a warning such as "cannot verify the developer" or "could not verify … is free of malware" (**this is not a malware detection**; see the "Read this first" section above):
   - **Recommended**: In Finder, right-click Transnote → choose **Open** (it launches normally from then on)
   - Or allow Transnote to launch in System Settings → Privacy & Security
3. The first time you use the app, you need to download a Whisper model. Follow the on-screen instructions.
4. An internet connection is needed only to download models. Transcription itself runs entirely on the device.

## Updating

When a new version is released, download the latest DMG and run **インストール.command** from Terminal (Method A above). The old version is replaced automatically. User data (`~/Library/Application Support/LocalTranscriber/`) is preserved.

## File access

Transnote runs in the App Sandbox. Reading and writing audio files requires access to files the user has chosen through the file selection dialog or drag & drop.

## Uninstalling

1. Move Transnote from Applications to the Trash.
2. If needed, delete the data under `~/Library/Application Support/LocalTranscriber/`.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| "could not verify … is free of malware" appears | **This is not a malware detection.** It is a warning shown for all unsigned apps. Close with "Done" and try right-clicking Transnote in Finder → **Open** (see [Read this first: about the malware warning](#-read-this-first-about-the-malware-warning)) |
| The app does not open | Try right-click → **Open** in Finder. If it still does not open, reinstall from the DMG |
| The install script will not run ("Not Opened") | Do not press **Move to Trash**; close with **Done**. In Terminal, run `xattr -cr "/Volumes/Transnote/"` followed by `bash "/Volumes/Transnote/インストール.command"` (recommended). Right-click → **Open** or **Open Anyway** in System Settings may also work, but Terminal is reliable on recent macOS |
| An old version remains | Reinstall using **インストール.command**. If you dragged the app manually, delete duplicates in Applications and place it again |
| Multiple copies of the app appear | Eject any still-mounted DMGs (`Transnote`, `Transnote 1`, etc.) in Finder. If Applications contains `Transnote 2.app` or similar, delete it and reinstall with **インストール.command** |
| Models cannot be downloaded | Check your network connection and firewall settings |
| Transcription is slow | Choose a smaller model, or split long audio |

If problems persist, report them on [GitHub Issues](https://github.com/T3pp31/Transnote/issues).
