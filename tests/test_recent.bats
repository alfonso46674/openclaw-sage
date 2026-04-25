#!/usr/bin/env bats
# Tests for scripts/recent.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RECENT_SH="$REPO_ROOT/scripts/recent.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# ---------------------------------------------------------------------------
# BUG-09 — $DAYS validation
# ---------------------------------------------------------------------------

@test "BUG-09: non-numeric argument exits 1 with usage message" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_SOURCE='local:$TEST_CACHE/src' '$RECENT_SH' foo 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "BUG-09: float argument exits 1 with usage message" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_SOURCE='local:$TEST_CACHE/src' '$RECENT_SH' 3.5 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "BUG-09: numeric argument is accepted" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_SOURCE='local:$TEST_CACHE/src' '$RECENT_SH' 14 2>&1"
  [ "$status" -eq 0 ]
}

@test "BUG-09: default (no argument) runs without error" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_SOURCE='local:$TEST_CACHE/src' '$RECENT_SH' 2>&1"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# New behaviour — no sitemap, uses local mtime
# ---------------------------------------------------------------------------

@test "recent: does not show 'updated at source' section" {
  run "$REPO_ROOT/scripts/recent.sh"
  [[ "$output" != *"updated at source"* ]]
  [[ "$output" == *"Recently accessed locally"* ]]
}

@test "recent: shows cache.sh status hint" {
  run "$REPO_ROOT/scripts/recent.sh"
  [[ "$output" == *"cache.sh status"* ]]
}

@test "recent --version: accepts --version flag without erroring" {
  run "$REPO_ROOT/scripts/recent.sh" --version v2026.4.9
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recently accessed locally"* ]]
}
