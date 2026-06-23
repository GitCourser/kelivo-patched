#!/usr/bin/env sh
set -eu

OWNER_REPO="${OWNER_REPO:-Chevey339/kelivo}"
WORK_DIR="${WORK_DIR:-work}"
SOURCE_DIR="${SOURCE_DIR:-kelivo-src}"
PATCH_SCRIPT="${PATCH_SCRIPT:-patch_disable_default_enabled_features.sh}"
PORTABLE_PATCH_SCRIPT="${PORTABLE_PATCH_SCRIPT:-patch_portable_data_path.sh}"
GET_VERSION_SCRIPT="${GET_VERSION_SCRIPT:-./get_latest_version.sh}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd tar

if [ ! -f "$PATCH_SCRIPT" ]; then
  echo "ERROR: patch script not found: $PATCH_SCRIPT" >&2
  exit 1
fi

if [ -z "${VERSION_TAG:-}" ]; then
  if [ ! -f "$GET_VERSION_SCRIPT" ]; then
    echo "ERROR: version script not found: $GET_VERSION_SCRIPT" >&2
    exit 1
  fi
  VERSION_TAG=$(OWNER_REPO="$OWNER_REPO" WORK_DIR="$WORK_DIR" sh "$GET_VERSION_SCRIPT")
fi

if [ -z "$VERSION_TAG" ]; then
  echo "ERROR: VERSION_TAG is empty" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 使用 GitHub API 的 tarball 地址，兼容只有 Release 但没有 refs/tags 归档的上游版本。
archive_url="https://api.github.com/repos/${OWNER_REPO}/tarball/${VERSION_TAG}"
archive_file="$WORK_DIR/${VERSION_TAG}.tar.gz"

echo "Latest release tag: $VERSION_TAG"
echo "Downloading source tar.gz: $archive_url"
curl -fL "$archive_url" -o "$archive_file"

rm -rf "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
tar -xzf "$archive_file" -C "$SOURCE_DIR" --strip-components=1

cp "$PATCH_SCRIPT" "$SOURCE_DIR/$PATCH_SCRIPT"
(
  cd "$SOURCE_DIR"
  sh "./$PATCH_SCRIPT"
)

cp "$PORTABLE_PATCH_SCRIPT" "$SOURCE_DIR/$PORTABLE_PATCH_SCRIPT"
(
  cd "$SOURCE_DIR"
  sh "./$PORTABLE_PATCH_SCRIPT"
)

echo "Patched source is ready: $SOURCE_DIR"
