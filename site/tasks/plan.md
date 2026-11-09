# Build plan: TaskDock landing page

Vertical slices. Each task builds one section end to end (HTML, CSS, JS if any, copy, checks) and ends with the sight loop
(before/after screenshots at 1440×900 and 390×844 plus the diff mask) and a passing check script. No commits unless asked.

Serve: `python3 -m http.server 4173 --directory site`. Checks: `.context/checks/page.spec.mjs` with the harness Playwright.

## Phase 0: foundation

**T0. Assets and skeleton.** Run `scripts/shots.sh .context/shots` (after approval; it takes keyboard focus). Subset and
self-host Geist, Newsreader 300, DM Mono with OFL files. `index.html` skeleton with metadata, landmarks, nav; `styles.css`
with tokens from DESIGN.md; empty `main.js`. Write the check script with all sections' assertions (all failing except nav).
- Accept: fonts load with no failed request; nav passes keyboard and 320px checks; metadata gate passes except canonical/og:url (empty by decision).

**T1. Stage and glass primitives.** `.stage`, `.glass`, `.btn-bevel`, corner labels, dot-matrix numeral, fallback for
no `backdrop-filter` and `prefers-reduced-transparency`. Rendered on the token sheet first.
- Accept: white text on every glass area ≥ 4.5:1 (measured); ≤ 3 blurred layers per viewport; fallback screenshot captured.

## Phase 1: sections (one per task, in page order)

**T2. Hero.** Two-tone H1, lead, buttons, stage 1 with the picker screenshot, cropped by the section edge.
**T3. How it works.** 01/02/03 boxes, stacking under 768px.
**T4. Focus.** Before/after Dock illustration with a keyboard-operable toggle, three items.
**T5. Resume.** Resume-card screenshot stage, three items.
**T6. Agent hand-off** (only if approved). Scroll-linked showcase via IntersectionObserver (no scroll-jacking), recreations of
the nudge picker, menu bar glyphs and the banner; mobile stacks steps. Reduced-motion path.
**T7. Works with.** Hairline index with hover/focus ↗ and per-row line.
**T8. Under the hood.** Hairline table, undo code block, limits line.
**T9. Who made it, Close, Footer.** First-person copy stays marked DRAFT until approved.

Each accept: section copy matches SPEC.md exactly; check script green for that section; no horizontal scroll at 320/390/768/1024/1440/1920;
sight loop diff described.

## Phase 2: demo and polish

**T10. Picker demo** (hero or hand-off step 2, decided by fidelity): filter, ↑↓, ↩, Esc, nudge state; aria-live; reduced motion.
- Accept: side-by-side with the real screenshot at 1× shows matching strings, widths and radii.
**T11. Polish and gates.** de-feel pass, de-a11y/axe (no serious issues), Lighthouse mobile, og.png, reduced-motion sweep.

## Phase 3: review

**T12. Council loop** (Opus 5.5 on claudeAgent + latest GPT on codex, high effort) until both APPROVE on one frozen build; ledger in `COUNCIL.md`.
**T13. /code-review, then /simplify.** Hand back with evidence.

## Risks

- Glass contrast on the lighter top-right of the stage gradient: keep text-bearing tiles on the darker half, measured in T1.
- The picker recreation may drift from the real UI: fall back to screenshots (allowed by the brief).
- Fonts: Geist at -0.04em may feel tighter than Saans at 100px; tune tracking between -0.035 and -0.04em in T2 with screenshots.
