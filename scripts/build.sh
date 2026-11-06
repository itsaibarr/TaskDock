#!/bin/sh
# Builds build/TaskDock.app (menu bar app, ad-hoc signed).
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/TaskDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TaskDock "$APP/Contents/MacOS/TaskDock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
