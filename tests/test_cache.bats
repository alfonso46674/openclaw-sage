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

@test "status shows cache location" {
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cache location"* ]]
}

@test "status always shows TTL config section" {
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"TTL config"* ]]
}

@test "status with empty version dir shows 0 docs" {
  # parse_version_flag always creates the latest/ dir; it just has 0 docs
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest"* ]]
  [[ "$output" == *"0 docs"* ]]
}

@test "status with version dirs shows version name and doc count" {
  mkdir -p "$TEST_CACHE/latest"
  touch "$TEST_CACHE/latest/doc_gateway_configuration.txt"
  run "$CACHE_SH" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest"* ]]
  [[ "$output" == *"1"* ]]
}

# --- dir ---

@test "dir prints the versioned cache directory path" {
  run "$CACHE_SH" dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_CACHE"* ]]
}

# --- refresh ---

@test "refresh removes docs.json from active version dir" {
  mkdir -p "$TEST_CACHE/latest"
  echo '{}' > "$TEST_CACHE/latest/docs.json"
  run "$CACHE_SH" refresh
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/docs.json" ]
}

@test "refresh succeeds even when docs.json does not exist" {
  run "$CACHE_SH" refresh
  [ "$status" -eq 0 ]
}

# --- clear-docs ---

@test "clear-docs removes doc_*.txt files from active version dir" {
  mkdir -p "$TEST_CACHE/latest"
  echo "content" > "$TEST_CACHE/latest/doc_gateway_config.txt"
  echo "content" > "$TEST_CACHE/latest/doc_providers_discord.txt"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/doc_gateway_config.txt" ]
  [ ! -f "$TEST_CACHE/latest/doc_providers_discord.txt" ]
}

@test "clear-docs removes doc_*.md files from active version dir" {
  mkdir -p "$TEST_CACHE/latest"
  echo "# Doc" > "$TEST_CACHE/latest/doc_gateway_config.md"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/doc_gateway_config.md" ]
}

@test "clear-docs removes index.txt from active version dir" {
  mkdir -p "$TEST_CACHE/latest"
  echo "path|content" > "$TEST_CACHE/latest/index.txt"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/index.txt" ]
}

@test "clear-docs removes index_meta.json from active version dir" {
  mkdir -p "$TEST_CACHE/latest"
  echo '{"num_docs": 0}' > "$TEST_CACHE/latest/index_meta.json"
  run "$CACHE_SH" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/index_meta.json" ]
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

@test "status: lists version subdirectories with doc counts" {
  mkdir -p "$TEST_CACHE/latest" "$TEST_CACHE/v2026.4.9"
  touch "$TEST_CACHE/latest/doc_a.txt" "$TEST_CACHE/latest/doc_b.txt"
  touch "$TEST_CACHE/v2026.4.9/doc_a.txt"
  run "$REPO_ROOT/scripts/cache.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest"* ]]
  [[ "$output" == *"v2026.4.9"* ]]
  [[ "$output" == *"2"* ]]
}

@test "tags: prints message when source is local" {
  export OPENCLAW_SAGE_SOURCE="local:/tmp/myrepo"
  run "$REPO_ROOT/scripts/cache.sh" tags
  [ "$status" -eq 0 ]
  [[ "$output" == *"not available"* || "$output" == *"local"* ]]
}

@test "clear-docs: removes docs only from active version dir" {
  mkdir -p "$TEST_CACHE/latest" "$TEST_CACHE/v2026.4.9"
  touch "$TEST_CACHE/latest/doc_a.txt" "$TEST_CACHE/latest/index.txt"
  touch "$TEST_CACHE/v2026.4.9/doc_a.txt"
  run "$REPO_ROOT/scripts/cache.sh" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/doc_a.txt" ]
  [ -f "$TEST_CACHE/v2026.4.9/doc_a.txt" ]
}
