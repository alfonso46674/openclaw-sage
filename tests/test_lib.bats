#!/usr/bin/env bats
# Tests for scripts/lib.sh shared library

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/lib.sh"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# --- is_cache_fresh ---

@test "is_cache_fresh: returns 1 for missing file" {
  run is_cache_fresh "$TEST_CACHE/nonexistent.txt" 3600
  [ "$status" -eq 1 ]
}

@test "is_cache_fresh: returns 0 for a file just created" {
  touch "$TEST_CACHE/fresh.txt"
  run is_cache_fresh "$TEST_CACHE/fresh.txt" 3600
  [ "$status" -eq 0 ]
}

@test "is_cache_fresh: returns 1 for a file with a past mtime" {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    touch -t 202001010000 "$TEST_CACHE/old.txt"
  else
    touch -d "2020-01-01" "$TEST_CACHE/old.txt"
  fi
  run is_cache_fresh "$TEST_CACHE/old.txt" 3600
  [ "$status" -eq 1 ]
}

# --- Environment variables ---

@test "CACHE_DIR is set and non-empty" {
  [ -n "$CACHE_DIR" ]
}

@test "CACHE_DIR matches OPENCLAW_SAGE_CACHE_DIR override" {
  [ "$CACHE_DIR" = "$TEST_CACHE" ]
}

@test "DOCS_BASE_URL is set and starts with https" {
  [ -n "$DOCS_BASE_URL" ]
  [[ "$DOCS_BASE_URL" == https://* ]]
}

@test "SITEMAP_TTL is a positive integer" {
  [[ "$SITEMAP_TTL" =~ ^[0-9]+$ ]]
  [ "$SITEMAP_TTL" -gt 0 ]
}

@test "DOC_TTL is a positive integer" {
  [[ "$DOC_TTL" =~ ^[0-9]+$ ]]
  [ "$DOC_TTL" -gt 0 ]
}

@test "SITEMAP_TTL can be overridden via env var" {
  OPENCLAW_SAGE_SITEMAP_TTL=999 source "$REPO_ROOT/scripts/lib.sh"
  [ "$SITEMAP_TTL" -eq 999 ]
}

@test "DOC_TTL can be overridden via env var" {
  OPENCLAW_SAGE_DOC_TTL=42 source "$REPO_ROOT/scripts/lib.sh"
  [ "$DOC_TTL" -eq 42 ]
}

@test "CACHE_DIR is created on source" {
  NEW_CACHE="$(mktemp -d)"
  rm -rf "$NEW_CACHE"
  OPENCLAW_SAGE_CACHE_DIR="$NEW_CACHE" source "$REPO_ROOT/scripts/lib.sh"
  [ -d "$NEW_CACHE" ]
  rm -rf "$NEW_CACHE"
}
