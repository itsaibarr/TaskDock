# Contributing

Thanks for helping. TaskDock is a small project; small, focused pull requests are easiest to review.

## Setup

- macOS with Xcode (Swift 6 tools). Node.js for the extension tests.
- `./scripts/test.sh` runs everything. `./scripts/build.sh` builds `build/TaskDock.app`.

Run against sample data so you don't touch your real templates:

```sh
TASKDOCK_DATA_DIR=/tmp/taskdock-dev swift run
```

Quit an installed TaskDock first: two copies compete for the ⌃⌥Space hotkey and the bridge port.

**Careful:** starting a task rewrites your real Dock preferences and hides apps, even in a dev build.
Your Dock backup is in `~/Library/Application Support/TaskDock/dock-original.plist` (see the README).
Only run `TASKDOCK_LIVE_DOCK=1 ./scripts/test.sh` on purpose.

## Pull requests

- Keep changes focused; explain the user-visible effect and how you tested it.
- `./scripts/test.sh` must pass. Add a test for logic changes where practical.
- For UI changes, include before/after screenshots in light and dark mode (`./scripts/shots.sh <dir>` helps).
- No new dependencies without discussing it in an issue first.
- Match the surrounding style (4-space indentation, short comments that explain *why*).

## Reporting bugs

Use the bug report template. Include your macOS version, browser (if relevant), and steps to reproduce.
For security issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
