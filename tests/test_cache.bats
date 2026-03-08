#!/usr/bin/env bats
# Tests for scripts/cache.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CACHE_SH="$REPO_ROOT/scripts/cache.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# --- status ---

@test "status with no sitemap shows EMPTY" {
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cache status: EMPTY"* ]]
}

@test "status always shows TTL config section" {
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"TTL config"* ]]
}

@test "status with fresh sitemap shows FRESH and doc count" {
  echo "sitemap content" > "$TEST_CACHE/sitemap.txt"
  echo "doc content" > "$TEST_CACHE/doc_gateway_configuration.txt"
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cache status: FRESH"* ]]
  [[ "$output" == *"Cached docs:"* ]]
  [[ "$output" == *"1"* ]]
}

@test "status with stale sitemap shows STALE" {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    touch -t 202001010000 "$TEST_CACHE/sitemap.txt"
  else
    touch -d "2020-01-01" "$TEST_CACHE/sitemap.txt"
  fi
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cache status: STALE"* ]]
}

# --- dir ---

@test "dir prints the cache directory path" {
  run "$CACHE_SH" dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_CACHE"* ]]
}

# --- refresh ---

@test "refresh removes sitemap.txt" {
  echo "content" > "$TEST_CACHE/sitemap.txt"
  run "$CACHE_SH" refresh
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/sitemap.txt" ]
}

@test "refresh removes sitemap.xml" {
  echo "<xml/>" > "$TEST_CACHE/sitemap.xml"
  run "$CACHE_SH" refresh
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/sitemap.xml" ]
}

@test "refresh succeeds even when no sitemap exists" {
  run "$CACHE_SH" refresh
  [ "$status" -eq 0 ]
}

# --- clear-docs ---

@test "clear-docs removes doc_*.txt files" {
  echo "content" > "$TEST_CACHE/doc_gateway_config.txt"
  echo "content" > "$TEST_CACHE/doc_providers_discord.txt"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/doc_gateway_config.txt" ]
  [ ! -f "$TEST_CACHE/doc_providers_discord.txt" ]
}

@test "clear-docs removes doc_*.html files" {
  echo "<html/>" > "$TEST_CACHE/doc_gateway_config.html"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/doc_gateway_config.html" ]
}

@test "clear-docs removes index.txt" {
  echo "path|content" > "$TEST_CACHE/index.txt"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/index.txt" ]
}

@test "clear-docs removes index_meta.json" {
  echo '{"num_docs": 0}' > "$TEST_CACHE/index_meta.json"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/index_meta.json" ]
}

@test "clear-docs succeeds on empty cache" {
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
}

# --- unknown subcommand ---

@test "unknown subcommand prints usage" {
  run "$CACHE_SH" doesnotexist
  [[ "$output" == *"Usage"* ]]
}
