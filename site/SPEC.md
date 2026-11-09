# TaskDock landing page: spec

Status: draft for the approval gate. Copy marked **[DRAFT, first person]** needs the author's approval.

## Objective

One static page at `site/index.html` in the public TaskDock repo. It shows TaskDock working (visual story first), proves the engineering in one compact section, and doubles as a portfolio piece. Primary action: **Get it on GitHub**. Every claim traces to `README.md`, `CHANGELOG.md` or the source.

Readers: developers who might build and use it; people evaluating the author's work.

## Stack

Plain HTML, CSS and vanilla JS. No framework, build step, npm dependency or CDN script, matching the repo's zero-dependency rule. Fonts self-hosted in `site/fonts/`. Images in `site/assets/` as AVIF with WebP fallback, width and height set.

```
site/
  index.html   styles.css   main.js
  assets/      (processed screenshots, og.png)
  fonts/       (Geist, Newsreader, DM Mono subset woff2 + OFL.txt each)
  DESIGN.md    SPEC.md      COUNCIL.md   tasks/plan.md   tasks/todo.md
```

Hosting: GitHub Pages from `site/`, only after explicit approval (D4 step; rollback = disable Pages and revert the workflow commit).

## Information architecture and copy

Nav, sticky, white: `◎ TaskDock` · How it works · Agents · Under the hood · **View on GitHub** (outline button, →).

### 1. Hero (`#top`, white paper)

