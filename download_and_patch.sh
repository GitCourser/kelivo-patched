#!/usr/bin/env sh
set -eu

OWNER_REPO="${OWNER_REPO:-Chevey339/kelivo}"
GITHUB_RELEASES_URL="https://github.com/${OWNER_REPO}/releases"
GITHUB_API_URL="https://api.github.com/repos/${OWNER_REPO}/releases/latest"
WORK_DIR="${WORK_DIR:-work}"
SOURCE_DIR="${SOURCE_DIR:-kelivo-src}"
PATCH_SCRIPT="${PATCH_SCRIPT:-patch_disable_default_enabled_features.sh}"

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

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

release_json="$WORK_DIR/latest-release.json"
echo "Checking latest release: $GITHUB_RELEASES_URL"
curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$GITHUB_API_URL" \
  -o "$release_json"

tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" | head -n 1)
if [ -z "$tag" ]; then
  echo "ERROR: failed to read latest release tag from GitHub API" >&2
  exit 1
fi

archive_url="https://github.com/${OWNER_REPO}/archive/refs/tags/${tag}.tar.gz"
archive_file="$WORK_DIR/${tag}.tar.gz"

echo "Latest release tag: $tag"
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

echo "Patched source is ready: $SOURCE_DIR"
