# TaskDock

A macOS menu bar app for starting focused work. Press **⌃⌥Space**, pick a task template, and
only that task's apps stay visible and pinned in the Dock. Your browser opens a fresh window while
your other windows (and their tabs) are paused. When you finish, everything goes back the way it was.

> **Status: early software (0.3.0, pre-1.0).** It rewrites your Dock preferences and hides
> other apps. Read [Safety](#safety-and-undo) before using it.

## Features

- **Task templates** — an icon, a name, a list of apps, and optional Apple Shortcuts to run on start and finish.
- **Hotkey picker (⌃⌥Space)** — a small search panel. Pick a template, optionally type what you'll finish, and press ↩.
  Templates can be edited in place (icon, name, apps), reordered by dragging, and edited or deleted from a right-click menu.
- **Focus on start** — the template's apps open; every other app is hidden (not quit); the Dock shows only the template's apps.
- **Restore on finish** — previously visible apps come back, apps TaskDock opened for the task are quit (normally,
  so they can still ask to save), and your exact previous Dock is restored.
- **Pick up where you left off** — finishing or switching saves the task's browser tabs, the documents open in
  its scriptable apps (Preview, TextEdit, Pages…; Preview also reopens a PDF at the page you were on), the note
  open in Obsidian, and your "where did you stop? what's next?" note. Next time you pick the template, ↩ reopens it
  all; **Start fresh** skips it.
- **Phi Spaces (optional)** — a template that includes [Phi](https://phibrowser.com) switches Phi to the Space named
  like the template (or the one you pick in the picker). Phi keeps that Space's tabs itself. If there's no such
  Space, TaskDock creates it (needs Accessibility).
- **AeroSpace (optional)** — with [AeroSpace](https://github.com/nikitabobko/AeroSpace) installed, finishing a task
  remembers which workspace each of its apps was on, and the next start moves their windows back there.
- **Browser extension (optional)** — for templates that include a browser: opens a fresh window, minimizes the
  other windows and unloads their tabs until you finish.
- **Calendar suggestion (optional)** — with calendar access, the event happening now (or in the next 15 minutes)
  is suggested at the top of the picker; a template whose name appears in the event title is matched automatically.
- Follows the system light/dark appearance.

## Requirements

| | |
|---|---|
| macOS | Declared minimum 15.0. **Only verified on macOS 26.5.** |
| Build tools | Xcode with Swift 6 tools (verified with Xcode 26.5 / Swift 6.3). Xcode is needed for the Swift tests (XCTest). |
| Browser extension | A Chromium-based browser, version 116+. Developed with Helium and Brave. |
| Node.js | Only for the extension's unit tests (`node --test`). |

There are no third-party dependencies (Swift Package Manager or npm).

## Install (from source)

Releases are source-only; there are no prebuilt or notarized downloads yet. See [CHANGELOG.md](CHANGELOG.md).

```sh
./scripts/build.sh          # builds build/TaskDock.app (ad-hoc signed)
open build/TaskDock.app      # a ◎ icon appears in the menu bar
```

Optionally move `build/TaskDock.app` into `/Applications`.

### Browser extension (optional)

1. Open `chrome://extensions` in your browser (`brave://extensions`, `helium://extensions`, …).
2. Turn on **Developer mode** → **Load unpacked** → choose the `extension/` folder.
3. The ◎ menu should say "Browser connected" within about 30 seconds.

### Calendars (optional)

◎ menu → **Connect Calendars…** and allow access. TaskDock reads calendars through macOS (EventKit), so it
sees whatever Calendar.app sees. For Google calendars, add your Google account in
**System Settings › Internet Accounts** and turn on Calendars. Event data is only read locally.

## Usage

1. Open the apps a task needs → ◎ → **New Template from Current Setup** (or create one in the picker or ◎ → **Edit Templates…**).
2. Press **⌃⌥Space**, pick a template, optionally type a goal, press ↩.
3. To finish, press **⌃⌥Space** again (or use ◎), note where you stopped, press ↩. **Switch Task…** moves straight to another template.

## Permissions

| Permission | Why | When asked |
|---|---|---|
| Calendars (full access) | Suggest the current event | Only after **Connect Calendars…** |
| Automation (per app, e.g. Preview) | Read which documents a task had open | First finish of a task using that app |
| Automation (Phi) | List Phi's Spaces and switch to the task's Space | First start of a task using Phi |
| Accessibility (optional) | Create a missing Phi Space through Phi's **New Space** menu (Phi's scripting can't create Spaces) | When you choose **Create “…” Now** in the picker |
| Documents folder | Read Obsidian's open note (vault in `~/Documents`) | First finish of a task using Obsidian |
| None for hiding apps | Uses `NSRunningApplication.hide()` | — |

Starting and finishing a task may run `/usr/bin/shortcuts run "<name>"` for the Shortcut names you set on a template.

## Configuration

Everything is configured in the app. The hotkey is fixed to ⌃⌥Space.

Environment variables (for development; none are needed for normal use):

| Variable | Build | Effect |
|---|---|---|
| `TASKDOCK_DATA_DIR=<dir>` | any | Use `<dir>` instead of `~/Library/Application Support/TaskDock` (e.g. sample data). |
| `TASKDOCK_SHOTS=<dir>` | debug only | Open the windows, save screenshots to `<dir>`, then quit. Used by `scripts/shots.sh`. |
| `TASKDOCK_LIVE_DOCK=1` | tests | Run the test that swaps and restores your **real** Dock (about 15 s). |

## Data and privacy

All data stays on your Mac. Nothing is sent over the network.

- `~/Library/Application Support/TaskDock/templates.json` — your templates, "where you stopped" notes, and each
  task's saved state (tab URLs and file paths).
- `…/session.json` — the running task, including your previous Dock layout (deleted on finish).
- `…/dock-original.plist` — a backup of your Dock from the first time TaskDock changed it.
- The browser bridge is a WebSocket on `127.0.0.1:47123` (loopback only). It sends the current task's name,
  icon, goal, start time and saved tab URLs to connected extensions, which keep them in the extension's local storage.
  When a task ends, the extension sends back that task window's web addresses (http/https only).
  See [SECURITY.md](SECURITY.md) for its limits.

## Safety and undo

- TaskDock edits the `com.apple.dock` preferences and restarts the Dock, like `dockutil` does.
  The pre-task Dock is saved to `session.json` **before** anything changes. If TaskDock quits mid-task,
  reopening it resumes the task, so Finish still restores.
- To restore your original Dock by hand:
  ```sh
  defaults import com.apple.dock ~/Library/Application\ Support/TaskDock/dock-original.plist && killall Dock
  ```
- Apps that were open before a task are only hidden, never quit. Apps TaskDock opened for the task are quit
  when it ends with a normal quit, so apps with unsaved work ask first.

### Uninstall

Finish any running task, quit TaskDock (◎ → Quit), delete the app, remove the browser extension, and delete
`~/Library/Application Support/TaskDock` (keep `dock-original.plist` first if you may need it).

## Known limitations

- macOS always shows running apps in the Dock. Hidden apps keep their Dock icon (only pinned apps are removed).
- The Dock flickers for about a second on start and finish; starting within ~6 s of the last Dock change waits for it to settle.
- The hotkey is fixed (⌃⌥Space) and there is no launch-at-login.
- The task's browser window (extension browsers) stays open after the task ends.
- If two browsers have the extension, both pause their windows during a browser task.
- Saved state is per app, not per task: if two tasks share Preview, each saves every document Preview has open.
  Window positions and scroll position inside web pages aren't saved. Other apps (VS Code, etc.) rely on their own restore.
- AeroSpace workspaces are saved per app: every window of an app moves to that app's saved workspace on start.
- Ad-hoc signed only: not notarized. After each rebuild macOS may ask for calendar and Automation access again, and
  the Accessibility switch for TaskDock must be turned off and on again (it looks on but no longer applies).

## How it works

- **App** (`Sources/TaskDock`, SwiftUI + AppKit): `MenuBarExtra`, a borderless panel for the picker, a Templates window.
  The hotkey uses Carbon `RegisterEventHotKey` (no Accessibility permission).
- **Dock** (`Dock.swift`): macOS has no public Dock API, so preferences are rewritten with `defaults` and the Dock is
  restarted. Changes are queued, wait for the Dock to settle, and are read back and retried.
- **Bridge** (`Bridge.swift`): loopback-only WebSocket that accepts `chrome-extension://` origins. It needs no
  per-browser native-messaging setup.
- **Extension** (`extension/`, Manifest V3): minimizes windows and unloads tabs with `tabs.discard`;
  restore info lives in `storage.local` so it survives the service worker sleeping.

## Development

```sh
./scripts/test.sh                    # Swift tests (needs Xcode) + extension tests (node --test)
TASKDOCK_LIVE_DOCK=1 ./scripts/test.sh   # also swaps and restores your real Dock
./scripts/build.sh                   # release build → build/TaskDock.app
./scripts/shots.sh /tmp/taskdock-shots   # debug build screenshots (dark + light) on sample data
```

`scripts/test.sh` uses `$DEVELOPER_DIR` if set, otherwise `/Applications/Xcode.app`.
`shots.sh` briefly takes keyboard focus; avoid typing while it runs.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Aibar Yerzhuman
