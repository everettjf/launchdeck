#!/bin/bash

set -euo pipefail

app_path="${1:-}"
[[ -n "$app_path" && -d "$app_path" ]] || {
  echo "release validation: LaunchDeck.app path is required" >&2
  exit 64
}

plist="$app_path/Contents/Info.plist"
binary="$app_path/Contents/MacOS/LaunchDeck"
[[ -f "$plist" && -x "$binary" ]] || {
  echo "release validation: app bundle is incomplete" >&2
  exit 1
}

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "com.everettjf.launchdeck" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$plist")" == "launchdeck" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$plist")" == "false" ]]
lipo -verify_arch arm64 "$binary"
lipo -verify_arch x86_64 "$binary"

echo "release validation: metadata and universal architectures passed"
