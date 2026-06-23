#!/usr/bin/env sh
set -eu

# 将 Kelivo 的 Windows 数据路径改为便携路径：
# 1. 应用自身数据从 path_provider 的 AppData/Roaming 目录改到程序目录旁。
# 2. shared_preferences.json 也写入同一个便携目录，避免污染系统用户目录。
# 3. 启动路径修正逻辑不再调用 Windows 的 getApplicationSupportDirectory()。
#
# 用法：
#   sh patch_portable_data_path.sh

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIRS_FILE="$ROOT_DIR/lib/utils/app_directories.dart"
SANDBOX_FILE="$ROOT_DIR/lib/utils/sandbox_path_resolver.dart"
MAIN_FILE="$ROOT_DIR/lib/main.dart"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
PREFS_FILE="$ROOT_DIR/lib/utils/portable_shared_preferences.dart"
TMP_FILE="$ROOT_DIR/.patch_portable_data_path.tmp.$$"

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT HUP INT TERM

require_file() {
  if [ ! -f "$1" ]; then
    echo "ERROR: 找不到目标文件：$1" >&2
    exit 1
  fi
}

write_tmp_to() {
  cat "$TMP_FILE" > "$1"
  rm -f "$TMP_FILE"
}

require_file "$APP_DIRS_FILE"
require_file "$SANDBOX_FILE"
require_file "$MAIN_FILE"
require_file "$PUBSPEC_FILE"

# 修补 AppDirectories，让 Windows 应用数据目录位于可执行文件所在目录旁。
if grep -Fq "便携模式：使用程序所在目录" "$APP_DIRS_FILE" || grep -Fq "Portable mode:" "$APP_DIRS_FILE"; then
  echo "SKIP: 应用数据便携路径已修补"
else
  if ! grep -Fq "case TargetPlatform.windows:" "$APP_DIRS_FILE"; then
    echo "ERROR: 未找到 Windows 平台分支" >&2
    exit 1
  fi

  sed '
/^      case TargetPlatform.windows:$/,/^        return await getApplicationSupportDirectory();$/c\
      case TargetPlatform.windows:\
        // 便携模式：使用程序所在目录，避免写入 %AppData%/Roaming\
        final exeFile = File(Platform.resolvedExecutable);\
        return Directory('\''${exeFile.parent.path}${Platform.pathSeparator}com.psyche${Platform.pathSeparator}kelivo'\'');\
      case TargetPlatform.macOS:\
      case TargetPlatform.linux:\
        return await getApplicationSupportDirectory();
' "$APP_DIRS_FILE" > "$TMP_FILE"
  write_tmp_to "$APP_DIRS_FILE"
  echo "PATCHED: 应用数据便携路径：$APP_DIRS_FILE"
fi

# 修补 SandboxPathResolver，避免启动时为缓存 supportDir 创建 AppData/Roaming 空目录。
if grep -Fq "Windows 便携模式：复用 AppDirectories 的便携目录" "$SANDBOX_FILE"; then
  echo "SKIP: SandboxPathResolver 已避免创建 Roaming 空目录"
else
  if ! grep -Fq "final sup = await getApplicationSupportDirectory();" "$SANDBOX_FILE"; then
    echo "ERROR: SandboxPathResolver 中未找到 supportDir 初始化代码" >&2
    exit 1
  fi

  sed '
/^        final sup = await getApplicationSupportDirectory();$/c\
        // Windows 便携模式：复用 AppDirectories 的便携目录。\
        // 避免 getApplicationSupportDirectory() 创建 %AppData%/Roaming 空目录。\
        final sup = Platform.isWindows\
            ? dir\
            : await getApplicationSupportDirectory();
' "$SANDBOX_FILE" > "$TMP_FILE"
  write_tmp_to "$SANDBOX_FILE"
  echo "PATCHED: SandboxPathResolver 避免创建 Roaming 空目录：$SANDBOX_FILE"
fi

# 写入 Windows 便携版 SharedPreferences 实现，接管默认的 AppData/Roaming 存储。
mkdir -p "$(dirname -- "$PREFS_FILE")"
cat > "$PREFS_FILE" <<'DART'
import 'dart:convert' show json;
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Windows 便携版专用的 SharedPreferences 存储实现。
///
/// 官方 Windows 实现会通过 path_provider_windows 写入
/// %AppData%\Roaming\...\shared_preferences.json。便携版需要把同名文件
/// 写到程序目录旁边的 com.psyche\kelivo 目录，避免污染系统用户目录。
class PortableSharedPreferencesStore extends SharedPreferencesStorePlatform {
  PortableSharedPreferencesStore._(this._file);

  static const String _defaultPrefix = 'flutter.';
  static bool _registered = false;

  final File _file;
  Map<String, Object>? _cachedPreferences;

