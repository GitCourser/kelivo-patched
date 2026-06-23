#!/usr/bin/env sh
set -eu

# 调整 Kelivo 在自动打包中的默认设置：
# 1. 默认关闭应用更新检查通知。
# 2. 默认关闭桌面托盘图标。
# 3. 默认关闭窗口关闭时最小化到托盘。
#
# 用法：
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

  # 先查找旧代码。因为目标文件其他位置可能本来就包含新代码片段，
  # 如果先查新代码会误判已修补，导致 _load() 中的默认值没有真正替换。
  if grep -Fq "$old" "$TARGET_FILE"; then
    sed "s|$old|$new|" "$TARGET_FILE" > "$TMP_FILE"
    cat "$TMP_FILE" > "$TARGET_FILE"
    rm -f "$TMP_FILE"
    echo "PATCHED: $label"
    return 0
  fi

  if grep -Fq "$new" "$TARGET_FILE"; then
    echo "SKIP: already patched: $label"
    return 0
  fi

  echo "ERROR: expected code not found for $label" >&2
  echo "       $old" >&2
  exit 1
}

replace_line \
  "默认关闭应用更新检查通知" \
  "_showAppUpdates = prefs.getBool(_displayShowAppUpdatesKey) ?? true;" \
  "_showAppUpdates = prefs.getBool(_displayShowAppUpdatesKey) ?? false;"

replace_line \
  "初始化时默认关闭应用更新检查通知" \
  "bool _showAppUpdates = true;" \
  "bool _showAppUpdates = false;"

replace_line \
  "默认关闭桌面托盘图标" \
  "_desktopShowTray = isDesktop;" \
  "_desktopShowTray = false;"

replace_line \
  "默认关闭关闭窗口时最小化到托盘" \
  "_desktopMinimizeToTrayOnClose = _desktopShowTray;" \
  "_desktopMinimizeToTrayOnClose = false;"

echo "Done: $TARGET_FILE"

# ---------------------------------------------------------------------------
# 修补 windows/CMakeLists.txt，绕过新版 MSVC 的实验性 coroutine 报错。
# 较新的 MSVC 工具链会在包含 <experimental/coroutine> 时触发硬错误。
# 当前若干 Flutter 插件仍会使用它，因此临时添加宏，等待上游迁移到 C++20。
#
# 对应上游提交：
#   https://github.com/Chevey339/kelivo/commit/b0e78ee
# ---------------------------------------------------------------------------
CMAKE_FILE="$ROOT_DIR/windows/CMakeLists.txt"

if [ ! -f "$CMAKE_FILE" ]; then
  echo "WARNING: CMakeLists.txt not found: $CMAKE_FILE" >&2
else
  INSERT_MARKER="add_definitions(-DUNICODE -D_UNICODE)"
  if grep -Fq "SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS" "$CMAKE_FILE"; then
    echo "SKIP: MSVC coroutine silence already patched"
  elif grep -Fq "$INSERT_MARKER" "$CMAKE_FILE"; then
    sed "/^add_definitions(-DUNICODE -D_UNICODE)/a\\
# 绕过新版 MSVC 对 <experimental/coroutine> 的静态断言报错。\\
# 部分插件仍依赖实验性 coroutine 头文件，临时保留该宏直到上游迁移到 C++20。\\
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
