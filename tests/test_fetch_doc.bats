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
  # _seed_doc <safe_path> <txt_content> [md_content]
  # Writes to $TEST_CACHE/latest/ (the default VERSION_CACHE_DIR for github source)
  local safe="$1" txt="$2" md="${3:-}"
  mkdir -p "$TEST_CACHE/latest"
  printf '%s\n' "$txt" > "$TEST_CACHE/latest/doc_${safe}.txt"
  if [ -n "$md" ]; then
    printf '%s\n' "$md" > "$TEST_CACHE/latest/doc_${safe}.md"
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

# --- --toc from cached .md ---

@test "--toc extracts headings from cached .md (requires python3 for --section but not --toc)" {
  _seed_doc "test_page" "Title" \
    "$(printf '# Overview\n## Setup\n## Config')"
  run "$FETCH_SH" test/page --toc
  [ "$status" -eq 0 ]
  [[ "$output" == *"Overview"* ]]
  [[ "$output" == *"Setup"* ]]
}

@test "--toc indents sub-headings relative to parent" {
  _seed_doc "test_page" "Title" \
    "$(printf '# Top\n## Sub')"
  run "$FETCH_SH" test/page --toc
  [ "$status" -eq 0 ]
  # h2 gets 2 spaces of indent (level 2 → (2-1)*2 = 2 spaces)
  [[ "$output" == *"  Sub"* ]]
}

# --- --section from cached .md ---

@test "--section extracts named section content" {
  _seed_doc "test_page" "Title" \
    "$(printf '# Overview\nOverview content\n\n## Setup\nSetup content')"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run "$FETCH_SH" test/page --section overview
  [ "$status" -eq 0 ]
  [[ "$output" == *"Overview content"* ]]
}

@test "--section is case-insensitive" {
  _seed_doc "test_page" "Title" \
    "$(printf '# Authentication\nAuth details here')"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run "$FETCH_SH" test/page --section AUTHENTICATION
  [ "$status" -eq 0 ]
  [[ "$output" == *"Auth details here"* ]]
}

@test "--section missing heading exits 1 with available sections" {
  _seed_doc "test_page" "Title" \
    "$(printf '# Overview\n## Setup')"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  # Merge stderr into stdout so bats captures the error message in $output
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \"$FETCH_SH\" test/page --section nonexistent 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Section not found"* ]]
}

# --- BUG-18 regression: no local fetch_and_cache shadowing lib.sh ---

@test "BUG-18: fetch-doc.sh does not define its own fetch_and_cache function" {
  # Verify the script no longer contains a local fetch_and_cache definition
  ! grep -q '^fetch_and_cache()' "$FETCH_SH"
}

# --- BUG-05 regression (updated): missing .md cache gives clear error ---
# With markdown-based extraction, missing .md gives an actionable error message;
# there is no longer a separate online fetch for the .md (it is fetched together with .txt).

@test "--toc without .md cache exits 1 with clear error (BUG-05 regression)" {
  # Seeds .txt but no .md — the script should exit with a clear error.
  _seed_doc "test_page" "some content"
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$FETCH_SH' test/page --toc 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a fetched cache"* ]]
}

@test "--section without .md cache exits 1 with clear error (BUG-05 regression)" {
  _seed_doc "test_page" "some content"
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$FETCH_SH' test/page --section overview 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a fetched cache"* ]]
}

@test "fetch-doc --toc: extracts headings from cached .md file" {
  mkdir -p "$TEST_CACHE/local"
  cat > "$TEST_CACHE/local/doc_gateway_configuration.md" <<'MD'
# Overview
## Authentication
### Token Auth
## Retry Settings
MD
  touch "$TEST_CACHE/local/doc_gateway_configuration.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/fetch-doc.sh" gateway/configuration --toc
  [ "$status" -eq 0 ]
  [[ "$output" == "Overview"* ]]
  [[ "$output" == *"  Authentication"* ]]
  [[ "$output" == *"    Token Auth"* ]]
  [[ "$output" == *"  Retry Settings"* ]]
}

@test "fetch-doc --section: extracts named section from .md file" {
  mkdir -p "$TEST_CACHE/local"
  cat > "$TEST_CACHE/local/doc_gateway_configuration.md" <<'MD'
# Overview
Overview text.

## Retry Settings
Configure retries here.
maxAttempts: 3

## Logging
Log config.
MD
  touch "$TEST_CACHE/local/doc_gateway_configuration.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/fetch-doc.sh" gateway/configuration --section "Retry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Configure retries"* ]]
  [[ "$output" != *"Log config"* ]]
}

@test "fetch-doc --version: reads from versioned cache dir" {
  mkdir -p "$TEST_CACHE/v2026.4.9"
  echo "Old config text." > "$TEST_CACHE/v2026.4.9/doc_gateway_configuration.txt"
  cat > "$TEST_CACHE/v2026.4.9/doc_gateway_configuration.md" <<'MD'
# Config
Old config text.
MD
  # Do not use local: source — that overrides VERSION to "local".
  # With a fresh .txt cache, no network fetch occurs.
  run env OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
          OPENCLAW_SAGE_SOURCE="github" \
          "$REPO_ROOT/scripts/fetch-doc.sh" --version v2026.4.9 gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"Old config text"* ]]
}
