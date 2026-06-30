# JasoGuard

JasoGuard is a macOS menu bar utility that normalizes decomposed Korean file and folder names to NFC, the composed form commonly used on Windows.

It watches configured folders in the background and renames only filenames or folder names when normalization is needed.

## What it does not do

JasoGuard does not read or modify file contents. It does not delete files, overwrite naming collisions, upload data, or send anything over the network. If a target NFC name already exists, the item is skipped.

## Requirements

- macOS 13 or later
- Xcode 15 or later for building from source
- No Apple Developer Team ID is required for the default unsigned local build

## Build in Xcode

1. Open `JasoGuard.xcodeproj`.
2. Select the `JasoGuard` scheme.
3. Select `My Mac` as the destination.
4. Choose `Product -> Build`.

To find the built app:

```text
Product -> Show Build Folder in Finder
```

For a Release build, change the build configuration:

```text
Product -> Scheme -> Edit Scheme... -> Run -> Info -> Build Configuration -> Release
```

The app is typically created under:

```text
Products/Release/JasoGuard.app
```

## Create a ZIP for GitHub Releases

From the folder that contains `JasoGuard.app`:

```bash
ditto -c -k --keepParent JasoGuard.app JasoGuard-unsigned.zip
shasum -a 256 JasoGuard-unsigned.zip > JasoGuard-unsigned.zip.sha256
```

Upload these files to GitHub Releases:

```text
JasoGuard-unsigned.zip
JasoGuard-unsigned.zip.sha256
```

## Install and run

1. Copy `JasoGuard.app` to `/Applications`.
2. Open the app.
3. On first run, review the permission and scan notice.
4. Click `Agree and Start`.
5. The menu bar icon appears when the app is running.

The permission and scan notice is saved after the first approval. JasoGuard will not ask again on later launches or manual scans unless the app preferences are reset.

## Menu bar controls

The menu bar item shows an icon only:

```text
Check icon: running normally
Exclamation icon: error
```

Available menu actions:

- Check current status
- Toggle launch at login
- Toggle launch confirmation window
- Choose language: System Language, English, or Korean
- Restart watcher
- Scan watched paths now
- Open config file
- Open log folder
- Hide menu bar widget
- Quit completely

## Launch at login

Use the menu bar action:

```text
Launch at Login
```

This creates:

```text
~/Library/LaunchAgents/io.github.local.jasoguard.plist
```

The LaunchAgent opens the app itself, so the menu bar widget appears after login.

## Gatekeeper notice for unsigned builds

The default build is unsigned and not notarized. macOS may block the first launch with a warning such as:

```text
Apple cannot check it for malicious software.
```

Only continue if you trust the release and the checksum matches.

Recommended method:

1. Unzip `JasoGuard-unsigned.zip`.
2. Move `JasoGuard.app` to `/Applications`.
3. Try to open the app once.
4. Open `System Settings -> Privacy & Security`.
5. Click `Open Anyway` for JasoGuard.
6. Confirm with Touch ID or your Mac password.
7. Open JasoGuard again.

Alternative method:

1. Control-click or right-click `/Applications/JasoGuard.app`.
2. Choose `Open`.
3. Confirm `Open` again.

Advanced terminal method:

```bash
xattr -dr com.apple.quarantine /Applications/JasoGuard.app
open /Applications/JasoGuard.app
```

## Full Disk Access

If JasoGuard cannot read a watched folder, grant Full Disk Access:

```text
System Settings -> Privacy & Security -> Full Disk Access -> +
```

Add:

```text
/Applications/JasoGuard.app
```

If macOS asks for a specific executable path, use:

```text
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard
```

## Configuration

Config file:

```text
~/.config/jasoguard/config.json
```

Default watched folders:

```text
~/Desktop
~/Documents
~/Downloads
```

Default ignored folders:

```text
~/Library
~/.Trash
```

Important settings:

- `watch`: folders to watch
- `ignore`: folders to skip
- `latencySeconds`: file event batching delay, default `0.25`
- `directoryEventDepth`: scan depth for new directory events, default `2`
- `scanExistingOnStart`: scan existing watched paths once at startup, default `true`
- `startupScanDepth`: startup scan depth, default `8`
- `skipHiddenFiles`: skip hidden files when enabled

After editing the config, use `Restart Watcher` from the menu bar.

## Watching `/Users`

You can watch `/Users`, but it is safer to ignore Library, Trash, and Shared folders:

```json
{
  "watch": [
    {
      "path": "/Users",
      "recursive": true
    }
  ],
  "ignore": [
    "~/Library",
    "~/.Trash",
    "/Users/Shared"
  ],
  "latencySeconds": 0.25,
  "directoryEventDepth": 2,
  "scanExistingOnStart": true,
  "startupScanDepth": 5,
  "skipHiddenFiles": false
}
```

For only the current user account, this is usually safer:

```json
{
  "watch": [
    {
      "path": "~",
      "recursive": true
    }
  ],
  "ignore": [
    "~/Library",
    "~/.Trash"
  ],
  "latencySeconds": 0.25,
  "directoryEventDepth": 2,
  "scanExistingOnStart": true,
  "startupScanDepth": 6,
  "skipHiddenFiles": false
}
```

## CLI

The menu bar app is the recommended way to use JasoGuard, but CLI commands are also available:

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard status
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard scan
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard add ~/Projects
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard ignore ~/Library
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive --dry-run
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard install-agent --app-path /Applications/JasoGuard.app
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard uninstall-agent
```

Use `--dry-run` before manual conversion to preview what would be renamed.

## Logs

Log folder:

```text
~/.local/state/jasoguard/
```

You can open it from the menu bar with `Open Log Folder`.

## License

MIT. See `LICENSE`.
