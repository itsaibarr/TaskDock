# Spec: Hand off to the agent

## Problem
On big tasks the AI agent runs 20+ minutes. You stay half-waiting the whole time: the agent window
is in view, part of your attention checks on it, so it *feels* like work, yet nothing else gets
started. Research calls this attention residue (Leroy 2009): expecting an interruption costs
focus by itself. Willpower doesn't fix it. Taking away the reasons to watch does.

Three things keep you watching:
1. **No "done" signal.** You can only find out by looking.
2. **Deciding what to do next costs effort** at the exact moment your head is still in the prompt.
3. **Leaving feels risky.** What if it needs me? What if I lose my place?

## Approach
TaskDock already switches tasks, hides other apps and saves/restores state. Add one thing: it
knows when an agent is working for a task, and acts at the moment half-waiting starts.

1. **Know.** T3 Code's own records (every provider: Claude, Codex…) and, for chats outside T3, Claude
   Code hooks tell TaskDock when you send a prompt, when the agent stops and when it needs you. Each
   chat belongs to the task you were in when you sent the prompt.
2. **Offer the switch when half-waiting starts.** If the agent is still working 2 minutes after
   the prompt, and you're still in that task, the picker opens by itself:
   > **Agent is on it.** Coding · TaskDock. What will you do meanwhile?

   Pick a task to switch (apps hidden, state saved like any switch); Esc keeps watching and
   nothing else appears for that run. Short replies (under 2 min) never trigger it.
3. **Park, don't close.** A task whose agent is working is *parked*: switching away hides its apps
   but never quits them, so the agent's window (T3 Code, Terminal…) keeps running.
4. **Signal, don't pull.** While agents work, the menu bar shows ⧗ (finished: ✓, needs you: !). When one
   finishes: a quiet notification (no sound): "Coding · TaskDock: agent finished". When one needs
   you (permission, question): a normal notification: "Coding · TaskDock: agent needs you".
   Clicking either switches back to that task.
5. **Make coming back easy.** Parked tasks show their state in the picker and the ◎ menu:
   "Agent working · 14m" or "Agent finished 3m ago"; clicking the menu row returns to the task.
   Returning clears a finished run. The nudge picker leaves out the parked task itself.

Several agents on different tasks work the same way, each tracked by its own session.

## How events reach TaskDock
Two sources, one set of rules: each turns what it sees into the same events (`Agent.Event`), and
`Agent.apply` alone decides what they mean.

**T3 Code** (`T3.swift`, every query in that file): read every 2 s from its database, read-only (see
"Reading T3 Code directly"). A chat T3 knows is T3's: hook events for its Claude session are dropped, so
nothing counts twice, background work included (T3 records it). A new T3 chat's first hook event, which can arrive
before T3 has recorded the chat, is looked at again after 3 s.

