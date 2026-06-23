#!/usr/bin/env bash
set -eu

# Patch Kelivo to use portable data path on Windows:
# Instead of storing data in %AppData%/Roaming/com.psyche/kelivo,
# store it in <exe_dir>/com.psyche/kelivo (portable mode).
#
# Usage:
#   sh patch_portable_data_path.sh

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_FILE="$ROOT_DIR/lib/utils/app_directories.dart"
TMP_FILE="$TARGET_FILE.tmp.$$"

if [ ! -f "$TARGET_FILE" ]; then
  echo "ERROR: target file not found: $TARGET_FILE" >&2
  exit 1
fi

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT HUP INT TERM

# Check if already patched
if grep -Fq "Portable mode:" "$TARGET_FILE"; then
  echo "SKIP: portable data path already patched"
  exit 0
fi

# Verify the original code pattern exists
if ! grep -Fq "case TargetPlatform.windows:" "$TARGET_FILE"; then
  echo "ERROR: expected 'case TargetPlatform.windows:' not found" >&2
  exit 1
fi

# Replace the Windows case block: split Windows from macOS/Linux so that
# Windows uses executable-relative path, while macOS/Linux keep using
# getApplicationSupportDirectory().
#
# Before:
#       case TargetPlatform.windows:
#       case TargetPlatform.macOS:
#       case TargetPlatform.linux:
#         return await getApplicationSupportDirectory();
#
# After:
#       case TargetPlatform.windows:
#         // Portable mode: use exe directory instead of %AppData%/Roaming
#         final exeFile = File(Platform.resolvedExecutable);
#         return Directory('${exeFile.parent.path}${Platform.pathSeparator}com.psyche${Platform.pathSeparator}kelivo');
#       case TargetPlatform.macOS:
#       case TargetPlatform.linux:
#         return await getApplicationSupportDirectory();

sed '
/^      case TargetPlatform.windows:$/,/^        return await getApplicationSupportDirectory();$/c\
      case TargetPlatform.windows:\
        // Portable mode: use exe directory instead of %AppData%/Roaming\
        final exeFile = File(Platform.resolvedExecutable);\
        return Directory('\''${exeFile.parent.path}${Platform.pathSeparator}com.psyche${Platform.pathSeparator}kelivo'\'');\
      case TargetPlatform.macOS:\
      case TargetPlatform.linux:\
        return await getApplicationSupportDirectory();
' "$TARGET_FILE" > "$TMP_FILE"

cat "$TMP_FILE" > "$TARGET_FILE"
rm -f "$TMP_FILE"

echo "PATCHED: portable data path in $TARGET_FILE"
echo "Done."
