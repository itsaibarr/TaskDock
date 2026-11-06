# Changelog

All notable changes to TaskDock. Versions follow [Semantic Versioning](https://semver.org/) (pre-1.0: minor versions may change behavior).

Only 0.3.0 has published source. 0.1.0 and 0.2.0 were development milestones before the project
was put under version control; their source was not kept, so they have no tags or downloads.

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
