#!/bin/bash
#
# Builds Dear Diary and puts it in Applications, replacing the copy that is there.
#
#   ./scripts/install.sh
#
# Run it again whenever the code has changed and you want the app you open
# from Applications to have the change. If Dear Diary is open it is closed
# and opened again; if it is not, it stays closed.
#
# Your journal and settings are not touched. The installed app uses the same
# data as any other copy of Dear Diary on this Mac.
#
# Only one copy of the app is left on the Mac: the one in Applications. The
# build is made in build/install.noindex inside this folder (git ignores it,
# and Spotlight ignores folders ending in .noindex), and the built app is
# removed from there once it has been copied.
#
# The app is signed with your own Apple Development identity, so it runs on
# this Mac. It is not notarised, so it is not ready to hand to other people.

set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Dear Diary"
BUILD="$PWD/build/install.noindex"
BUILT="$BUILD/Build/Products/Release/$NAME.app"
TARGET="/Applications/$NAME.app"
LOG="build/install-log.txt"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

mkdir -p build
echo "Building…"
if ! xcodebuild -project freewrite.xcodeproj -scheme freewrite -configuration Release \
        -derivedDataPath "$BUILD" build > "$LOG" 2>&1; then
    echo "The build failed. The end of $LOG:"
    tail -20 "$LOG"
    exit 1
fi
codesign --verify --deep --strict "$BUILT"

# If Dear Diary is open it is closed for the swap and opened again afterwards.
# If it is not open, it is left closed.
WAS_OPEN=0
if pgrep -f "$NAME.app/Contents/MacOS/$NAME" > /dev/null; then
    WAS_OPEN=1
    echo "Closing Dear Diary…"
fi
pkill -TERM -f "$NAME.app/Contents/MacOS/$NAME" || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$NAME.app/Contents/MacOS/$NAME" > /dev/null || break
    sleep 0.5
done

echo "Installing…"
rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"

# Leave one copy: forget the built one and remove it.
"$LSREGISTER" -u "$BUILT" > /dev/null 2>&1 || true
rm -rf "$BUILT"
"$LSREGISTER" -f "$TARGET" > /dev/null 2>&1 || true

if [ "$WAS_OPEN" = 1 ]; then
    open "$TARGET"
    echo "Done. Dear Diary is in Applications and open again."
else
    echo "Done. Dear Diary is in Applications."
fi
