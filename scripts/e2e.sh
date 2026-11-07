#!/bin/sh
# Dev: end-to-end run of start → work → finish → start again on this Mac, beside the installed app.
# Uses TextEdit, Preview, Helium and Phi (and AeroSpace if installed); hides your other apps for about a minute
# and swaps the Dock, then puts everything back. Usage: scripts/e2e.sh [out-dir]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/taskdock-e2e}"
PORT=47124
# Close test copies a previous run left in Preview (deleting a file Preview has open confuses it).
close_tests() { pgrep -x Preview >/dev/null && osascript -e 'tell application id "com.apple.Preview" to close (every document whose name is "e2e-image.png")' >/dev/null 2>&1 || true; }
close_tests
rm -rf "$OUT"; mkdir -p "$OUT/data"
printf 'TaskDock end-to-end note\n' > "$OUT/e2e-note.txt"
sips -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns --out "$OUT/e2e-image.png" >/dev/null
python3 - "$OUT/data/templates.json" <<'PY'
import json, sys, uuid, os, plistlib
def app(path):
    info = plistlib.load(open(path + '/Contents/Info.plist', 'rb'))
    return {"bundleID": info['CFBundleIdentifier'], "name": os.path.basename(path)[:-4], "path": path}
apps = [app(p) for p in ['/System/Applications/TextEdit.app', '/System/Applications/Preview.app',
                         '/Applications/Helium.app', '/Applications/Phi.app'] if os.path.exists(p)]
json.dump([{"id": str(uuid.uuid4()).upper(), "name": "E2E Test", "emoji": "🧪", "apps": apps,
            "startShortcut": "", "endShortcut": "", "lastStopNote": "", "phiSpace": "Default"}], open(sys.argv[1], 'w'))
PY
swift build
node scripts/e2e/fake-browser.mjs $PORT "$OUT/browser.json" & NODE=$!
trap 'kill $NODE 2>/dev/null; close_tests' EXIT
TASKDOCK_DATA_DIR="$OUT/data" TASKDOCK_PORT=$PORT TASKDOCK_E2E="$OUT/app.json" \
  TASKDOCK_E2E_FILES="$OUT/e2e-note.txt|$OUT/e2e-image.png" .build/debug/TaskDock
sleep 1
echo "--- app"; cat "$OUT/app.json"
echo "--- browser"; cat "$OUT/browser.json"
python3 - "$OUT" <<'PY'
import json, sys
app = json.load(open(sys.argv[1] + '/app.json')); b = json.load(open(sys.argv[1] + '/browser.json'))
ok = app.get('passed') and b['protocolHello'] == 2 and b['restoredTabs'] == ['https://e2e.example/a', 'https://e2e.example/b'] \
     and b['blankRemovedAfterRestore'] and 1 in b['minimized']
print('E2E', 'PASSED' if ok else 'FAILED'); sys.exit(0 if ok else 1)
PY
