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
  printf 'word1 word2 word3 word4 word5\n' > "$TEST_CACHE/doc_gateway_configuration.txt"
  run "$INFO_SH" gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"words:"* ]]
}

@test "cached txt-only path shows url" {
  printf 'some content here\n' > "$TEST_CACHE/doc_gateway_configuration.txt"
  run "$INFO_SH" gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"url:"* ]]
  [[ "$output" == *"gateway/configuration"* ]]
}

@test "cached txt-only path with --json returns word_count field" {
  printf 'one two three\n' > "$TEST_CACHE/doc_gateway_configuration.txt"
  run "$INFO_SH" gateway/configuration --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"word_count"'* ]]
  [[ "$output" == *'"path"'* ]]
  [[ "$output" == *'"url"'* ]]
  [[ "$output" == *'"cached_at"'* ]]
}

# --- Cached .html ---

@test "cached html provides title in output" {
  printf 'content line\n' > "$TEST_CACHE/doc_test_page.txt"
  printf '<html><head><title>Test Page Title</title></head><body><h1>Heading</h1></body></html>\n' \
    > "$TEST_CACHE/doc_test_page.html"
  run "$INFO_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *"Test Page Title"* ]]
}

@test "cached html provides headings in output" {
  printf 'content\n' > "$TEST_CACHE/doc_test_page.txt"
  printf '<html><body><h1>Overview</h1><h2>Setup</h2></body></html>\n' \
    > "$TEST_CACHE/doc_test_page.html"
  run "$INFO_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *"Overview"* ]]
}

@test "OPENCLAW_SAGE_OUTPUT=json works as --json alternative" {
  printf 'content\n' > "$TEST_CACHE/doc_test_page.txt"
  run env OPENCLAW_SAGE_OUTPUT=json OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$INFO_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *'"word_count"'* ]]
}
