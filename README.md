# ThorReborn

A menu-bar app for macOS that switches to apps with global keyboard shortcuts. Press an app's shortcut to launch or activate it; press it again while that app is frontmost to hide it.

ThorReborn is a from-scratch rewrite of [Thor](https://github.com/gbammc/Thor) by Alvin Zhu (MIT license). It aims for full functional parity, built with Swift 6, SwiftUI, Swift Package Manager, [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and [Sparkle 2](https://sparkle-project.org). It drops Thor's CocoaPods setup, storyboards, MASShortcut, and LaunchAtLogin helper app. It reads and writes Thor's `apps.json` format, so you can import an export from the original.

## Features

- Runs from the menu bar only (no Dock icon). The menu has: Show Apps, Enable/Disable Shortcuts, Export/Import Shortcuts, Check for Updates, the version, Privacy Policy, and Quit.
- Main window with one row per app (36×36 icon, name, shortcut recorder). You can drag rows to reorder them. To delete, swipe, use the − button, the Delete key, or the context menu.
- An app picker that finds apps in `/Applications`, `/System/Applications`, `~/Applications`, and through Spotlight (`kMDItemContentType == "com.apple.application-bundle"`), and filters as you type.
- Conflict detection. Recording a shortcut that another row already uses asks before moving it. The menu bar toggle hotkey can't be assigned at all.
- A global switch to enable or disable all shortcuts.
- An optional deactivate key: double-press Shift, Control, Option or Command to pause all shortcuts. They come back on their own after 0.1–2.0 s (0.3 s by default).
- **⇧⌃⌥⌘T** shows or hides the menu bar icon. You can turn this hotkey off in Settings.
- Launch at login through `SMAppService`.
- JSON export and import (the default file name is `thor_shortcuts.json`).

## Build and run

Requirements: Xcode 16 or later (built and tested with Xcode 27.1). The app runs on macOS 14 or later, on Apple Silicon and Intel.

**In Xcode:** open `ThorReborn.xcodeproj`, pick the **ThorReborn** scheme, and press ⌘R. Xcode fetches the Swift packages on first open.

**From the command line:**

```sh
xcodebuild -scheme ThorReborn -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/ThorReborn-*/Build/Products/Debug/ThorReborn.app

# Universal (arm64 + x86_64) release build
xcodebuild -scheme ThorReborn -configuration Release -destination 'generic/platform=macOS' build
```

If `xcodebuild` says the active developer directory is the Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

### Tests

The unit tests use Swift Testing. They cover round-trips of shortcut strings and of store save/load and export/import. They live in the `ThorRebornCore` package and run either way:

```sh
cd Packages/ThorRebornCore && swift test                             # SwiftPM
xcodebuild -scheme ThorReborn -destination 'platform=macOS' test     # Xcode (ThorRebornCoreTests target)
```

Debug builds also contain an end-to-end self-test that drives the real services. It assigns ⇧⌘G to Calculator, launches, hides and reactivates it, disables and re-enables shortcuts, double-presses the deactivate key, toggles launch at login, and runs export, delete-all and import. It checks hotkey registration directly against Carbon. It runs against a temporary `apps.json` and a separate defaults suite, so your real data is never touched:

```sh
open -n path/to/Debug/ThorReborn.app --args --self-test /tmp/thor-selftest.txt
```

## Permissions

| Permission | Why |
| --- | --- |
| **Accessibility** (Privacy & Security › Accessibility) | Needed to watch modifier keys while other apps are in front, which the deactivate-key double-press depends on. On first launch, ThorReborn shows a screen explaining this, with a button that opens the right System Settings pane. If you revoke the permission while the app is running, that screen comes back. The app shortcuts themselves are Carbon hot keys and keep working without it. |
| **Login Items** | Only if you turn on *Launch at login*. macOS may ask you to approve ThorReborn under General › Login Items. |

**Rebuilding and Accessibility.** Local builds are ad-hoc signed ("Sign to Run Locally"). macOS stores the grant against the binary's exact hash, so every rebuild produces an app the existing grant doesn't cover. The list still shows ThorReborn as *on*, but that entry belongs to the old build, and the onboarding screen reappears. To fix it:

```sh
tccutil reset Accessibility dev.thorreborn.ThorReborn   # forget the stale grant
```

Then click **Open System Settings** in ThorReborn and switch the new entry on. To stop this happening on every build, choose a Team in Xcode › Signing & Capabilities (a free Personal Team works). A certificate-based signature stays the same across builds.

Only one copy of ThorReborn runs at a time. Launching a second copy brings the running one forward and quits.

## Data format

Assignments live in `~/Library/Application Support/ThorReborn/apps.json`. This is the same structure as the original Thor's `~/Library/Application Support/Thor/apps.json`:

```json
[
  {
    "appBundleURL" : "file:///Applications/Safari.app/",
    "appDisplayName" : "Safari",
    "shortcut" : "shift+cmd+s"
  }
]
```

| Key | Meaning |
| --- | --- |
| `appBundleURL` | The `file://` URL of the `.app` bundle (`URL.absoluteString`, with a trailing slash). Rows are unique by this value. |
| `appDisplayName` | The name shown in the list. |
| `shortcut` | Modifiers joined with `+`, then the key name. An empty string means no shortcut. |

Shortcut strings use Thor's own vocabulary:

- **Modifiers:** `shift`, `ctrl`, `alt`, `cmd`.
- **Key names:** `a`–`z`, `0`–`9`, the punctuation characters (with `"` for the quote key, as Thor writes it), `numpad0`–`numpad9`, `numpad_add`/`numpad_subtract`/…, `return`, `tab`, `space`, `delete`, `escape`, `capslock`, `home`, `end`, `pageup`, `pagedown`, `left`/`right`/`up`/`down`, and `f1`–`f20`.

When saving, ThorReborn writes modifiers in Thor's fixed order (shift, ctrl, alt, cmd). So ⌘⇧G is written as `"shift+cmd+g"`, byte-for-byte what Thor wrote. When reading, modifiers can come in any order, so `"cmd+shift+g"` also works.

A shortcut made only of modifiers (`"cmd+shift"`) is invalid. The parser rejects it, and the recorder won't accept one.

## Choices made where the original was ambiguous

1. **Modifier order.** The spec's example says `cmd+shift+g`, but Thor actually wrote `shift+cmd+g`. ThorReborn writes Thor's order for compatibility and accepts either order when reading.
2. **Apps without a shortcut** are kept and written as `"shortcut": ""`. Thor dropped such rows on load. If a row's shortcut string can't be parsed, ThorReborn keeps the app and clears the shortcut rather than dropping the row.
3. **Cleaning up on load.** Entries whose bundle no longer exists, entries that can't be decoded, and duplicate entries are dropped and logged (`log stream --predicate 'subsystem == "ThorRebornCore"'`). The cleaned file is then saved back.
4. **Extra key names.** Thor's key table had no names for a few keys, so it saved them as `""`. ThorReborn adds `forwarddelete`, `help` and `section`, and writes any other key as `keycode_<n>`. Thor will ignore these entries.
5. **Deactivate key.** It uses Thor's fixed 0.3 s double-press window, and the slider (0.1–2.0 s) sets how long shortcuts stay paused. Only a press of that modifier on its own counts, so ⇧ held as part of ⇧⌘G doesn't trigger it. Unlike Thor, pausing doesn't flip the saved "Enable shortcuts" setting. So quitting during a pause doesn't leave shortcuts off, and a pause never turns shortcuts on if you had them off.
6. **The toggle hotkey vs. conflicts.** The spec asks for a warning when a shortcut collides with the menu-bar toggle hotkey, and also says that hotkey must never be taken. Recording ⇧⌃⌥⌘T is refused with an explanation, and there's no "use anyway" option. Collisions between rows show a confirmation, and confirming moves the shortcut.
7. **Settings are a tab in the main window** (Apps | Settings), like Thor's toolbar tabs, rather than a separate Settings window.
8. **Import replaces** the current list, as in Thor. ThorReborn asks for confirmation first when the list isn't empty. Thor's older NSKeyedArchiver (MASShortcut) format isn't supported. Only JSON is.
9. **Export/Import** appear both in the menu bar menu (as in Thor) and at the bottom of the main window.
10. **The main window opens** on launch when no apps are assigned, and whenever the running app is opened again (Finder, Spotlight, `open`). Activations in the first second after launch are ignored, the same intent as Thor's `hasLaunched` flag.
11. **Matching the frontmost app** is by bundle identifier (as in Thor), falling back to the bundle path for bundles without an identifier.
12. **Settings storage.** Settings live in `UserDefaults` under Thor's key names (`EnableShortcut`, `DeactivateKey`, `DelayInterval`, and so on), with Thor's defaults. Shortcuts are stored only in `apps.json`. KeyboardShortcuts is used in binding mode, so it writes nothing to `UserDefaults`.
13. **Bundle identifier** is `dev.thorreborn.ThorReborn`, and the menu bar icon is the SF Symbol `hammer.fill`.
14. **Single instance.** Thor didn't guard against a second copy. ThorReborn does, because two copies would both handle every hotkey.
15. **No sandbox and no hardened runtime** in local builds. The sandbox would block Accessibility-based key monitoring and need Sparkle's XPC services. Hardened runtime combined with ad-hoc signing breaks loading Sparkle.framework. For distribution, sign with a Developer ID, enable hardened runtime, and notarize.

## Updates (Sparkle)

Check for Updates is wired to Sparkle 2's `SPUStandardUpdaterController`. The values in `Config/Info.plist` are **placeholders**:

- `SUFeedURL` = `https://example.com/thorreborn/appcast.xml`. Replace it with your real appcast URL.
- `SUPublicEDKey` is a throwaway Ed25519 public key generated just so Sparkle's configuration check passes. Its private key was never stored. Before shipping, run Sparkle's `generate_keys` tool, put its public key here, and sign updates with `sign_update`.
- `SUEnableAutomaticChecks` is `false` until a real feed exists.

Until then, Check for Updates reports that it can't reach the feed.

## Project layout

```
ThorReborn.xcodeproj         Xcode project (file-system-synchronized groups) and shared scheme
Config/Info.plist            LSUIElement + Sparkle keys (merged with generated Info.plist)
ThorReborn/
  App/                       ThorRebornApp (@main), AppDelegate, AppServices, WindowCoordinator, AppCommands
  Services/                  AppKit lives here: ActivationService, HotkeyService, DeactivateKeyMonitor,
                             MenuBarService, AppDiscoveryService, AccessibilityService,
                             LaunchAtLoginService, ImportExportService, AppIconProvider
  Views/                     SwiftUI: MainWindowView, AddAppPickerView, SettingsView, OnboardingView
  Support/                   AppSettings, shortcut bridging, DEBUG self-test
  Assets.xcassets            App icon (regenerate with `swift scripts/make-app-icon.swift`)
Packages/ThorRebornCore/     AssignedApp, ThorShortcut (string parse/serialize), AppAssignmentStore + tests
```

## License

MIT, like the original Thor, whose design and `apps.json` format this project follows.
