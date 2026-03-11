#!/usr/bin/env bats
# Tests for scripts/fetch-doc.sh (offline / cache-only scenarios)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FETCH_SH="$REPO_ROOT/scripts/fetch-doc.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

_seed_doc() {
  # _seed_doc <safe_path> <txt_content> [html_content]
  local safe="$1" txt="$2" html="${3:-}"
  printf '%s\n' "$txt" > "$TEST_CACHE/doc_${safe}.txt"
  if [ -n "$html" ]; then
    printf '%s\n' "$html" > "$TEST_CACHE/doc_${safe}.html"
  fi
}

# --- Argument validation ---

@test "no args prints usage and exits 1" {
  run "$FETCH_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "flag-only arg (--toc) prints usage and exits 1" {
  run "$FETCH_SH" --toc
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "unknown flag exits 1" {
  run "$FETCH_SH" gateway/configuration --bogus-flag
  [ "$status" -eq 1 ]
}

# --- Serve from cache ---

@test "--max-lines truncates output from a cached doc" {
  _seed_doc "test_page" "$(seq 1 100 | tr '\n' '\n')"
  run "$FETCH_SH" test/page --max-lines 10
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -le 10 ]
}

@test "serves full cached doc without flags" {
  _seed_doc "test_page" "$(printf 'line one\nline two\nline three')"
  run "$FETCH_SH" test/page
  [ "$status" -eq 0 ]
  [[ "$output" == *"line one"* ]]
  [[ "$output" == *"line three"* ]]
}

# --- --toc from cached HTML ---

@test "--toc extracts headings from cached HTML (requires python3)" {
  _seed_doc "test_page" "Title" \
    "<html><body><h1>Overview</h1><h2>Setup</h2><h2>Config</h2></body></html>"
  run "$FETCH_SH" test/page --toc
  if command -v python3 &>/dev/null; then
    [ "$status" -eq 0 ]
    [[ "$output" == *"Overview"* ]]
    [[ "$output" == *"Setup"* ]]
  else
    [ "$status" -eq 1 ]
    [[ "$output" == *"python3"* ]]
  fi
}

@test "--toc indents sub-headings relative to parent" {
  _seed_doc "test_page" "Title" \
    "<html><body><h1>Top</h1><h2>Sub</h2></body></html>"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run "$FETCH_SH" test/page --toc
  [ "$status" -eq 0 ]
  # h2 gets 2 spaces of indent (level 2 → (2-1)*2 = 2 spaces)
  [[ "$output" == *"  Sub"* ]]
}

# --- --section from cached HTML ---

@test "--section extracts named section content" {
  _seed_doc "test_page" "Title" \
    "<html><body><h1>Overview</h1><p>Overview content</p><h2>Setup</h2><p>Setup content</p></body></html>"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run "$FETCH_SH" test/page --section overview
  [ "$status" -eq 0 ]
  [[ "$output" == *"Overview content"* ]]
}

@test "--section is case-insensitive" {
  _seed_doc "test_page" "Title" \
    "<html><body><h1>Authentication</h1><p>Auth details here</p></body></html>"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run "$FETCH_SH" test/page --section AUTHENTICATION
  [ "$status" -eq 0 ]
  [[ "$output" == *"Auth details here"* ]]
}

@test "--section missing heading exits 1 with available sections" {
  _seed_doc "test_page" "Title" \
    "<html><body><h1>Overview</h1><h2>Setup</h2></body></html>"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  # Merge stderr into stdout so bats captures the error message in $output
  run bash -c "\"$FETCH_SH\" test/page --section nonexistent 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Section not found"* ]]
}

# --- BUG-05 regression: offline + missing HTML cache gives clear error ---

# --- BUG-18 regression: no local fetch_and_cache shadowing lib.sh ---

@test "BUG-18: fetch-doc.sh does not define its own fetch_and_cache function" {
  # Verify the script no longer contains a local fetch_and_cache definition
  ! grep -q '^fetch_and_cache()' "$FETCH_SH"
}

# --- BUG-05 regression: offline + missing HTML cache gives clear error ---

@test "--toc without HTML cache exits 1 with offline message when host unreachable (BUG-05 regression)" {
  # Seeds only .txt (no .html), then points to an unreachable host.
  # Before the fix this fell through to a misleading "run without --toc first" error.
  # After the fix it exits immediately with "Offline: cannot fetch HTML...".
  _seed_doc "test_page" "some content"
  run bash -c "OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$FETCH_SH' test/page --toc 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Offline"* ]]
}

@test "--section without HTML cache exits 1 with offline message when host unreachable (BUG-05 regression)" {
  _seed_doc "test_page" "some content"
  run bash -c "OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$FETCH_SH' test/page --section overview 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Offline"* ]]
}