- H1, two-tone: **One hotkey, one task.** <span grey>The rest can wait.</span>
- Serif lead: "Press ⌃⌥Space and pick a task. Only its apps stay visible and in the Dock, and your browser opens a fresh window. When you finish, everything goes back the way it was."
- Buttons: **Get it on GitHub** (filled) · **See how it works** (outline, anchors to #how).
- Stage 1, cropped by the section's bottom edge: the real picker screenshot (`picker-goal-light` or `picker-list-light` from `shots.sh`) on glass, amber glow behind it.
- Stage corner labels: `⌃⌥SPACE` · `MACOS 15+` · `V0.3.0` · `MIT`.

### 2. How it works (`#how`, white): 01/02/03 boxes

- H2: **Start, switch, finish.** <grey>Your Mac follows.</grey>
- 01 **Focus**: "The task's apps open. Every other app is hidden, not quit, and the Dock shows only the task's apps."
- 02 **Resume**: "Pick the task again and ↩ reopens its tabs, documents, Obsidian note and the note you left. Start fresh skips it."
- 03 **Restore**: "Finish brings back the apps you had, quits the ones TaskDock opened so they can still ask to save, and restores your exact Dock."

### 3. Focus (`#focus`, warm paper)

- Eyebrow: `■ FOCUS`. H2: **Your Dock,** <grey>down to one task.</grey>
- Lead: "Pick a template and only its apps stay in the Dock. Everything else is hidden, not quit, so nothing loses its place."
- Stage: before/after Dock illustration (labelled `ILLUSTRATION`), toggled by a stage pill "Before / During task" (keyboard operable). App tiles are neutral glyph chips with app names, not Apple icons.
- Items:
  - **Hidden, not quit.** "Apps that were open before the task stay running. They come back when you finish."
  - **Shortcuts on start and finish.** "Each template can run an Apple Shortcut when it starts and another when it ends."
  - **A fresh browser window.** "With the extension, your browser opens a new window and unloads the other windows' tabs until you finish."

### 4. Pick up where you left off (`#resume`, warm paper)

- Eyebrow: `■ RESUME`. H2: **Pick up** <grey>where you left off.</grey>
- Lead: "Finishing or switching saves what the task had open. Next time, ↩ reopens it all."
- Stage: real `picker-goal-light` screenshot showing the sample "Writing ✍️" template's resume card ("page 45, exercise 4.3 done; next: try 4.4 before reading 4.5", 3 tabs, the Calculus PDF, "Week 3 notes"). Verify the screenshot shows this before using the caption.
- Items:
  - **Browser tabs.** "The task window's tabs are saved as they change, so they survive the browser quitting."
  - **Documents and notes.** "Files open in Preview, TextEdit, Pages and other scriptable apps, and the note open in Obsidian. Preview reopens a PDF at the page you were on."
  - **Your own note.** "Finishing asks “Where did you stop? What's next?” and shows your answer next time."

### 5. Agent hand-off (`#agents`, white): gate decision: show as "next release" or omit

- Eyebrow: `■ AGENTS` + tag `NEXT RELEASE`. H2: **Waiting on an agent?** <grey>Start something else.</grey>
- Lead: "When an AI agent is still working 2 minutes after your prompt, TaskDock offers another task. The agent's task is parked, and a banner calls you back."
- Scroll-linked showcase (list left, stage right; on mobile, each step stacks with its own stage card). Steps:
  1. **You send a prompt.** "Claude Code hooks tell TaskDock the chat started working. No prompt text or code leaves the hook."
  2. **Two minutes pass.** Dot-matrix `2 min`. "The picker opens with “Agent is on it” and “What will you do meanwhile?”. With several chats it reads “3 agents are on it”."
  3. **The agent's task is parked.** "Its apps are hidden, never quit. The menu bar shows ⧗ while agents work."
  4. **It finishes.** Dot-matrix `23 min`. Banner recreation: title = chat name, second line = "✍️ Writing", body = "Done after 23 min". Menu bar ✓. Alternate: "Waiting for your answer" with !.
  5. **Click back.** "The banner takes you back to the task and the chat's app."
- Footnote: "Works with Claude Code hooks. In T3 Code it also reads T3's own records, read-only, for every provider."
- Stage visuals are recreations labelled `DEMO` (the screenshot script has no nudge or banner capture).

### 6. Works with (`#works-with`, warm paper): giant hairline index

Left: a stage card with a small caption ("Every integration is optional."). Right: list, inactive grey, hover/focus ink + ↗. Each row expands a one-line description (visible on mobile).

| Item | Line | Link |
|---|---|---|
| Phi Spaces | Switches Phi to the Space named like the template, and creates it with the template's emoji if missing. | phibrowser.com |
| AeroSpace | Remembers each app's workspace on finish and moves the windows back on start. | github.com/nikitabobko/AeroSpace |
| Browser extension | Opens a fresh window and unloads the other windows' tabs. Chromium 116+. | README#browser-extension-optional |
| Calendar | Suggests the event happening now, or in the next 15 minutes, at the top of the picker. | README#calendars-optional |
| Apple Shortcuts | Runs a Shortcut when a task starts and another when it ends. | README#features |
| Claude Code | Hooks report when an agent works, finishes or needs you. (hand-off only) | README#t3-code-and-claude-code-optional |
| T3 Code | Reads T3's own records, read-only, for every provider. (hand-off only) | README#t3-code-and-claude-code-optional |

### 7. Under the hood (`#engineering`, white)

- Eyebrow: `■ UNDER THE HOOD`. H2: **No Dock API,** <grey>so it treats yours carefully.</grey>
- A two-column hairline table (label in mono, text in sans):
  - DOCK: "macOS has no public Dock API. TaskDock rewrites the `com.apple.dock` preferences and restarts the Dock. Changes are queued, wait for the Dock to settle, and are read back and retried."
  - SAFETY: "The pre-task Dock is saved before anything changes. If TaskDock quits mid-task, reopening it resumes the task, so Finish still restores." + one-line undo in a code block.
  - HOTKEY: "Carbon `RegisterEventHotKey`, so the hotkey needs no Accessibility permission."
  - BROWSER BRIDGE: "A loopback-only WebSocket on 127.0.0.1:47123 that accepts `chrome-extension://` origins. The Manifest V3 extension unloads tabs with `tabs.discard`."
  - PRIVACY: "All data stays on your Mac. Nothing is sent over the network."
  - TESTS: "XCTest unit tests, extension tests with `node --test`, and end-to-end scenarios that drive the real app."
  - APP: "SwiftUI and AppKit, `MenuBarExtra`, and a borderless panel for the picker. No third-party dependencies."
- Limits line: "Known limits: hidden apps keep their Dock icon, the Dock flickers for about a second, the hotkey is fixed, and builds are ad-hoc signed, not notarized." Link: "All limits in the README".

### 8. Who made it (`#author`, warm paper) **[DRAFT, first person]**

"I'm Aibar Yerzhuman. I built TaskDock because I kept losing focus to clutter: every app and tab from every task open at once. The agent hand-off came later. When I gave a coding agent a long task, I sat half-waiting, busy without doing anything useful. Now switching to something else is the easy default, and TaskDock calls me back when the agent is done."
Links: GitHub · X · LinkedIn.

### 9. Close (`#install`, stage)

- H2 (white on stage): **Build it from source.**
- Code block: `./scripts/build.sh` / `open build/TaskDock.app`.
- Line: "Early software. Source only, ad-hoc signed, not notarized. It rewrites your Dock preferences, so read Safety and undo first."
- Bevelled stage CTA: **Get it on GitHub**. Secondary text link: "Read the changelog".

### 10. Footer (white)

Mono grey labels. PRODUCT: How it works, Agents, Works with, Under the hood. PROJECT: GitHub, Changelog, Security, MIT License. AUTHOR: GitHub, X, LinkedIn. Bottom line: "MIT © 2026 Aibar Yerzhuman".

## Interactive demo (picker)

In the hero stage, a clickable picker recreation replaces the static screenshot only if it matches the real UI pixel-for-pixel in strings, widths (320 → 480), radii (24 shell, 18 cards, 12 rows, 7–9 chips) and states. Otherwise the hero keeps the screenshot and the demo lives in the hand-off showcase step 2. Behaviour: type to filter templates, ↑↓ to choose, ↩ to select, Esc to close; strings verbatim ("Start a task…", "↑↓ choose · ↩ select · esc close", "What will you finish? (optional)", "↩ start · esc close", "New Template “query”", "Agent is on it", "What will you do meanwhile?"). Labelled `DEMO`, `aria-live="polite"` announces the state, reduced-motion path uses fades.

## Assets

- From `scripts/shots.sh` (needs approval to run: it takes keyboard focus briefly): `picker-list-light`, `picker-goal-light`, `picker-finish-light`, `menu-task-light`. Output to `.context/shots/` (gitignored); processed AVIF/WebP to `site/assets/`.
- `og.png` 1200×630: hero headline + stage, rendered from the page.
- No third-party images.

## Metadata

`<html lang="en">`, title "TaskDock: one hotkey, one task on your Mac", description "TaskDock is a macOS menu bar app. Press ⌃⌥Space, pick a task, and only its apps stay in view. Finish, and everything comes back.", og:title/og:description matching, og:image `assets/og.png`. `canonical` and `og:url` stay empty until a deploy URL is approved.

## Tests (each fails before its section exists)

A Playwright script outside the repo (`.context/checks/page.spec.mjs`, run with the harness's Playwright) that, per section:

- the section landmark and heading exist, with exact copy from this spec;
- all links resolve (local anchors exist; external links return < 400 once, cached);
- console has no errors, no failed requests;
- `document.documentElement.scrollWidth <= innerWidth` at 320, 390, 768, 1024, 1440, 1920;
- one h1, no skipped heading levels;
- demo: keyboard path reaches every state; `prefers-reduced-motion` emulated run passes.

Plus axe-core (from the harness), Lighthouse mobile, and the sight loop for every visual change.

## Boundaries

- Touch only `site/`, one `.gitignore` line (`.context/`) and, if approved, a Pages workflow and a README link.
- Never touch `Sources/`, `extension/`, `Tests/`, existing scripts, or the main working copy.
- No commits unless asked. No push, PR, Pages or deploy without explicit yes.

## Build changes after the gate (2026-11-09)

- The author asked for Intercom's typography, colors, accent, image type, tones and transitions to be copied in full. DESIGN.md records what was copied and what was matched instead (commercial fonts, Intercom's art).
- Stages are Intercom-style inset panels with original blue fibre art, with TaskDock's glass UI on top, replacing the slate gradient stages.
- The hero holds the interactive picker demo (it matched the real UI closely enough); Resume uses real screenshot crops.
- Added headings: "Works with the tools you already use." and "Why I built it.".
- Closing buttons follow the paper rule (solid and line), so the bevelled stage button is not used.
- Claude Code and T3 Code rows link to the tools' sites, because the public README on `main` has no section for them yet.
