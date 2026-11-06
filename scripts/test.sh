#!/bin/sh
# XCTest ships with Xcode, not the Command Line Tools.
set -e
cd "$(dirname "$0")/.."
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift test
node --test extension/*.test.js
