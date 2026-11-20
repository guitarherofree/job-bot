#!/bin/bash
# Install a built "Job Bot.app" into Applications: closes the running copy, replaces the installed
# bundle in place (so a Dock item keeps working), and reopens it.
#
# Usage:  bash Scripts/install_app.sh ["build/Job Bot.app"] [--no-open]
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
# shellcheck source=Scripts/common.sh
. Scripts/common.sh

APP="build/$APP_NAME"
OPEN=1
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN=0 ;;
    *) APP="$arg" ;;
  esac
done
if [ ! -d "$APP" ]; then
  echo "✗ There is no built app at $APP"
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "?")"

DEST_DIR="/Applications"
[ -w "$DEST_DIR" ] || DEST_DIR="$HOME/Applications"
mkdir -p "$DEST_DIR"
if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  echo "▸ Closing the running app (your work is saved continuously)"
  osascript -e 'tell application id "com.guitarherofree.jobbot" to quit' >/dev/null 2>&1 || pkill -x "$PROCESS_NAME" || true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do pgrep -x "$PROCESS_NAME" >/dev/null 2>&1 || break; sleep 0.3; done
fi
mkdir -p "$DEST_DIR/$APP_NAME"
rsync -a --delete "$APP/" "$DEST_DIR/$APP_NAME/"
xattr -dr com.apple.quarantine "$DEST_DIR/$APP_NAME" 2>/dev/null || true
touch "$DEST_DIR/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DEST_DIR/$APP_NAME" >/dev/null 2>&1 || true
echo "✓ Installed Job Bot $VERSION in $DEST_DIR"
if [ "$OPEN" -eq 1 ]; then open "$DEST_DIR/$APP_NAME"; fi