**Claude Code hooks** (chats outside T3, or everything when T3 can't be read):
- The hook command is the TaskDock binary itself: `TaskDock.app/Contents/MacOS/TaskDock agent <event>`.
  In that mode it reads the hook's JSON from stdin (session id), posts a local distributed
  notification to the running app, and exits 0 at once. No port and no script, and nothing to
  install besides the hook entries.
- The hook also finds the chat's app (T3 Code, Terminal…) by walking up its parent processes.
- Events: `UserPromptSubmit` → working, `Stop` → finished, `PermissionRequest` → needs you,
  `SessionEnd` → forget. The hook passes ids and states only: the prompt's id (`prompt_id`), and for a request the
  tool's name with a hash of its input, never the input or the prompt.
- What sends no event is read from the chat's transcript as it grows, every 2 s (each run keeps how far it has
  read): who wrote the prompt (Claude Code writes it just after the hook, so the prompt waits 1 s), your interrupt,
  your answer to a request (that tool call's result), delegates going out and reporting back. An older version's
  `PostToolUse` hook is removed on launch.
- **Setup:** ◎ menu → "Connect Claude Code…" adds these hooks to `~/.claude/settings.json`.
  It keeps every existing hook, backs up the original once, and is removed by the same button.
- If TaskDock isn't running or anything fails, the hook still exits 0. Claude Code is never slowed
  or blocked.

## Verified in T3 Code (logging hook, 2026-11-08)
- Hooks fire in T3 Code chats, and settings changes reach running chats without a restart.
- `UserPromptSubmit` carries `session_title` (the chat's title). `Stop` carries `background_tasks`.
- A question to you (AskUserQuestion) fires `PermissionRequest`, not `Notification`, even in bypass mode.
- An interrupt fires no `Stop`; the transcript gets a user line `[Request interrupted by user…]`.
- When background work ends, the agent's wake-up fires `UserPromptSubmit` (then `Stop` again).

## Verified in Claude Code and T3 (2026-11-09)
- **Who typed a prompt.** Each transcript prompt line has `promptId` (the hook's `prompt_id`), `entrypoint` and
  `origin`. In a terminal (`entrypoint: cli`) a typed prompt is `origin.kind: human`; wake-ups are
  `task-notification`. T3 and the SDK record every prompt as `promptSource: sdk` with no origin, so there it
  says nothing and key presses still decide. The hook fires before the line is written (seen with a probe hook).
- **Which call a request is about.** `PermissionRequest` has `tool_name` and `tool_input` but no `tool_use_id`
  (Claude Code hooks docs). The transcript's `tool_use` has the same name and input, so a hash of both finds it;
  its `tool_result` (allowed or denied) is the answer.
- **Background work in T3.** Provider threads carry `pendingBackgroundTasks` (`kind`: `command`, `monitor`,
  `subagent`, `background_task`; `awaited` when the agent waits on it). T3 itself holds a chat open while one is
  awaited or is a subagent or background task (`backgroundWorkHoldsCompletion`), not for a plain command or monitor.
  Claude, OpenCode and Muse chats report it. Codex doesn't: its background terminals are only stopped on interrupt,
  and the current T3 has no Codex wake-up (the one Codex `background_command` wake-up on record is from an older
  version, 2026-10-20). So a Codex turn's end is final, and "finished" is right.

## Verified live with the installed app (2026-11-08)
- A real T3 prompt was recorded as yours, with T3 Code as its app: the key press and front app were read correctly.
- About 2 minutes later the picker opened by itself: "Agent is on it · Mac Focus Workspaces and Task Flows".
- A real `delegate_task` kept the chat working until the delegate reported back.
- Banners were blocked because macOS had notifications off for TaskDock. The menu now shows **Allow Notifications…** in that case.
- Once notifications were allowed, clicking a real banner opened its chat and brought T3 Code to the front.
- Starting a template that includes Phi created its Phi Space through Phi's "New Space…" menu, within about a second, and switched Phi to it.

## Reading T3 Code directly (spike, 2026-11-08, T3 server 0.1.7, migration 79)

**Decision: read T3's database read-only.** One small adapter (`T3.swift`) opens
`~/.t3/userdata/statev2.sqlite` read-only, keeps the connection, and queries it every 2 s (about 1 ms each;
simpler than watching the `-wal` file, which T3 rewrites on every checkpoint). It's on only while Claude Code is
connected (◎ menu), like the hooks. It requires `effect_sql_migrations.migration_id` at 79 or newer and queries
that still run; a unit test opens the live database to check exactly that. Older schema, missing file or any query
error → the adapter goes quiet and the hooks work as before. Dev runs on sample data read a test copy
(`t3.sqlite` in the data folder), never the real one.

Why not the other two:
- **Local server** (`127.0.0.1:3773`): every HTTP path returns the web app's page; the real API is a
  WebSocket that needs a paired bearer or DPoP token. Pairing hands out broad scopes (operate chats,
  write files, terminals), far more than TaskDock should hold, and needs a user pairing step.
- **MCP tools** (`t3_thread_list`, `task_status`): served to agent sessions T3 starts, not to outside apps.

What the database gives (checked against live rows; no message text read):
- **Who sent a prompt.** `actor_kind` is `server` on every event now, so it doesn't help. Instead each
  run (`orchestration_v2_projection_runs`) names its `userMessageId`, and that message's payload says
  who made it: `createdBy: user, creationSource: web` = you (Send button, dictation or ↩ alike);
  `createdBy: user, creationSource: server` = T3 resuming a chat by itself (they come in bursts on the hour);
  `createdBy: agent, creationSource: provider` with `notification.source.kind` = a wake-up;
  `createdBy: agent, creationSource: mcp` with `senderThreadId` = a delegate's first prompt.
- **Which chats are sub-threads.** Thread payload `lineage.parentThreadId` and
  `lineage.relationshipToParent: subagent`; `createdBy: agent` for threads an agent made.
- **Working / finished / interrupted.** Run `status`: `preparing`, `running`, `waiting`, `completed`,
  `interrupted`, `failed`, `cancelled`. Covers every provider (claudeAgent, codex and opencode runs all present).
- **Delegates.** `orchestration_v2_projection_subagents` has one row per delegate with exact `status`
  and `completion_delivery_state` (`claimed` → `delivered`). The parent run completes *before* the
  delegate reports; the report then starts a new run. So a chat is working while a run is active or
  a delegate of it is running or not yet delivered. `mode: wait` timeouts and long turns don't matter.
- **Needs you.** `orchestration_v2_projection_runtime_requests`: `kind` (`user_input`, `command`),
  `status` `pending` → `resolved`. Its payload also holds your answers, so TaskDock reads only
  `kind`, `status` and ids.
- **Hook ↔ T3 chat.** The Claude hook's `session_id` is
  `provider_threads.payload.nativeThreadRef.nativeId`; its `thread_id` is the T3 chat.
- **Chat on screen.** Thread payload `lastVisitedAt` is refreshed about every 10 s for the chat open in
  T3's window, so the most recently visited chat is the one on screen. (A visit after a chat finished
  doesn't prove you saw it: the refresh continues while T3 is hidden.)
- **Title.** `orchestration_v2_projection_threads.title`.
- **Background work.** `orchestration_v2_projection_provider_threads.payload.pendingBackgroundTasks`; TaskDock reads
  only each entry's `kind` and `awaited`, never its description, and only on the provider thread whose
  `last_run_ordinal` is the chat's latest run (a chat that switched provider keeps its old one, now done). An interrupted
  chat ends even if background work is left running; a delegate still out keeps it going, as before.
- **Remote machines.** `peer_environment_links` lists linked machines but their chats live in their own
  server's database, not here. Stays a limit (no linked machines today).
- `orchestration_v2_events` is empty; the live log is `orchestration_events` (pruned to the last ~20k).
  TaskDock needs only the projection tables, not the log.

## Risk cases
Tested by: **E** `scripts/e2e-agent.sh` (real hook binary → app; T3 from a test database with T3's schema;
input and frontmost app stubbed), **U** unit tests, **L** observed live in T3, **D** documented limit.

| # | Case | What TaskDock does | Test |
|---|---|---|---|
| 1 | **Several chats at once** (5 projects in T3) | Each chat is its own run, labelled with its chat title. Every prompt you send can nudge; one picker covers all runs already working, so a burst of prompts nudges once and a later prompt nudges again. One menu row and one notification per chat. The menu bar shows every state present (`! ⧗ ✓`), so one finished chat doesn't hide four still working. | E U |
| 2 | **No TaskDock task active** (just using T3) | Still tracked. The nudge offers to start a task; returning brings the chat's app to the front. | E |
| 3 | **You're typing when the nudge is due** | Waits until no key press for 10 s (an ↩ mid-sentence could switch tasks), and while the picker is already open. | E |
| 4 | **Who sent a prompt** | **T3 chats:** T3 records who wrote it. Yours whether you pressed ↩, clicked Send or dictated; a wake-up (background work done, a delegate reporting) or a delegate's own chat never is, whatever you're typing. **Claude Code in a terminal:** Claude Code records it (`origin: human`), so a prompt you typed is yours and anything else isn't, whatever you're typing. **Other chats (hooks), or an older Claude Code:** sent if a key was pressed in the 5 s before it with the chat's app in front; wake-ups (`<task-notification>`, `Delegated task node`, flagged by the hook without passing the text) never count. Either way a chat you sent to stays yours: its wake-ups stay with its task and notify, but don't nudge. Chats you never prompted protect their app but don't nudge, notify, park a task or show, unless they need you (5). | E U |
| 5 | **A sub-thread needs you** | "Needs you" notifies and shows for every chat, prompted or not: it blocks your work either way. | E U |
| 6 | **Interrupted** (Stop button) | T3 chats: the run's status says so. Hooks (no `Stop` comes): Claude Code's interrupt line as the transcript's last message, within 2 s. Ends the run quietly (marked seen, still yours). A tool result quoting the line doesn't count. | E U |
| 7 | **Turn ends while background work or a delegate runs** (a test, a build, council) | Delegates: T3 chats use T3's delegate records (exact: running until the report is delivered, any length, `mode: wait` timeouts included). Hooks count calls and reports in the transcript as it grows, from the call to its `Delegated task node` report; one that failed to start, or a `mode: wait` one that answered in place, never counts; one that timed out counts until its report. No time cap for hooks; a lost one is dropped by the 3-hour rule. T3 keeps a chat tracked while its run, a delegate or held background work is still going, up to a day, so a stuck record can't pin it. Background work: T3 chats use T3's own list for any provider that reports it; work the agent waits on, a background agent or task has no 30-minute cap (as in T3; the 24-hour tracking limit still applies, so an entry T3 leaves behind can't pin a chat longer), a plain command or monitor keeps it working for up to 30 minutes (a dev server never ends) → finished. Hooks: `Stop` with background tasks, same 30 minutes. The nudge still comes and there's no early "finished". Codex chats have no background wake-ups in T3, so their turn's end is final. | E U L |
| 8 | **Agent asks you something** (question or approval) | "Needs you" with a sound. Answered → working again: T3 chats as soon as T3 marks the request resolved (within 2 s); hooks when that tool call's result is in the transcript, allowed or denied (within 2 s); a parallel call's result doesn't count. If the call isn't in the transcript (a sub-agent's call lives in its own file, or its input reached the hook changed), or with an older hook: any message after the request. | E U L |
| 9 | **The agent's app must not quit** | A task with a working run is parked: switching away or Finish only hides its apps; they're handed back when the task starts again, and a later Finish quits them. An app is quit only when nobody else owns it: the current task, a parked task (two tasks can share an app) or a working chat (T3 Code, Terminal; any working T3 chat, Codex included, protects T3). Parked apps are saved to `parked.json`, so this holds across a restart. | E |
| 10 | **You watched it finish** | Marked seen (its row, ✓ and banner go) when you return to or finish its task, or click it, and: a T3 chat while it's the chat open in T3 with T3 in front; another chat once its app is in front in its task. A seen chat stays yours, so a later wake-up still notifies. | E |
| 11 | **TaskDock restarts mid-run** | Runs are saved to `agents.json` and reloaded. On its first read T3 tracks chats already working (not as sent by you) and reports ones that finished meanwhile. | E (file written) U |
| 12 | **Run never reports back** (crash) | Forgotten 3 hours after its last event (a T3 chat: 3 hours after it leaves T3's list of recent or working chats). | U |
| 13 | **App moved / rebuilt** | On launch the installed app (not a dev build) points the hooks at its current location and drops hooks it no longer uses. While it's rebuilt the hook fails silently (`|| true`). | U |
| 14 | **Settings file unreadable** | Left alone; Connect does nothing and logs why. | — |
| 15 | **T3 can't be read** (schema change, file gone, T3 not installed) | Hooks work as before; no crash. Chats T3 was tracking keep protecting T3 until they're dropped (3 hours), so nothing is quit wrongly. Reading resumes when the database reads again; a chat the hooks tracked meanwhile moves over to T3 (still yours), so it isn't counted twice. | E U |
| 17 | **A chat deleted in T3 while working** | Forgotten at once, not left working. | U |
| 18 | **T3 resumes chats by itself** (after a usage limit) | Not yours: no nudge, no parking. | U |
| 19 | **A task is deleted while parked** | Its parked apps aren't kept for it any more (dropped at once, and on launch). | — |
| 16 | **You click away from the nudge** | The picker closes and the ◎ menu shows **Pick a Task Meanwhile…** while that task's agent still works; it doesn't pop up again. Esc leaves nothing. | E |

### Known limits (deliberate)
- **Remote machines** linked to T3: their chats live in that machine's T3 database, and its hooks fire there.
  TaskDock doesn't see them. Reading a peer's server needs a paired token with broad access; not worth it.
- **Claude Code outside T3, "seen"** is per app, not per chat: telling chats in one terminal apart would mean
  reading other apps' window titles. (Terminal Claude was used once on this Mac since September.)
- **When T3 can't be read**, T3 chats fall back to the hooks: Codex chats aren't seen and case 4 uses key presses
  (T3 records every prompt the same way in the transcript).
- **Timing**: T3 chats and hook-path answers and interrupts are noticed within 2 s; a terminal prompt 1 s after
  the hook.
- Not tested automatically: real banners and clicking them (needs the signed app), real key/frontmost detection.
  T3's behaviour is tested from a copy of its schema; one unit test runs the queries on the live database.

## Acceptance
- In Coding · TaskDock, send a prompt that runs > 2 min → the picker opens with the "Agent is on it"
  header. Pick Further Math → it switches; T3 Code is hidden, not quit, and the agent keeps going.
- A reply that finishes in under 2 min → nothing appears.
- Esc on that picker → no second prompt for that run. Clicking elsewhere → a quiet **Pick a Task Meanwhile…**
  in the ◎ menu instead.
- Sent with T3's Send button or by dictation → counts as yours and nudges. A T3 delegate's chat never does;
  its parent finishes only after every delegate reports. A Codex chat in T3 parks its task, protects T3 Code and
  notifies when it finishes. An answered approval is working again at once.
- Agent finishes → quiet notification; the menu count drops; clicking returns to Coding · TaskDock
  with its saved state.
- Agent asks for permission → "needs you" notification.
- `scripts/e2e-agent.sh` passes (see the Test column above for what it covers).
- TaskDock quit → Claude Code works normally, hooks return instantly.
- "Connect Claude Code" leaves the existing gstack/mempalace hooks intact; removing restores the file.
