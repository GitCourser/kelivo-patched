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

# ---------------------------------------------------------------------------
# Patch windows/CMakeLists.txt to silence MSVC experimental coroutine errors.
# Newer MSVC toolsets (VS 18 / MSVC 14.51+) emit a hard error when
# <experimental/coroutine> is included. Several Flutter plugins
# (audioplayers_windows, permission_handler_windows, webview_windows) still
# use it; adding the define keeps them compiling until upstream migrates.
#
# This matches upstream commit:
#   https://github.com/Chevey339/kelivo/commit/b0e78ee
# ---------------------------------------------------------------------------
CMAKE_FILE="$ROOT_DIR/windows/CMakeLists.txt"

if [ ! -f "$CMAKE_FILE" ]; then
  echo "WARNING: CMakeLists.txt not found: $CMAKE_FILE" >&2
else
  INSERT_MARKER="add_definitions(-DUNICODE -D_UNICODE)"
  INSERT_AFTER="# Silence the deprecated static assertion in newer MSVC"
  if grep -Fq "SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS" "$CMAKE_FILE"; then
    echo "SKIP: MSVC coroutine silence already patched"
  elif grep -Fq "$INSERT_MARKER" "$CMAKE_FILE"; then
    sed "/^add_definitions(-DUNICODE -D_UNICODE)/a\\
# Silence the deprecated static assertion in newer MSVC\\
# toolsets (VS 18 \/ MSVC 14.51+). Several plugins still use it; this keeps them\\
# compiling until they migrate to C++20.\\
add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)" \
      "$CMAKE_FILE" > "$CMAKE_FILE.tmp.$$"
    cat "$CMAKE_FILE.tmp.$$" > "$CMAKE_FILE"
    rm -f "$CMAKE_FILE.tmp.$$"
    echo "PATCHED: MSVC coroutine silence in windows/CMakeLists.txt"
  else
    echo "WARNING: marker '$INSERT_MARKER' not found in $CMAKE_FILE" >&2
  fi
fi

echo "All patches applied."
