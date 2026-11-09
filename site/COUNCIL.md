# Council ledger

Members: Claude (`claude-opus-5-5`, claudeAgent provider) and GPT (`gpt-6-luna`, codex provider), high effort.

**2026-11-09: the author approved a Claude Opus–only Council** from round 4 on, because the GPT member was blocked by a Codex usage limit in rounds 1–3. Approval below means one member (Claude Opus) returned APPROVE. Criteria scored 1–10:
C1 reference fidelity · C2 layout · C3 typography · C4 spacing · C5 color and glass · C6 product presentation · C7 motion and interaction · C8 consistency · C9 coherence as TaskDock · C10 responsive.

| Round | Build | Member (model, effort) | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | C10 | Overall | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | bc5cc638475e | Claude `claude-opus-5-5`, reported effort "low (harness setting)"; requested high | 7 | 7 | 8 | 7 | 8 | 7 | 7 | 8 | 7 | 6 | 7.2 | NEEDS CHANGES |
| 1 | bc5cc638475e | GPT `gpt-6-luna`, high | no score | no score | no score | no score | no score | no score | no score | no score | no score | no score | no score | blocked: Codex usage limit until 2026-11-28 13:09 |
| 2 | d8c9f5c9000c | Claude `claude-opus-5-5`, effort not visible to the member (requested high) | 8 | 8 | 8 | 7 | 8 | 7 | 8 | 7 | 8 | 7 | 7.6 | NEEDS CHANGES |
| 2 | d8c9f5c9000c | GPT `gpt-6-luna`, high | no score | no score | no score | no score | no score | no score | no score | no score | no score | no score | no score | blocked: Codex usage limit until 2026-11-28 13:09 |
| 3 | fc75d85c7a44 | Claude `claude-opus-5-5`, reported effort "low (session setting)"; requested high | 8 | 8 | 8 | 7 | 8 | 8 | 7 | 7 | 8 | 7 | 7.7 | NEEDS CHANGES |
| 3 | fc75d85c7a44 | GPT `gpt-6-luna` | not run | | | | | | | | | | | known blocked until 2026-11-28 13:09; no substitute |
| 4 | 620547cabd6f | Claude Opus `claude-opus-5-5`, reported effort "low (session setting)"; requested high | 8 | 8 | 8 | 7 | 8 | 8 | 6 | 8 | 8 | 6 | 7.5 | NEEDS CHANGES |
| 5 | fe1fc6784ef8 | Claude Opus `claude-opus-5-5`, reported effort "low (session setting)"; requested high | 8 | 8 | 8 | 7 | 8 | 8 | 7 | 8 | 8 | 7 | 7.7 | NEEDS CHANGES |
| 6 | 3386f3dd5601 | Claude Opus `claude-opus-5-5`, effort not visible to the member (requested high) | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8.0 | **APPROVE** |

Round 1 counts as a one-member round only if the author approves; the GPT member was blocked, and no substitute was used.

### Round 1 findings (Claude)

Applied:
- HIGH: hero corner label overlapped (`⌃⌥` over "Space"): selector narrowed to `.corner-labels > span`.
- Dock illustration dimmed hidden apps, which macOS doesn't do: dimming removed, caption reworded.
- Dock caption was a flat box on the art: now glass, 12px radius, 8×12 padding, system font.
- Dock too small in its panel: 72px tiles at ≥901px.
- Agents panel glass tiles weren't labelled as illustration: "Illustration · next release" label added.
- Undo command clipped: broken over three lines.
- Closing dot grid: 3px accent squares every 180px (Intercom), hidden on mobile, masked out of the text column.
- Closing art tiles mostly beige: replaced with dense crops (`assets/tile-0..2`).
- Closing H2 raised to 80px desktop (`clamp(40px, …, 80px)`), -0.04em.
- Mobile hero: demo tag on white, art at 130vw.
- Index: one active row only (hover sets `aria-current`; `:hover` styling removed).
- Showcase: active step on inset, step titles 20/24.
- Panel labels on inset chips; Engineering H2 breaks at the tone change; hero demo padding 0; cursor sits on the banner; nav links grouped left; footer top border removed.

