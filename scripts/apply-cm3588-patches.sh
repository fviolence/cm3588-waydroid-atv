#!/usr/bin/env bash
set -euo pipefail

ANDROID="$(realpath "${1:?Usage: apply-cm3588-patches.sh <android-tree>}")"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$PROJECT/patches"

test -d "$ANDROID/.repo" || {
    echo "ERROR: Not an Android repo checkout: $ANDROID" >&2
    exit 1
}

# Upstream Waydroid patches must be applied first.
git -C "$ANDROID/bionic" rev-parse -q --verify \
    refs/tags/autopatch/base-patches-36 >/dev/null || {
    echo "ERROR: Upstream Waydroid patch tag is missing." >&2
    exit 1
}

# Our HWC patch series requires this exact original revision.
EXPECTED_HWC=ce61fbc895d183279c304c1d1c516a710d587c7f

ACTUAL_HWC="$(git -C "$ANDROID/hardware/waydroid" rev-parse HEAD)"

if [[ "$ACTUAL_HWC" != "$EXPECTED_HWC" ]]; then
    echo "ERROR: Unexpected HWC revision: $ACTUAL_HWC" >&2
    echo "Expected: $EXPECTED_HWC" >&2
    exit 1
fi

mapfile -t DIRS < <(
    find "$PATCHES" -type f -name '*.patch' -printf '%h\n' |
        LC_ALL=C sort -u
)

# Preflight every repository before modifying any of them.
echo "Checking ${#DIRS[@]} patch-target repositories..."

for DIR in "${DIRS[@]}"; do
    NAME="${DIR#"$PATCHES"/}"
    TARGET="$ANDROID/$NAME"

    if [[ ! -e "$TARGET/.git" ]]; then
        echo "ERROR: Missing Git checkout: $NAME" >&2
        exit 1
    fi

    if [[ -n "$(git -C "$TARGET" status --porcelain)" ]]; then
        echo "ERROR: Dirty repository: $NAME" >&2
        exit 1
    fi
done

echo "Preflight passed. Applying CM3588 patches..."

for DIR in "${DIRS[@]}"; do
    NAME="${DIR#"$PATCHES"/}"
    echo "=== $NAME ==="

    if ! git -C "$ANDROID/$NAME" am -3 "$DIR"/*.patch; then
        git -C "$ANDROID/$NAME" am --abort || true
        echo "ERROR: Patch application failed: $NAME" >&2
        exit 1
    fi
done

echo "CM3588 patches applied successfully."
