#!/usr/bin/env sh
set -eu

# Patch Kelivo defaults for GitHub Actions:
# 1. Disable app update check notifications by default.
# 2. Disable desktop tray icon by default.
# 3. Disable minimize-to-tray-on-close by default.
#
# Usage:
#   sh patch_disable_default_enabled_features.sh

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_FILE="$ROOT_DIR/lib/core/providers/settings_provider.dart"
TMP_FILE="$TARGET_FILE.tmp.$$"

if [ ! -f "$TARGET_FILE" ]; then
  echo "ERROR: target file not found: $TARGET_FILE" >&2
  exit 1
fi

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT HUP INT TERM

replace_line() {
  label=$1
  old=$2
  new=$3

  if grep -Fq "$new" "$TARGET_FILE"; then
    echo "SKIP: already patched: $label"
    return 0
  fi

  if ! grep -Fq "$old" "$TARGET_FILE"; then
    echo "ERROR: expected code not found for $label" >&2
    echo "       $old" >&2
    exit 1
  fi

  # GitHub Actions Linux runners provide GNU sed. This script intentionally
  # uses only sh + grep + sed, without Python/Perl dependencies.
  sed "s|$old|$new|" "$TARGET_FILE" > "$TMP_FILE"
  cat "$TMP_FILE" > "$TARGET_FILE"
  rm -f "$TMP_FILE"
  echo "PATCHED: $label"
}

replace_line \
  "default app update check notification" \
  "_showAppUpdates = prefs.getBool(_displayShowAppUpdatesKey) ?? true;" \
  "_showAppUpdates = prefs.getBool(_displayShowAppUpdatesKey) ?? false;"

replace_line \
  "initial app update check notification state" \
  "bool _showAppUpdates = true;" \
  "bool _showAppUpdates = false;"

replace_line \
  "default desktop tray icon" \
  "_desktopShowTray = isDesktop;" \
  "_desktopShowTray = false;"

replace_line \
  "default minimize-to-tray-on-close" \
  "_desktopMinimizeToTrayOnClose = _desktopShowTray;" \
  "_desktopMinimizeToTrayOnClose = false;"

echo "Done: $TARGET_FILE"
