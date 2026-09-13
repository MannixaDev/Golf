#!/usr/bin/env bash
#
# One command to ship: check, build, publish.
#
# The order is the point. Every harness runs before anything is exported, and
# the licence gate runs against the built packs rather than the repository --
# so a red suite or a build that forgot to carry the font licence stops the
# release instead of reaching players. Balance on this project is measured
# rather than guessed, and shipping should be too.
#
#   ./deploy/release.sh            check, build, and push to itch
#   ./deploy/release.sh --no-push  check and build only
#
# butler does differential uploads, so only the changed chunks of a 40MB build
# actually travel. Install it once from https://itch.io/docs/butler/ and run
# `butler login`; after that this script is the whole of publishing.
set -euo pipefail

GODOT="${GODOT:-/c/Users/jak_m/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
# user/game on itch. The channel name after the colon is how itch decides which
# platform a build is for: "html" is played in the browser, "windows" downloads.
ITCH_TARGET="${ITCH_TARGET:-mannixa/fairwayfiends}"

cd "$(dirname "$0")/.."
PUSH=1
[ "${1:-}" = "--no-push" ] && PUSH=0

SUITES=(palette_check texture_check audio_check card_check card_fit_check
        relic_check rules_check effects_test hand_check map_check route_check
        short_game_check tree_check swing_check green_check leaderboard_check
        fusion_check synergy_check tour_check scorecard_check)

echo "=== checks ==="
failed=0
for suite in "${SUITES[@]}"; do
    if "$GODOT" --headless --path . --script "res://tools/$suite.gd" 2>&1 \
            | grep -q "ALL CHECKS PASSED"; then
        printf '  ok    %s\n' "$suite"
    else
        printf '  FAIL  %s\n' "$suite"
        failed=1
    fi
done

# The flow walk boots the real game and walks it end to end. It has no business
# being skipped: it is the only check that would notice the front end breaking.
if "$GODOT" --headless --path . --script res://tools/screenshot.gd 2>&1 \
        | grep -q "ALL FLOW CHECKS PASSED"; then
    printf '  ok    flow walk\n'
else
    printf '  FAIL  flow walk\n'
    failed=1
fi

if [ "$failed" -ne 0 ]; then
    echo
    echo "Something is red. Not shipping."
    exit 1
fi

echo
echo "=== build ==="
"$GODOT" --headless --path . --export-release "Windows Desktop" \
    build/windows/FairwayFiends.exe >/dev/null
"$GODOT" --headless --path . --export-release "Web" \
    build/web/index.html >/dev/null
echo "  windows and web exported"

# Run against the built packs, so this catches a build that dropped the licence
# as well as a repository that never had it.
if "$GODOT" --headless --path . --script res://tools/licence_check.gd 2>&1 \
        | grep -q "ALL CHECKS PASSED"; then
    echo "  ok    licence travels with both builds"
else
    echo "  FAIL  a build is missing the font licence. Not shipping."
    exit 1
fi

if [ "$PUSH" -eq 0 ]; then
    echo
    echo "Built, not pushed."
    exit 0
fi

if ! command -v butler >/dev/null 2>&1; then
    echo
    echo "butler is not on PATH. Install it from https://itch.io/docs/butler/"
    echo "and run 'butler login' once. Builds are in build/ meanwhile."
    exit 1
fi

echo
echo "=== publish ==="
# butler takes a directory rather than a zip, and works out for itself what has
# changed since last time.
butler push build/web     "$ITCH_TARGET:html"
butler push build/windows "$ITCH_TARGET:windows"
echo
echo "Live. https://${ITCH_TARGET%%/*}.itch.io/${ITCH_TARGET##*/}"
