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
paths = ['/Applications/Helium.app', '/Applications/Obsidian.app', '/Applications/Ghostty.app',
         '/Applications/ChatGPT.app', '/System/Applications/Notes.app', '/System/Applications/Calendar.app']
apps = [app(p) for p in paths if os.path.exists(p)]
t = lambda n, e, a, note="": {"id": str(uuid.uuid4()).upper(), "name": n, "emoji": e, "apps": a,
     "startShortcut": "Focus On", "endShortcut": "Focus Off", "lastStopNote": note}
json.dump([t("Writing", "✍️", apps, "intro half done, fix 2nd paragraph"), t("Coding — repo-x", "💻", apps[:3]),
           t("Study — IELTS", "📚", apps[3:])], open(sys.argv[1], 'w'), indent=2, ensure_ascii=False)
PY
swift build
TASKDOCK_DATA_DIR="$DATA" TASKDOCK_SHOTS="$OUT" .build/debug/TaskDock
ls "$OUT"
