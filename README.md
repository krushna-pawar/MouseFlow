# MouseFlow

A macOS menu-bar utility (macOS 13+) for external mice: scroll direction, speed and smoothing, lines per tick, modifier-key scrolling (zoom, horizontal, fast), pointer sensitivity, and actions for each mouse button. Trackpads are left untouched.

## Install

1. Move `MouseFlow.app` to `/Applications` and open it. It runs in the menu bar, with no Dock icon.
2. When asked, turn on MouseFlow under **System Settings › Privacy & Security › Accessibility**. MouseFlow starts working as soon as access is on; no relaunch needed.
3. Optional: turn on **Launch at Login** in MouseFlow's Settings › General.

## Troubleshooting

**MouseFlow is switched on in Accessibility but does nothing.** This usually happens after an update or a rebuild. macOS ties the permission to the app's code signature, so a newly signed copy is not trusted even though the switch still looks on. Fix it like this:

1. Quit MouseFlow.
2. In System Settings › Privacy & Security › Accessibility, select MouseFlow and remove it with the **–** button.
3. Open MouseFlow again and turn it back on when asked.

**Pointer speed feels wrong after quitting.** MouseFlow restores the system pointer settings when it quits normally. After a crash or force-quit, open MouseFlow and quit it again, or change Tracking speed in System Settings › Mouse.

## Build from source

Plain Xcode project with no dependencies.

```sh
xcodebuild -project MouseFlow.xcodeproj -scheme MouseFlow -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/MouseFlow.app --args --settings
```

Debug builds log with a `[MouseFlow]` prefix:

```sh
log stream --predicate 'eventMessage CONTAINS "[MouseFlow]"' --style compact
```

Release builds only log errors and event-tap start and stop.

## License

MIT, see [`LICENSE`](LICENSE). Third-party notices are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
