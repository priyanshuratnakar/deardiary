#!/bin/bash
#
# Builds Dear Diary and puts it in Applications, replacing the copy that is there.
#
#   ./scripts/install.sh
#
# Run it again whenever the code has changed and you want the app you open
# from Applications to have the change.
#
# Your journal and settings are not touched. The installed app uses the same
# data as any other copy of Dear Diary on this Mac.
#
# The build goes into build/install inside this folder, which git ignores.
# It is signed with your own Apple Development identity, so it runs on this
# Mac. It is not notarised, so it is not ready to hand to other people.

set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Dear Diary"
BUILT="build/install/Build/Products/Release/$NAME.app"
TARGET="/Applications/$NAME.app"
LOG="build/install-log.txt"

mkdir -p build
echo "Building…"
if ! xcodebuild -project freewrite.xcodeproj -scheme freewrite -configuration Release \
        -derivedDataPath "$PWD/build/install" build > "$LOG" 2>&1; then
    echo "The build failed. The end of $LOG:"
    tail -20 "$LOG"
    exit 1
fi
codesign --verify --deep --strict "$BUILT"

echo "Closing Dear Diary if it is open…"
pkill -TERM -f "$NAME.app/Contents/MacOS/$NAME" || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$NAME.app/Contents/MacOS/$NAME" > /dev/null || break
    sleep 0.5
done

echo "Installing…"
rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"

open "$TARGET"
echo "Done. Dear Diary is in Applications and open."
