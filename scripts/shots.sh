#!/bin/sh
# Dev: screenshot the real windows (dark + light) using sample data. Usage: scripts/shots.sh <out-dir>
set -e
cd "$(dirname "$0")/.."
OUT="${1:?out dir}"
DATA="$OUT/sample-data"
mkdir -p "$OUT" "$DATA"
rm -f "$OUT"/*.png "$DATA/session.json"
python3 - "$DATA/templates.json" <<'PY'
import json, sys, uuid, os, plistlib
def app(path):
    info = plistlib.load(open(path + '/Contents/Info.plist', 'rb'))
    return {"bundleID": info['CFBundleIdentifier'], "name": os.path.basename(path)[:-4], "path": path}
paths = ['/Applications/Helium.app', '/Applications/Phi.app', '/System/Applications/Preview.app', '/Applications/Obsidian.app', '/Applications/Ghostty.app',
         '/Applications/ChatGPT.app', '/System/Applications/Notes.app', '/System/Applications/Calendar.app']
apps = [app(p) for p in paths if os.path.exists(p)]
t = lambda n, e, a, note="": {"id": str(uuid.uuid4()).upper(), "name": n, "emoji": e, "apps": a,
     "startShortcut": "Focus On", "endShortcut": "Focus Off", "lastStopNote": note}
import time
w = t("Writing", "✍️", apps, "page 45, exercise 4.3 done; next: try 4.4 before reading 4.5")
w["resume"] = {"savedAt": time.time() - 978307200 - 7200, "tabs": ["https://a.example", "https://b.example", "https://c.example"],
               "items": [{"app": "com.apple.Preview", "url": "file:///Users/me/Books/Calculus%20Early%20Transcendentals.pdf"},
                         {"app": "md.obsidian", "url": "obsidian://open?path=/Vault/Math/Week%203%20notes.md"}]}
json.dump([w, t("Coding — repo-x", "💻", apps[:3]),
           t("Study — IELTS", "📚", apps[3:])], open(sys.argv[1], 'w'), indent=2, ensure_ascii=False)
PY
swift build
TASKDOCK_DATA_DIR="$DATA" TASKDOCK_SHOTS="$OUT" .build/debug/TaskDock
ls "$OUT"
