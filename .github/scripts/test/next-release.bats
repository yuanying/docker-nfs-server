#!/usr/bin/env bats
# Tests for .github/scripts/next-release.sh, run against a scratch repository.

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../next-release.sh"

RENOVATE='renovate[bot]'
RENOVATE_EMAIL='29139614+renovate[bot]@users.noreply.github.com'
RESPONDER='fraction-vuln-responder[bot]'
RESPONDER_EMAIL='348762456+fraction-vuln-responder[bot]@users.noreply.github.com'
HUMAN='OTSUKA, Yuanying'
HUMAN_EMAIL='human@example.com'

setup() {
  cd "$BATS_TEST_TMPDIR"
  git init -q -b main repo
  cd repo
  git config user.name "$HUMAN"
  git config user.email "$HUMAN_EMAIL"
  echo 'FROM debian:12' > Dockerfile
  echo '#!/bin/sh' > entrypoint.sh
  echo 'ok' > index.html
  echo '# docker-nfs-server' > README.md
  git add -A
  git commit -q -m 'Initial'
  git tag v1.2.3
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
  export GITHUB_REPOSITORY=yuanying/docker-nfs-server
}

# commit_as <name> <email> <file> <subject>
commit_as() {
  echo "$4" >> "$3"
  git add "$3"
  GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" git commit -q -m "$4"
}

@test "no vX.Y.Z tag: no release" {
  git tag -d v1.2.3
  run --separate-stderr "$SCRIPT" HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "release=false" ]
}

@test "weekly: no image change since the tag: no release" {
  commit_as "$HUMAN" "$HUMAN_EMAIL" README.md 'Docs'
  run --separate-stderr "$SCRIPT" HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=false"* ]]
  [[ "$output" == *"latest=v1.2.3"* ]]
}

@test "weekly: a human's image change is released" {
  commit_as "$HUMAN" "$HUMAN_EMAIL" Dockerfile 'Tweak'
  run --separate-stderr "$SCRIPT" HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"version=1.2.4"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
}

@test "weekly: a vuln-responder change is released like Renovate's" {
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" Dockerfile 'Fix CVE'
  run --separate-stderr "$SCRIPT" HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
}

@test "bots-only: Renovate's commits only are released" {
  commit_as "$RENOVATE" "$RENOVATE_EMAIL" Dockerfile 'Update debian'
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
  [[ "$output" != *"blocked=true"* ]]
}

@test "bots-only: vuln-responder's commits only are released" {
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" Dockerfile 'Fix CVE-2026-0001'
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
}

@test "bots-only: Renovate and vuln-responder mixed are released" {
  commit_as "$RENOVATE" "$RENOVATE_EMAIL" Dockerfile 'Update debian'
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" entrypoint.sh 'Fix CVE-2026-0001'
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

@test "bots-only: a human's image commit blocks the release and is summarized" {
  commit_as "$HUMAN" "$HUMAN_EMAIL" index.html 'Change the index'
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" Dockerfile 'Fix CVE-2026-0001'
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=false"* ]]
  [[ "$output" == *"blocked=true"* ]]
  [[ "$output" != *"tag="* ]]
  human_sha=$(git rev-parse --short HEAD~1)
  bot_sha=$(git rev-parse --short HEAD)
  summary=$(cat "$GITHUB_STEP_SUMMARY")
  [[ "$summary" == *"$human_sha"* ]]
  [[ "$summary" == *"Change the index"* ]]
  [[ "$summary" == *"$HUMAN"* ]]
  [[ "$summary" != *"$bot_sha"* ]]
  [[ "$summary" == *"gh workflow run release.yml --repo yuanying/docker-nfs-server --ref main"* ]]
}

@test "bots-only: a human's commit outside the image does not block" {
  commit_as "$HUMAN" "$HUMAN_EMAIL" README.md 'Docs'
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" Dockerfile 'Fix CVE-2026-0001'
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
}

@test "bots-only: merge commits are not counted" {
  git checkout -q -b vuln-responder/cve-2026-0001
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" Dockerfile 'Fix CVE-2026-0001'
  git checkout -q main
  git merge -q --no-ff -m 'Merge pull request #9' vuln-responder/cve-2026-0001
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=true"* ]]
  [[ "$output" == *"tag=v1.2.4"* ]]
}

@test "bots-only: no image change since the tag: no release, no summary" {
  commit_as "$RESPONDER" "$RESPONDER_EMAIL" README.md 'Docs'
  run --separate-stderr "$SCRIPT" --bots-only HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"release=false"* ]]
  [[ "$output" != *"blocked=true"* ]]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}
