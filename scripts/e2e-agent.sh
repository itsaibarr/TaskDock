#!/bin/sh
# Dev: end-to-end run of the agent hand-off (hook → nudge → park → notify → return), beside the installed app.
# Events go through the real hook binary on a private channel. Opens TextEdit and hides your other apps for
# about a minute, then puts them back. Usage: scripts/e2e-agent.sh [out-dir]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/taskdock-agent-e2e}"
rm -rf "$OUT"; mkdir -p "$OUT/data"
OUT=$(cd "$OUT" && pwd -P) # /tmp is a link to /private/tmp
VISIBLE=$(osascript -e 'tell application "System Events" to get bundle identifier of (every process whose visible is true and background only is false)')
python3 - "$OUT/data/templates.json" <<'PY'
import json, sys, uuid
te = {"bundleID": "com.apple.TextEdit", "name": "TextEdit", "path": "/System/Applications/TextEdit.app"}
t = lambda name, apps: {"id": str(uuid.uuid4()).upper(), "name": name, "emoji": "🧪", "apps": apps,
                        "startShortcut": "", "endShortcut": "", "lastStopNote": ""}
json.dump([t("Coding", [te]), t("Further Math", []), t("Writing", [te])], open(sys.argv[1], 'w'))
PY
swift build
TASKDOCK_DATA_DIR="$OUT/data" TASKDOCK_PORT=47125 TASKDOCK_AGENT_CHANNEL=e2e TASKDOCK_NUDGE_AFTER=2 \
  TASKDOCK_AGENT_E2E="$OUT/app.json" .build/debug/TaskDock || true
# Bring back the apps that were visible before (finishing "Further Math" never ran its restore).
for id in $(echo "$VISIBLE" | tr ',' ' '); do
  osascript -e "tell application \"System Events\" to set visible of (first process whose bundle identifier is \"$id\") to true" >/dev/null 2>&1 || true
done
cat "$OUT/app.json"
python3 -c "import json,sys; ok=json.load(open(sys.argv[1]))['passed']; print('\nAGENT E2E', 'PASSED' if ok else 'FAILED'); sys.exit(0 if ok else 1)" "$OUT/app.json"
