#!/bin/sh
# Builds the arm64 release binary and wraps it in an ad-hoc signed MacMirrorScreen.app plus a zip.
# Usage: scripts/bundle.sh [version]   (a leading "v" is stripped, e.g. v1.2.0 -> 1.2.0)
set -eu
cd "$(dirname "$0")/.."

VERSION=${1:-0.0.0}
VERSION=${VERSION#v}
APP=dist/MacMirrorScreen.app

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacMirrorScreen"

rm -rf dist
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MacMirrorScreen"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - --identifier io.github.ac50.MacMirrorScreen "$APP"
ditto -c -k --keepParent "$APP" dist/MacMirrorScreen.zip
echo "built $APP version $VERSION"
