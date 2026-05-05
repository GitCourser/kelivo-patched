#!/usr/bin/env sh
set -eu

OWNER_REPO="${OWNER_REPO:-Chevey339/kelivo}"
GITHUB_RELEASES_URL="https://github.com/${OWNER_REPO}/releases"
GITHUB_API_URL="https://api.github.com/repos/${OWNER_REPO}/releases/latest"
WORK_DIR="${WORK_DIR:-work}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd sed

mkdir -p "$WORK_DIR"
release_json="$WORK_DIR/latest-release.json"

echo "Checking latest release: $GITHUB_RELEASES_URL" >&2
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

printf '%s\n' "$tag"
