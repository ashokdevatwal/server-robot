#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$REPO_ROOT/go.mod" ]]; then
  echo "Run this script from inside the repository."
  exit 1
fi

usage() {
  cat <<'USAGE'
Usage: ./scripts/release-local.sh --tag v0.1.0 [--repo owner/repo] [--skip-gh-release]

Options:
  --tag TAG            Release tag, for example: v0.1.0 (required)
  --repo OWNER/REPO    GitHub repository (default: ashokdevatwal/server-robot)
  --skip-gh-release    Only build assets locally in dist/release/<tag>
  -h, --help           Show help

Requirements:
  - go
  - tar
  - sha256sum
  - gh (only when publishing release)
USAGE
}

TAG=""
REPO="ashokdevatwal/server-robot"
SKIP_GH_RELEASE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      shift
      TAG="${1:-}"
      [[ -n "$TAG" ]] || { echo "--tag requires a value"; exit 1; }
      ;;
    --repo)
      shift
      REPO="${1:-}"
      [[ -n "$REPO" ]] || { echo "--repo requires a value"; exit 1; }
      ;;
    --skip-gh-release)
      SKIP_GH_RELEASE="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$TAG" ]]; then
  echo "--tag is required"
  usage
  exit 1
fi

for cmd in go tar sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

if [[ "$SKIP_GH_RELEASE" != "true" ]]; then
  for cmd in gh git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Missing required command: $cmd"
      exit 1
    fi
  done
  gh auth status >/dev/null 2>&1 || {
    echo "GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
  }
fi

DIST_DIR="$REPO_ROOT/dist/release/$TAG"
mkdir -p "$DIST_DIR"

build_asset() {
  local goarch="$1"
  local bin_name="server-monitor-linux-${goarch}"
  local bin_path="$DIST_DIR/$bin_name"
  local tar_path="$DIST_DIR/${bin_name}.tar.gz"

  echo "Building ${bin_name}..."
  CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath -ldflags "-s -w -X main.version=$TAG" -o "$bin_path" "$REPO_ROOT/cmd/monitor"

  tar -C "$DIST_DIR" -czf "$tar_path" "$bin_name"
  sha256sum "$tar_path" >> "$DIST_DIR/sha256sums.txt"
  rm -f "$bin_path"
}

: > "$DIST_DIR/sha256sums.txt"
build_asset amd64
build_asset arm64

echo "Assets generated in: $DIST_DIR"

if [[ "$SKIP_GH_RELEASE" == "true" ]]; then
  echo "Skipping GitHub release publish."
  exit 0
fi

cd "$REPO_ROOT"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally."
else
  git tag "$TAG"
fi

git push origin "$TAG"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Uploading assets..."
else
  gh release create "$TAG" --repo "$REPO" --title "$TAG" --notes "Release $TAG"
fi

gh release upload "$TAG" --repo "$REPO" --clobber \
  "$DIST_DIR/server-monitor-linux-amd64.tar.gz" \
  "$DIST_DIR/server-monitor-linux-arm64.tar.gz" \
  "$DIST_DIR/sha256sums.txt"

echo
echo "Published release assets for $TAG"
echo "Install command example:"
echo "curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/quick-install.sh | sudo env RELEASE_TAG=${TAG} bash"
