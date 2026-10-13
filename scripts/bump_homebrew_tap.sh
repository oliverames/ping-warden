#!/usr/bin/env bash
# Bump the Ping Warden cask in oliverames/homebrew-tap to a released version.
# Usage: scripts/bump_homebrew_tap.sh VERSION   (e.g. 4.3.3, no leading "v")
# Env:   TAP_DIR  local clone of the tap (default: ~/Developer/Projects/homebrew-tap)
#        NO_PUSH=1 to commit locally without pushing
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 VERSION (e.g. 4.3.3)" >&2
  exit 2
fi

REPO="oliverames/ping-warden"
TAP_REPO="oliverames/homebrew-tap"
TAP_DIR="${TAP_DIR:-$HOME/Developer/Projects/homebrew-tap}"
CASK="$TAP_DIR/Casks/ping-warden.rb"
ASSET="PingWarden-$VERSION.dmg"

if [[ ! -d "$TAP_DIR/.git" ]]; then
  git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
fi
git -C "$TAP_DIR" pull --ff-only --quiet

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh release download "v$VERSION" -R "$REPO" -p "$ASSET" -D "$WORK"
SHA="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"

# Cross-check against the digest GitHub recorded for the asset, when present.
DIGEST="$(gh release view "v$VERSION" -R "$REPO" --json assets \
  --jq ".assets[] | select(.name==\"$ASSET\") | .digest // empty" || true)"
if [[ -n "$DIGEST" && "$DIGEST" != "sha256:$SHA" ]]; then
  echo "sha256 mismatch: downloaded $SHA, GitHub reports $DIGEST" >&2
  exit 1
fi

sed -i '' -E \
  -e "s/^  version \"[^\"]+\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \"[0-9a-f]{64}\"/  sha256 \"$SHA\"/" \
  "$CASK"

if git -C "$TAP_DIR" diff --quiet -- Casks/ping-warden.rb; then
  echo "Cask already at $VERSION; nothing to do."
  exit 0
fi

git -C "$TAP_DIR" add Casks/ping-warden.rb
git -C "$TAP_DIR" commit -m "ping-warden $VERSION"
if [[ "${NO_PUSH:-0}" != "1" ]]; then
  git -C "$TAP_DIR" push
fi
echo "Cask bumped to $VERSION ($SHA)."
