#!/usr/bin/env bats
# Tests for scripts/info.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INFO_SH="$REPO_ROOT/scripts/info.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# --- Argument validation ---

@test "no args prints usage and exits 1" {
  run "$INFO_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "flag-only arg prints usage and exits 1" {
  run "$INFO_SH" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# --- Not cached ---

@test "uncached path exits 1 with not-cached message" {
  run "$INFO_SH" gateway/configuration
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not cached"* ]]
}

@test "uncached path with --json exits 1 with JSON error" {
  run "$INFO_SH" gateway/configuration --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"error"'* ]]
  [[ "$output" == *"not_cached"* ]]
}

@test "uncached path --json includes path and url fields" {
  run "$INFO_SH" gateway/configuration --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"path"'* ]]
  [[ "$output" == *'"url"'* ]]
}

# --- Cached .txt only ---

@test "cached txt-only path exits 0 and shows word count" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'word1 word2 word3 word4 word5\n' > "$TEST_CACHE/latest/doc_gateway_configuration.txt"
  run "$INFO_SH" gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"words:"* ]]
}

@test "cached txt-only path shows url" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'some content here\n' > "$TEST_CACHE/latest/doc_gateway_configuration.txt"
  run "$INFO_SH" gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"url:"* ]]
  [[ "$output" == *"gateway/configuration"* ]]
}

@test "cached txt-only path with --json returns word_count field" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'one two three\n' > "$TEST_CACHE/latest/doc_gateway_configuration.txt"
  run "$INFO_SH" gateway/configuration --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"word_count"'* ]]
  [[ "$output" == *'"path"'* ]]
  [[ "$output" == *'"url"'* ]]
  [[ "$output" == *'"cached_at"'* ]]
}

# --- Cached .md (frontmatter title and headings) ---

@test "cached md provides frontmatter title in output" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'content line\n' > "$TEST_CACHE/latest/doc_test_page.txt"
  cat > "$TEST_CACHE/latest/doc_test_page.md" <<'MD'
---
title: "Test Page Title"
---
# Heading
MD
  run "$INFO_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *"Test Page Title"* ]]
}

@test "cached md provides headings in output" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'content\n' > "$TEST_CACHE/latest/doc_test_page.txt"
  printf '# Overview\n## Setup\n' \
    > "$TEST_CACHE/latest/doc_test_page.md"
  run "$INFO_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *"Overview"* ]]
}

@test "OPENCLAW_SAGE_OUTPUT=json works as --json alternative" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'content\n' > "$TEST_CACHE/latest/doc_test_page.txt"
  run env OPENCLAW_SAGE_OUTPUT=json OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$INFO_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *'"word_count"'* ]]
}

@test "info: extracts title from YAML frontmatter in .md cache" {
  mkdir -p "$TEST_CACHE/local"
  cat > "$TEST_CACHE/local/doc_gateway_configuration.md" <<'MD'
---
title: "Gateway Configuration"
summary: "Config overview"
---
# Config
MD
  echo "word content here" > "$TEST_CACHE/local/doc_gateway_configuration.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/info.sh" gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gateway Configuration"* ]]
}

@test "info --version: reads from versioned cache dir" {
  mkdir -p "$TEST_CACHE/v2026.4.9"
  cat > "$TEST_CACHE/v2026.4.9/doc_gateway_configuration.md" <<'MD'
---
title: "Old Config"
---
MD
  echo "words" > "$TEST_CACHE/v2026.4.9/doc_gateway_configuration.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run env OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
          OPENCLAW_SAGE_SOURCE="github" \
          "$REPO_ROOT/scripts/info.sh" --version v2026.4.9 gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"Old Config"* ]]
}
