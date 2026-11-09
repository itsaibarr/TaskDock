#!/bin/sh
# Dev: saved X posts end to end on throwaway data. A fake extension saves posts over the real bridge,
# then the app runs Start writing into a temporary Obsidian vault. Doesn't touch your data or open Obsidian.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
OUT=$(cd "$OUT" && pwd -P)
swift build
TASKDOCK_DATA_DIR="$OUT/data" TASKDOCK_PORT=47127 TASKDOCK_NO_EMBED=1 TASKDOCK_VAULT="$OUT/vault" \
  TASKDOCK_POSTS_WRITE_AFTER=6 .build/debug/TaskDock > "$OUT/app.log" 2>&1 &
APP=$!
node scripts/e2e/save-posts.mjs 47127 || { kill $APP; exit 1; }
wait $APP
python3 - "$OUT" <<'PY'
import json, sys, glob, os
out = sys.argv[1]
fails = 0
def check(ok, what):
    global fails
    print(("PASS " if ok else "FAIL ") + what); fails += not ok
posts = {p["id"]: p for p in json.load(open(f"{out}/data/posts.json"))}
check(set(posts) == {"20", "21"}, "posts.json holds the two saved posts")
check(posts["20"]["text"] == "just setting up my twttr" and posts["20"]["note"] == "first post ever", "text and note kept together")
check(posts["21"]["partial"] and posts["21"]["url"] == "https://x.com/jack/status/21" and posts["21"]["author"] == "jack", "link-only save waits for its text, link cleaned, named by handle")
notes = glob.glob(f"{out}/vault/Articles/Posts – *.md")
check(len(notes) == 1, "Start writing made one monthly note in Articles/")
text = open(notes[0]).read() if notes else ""
check("> just setting up my twttr" in text and "My take: first post ever" in text and "https://x.com/jack/status/21" in text, "the note quotes both posts with link and take")
check(all(p.get("usedIn") for p in posts.values()), "both posts are marked used")
sys.exit(1 if fails else 0)
PY
echo "e2e-posts: all checks passed ($OUT)"
