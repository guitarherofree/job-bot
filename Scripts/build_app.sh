#!/bin/bash
# Build "Job Bot.app" with Swift Package Manager (no Xcode project needed; the Command Line
# Tools are enough).
#
# Usage:  bash Scripts/build_app.sh                (release build, then open it)
#         bash Scripts/build_app.sh --install      (also install into Applications)
#         bash Scripts/build_app.sh --skip-tests   (don't run the unit tests)
#         bash Scripts/build_app.sh --no-open      (don't open the app afterwards)
#         bash Scripts/build_app.sh --zip          (also make build/Job-Bot-<version>.zip for a release)
#         bash Scripts/build_app.sh --universal    (one app for both Apple silicon and Intel Macs)
#         bash Scripts/build_app.sh debug          (debug build)
set -euo pipefail
# macOS bash 3.2 can treat UTF-8 bytes as part of variable names; parse byte-wise.
export LC_ALL=C
cd "$(dirname "$0")/.."

CONFIG="release"
SKIP_TESTS=0
INSTALL=0
OPEN=1
ZIP=0
ARCHS=()
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --install) INSTALL=1 ;;
    --no-open) OPEN=0 ;;
    --zip) ZIP=1 ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
  esac
done

# shellcheck source=Scripts/common.sh
. Scripts/common.sh
APP="build/$APP_NAME"
VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0)"

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [ -z "$DEV_DIR" ]; then
  echo "✗ Apple's developer tools are not installed."
  echo "  Run:  xcode-select --install   (or install Xcode from the App Store), then try again."
  exit 1
fi
# The unit tests use XCTest, which ships only with the full Xcode app.
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  SKIP_TESTS=1
  echo "ℹ︎ Using the Command Line Tools: skipping the unit tests (they need the full Xcode app)."
fi

if [ "$SKIP_TESTS" -eq 0 ]; then
  echo "▸ Running tests…"
  if swift test; then echo "✓ Tests passed"; else echo "⚠︎ Tests did not pass; continuing with the app build."; fi
fi

echo "▸ Building Job Bot $VERSION ($CONFIG)…"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --product JobBot

BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path 2>/dev/null)/JobBot"
if [ ! -f "$BIN" ]; then
  BIN="$(find .build -type f -name JobBot -perm -u+x ! -path '*.dSYM*' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)"
fi
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
  echo "✗ The build finished but the app executable could not be found in .build/."
  exit 1
fi

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/JobBot"
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/JobBot" 2>/dev/null || echo unknown)"
cp Resources/Info.plist "$APP/Contents/Info.plist"
make_icns Resources/Icons/AppIcon.png "$APP/Contents/Resources/AppIcon.icns" || echo "  (app icon skipped)"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"

# Ad-hoc signature with the hardened runtime. The explicit designated requirement (bundle
# identifier only) stays the same across builds, so macOS keeps trusting Job Bot's Keychain
# items after an update.
codesign --force --sign - --options runtime \
  --requirements "=designated => identifier \"${BUNDLE_ID}\"" "$APP"

if [ "$ZIP" -eq 1 ]; then
  ZIPFILE="build/Job-Bot-$VERSION.zip"
  rm -f "$ZIPFILE"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIPFILE"
  echo "✓ Packaged $ZIPFILE"
fi

if [ "$INSTALL" -eq 1 ]; then
  if [ "$OPEN" -eq 1 ]; then bash Scripts/install_app.sh "$APP"; else bash Scripts/install_app.sh "$APP" --no-open; fi
else
  echo "✓ Built version $VERSION: $(pwd)/$APP"
  if [ "$OPEN" -eq 1 ]; then open "$APP"; fi
fi
