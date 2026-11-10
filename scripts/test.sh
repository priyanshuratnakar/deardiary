#!/bin/bash
#
# Runs the tests, and leaves no extra copy of the app on the Mac afterwards.
#
#   ./scripts/test.sh                      # every test
#   ./scripts/test.sh LockTests            # one suite
#
# The tests build their own copy of Dear Diary to run inside. Built in the
# usual place, that copy shows up beside the real one in Spotlight and the
# Apps view. So it is built in build/dev.noindex (git ignores it, and
# Spotlight ignores folders ending in .noindex) and removed when the tests
# are done.
#
# The results are saved to build/tests.xcresult. To get the pictures out:
#   xcrun xcresulttool export attachments --path build/tests.xcresult --output-path build/pictures

set -uo pipefail
cd "$(dirname "$0")/.."

NAME="Dear Diary"
BUILD="$PWD/build/dev.noindex"
BUILT="$BUILD/Build/Products/Debug/$NAME.app"
RESULT="$PWD/build/tests.xcresult"
LOG="build/test-log.txt"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

ONLY="freewriteTests"
if [ $# -gt 0 ]; then
    ONLY="freewriteTests/$1"
fi

mkdir -p build
rm -rf "$RESULT"
xcodebuild test -project freewrite.xcodeproj -scheme freewrite \
    -derivedDataPath "$BUILD" -only-testing:"$ONLY" -resultBundlePath "$RESULT" > "$LOG" 2>&1
STATUS=$?

# Leave one copy of the app on the Mac: forget the copies made for the tests and remove them.
for app in "$BUILT" "$BUILD/Build/Products/Debug/"*.app; do
    [ -e "$app" ] || continue
    "$LSREGISTER" -u "$app" > /dev/null 2>&1 || true
    rm -rf "$app"
done

xcrun xcresulttool get test-results summary --path "$RESULT" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("%s: %d tests, %d passed, %d failed" % (d["result"], d["totalTestCount"], d["passedTests"], d["failedTests"]))
for f in d.get("testFailures", []):
    print("FAILED", f.get("testName"), "|", (f.get("failureText") or "")[:400])
' || tail -20 "$LOG"
exit $STATUS
