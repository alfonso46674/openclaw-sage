#!/usr/bin/env bats
# Tests for scripts/build-index.sh and the fetch_and_cache helper in lib.sh
# Covers: BUG-07 (fetch populates both .html and .txt caches)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
BUILD_INDEX_SH="$REPO_ROOT/scripts/build-index.sh"
LIB_SH="$REPO_ROOT/scripts/lib.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# ---------------------------------------------------------------------------
# BUG-07 — fetch_and_cache writes both .html and .txt
# ---------------------------------------------------------------------------

# Helper: call fetch_and_cache via an inline script that sources lib.sh
_run_fetch_and_cache() {
  local url="$1" safe="$2"
  bash -c "
    OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE'
    source '$LIB_SH'
    fetch_and_cache '$url' '$safe'
  "
}

@test "BUG-07: fetch_and_cache writes .txt file" {
  # Use a local HTTP stub via a minimal Python server on a tmp file
  local html_content="<html><body><h1>Hello</h1><p>World</p></body></html>"
  local port=19473
  local tmpdir
  tmpdir="$(mktemp -d)"
  echo "$html_content" > "$tmpdir/index.html"

  # Start a simple HTTP server
  python3 -m http.server "$port" --directory "$tmpdir" &>/dev/null &
  local server_pid=$!
  sleep 0.5  # give server time to start

  OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    bash -c "source '$LIB_SH'; fetch_and_cache 'http://127.0.0.1:$port/index.html' 'test_page'"
  local result=$?

  kill "$server_pid" 2>/dev/null
  rm -rf "$tmpdir"

  [ "$result" -eq 0 ]
  [ -f "$TEST_CACHE/doc_test_page.txt" ]
}

@test "BUG-07: fetch_and_cache writes .html file (regression — was never written before fix)" {
  local html_content="<html><body><h1>Hello</h1><p>World</p></body></html>"
  local port=19474
  local tmpdir
  tmpdir="$(mktemp -d)"
  echo "$html_content" > "$tmpdir/index.html"

  python3 -m http.server "$port" --directory "$tmpdir" &>/dev/null &
  local server_pid=$!
  sleep 0.5

  OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    bash -c "source '$LIB_SH'; fetch_and_cache 'http://127.0.0.1:$port/index.html' 'test_page'"
  local result=$?

  kill "$server_pid" 2>/dev/null
  rm -rf "$tmpdir"

  [ "$result" -eq 0 ]
  # This is the key regression: before BUG-07 fix, the .html file was never created
  [ -f "$TEST_CACHE/doc_test_page.html" ]
}

@test "BUG-07: fetch_and_cache returns 1 and writes nothing on unreachable URL" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' source '$LIB_SH'; fetch_and_cache 'http://127.0.0.1:1/nope' 'missing_page'"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_CACHE/doc_missing_page.txt" ]
  [ ! -f "$TEST_CACHE/doc_missing_page.html" ]
}

@test "BUG-07: build-index status shows correct doc count after fetch_and_cache" {
  # Seed two pre-fetched docs (simulating what a successful fetch_and_cache would produce)
  echo "<html><body>Doc one</body></html>" > "$TEST_CACHE/doc_providers_discord.html"
  echo "Doc one" > "$TEST_CACHE/doc_providers_discord.txt"
  echo "<html><body>Doc two</body></html>" > "$TEST_CACHE/doc_gateway_config.html"
  echo "Doc two" > "$TEST_CACHE/doc_gateway_config.txt"

  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' '$BUILD_INDEX_SH' status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
}
