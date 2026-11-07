# Plan: Resume where you stopped

1. **Model** — `Template.resume: Resume?` (`savedAt`, `tabs: [String]`, `items: [Resume.Item{app, url}]`).
   Optional so old files decode. Test: old JSON decodes; round trip.
2. **Capture** (`Snapshot.swift`) — AppleScript reader for scriptable apps (async `osascript`), Obsidian
   workspace reader (pure parse function + test). `Store.finish` and `Store.start` (switching) capture
   for the template being left. `Info.plist`: `NSAppleEventsUsageDescription`.
3. **Browser** — extension `finish()` sends `{type:'tabs', template, urls}` for windows opened during
   the task (pure `taskTabs()` in lib.js + node test); Bridge hands them to Store.
   State message carries `template` and `tabs`; `adoptTaskWindow` opens them.
4. **Restore** — `Store.start(resume:)` opens saved items with their apps.
5. **UI** — picker goal view: resume card + "Start fresh"; row note shows "Resume · 2h ago"; finish
   prompt "Where did you stop? What's next?". Screenshots light/dark via `scripts/shots.sh`.
6. **Docs** — README (feature, permissions, privacy), CHANGELOG Unreleased.

Gates per step: `./scripts/test.sh`, `./scripts/build.sh` (0 warnings). Then /code-review, /simplify,
and a live check with your Further Math template.
