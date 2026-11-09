# Changelog

All notable changes to TaskDock. Versions follow [Semantic Versioning](https://semver.org/) (pre-1.0: minor versions may change behavior).

Only 0.3.0 has published source. 0.1.0 and 0.2.0 were development milestones before the project
was put under version control; their source was not kept, so they have no tags or downloads.

## [Unreleased]

### Added
- Saved X posts: a ◎ button on every post on x.com saves its link and exact text to one list, with an optional
  thought. Right-click fallback, and an iPhone Share Shortcut. ◎ → **Saved Posts** to review and edit notes;
  **Start writing** adds the chosen posts to this month's Obsidian note. Saves wait in the extension until the app
  confirms them. Posts saved without text get it from X's public embed service (the app's only network request).
- Pick up where you left off: finishing or switching a task saves its browser tabs, documents open in
  scriptable apps (Preview reopens PDFs at the same page), the open Obsidian note, and your stop note.
  Picking the template again shows them and ↩ reopens everything; **Start fresh** skips it.
  Needs the updated browser extension; asks for Automation (per app) and Documents folder access once.
- Phi browser: a task switches Phi to its Space (named like the template, or picked in the picker), and creates
  the Space if it doesn't exist yet (through Phi's menu; needs Accessibility).
- AeroSpace: finishing remembers each app's workspace; starting moves the windows back.
- Finishing quits the apps TaskDock opened for the task (apps already open before stay open).
- Hand off to Claude Code: **Connect Claude Code…** adds hooks so TaskDock knows when an agent works for a task.
  Still working 2 minutes after the prompt → the picker offers another task meanwhile; the agent's task is parked
  (apps hidden, not quit). Several chats at once each get a menu row and their own notification; the menu bar shows
  ⧗ / ✓ / !. Turns waiting on background work or T3 delegates (council) count as working until they report back.
  Risk cases and limits: `docs/specs/agent-handoff.md`. Banners show the chat's name, its task (or app) and
  "Done after 23 min" or "Waiting for your answer".
- T3 Code chats are read from T3's own records (read-only, while Claude Code is connected), for every provider: a prompt sent with the Send button
  or by dictation counts as yours, a delegate's chat never does, delegates count until they report (any length,
  `mode: wait` timeouts included), an answered approval is working again at once, and "seen" is per chat. Codex
  chats in T3 park their task and protect T3 Code. If T3 can't be read, the Claude Code hooks work as before.
- Two tasks sharing an app: it's never quit while the parked one's agent works, even after TaskDock restarts.
- Clicking away from the "meanwhile" picker leaves **Pick a Task Meanwhile…** in the menu; Esc still leaves nothing.
- Picking a task from that picker no longer lets the parked task's app come back to the front a moment later.
- Claude Code outside T3: transcripts are read as they grow (no 1 MB limit), and the `PostToolUse` hook is no longer
  needed (removed on launch). In a terminal, a prompt counts as yours when Claude Code records you typed it, not
  from key presses. An approval clears "needs you" only when that tool call gets its result (a parallel call's
  result no longer does), and answers and interrupts are noticed within 2 s instead of 20 s.
- T3 chats' background work comes from T3's own records, for every provider that reports it: work the agent waits
  on keeps the chat working (up to a day), a plain command or dev server for up to 30 minutes.
- Deleting a task drops the apps saved for it while parked.
- App icon (TaskDock had none, so banners showed a blank square).
- A Phi Space that TaskDock creates gets the template's emoji as its icon instead of a random one.

### Fixed
- Browser tabs are saved as they change during the task, not only at the moment it ends, so they survive
  the browser quitting and tasks started by an older extension.

### Changed
- The finish prompt now asks "Where did you stop? What's next?".

## [0.3.0] - 2026-11-06

First public release. Source only (no prebuilt app).

### Added
- Redesigned picker: opens as a small pill and springs open; light frosted shell with opaque "cloud" cards.
- Edit templates right in the picker: icon grid, name, and an in-app app chooser with **Use Current Setup**.
- Reorder templates by dragging (picker and Templates window); right-click to edit or delete.
- Calendar suggestion: the current event (Apple, Google via Internet Accounts, and other macOS calendars) is
  suggested at the top of the picker after **Connect Calendars…**.
- Templates window redesign with an icon picker and the same app chooser.

### Changed
- Follows the system light/dark appearance.
- The goal is optional: press ↩ on an empty field to start immediately.
- Long template lists scroll inside the picker.
- Browser bridge rejects messages over 64 KB.

### Fixed
- Picker briefly opening in the wrong theme.
- Text jumping when the app chooser closes.
- Faint task name and "Choose apps" text on the frosted panel.
- Picker cut off at the bottom with many templates.

## [0.2.0] - 2026-11-05 (unreleased milestone)

### Changed
- A browser task now opens one fresh window and minimizes the other windows, unloading their tabs until you finish.

### Removed
- Per-template URLs and distracting-site nudges.

## [0.1.0] - 2026-11-05 (unreleased milestone)

### Added
- Menu bar app with ⌃⌥Space picker, task templates, and the goal shown in the menu bar.
- Hides non-task apps and shows only the template's apps in the Dock; restores both on finish.
- Apple Shortcuts on start and finish; "where did you stop" notes.
- Browser extension (Helium, Brave) connected over a local WebSocket.

[0.3.0]: https://github.com/itsaibarr/TaskDock/releases/tag/v0.3.0
