# MouseFlow

A macOS menu-bar utility (macOS 13+) for external mice: scroll direction, speed and smoothing, lines per tick, modifier-key scrolling (zoom, horizontal, fast), pointer sensitivity, and actions for each mouse button, including recorded keyboard macros. Trackpads are left untouched.

## Install

1. Download `MouseFlow-<version>.dmg` from the [latest release](../../releases/latest).
2. Open the DMG and drag `MouseFlow.app` to `Applications`.
3. Open MouseFlow. MouseFlow isn't notarized by Apple, so macOS blocks it the first time. Go to **System Settings › Privacy & Security**, scroll down to the message about MouseFlow, click **Open Anyway**, then confirm with **Open**. You only need to do this once.
4. MouseFlow runs in the menu bar, with no Dock icon. When asked, turn on MouseFlow under **System Settings › Privacy & Security › Accessibility**. MouseFlow starts working as soon as access is on; no relaunch needed.
5. Optional: turn on **Launch at Login** in MouseFlow's Settings › General.

## Troubleshooting

**MouseFlow is switched on in Accessibility but does nothing.** This usually happens after an update or a rebuild. macOS ties the permission to the app's code signature, so a newly signed copy is not trusted even though the switch still looks on. Fix it like this:

1. Quit MouseFlow.
2. In System Settings › Privacy & Security › Accessibility, select MouseFlow and remove it with the **–** button.
3. Open MouseFlow again and turn it back on when asked.

**Pointer speed feels wrong after quitting.** MouseFlow restores the system pointer settings when it quits normally. After a crash or force-quit, open MouseFlow and quit it again, or change Tracking speed in System Settings › Mouse.

## Build from source

Plain Xcode project with no dependencies. The project signs with the maintainer's Apple team, so select your own team under the target's **Signing & Capabilities**, or pass `DEVELOPMENT_TEAM=<your team ID>` to `xcodebuild`.

```sh
xcodebuild -project MouseFlow.xcodeproj -scheme MouseFlow -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/MouseFlow.app --args --settings
```

`scripts/release.sh` builds a Release DMG into `build/release/`.

MouseFlow logs with a `[MouseFlow]` prefix:

```sh
log stream --predicate 'eventMessage CONTAINS "[MouseFlow]"' --style compact
```

Debug builds add detailed traces. Release builds log only errors and lifecycle events, such as the event tap starting, stopping or restarting and pointer settings being restored.

## License

MIT, see [`LICENSE`](LICENSE). The smooth-scrolling code is licensed under CC BY-NC 4.0, so MouseFlow may not be used for commercial purposes. Third-party notices are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
