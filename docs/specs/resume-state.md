# Spec: Resume where you stopped

## Problem
After finishing or switching a task, coming back later means rebuilding the setup by memory:
which tabs, which book and page, which note — and what you were about to do next.

## Approach (adaptive = capture automatically what apps can tell us; ask the human only for intent)
Research on interrupted work (Leroy & Glomb 2018, "ready-to-resume plan"; Altmann & Trafton
on resumption lag) says a short "where I am / what's next" note is what cuts restart cost.
The machine can capture *where*; only you know *what next*. So:

On **Finish** and on **Switch Task**, TaskDock saves a snapshot on the template:
| Source | How | Permission |
|---|---|---|
| Browser tabs | Extension sends the URLs of the task's window(s) | none |
| Documents in scriptable apps (Preview, TextEdit, Pages, Keynote, Numbers…) | AppleScript: files of open documents | Automation, asked once per app |
| Obsidian | Active note from `<vault>/.obsidian/workspace.json` → `obsidian://open?path=…` | Documents folder, asked once |
| Your note | Existing "Where did you stop?" field, prompt changed to "Where did you stop? What's next?" | — |
| Anything else (VS Code, Antigravity…) | Nothing: those apps restore their own windows | — |

Preview remembers the page per PDF itself, so reopening the file returns to the page.

On next **Start** of that template: the picker shows a "Pick up where you left off" card —
your note, the saved items (tab/book/note names) and when it was saved. ↩ starts and reopens
everything (tabs open in the task's fresh browser window). "Start fresh" clears the snapshot.

## Out of scope (v1)
Window positions, scroll position inside web pages, screenshots, closing the task window on finish,
apps without AppleScript other than Obsidian.

## Acceptance
- Finish Further Math with 3 tabs, a PDF in Preview, a note in Obsidian → start it again → same 3 tabs
  in the new browser window, the PDF opens at the same page, the note opens, and the stop note is shown.
- Switching tasks saves the snapshot for the task being left.
- Old templates.json (no snapshot) still loads.
- Denied permissions only skip that source; nothing else breaks.
