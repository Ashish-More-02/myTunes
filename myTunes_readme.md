# myTunes

A SwiftUI macOS music player. Point it at a folder, get a clean, native player with playlists, artwork, and keyboard shortcuts. **Bring Your Own Music** — offline only, no network, no telemetry.

## Quick start

```bash
cd ~/Desktop/myTunes
swift build           # quick dev build
./build_app.sh        # produce myTunes.app
open myTunes.app
```

Requires macOS 13.0 or later.

## Project layout

```
~/Desktop/myTunes/
├── Package.swift                       # Swift Package, target "myTunes"
├── Info.plist                          # Bundle metadata for .app
├── build_app.sh                        # Build & wrap into .app
├── myTunes.app/                        # Compiled bundle — runnable
└── Sources/myTunes/
    ├── myTunesApp.swift                # @main entry, WindowGroup
    ├── ContentView.swift               # Sidebar + Main + PlayerBar + SettingsView + spacebar monitor
    ├── MusicPlayer.swift               # AVAudioPlayer wrapper, queue, playlists, persistence, FSEvents
    ├── Song.swift                      # Metadata model (Codable, lazy artwork)
    ├── Theme.swift                     # Navy / slate / amber / cream palette
    ├── FolderWatcher.swift             # FSEventStream wrapper
    └── LibraryStore.swift              # JSON persistence in ~/Library/Application Support/myTunes/library.json
```

## Features

- **Playlists from subfolders** — each immediate subfolder of the chosen root is a playlist; "All Songs" is the default virtual playlist.
- **Sidebar navigation** — Library / Settings, plus the playlist list with song counts. Selected playlist is persisted across launches.
- **Recursive scan** — mp3, m4a, wav, aac, flac, aiff, aif.
- **Playback** — play / pause / next / previous, seek bar, volume slider, auto-advance through the queue, stop at end.
- **Spacebar play/pause** — global, skipped when a text field has focus.
- **Larger song titles** — 17pt semibold in the song list for readability.
- **Embedded album artwork + ID3 metadata** — title, artist, album. Artwork loads lazily on first play.
- **Auto-detect folder changes** — FSEvents watcher rescans when songs are added or removed while the app runs.
- **Library cache** — folder + scanned songs survive relaunch (JSON in `~/Library/Application Support/myTunes/library.json`).
- **Dark mode (default) + light mode** — toggle in Settings.
- **Settings page** — Appearance, Library (folder, song / playlist counts, auto-detect toggle, Rescan / Choose Folder / Forget Library), Keyboard, Audio, Features, About.

## Architecture notes

- `Playlist` is a small struct in `MusicPlayer.swift` (folder URL + display name); playlists are derived from `songs` by `recomputePlaylists()`.
- `selectedPlaylistName: String` drives the UI selection; empty string means "All Songs". Persisted in `UserDefaults` under `selectedPlaylistName`.
- `displayedSongs` filters the master `songs` array by playlist folder prefix.
- `playbackQueue` is separate from `songs` — captured at the moment the user hits play. This way, switching playlists mid-play doesn't disrupt auto-advance.
- Spacebar handling uses `NSEvent.addLocalMonitorForEvents` (keyCode 49), skipping events when the first responder is `NSText` or `NSTextView`.

## Brand palette (`Theme.swift`)

- Navy `rgb(26, 50, 99)`
- Slate `rgb(84, 119, 146)`
- Amber `rgb(250, 185, 91)` ← accent
- Cream `rgb(232, 226, 219)`

## Known warning

One Swift 6 forward-compat warning: `NSImage?` not `Sendable` across actor boundaries in `MusicPlayer.loadArtworkIfNeeded`. Not an error in Swift 5 mode — compiles cleanly. Fix later by wrapping `NSImage` in `@unchecked Sendable` or transferring `Data` instead and constructing `NSImage` on the main actor.

## Open ideas

- **App icon** — generate a 1024×1024 PNG (music-note + navy/slate/amber gradient), convert with `iconutil` to `AppIcon.icns`, drop into `myTunes.app/Contents/Resources/`, add `CFBundleIconFile = AppIcon` to `Info.plist`.
- **Shuffle / repeat**
- **Search box**
- **Persist last-played song + position** in `LibraryStore.Snapshot`.
- **Recently played** virtual playlist.