  static void registerForWindowsIfNeeded() {
    if (_registered || kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    final exeFile = File(Platform.resolvedExecutable);
    final dataDir = Directory(
      p.join(exeFile.parent.path, 'com.psyche', 'kelivo'),
    );
    final prefsFile = File(p.join(dataDir.path, 'shared_preferences.json'));
    SharedPreferencesStorePlatform.instance =
        PortableSharedPreferencesStore._(prefsFile);
    _registered = true;
  }

  @override
  Future<bool> clear() {
    return clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: _defaultPrefix)),
    );
  }

  @override
  Future<bool> clearWithPrefix(String prefix) {
    return clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: prefix)),
    );
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final preferences = await _readPreferences();
    preferences.removeWhere(
      (key, _) => _matchesFilter(key, parameters.filter),
    );
    return _writePreferences(preferences);
  }

  @override
  Future<Map<String, Object>> getAll() {
    return getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: _defaultPrefix)),
    );
  }

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) {
    return getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
    );
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final preferences = Map<String, Object>.from(await _readPreferences());
    preferences.removeWhere(
      (key, _) => !_matchesFilter(key, parameters.filter),
    );
    return preferences;
  }

  @override
  Future<bool> remove(String key) async {
    final preferences = await _readPreferences();
    preferences.remove(key);
    return _writePreferences(preferences);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final preferences = await _readPreferences();
    preferences[key] = _normalizeStoredValue(value);
    return _writePreferences(preferences);
  }

  bool _matchesFilter(String key, PreferencesFilter filter) {
    return key.startsWith(filter.prefix) &&
        (filter.allowList == null || filter.allowList!.contains(key));
  }

  Future<Map<String, Object>> _readPreferences() async {
    final cached = _cachedPreferences;
    if (cached != null) {
      return cached;
    }

    final preferences = <String, Object>{};
    try {
      if (_file.existsSync()) {
        final content = _file.readAsStringSync();
        if (content.isNotEmpty) {
          final decoded = json.decode(content);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final key = entry.key;
              final value = _normalizeReadValue(entry.value);
              if (key is String && value != null) {
                preferences[key] = value;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('读取便携版 shared_preferences.json 失败: $e');
    }

    _cachedPreferences = preferences;
    return preferences;
  }

  Object? _normalizeReadValue(Object? value) {
    if (value is bool || value is int || value is double || value is String) {
      return value;
    }
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>().toList();
    }
    return null;
  }

  Object _normalizeStoredValue(Object value) {
    if (value is List) {
      return value.cast<String>().toList();
    }
    return value;
  }

  Future<bool> _writePreferences(Map<String, Object> preferences) async {
    try {
      if (!_file.parent.existsSync()) {
        _file.parent.createSync(recursive: true);
      }
      final tempFile = File('${_file.path}.tmp');
      tempFile.writeAsStringSync(json.encode(preferences), flush: true);
      if (_file.existsSync()) {
        _file.deleteSync();
      }
      tempFile.renameSync(_file.path);
      return true;
    } catch (e) {
      debugPrint('保存便携版 shared_preferences.json 失败: $e');
      return false;
    }
  }
}
DART
echo "PATCHED: 便携版 SharedPreferences 实现：$PREFS_FILE"

# 在程序入口注册便携版 SharedPreferences，必须早于第一次 SharedPreferences.getInstance()。
if grep -Fq "portable_shared_preferences.dart" "$MAIN_FILE"; then
  echo "SKIP: main.dart 已导入便携版 SharedPreferences"
else
  if ! grep -Fq "import 'utils/sandbox_path_resolver.dart';" "$MAIN_FILE"; then
    echo "ERROR: main.dart 中未找到导入插入点" >&2
    exit 1
  fi
  sed "/^import 'utils\/sandbox_path_resolver.dart';$/a\\
import 'utils/portable_shared_preferences.dart';" "$MAIN_FILE" > "$TMP_FILE"
  write_tmp_to "$MAIN_FILE"
  echo "PATCHED: main.dart 导入便携版 SharedPreferences"
fi

if grep -Fq "PortableSharedPreferencesStore.registerForWindowsIfNeeded();" "$MAIN_FILE"; then
  echo "SKIP: main.dart 已注册便携版 SharedPreferences"
else
  if ! grep -Fq "WidgetsFlutterBinding.ensureInitialized();" "$MAIN_FILE"; then
    echo "ERROR: main.dart 中未找到初始化插入点" >&2
    exit 1
  fi
  sed "/^      WidgetsFlutterBinding.ensureInitialized();$/a\\
      PortableSharedPreferencesStore.registerForWindowsIfNeeded();" "$MAIN_FILE" > "$TMP_FILE"
  write_tmp_to "$MAIN_FILE"
  echo "PATCHED: main.dart 注册便携版 SharedPreferences"
fi

# 在 pubspec 中声明直接依赖，避免导入传递依赖导致分析告警。
if grep -Fq "shared_preferences_platform_interface:" "$PUBSPEC_FILE"; then
  echo "SKIP: pubspec.yaml 已声明 shared_preferences_platform_interface"
else
  if ! grep -Fq "  shared_preferences: " "$PUBSPEC_FILE"; then
    echo "ERROR: pubspec.yaml 中未找到 shared_preferences 依赖" >&2
    exit 1
  fi
  sed "/^  shared_preferences: /a\\
  shared_preferences_platform_interface: ^2.4.1" "$PUBSPEC_FILE" > "$TMP_FILE"
  write_tmp_to "$PUBSPEC_FILE"
  echo "PATCHED: pubspec.yaml 声明 shared_preferences_platform_interface"
fi

echo "Done."
