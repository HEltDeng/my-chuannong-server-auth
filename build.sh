#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
task_app="build/MyChuannong Server Auth.app"
mkdir -p "$task_app/Contents/MacOS"
cp Info.plist "$task_app/Contents/Info.plist"
xcrun swiftc -O LocalServerAuth.swift -o "$task_app/Contents/MacOS/LocalServerAuth" -framework AppKit -framework Security
codesign --force --sign - "$task_app"
printf 'Built %s\n' "$task_app"
