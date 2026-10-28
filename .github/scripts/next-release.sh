#!/bin/bash
# Decide whether a release should cut a new patch version.
#
# Usage: next-release.sh [--bots-only] <ref>
#
# A release is due when the image's files changed since the latest vX.Y.Z
# tag. With --bots-only, as for the release on merging a vuln-responder/ pull
# request, it is also required that every commit since the tag that changed
# those files, merge commits aside, is by one of BOTS; otherwise the release
# is left to be made by hand, and the commits that held it back are written
# to $GITHUB_STEP_SUMMARY when it is set.
#
# Prints GITHUB_OUTPUT lines: release=true|false, latest=vX.Y.Z,
# blocked=true when --bots-only held the release back and, when releasing,
# version=X.Y.(Z+1) and tag=vX.Y.(Z+1).
set -euo pipefail

BOTS_ONLY=false
if [[ ${1:-} == --bots-only ]]; then
  BOTS_ONLY=true
  shift
fi
HEAD_REF=${1:-HEAD}

# Files that end up in the image. Changes elsewhere (.github/, renovate.json,
# README.md) do not warrant a release.
IMAGE_PATHS=(Dockerfile entrypoint.sh index.html)

# Authors whose commits may be released without a person deciding to.
BOTS=('renovate[bot]' 'fraction-vuln-responder[bot]')

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

if [[ $BOTS_ONLY == true ]]; then
  OTHERS=()
  while IFS=$'\t' read -r sha author subject; do
    is_bot=false
    for bot in "${BOTS[@]}"; do
      [[ $author == "$bot" ]] && is_bot=true
    done
    [[ $is_bot == true ]] || OTHERS+=("$sha"$'\t'"$author"$'\t'"$subject")
  done < <(git log --no-merges --reverse --format='%h%x09%an%x09%s' \
    "$LATEST..$HEAD_REF" -- "${IMAGE_PATHS[@]}")

  if (( ${#OTHERS[@]} > 0 )); then
    echo "Commits by others than ${BOTS[*]} since $LATEST; not releasing." >&2
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
      {
        echo "## Not released"
        echo
        echo "These commits since $LATEST changed the image and are not by ${BOTS[*]}:"
        echo
        for line in "${OTHERS[@]}"; do
          IFS=$'\t' read -r sha author subject <<< "$line"
          echo "- \`$sha\` $subject ($author)"
        done
        echo
        echo "To release them, run the release by hand, or wait for the weekly one:"
        echo
        echo '```'
        echo "gh workflow run release.yml --repo ${GITHUB_REPOSITORY:-<owner>/<repo>} --ref main"
        echo '```'
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    printf '%s\n' "${OTHERS[@]}" >&2
    echo "release=false"
    echo "latest=$LATEST"
    echo "blocked=true"
    exit 0
  fi
fi

IFS=. read -r MAJOR MINOR PATCH <<< "${LATEST#v}"
VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"

echo "Image changed since $LATEST; next version is $VERSION." >&2
echo "release=true"
echo "latest=$LATEST"
echo "version=$VERSION"
echo "tag=v$VERSION"
