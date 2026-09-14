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
#   ./deploy/release.sh "what changed"   commit, publish, and record it
#   ./deploy/release.sh                  same, with nothing left to commit
#   ./deploy/release.sh --no-push        check and build only, touch nothing
#
# Git and itch are done together on purpose. Kept apart they drift, and then
# the source on GitHub is no longer the source that made the build people are
# playing -- which is the one thing a repository is for.
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
MESSAGE=""
case "${1:-}" in
    --no-push) PUSH=0 ;;
    "")        ;;
    *)         MESSAGE="$1" ;;
esac

SUITES=(palette_check texture_check audio_check card_check card_fit_check
        relic_check rules_check effects_test hand_check map_check route_check
        short_game_check tree_check swing_check green_check cup_check
        leaderboard_check
        fusion_check synergy_check tour_check scorecard_check touch_check)

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

# Recorded before it is published, and only once everything above is green, so
# what is on GitHub is always exactly what made the build on itch.
echo
echo "=== source ==="
if [ -n "$(git status --porcelain)" ]; then
    if [ -z "$MESSAGE" ]; then
        echo "  There are uncommitted changes and no message to commit them with."
        echo "  Either say what changed:"
        echo "      ./deploy/release.sh \"what changed\""
        echo "  or commit them yourself first. Not publishing a build whose"
        echo "  source is not written down."
        exit 1
    fi
    git add -A
    git commit -q -m "$MESSAGE"
    echo "  committed: $MESSAGE"
else
    echo "  nothing to commit"
fi

if git remote get-url origin >/dev/null 2>&1; then
    git push -q origin HEAD
    echo "  pushed to $(git remote get-url origin)"
else
    echo "  no remote configured, so nothing pushed"
fi

BUTLER=""
# Found rather than demanded. Getting one .exe onto the PATH is a fight on
# Windows that has nothing to do with shipping a game, so look where it
# actually ends up -- including right here, beside the project.
CANDIDATES=(
    "${BUTLER_PATH:-}"
    "$(command -v butler 2>/dev/null || true)"
    "./butler.exe"
    "$HOME/butler/butler.exe"
    "$HOME/Downloads/butler/butler.exe"
    "$HOME/Desktop/butler/butler.exe"
)
for candidate in "${CANDIDATES[@]}"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        BUTLER="$candidate"
        break
    fi
done

if [ -z "$BUTLER" ]; then
    echo
    echo "butler not found. Download the WINDOWS build -- the macOS one will not"
    echo "run here, and the download page offers both:"
    echo "  https://broth.itch.zone/butler/windows-amd64/LATEST/archive/default"
    echo "Unzip it to ~/butler/ (keep butler.exe and the .dll together), then:"
    echo "  ~/butler/butler.exe login"
    echo "Builds are in build/ meanwhile, ready to upload by hand."
    exit 1
fi

echo
echo "=== publish ==="
echo "  using $BUTLER"
# butler takes a directory rather than a zip, and works out for itself what has
# changed since last time.
"$BUTLER" push build/web     "$ITCH_TARGET:html"
"$BUTLER" push build/windows "$ITCH_TARGET:windows"
echo
echo "Live. https://${ITCH_TARGET%%/*}.itch.io/${ITCH_TARGET##*/}"
echo "Built from $(git rev-parse --short HEAD)."
