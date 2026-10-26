# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

A personal fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) — a macOS menu-bar app (SwiftUI + AppKit) that turns the MacBook notch into a dynamic island: media controls with a Metal visualizer, calendar (TickTick via an iCal subscription), a file shelf with AirDrop, webcam mirror, battery indicator, and HUD replacements for volume/brightness/keyboard backlight.

The goal of the fork is to **strip features that aren't needed and add new ones**. When removing a feature, remove it completely: its views, manager, `Defaults` keys, settings UI, menu entries, entitlements/Info.plist usage strings and any SPM package that becomes unused.

## Requirements

- macOS 14+ (deployment target `14.0`)
- Full **Xcode** (CI uses Xcode 26.x; builds locally with Xcode 27.1). Command Line Tools alone are not enough — `xcodebuild` must point to Xcode:
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- Swift 5 language mode (`SWIFT_VERSION = 5.0`)

## Build & run

```bash
# Resolve SPM packages
xcodebuild -resolvePackageDependencies -project boringNotch.xcodeproj

# Release build (ad-hoc signed, output in ./build) + install
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO build
pkill -x "Boring Notch" 2>/dev/null; sleep 2; pkill -9 -x "Boring Notch" 2>/dev/null
rm -rf "/Applications/Boring Notch.app"
cp -R "build/Build/Products/Release/Boring Notch.app" /Applications/
open "/Applications/Boring Notch.app"
```

Notes:
- `ENABLE_HARDENED_RUNTIME=NO` is required for ad-hoc builds: with hardened runtime on, library validation refuses to load the embedded `MediaRemoteAdapter.framework` and the app dies at launch with a dyld "different Team IDs" error. Hardened runtime only matters for notarized distribution.
- First build on a fresh Xcode may need `sudo xcodebuild -license accept` and `xcodebuild -runFirstLaunch`.
- Ad-hoc signed builds change identity on every rebuild, so macOS may re-ask for Accessibility / Calendar / Camera permissions. If a permission silently stops working, reset it in System Settings → Privacy & Security (or `tccutil reset All theboringteam.boringnotch`).
- There is no test target. "Verify" means: it builds without new warnings, and the feature works in the running app.
- Logs: the app uses `Logger.log(_:category:)` (`boringNotch/utils/Logger.swift`), which prints to stdout. Run the binary directly to see them: `"/Applications/Boring Notch.app/Contents/MacOS/Boring Notch"`.

## Project layout

```
boringNotch/                     main app target
  boringNotchApp.swift           @main, AppDelegate, window/screen lifecycle
  ContentView.swift              root notch view (open/closed states, gestures)
  BoringViewCoordinator.swift    global UI state (current tab, sneak peeks, HUD routing)
  components/
    Notch/                       notch window (SkyLight), shape, header, home view
    Music/  Calendar/  Shelf/  Webcam/  Live activities/  Tabs/  Onboarding/  Tips/
    Settings/                    SettingsView, settings window, Sparkle updater UI
  fork/                          fork-only features: VPN, Amphetamine, snippets, agents, system stats (synced group)
  managers/                      Music, Volume, Brightness, Battery, Calendar, Webcam, NotchSpace…
  MediaControllers/              Apple Music, Spotify, YouTube Music, NowPlaying (MediaRemote)
  models/                        view models; Constants.swift holds all `Defaults.Keys`
  observers/                     drag detection, fullscreen detection, media-key interception
  metal/visualizer.metal         audio visualizer shader
  private/CGSSpace.swift         private CoreGraphics Spaces API
  XPCHelperClient/               client side of the privileged XPC helper
  Localizable.xcstrings          string catalog (synced with Crowdin upstream)
BoringNotchXPCHelper/            XPC service target (accessibility/brightness/keyboard backlight)
mediaremote-adapter/             bundled MediaRemoteAdapter.framework + perl bridge for Now Playing on macOS 15.4+
Configuration/dmg/               DMG packaging scripts (Python)
updater/appcast.xml              Sparkle appcast
.github/workflows/               upstream CI/CD (build, release, nightly, CodeQL, Crowdin)
```

**Where new code goes.** Most of `boringNotch/` is listed file-by-file in `project.pbxproj`; only `boringNotch/private/`, `boringNotch/fork/` and `BoringNotchXPCHelper/` are file-system synchronized groups. Put all fork-specific code (new `.swift` files and resources such as `agent-hook.sh`) in `boringNotch/fork/`: files there are compiled and bundled automatically, and keeping them apart makes upstream merges easier. Touch upstream files only for small wiring changes. A new file anywhere else must be added to `project.pbxproj` by hand. Edit `project.pbxproj` also for package, target, build-setting or entitlement changes.

Fork features are described in `SPEC.md`.

## Conventions

- Settings are stored with [`Defaults`](https://github.com/sindresorhus/Defaults). Upstream keys live in `models/Constants.swift`; fork keys go in `fork/ForkDefaults.swift`. Read them in views with `@Default(.key)`.
- The main app is sandboxed. Anything that needs to run system tools (e.g. `scutil`) goes through the unsandboxed XPC helper: add the method to **both** copies of `BoringNotchXPCHelperProtocol.swift` (helper and `XPCHelperClient/`), implement it in `BoringNotchXPCHelper.swift`, and wrap it in `XPCHelperClient`. Apple Events to another app need its bundle ID in `com.apple.security.temporary-exception.apple-events` in `boringNotch.entitlements`.
- External tools talk to the app through the `boringnotch://` URL scheme, handled in `AppDelegate.application(_:open:)` (e.g. `boringnotch://agent?…` from `fork/agent-hook.sh`).
- Global shortcuts use `KeyboardShortcuts` (`Shortcuts/ShortcutConstants.swift`).
- Managers are singletons (`XxxManager.shared`) exposing `@Published` state as `ObservableObject`s; views observe them.
- Animations use SwiftUI springs and the `Pow` package; Lottie for a few animations.
- User-facing strings go through the string catalog (`String(localized:)` / `Text("…")`).
- Match the style of surrounding code; keep comments sparse.

## Fork-specific gotchas

- **Sparkle is disabled, not removed.** The updater is created with `startingUpdater: false`, `SUFeedURL` is gone from `Info.plist`, and the "Check for Updates" UI is hidden — upstream releases would otherwise replace this build. The package, `SoftwareUpdater.swift` and the Sparkle entitlements are still there; to ship your own updates, add your own feed and `SUPublicEDKey` and start the updater again.
- Bundle ID is still `theboringteam.boringnotch` (and `…BoringNotchXPCHelper` for the helper). If both the official app and the fork are installed, they share preferences and permissions — change the bundle ID if that's a problem.
- Remotes: `origin` is the public fork `WithSoull/boring.notch` (default branch `fork/notch-features`); `upstream` is `TheBoredTeam/boring.notch`. Upstream does code work on `dev`; `main` is release-only. Never push to `upstream`.
- Upstream GitHub Actions need signing secrets that the fork doesn't have. Workflows are not enabled on the fork; remove or adjust them before enabling Actions.

## Before finishing a change

1. The project builds (`xcodebuild … build`) with no new errors or warnings.
2. Removed features leave no dead `Defaults` keys, settings rows, assets, or unused SPM packages.
3. UI changes were checked in the running app on a notched display (and, ideally, a non-notched external display).