Rejected or changed:
- "Use the app's sample strings (Writing — chapter 3 …)": they contain em dashes, which the page copy rules forbid. DESIGN.md now says UI strings are verbatim and sample names are the page's own.

### Round 2 findings (Claude)

Applied:
- Agents steps 1 and 3: the finish card hangs under the menu bar item like the real dropdown (`align-self: start; justify-items: end; margin-top: -26px`), so it no longer reads as a pop-up.
- Step 5: the pressed banner keeps its 360px width (`.pressed { width: min(360px, 100%) }`).
- Mobile hero: art at 240vw so the arch sits behind the picker's glass.
- Close: padding reduced to `clamp(72px, 48px + 6vw, 136px)` now that the decoration is gone.
- Closed demo state: no glass panel (the app shows none).
- Resume chips: one row as in the app (`nowrap`, gap 5px, ellipsis guard).
- Works-with H2 breaks at the tone change.
- Undo command: path split with a shell-valid continuation (checked: resolves to `~/Library/Application Support/TaskDock/dock-original.plist`); 12px code on phones.

Checked, no change needed:
- Index focus ring: a real Tab press shows the 2px accent outline. The capture had used a scripted focus.

### Round 3 findings (Claude)

Applied:
- Start fresh / Resume no longer replays the card's entrance (`reveal` only on choose and open).
- Agents steps 4–5: the banner lands top right under the menu bar, like macOS.
- Nav at 320: the empty `<nav>` is hidden on narrow screens and buttons don't wrap.
- Showcase at 320: the cards zoom to .56 and fit.
- Hero at ≤700px: stage 400px tall, 40px top margin.
- Dock glass resizes during the View Transition (`view-transition-name: dock`) instead of cross-fading.
- Touch devices see "Interactive demo. Tap a task."
- Step 1 copy now says you stay in your task.
- Undo path back on one line; phones scroll the code block.

Rejected:
- Re-crop the resume screenshots to include the header row: that row sits on the app's translucent shell, which shows the green test backdrop from `shots.sh`. Cropping it in would put that tint on the page.

Status after three rounds: Claude scores 7.2 → 7.6 → 7.7, with no HIGH findings since round 1. GPT has been blocked in every round.

### Round 4 findings (Claude Opus; one-member Council approved by the author)

Applied (each was browser-tested by the reviewer, then re-checked here):
- HIGH: showcase cards clipped at 361–429px. The view column is `minmax(0, 1fr)` with zoom .6 at ≤520px and .54 at ≤360px; checked at 320, 390 and 414.
- Glass lost its blur during the step fade: the fade moved from the `.view` wrapper to the glass itself, so the material stays frosted.
- Dock View Transition stretched the snapshot and squared its corners: only the live element is drawn, without blur, while it moves.
- Mobile hero dead space: stage 320px at ≤520px, so the arch crown shows above the picker.
- Index rows: 9px/11px padding (79px rhythm, as on Intercom).

### Round 5 findings (Claude Opus)

Applied:
- MEDIUM: on ≤900px the showcase stage now sits above the step list (340px tall, 300px at ≤360px), so tapping a step changes what's on screen. Checked at 390: the card and the active step are visible together.
- Dock: Music and Calendar fade in after the glass has widened (150ms, 100ms delay); leaving icons exit in 100ms.
- Works-with card: the art is out of the grid flow, so the icon is centred on purpose (offset 0px).

### Round 6 (Claude Opus): APPROVE, 8.0/10, build 3386f3dd5601

No HIGH or MEDIUM findings. LOW follow-ups, not applied, so the deployed build is the approved one:
- Hero and closing buttons at 16px with 14px side padding (Intercom).
- Showcase step text at 16/24.
- "01/02/03" in Geist so the zero isn't slashed.
- Wider art behind the Focus and Resume panels at ≤520px.
