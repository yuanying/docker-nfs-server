#!/bin/bash
# Decide whether the weekly release should cut a new patch version.
#
# Usage: next-release.sh <ref>
#
# Prints GITHUB_OUTPUT lines: release=true|false, latest=vX.Y.Z and, when
# releasing, version=X.Y.(Z+1) and tag=vX.Y.(Z+1).
set -euo pipefail

HEAD_REF=${1:-HEAD}

# Files that end up in the image. Changes elsewhere (.github/, renovate.json,
# README.md) do not warrant a release.
IMAGE_PATHS=(Dockerfile entrypoint.sh index.html)

# Only plain vX.Y.Z tags count; compared as semver.
LATEST=$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)

if [[ -z "$LATEST" ]]; then
  echo "No vX.Y.Z tag found; nothing to release from." >&2
  echo "release=false"
  exit 0
fi

if git diff --quiet "$LATEST" "$HEAD_REF" -- "${IMAGE_PATHS[@]}"; then
  echo "No image changes since $LATEST." >&2
  echo "release=false"
  echo "latest=$LATEST"
  exit 0
fi

IFS=. read -r MAJOR MINOR PATCH <<< "${LATEST#v}"
VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"

echo "Image changed since $LATEST; next version is $VERSION." >&2
echo "release=true"
echo "latest=$LATEST"
echo "version=$VERSION"
echo "tag=v$VERSION"
