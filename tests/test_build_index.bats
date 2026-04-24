#!/usr/bin/env bats
# Tests for scripts/build-index.sh and lib.sh helpers
# Covers: BUG-07, BUG-10, BUG-11, BUG-12, BUG-16, BUG-17, BUG-20,
#         ENH-09, ENH-15, ENH-20, ENH-26

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
BUILD_INDEX_SH="$REPO_ROOT/scripts/build-index.sh"
LIB_SH="$REPO_ROOT/scripts/lib.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  export TEST_BIN
  TEST_BIN="$TEST_CACHE/bin"
  mkdir -p "$TEST_BIN"
  # Seed a local markdown fixture used by fetch_markdown tests
  cat > "$TEST_CACHE/fixture.md" <<'MD'
---
title: "Hello"
---
# Hello

World
MD
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# ---------------------------------------------------------------------------
# BUG-07 — fetch_markdown writes both .md and .txt
# ---------------------------------------------------------------------------

@test "BUG-07: fetch_markdown writes .txt file from local source" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/test"
  cat > "$src/test/page.md" <<'MD'
# Hello
World
MD
  run bash -c "
    export OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE'
    export OPENCLAW_SAGE_SOURCE='local:$src'
    source '$LIB_SH'
    parse_version_flag
    fetch_markdown 'test_page' 'main'
  "
  [ "$status" -eq 0 ]
  [ -f "$TEST_CACHE/local/doc_test_page.txt" ]
}

@test "BUG-07: fetch_markdown writes .md file (regression)" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/test"
  cat > "$src/test/page.md" <<'MD'
# Hello
World
MD
  run bash -c "
    export OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE'
    export OPENCLAW_SAGE_SOURCE='local:$src'
    source '$LIB_SH'
    parse_version_flag
    fetch_markdown 'test_page' 'main'
  "
  [ "$status" -eq 0 ]
  [ -f "$TEST_CACHE/local/doc_test_page.md" ]
}

@test "BUG-07: fetch_markdown returns 1 and writes nothing when file missing" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src"
  run bash -c "
    export OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE'
    export OPENCLAW_SAGE_SOURCE='local:$src'
    source '$LIB_SH'
    parse_version_flag
    fetch_markdown 'missing_page' 'main'
  "
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_CACHE/local/doc_missing_page.txt" ]
  [ ! -f "$TEST_CACHE/local/doc_missing_page.md" ]
}

@test "BUG-10: fetch_markdown strips frontmatter while preserving content headings" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/guide"
  cat > "$src/guide/setup.md" <<'MD'
---
title: "Guide Title"
description: "chrome noise"
---

# Guide Title

Useful body text.
MD
  run bash -c "
    export OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE'
    export OPENCLAW_SAGE_SOURCE='local:$src'
    source '$LIB_SH'
    parse_version_flag
    fetch_markdown 'guide_setup' 'main'
  "
  [ "$status" -eq 0 ]
  [ -f "$TEST_CACHE/local/doc_guide_setup.md" ]
  [ -f "$TEST_CACHE/local/doc_guide_setup.txt" ]

  grep -q "Guide Title" "$TEST_CACHE/local/doc_guide_setup.txt"
  grep -q "Useful body text" "$TEST_CACHE/local/doc_guide_setup.txt"
  ! grep -q "^---" "$TEST_CACHE/local/doc_guide_setup.txt"
  ! grep -q "description:" "$TEST_CACHE/local/doc_guide_setup.txt"
}

# ---------------------------------------------------------------------------
# BUG-20 — error message goes to stderr, not stdout
# ---------------------------------------------------------------------------

@test "BUG-20: fetch empty-path error goes to stderr not stdout" {
  # Seed a docs.json with no pages that have slashes (so PATHS will be empty)
  local src="$TEST_CACHE/src"
  mkdir -p "$src"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{}}
JSON
  local stderr_file="$TEST_CACHE/stderr.txt"
  local stdout_file="$TEST_CACHE/stdout.txt"
  OPENCLAW_SAGE_SOURCE="local:$src" \
  OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
  "$BUILD_INDEX_SH" fetch >"$stdout_file" 2>"$stderr_file" || true
  # Error should be in stderr
  grep -q "Error: Could not extract doc paths" "$stderr_file"
  # Error should NOT be in stdout
  ! grep -q "Error: Could not extract doc paths" "$stdout_file"
}

# ---------------------------------------------------------------------------
# BUG-11 — docs.json fetch failures should be reported directly
# ---------------------------------------------------------------------------

@test "BUG-11: fetch stops with docs.json fetch error when docs.json curl fails" {
  cat > "$TEST_BIN/curl" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  if [ "$arg" = "-I" ]; then
    exit 0
  fi
done
# Fail for any -o (file download) requests
exit 7
EOF
  chmod +x "$TEST_BIN/curl"

  run env PATH="$TEST_BIN:$PATH" \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    OPENCLAW_SAGE_SOURCE="github" \
    "$BUILD_INDEX_SH" fetch

  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: failed to fetch docs.json"* || "$output" == *"Offline"* ]]
}

# ---------------------------------------------------------------------------
# BUG-12 — build must stop if build-meta fails
# ---------------------------------------------------------------------------

@test "BUG-12: build stops with error when build-meta fails" {
  mkdir -p "$TEST_CACHE/latest"
  echo "searchterm in doc content" > "$TEST_CACHE/latest/doc_test_page.txt"

  cat > "$TEST_BIN/python3" <<'EOF'
#!/bin/bash
if [ "$2" = "build-meta" ]; then
  exit 9
fi
exec /usr/bin/env python3 "$@"
EOF
  chmod +x "$TEST_BIN/python3"

  run env PATH="$TEST_BIN:$PATH" \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    "$BUILD_INDEX_SH" build

  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: build-meta failed"* ]]
  [[ "$output" != *"Location:"* ]]
}

# ---------------------------------------------------------------------------
# ENH-15 — build reuses unchanged index lines and only regenerates changed docs
# ---------------------------------------------------------------------------

@test "ENH-15: build incrementally updates changed docs and drops removed docs" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'alpha/doc|alpha old line\nbeta/doc|beta old line\nremoved/doc|stale line\n' > "$TEST_CACHE/latest/index.txt"
  echo "alpha old line" > "$TEST_CACHE/latest/doc_alpha_doc.txt"
  echo "beta new line" > "$TEST_CACHE/latest/doc_beta_doc.txt"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    touch -t 202001010000 "$TEST_CACHE/latest/doc_alpha_doc.txt"
    touch -t 202101010000 "$TEST_CACHE/latest/index.txt"
    touch -t 202201010000 "$TEST_CACHE/latest/doc_beta_doc.txt"
  else
    touch -d "2020-01-01 00:00:00" "$TEST_CACHE/latest/doc_alpha_doc.txt"
    touch -d "2021-01-01 00:00:00" "$TEST_CACHE/latest/index.txt"
    touch -d "2022-01-01 00:00:00" "$TEST_CACHE/latest/doc_beta_doc.txt"
  fi

  run env OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$BUILD_INDEX_SH" build

  [ "$status" -eq 0 ]
  grep -q '^alpha/doc|alpha old line$' "$TEST_CACHE/latest/index.txt"
  grep -q '^beta/doc|beta new line$' "$TEST_CACHE/latest/index.txt"
  ! grep -q '^beta/doc|beta old line$' "$TEST_CACHE/latest/index.txt"
  ! grep -q '^removed/doc|' "$TEST_CACHE/latest/index.txt"
}

@test "ENH-15: build leaves index untouched when no docs changed" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'alpha/doc|alpha line\n' > "$TEST_CACHE/latest/index.txt"
  echo "alpha line" > "$TEST_CACHE/latest/doc_alpha_doc.txt"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    touch -t 202001010000 "$TEST_CACHE/latest/doc_alpha_doc.txt"
    touch -t 202101010000 "$TEST_CACHE/latest/index.txt"
  else
    touch -d "2020-01-01 00:00:00" "$TEST_CACHE/latest/doc_alpha_doc.txt"
    touch -d "2021-01-01 00:00:00" "$TEST_CACHE/latest/index.txt"
  fi

  local before_mtime
  before_mtime="$(bash -c "source '$LIB_SH'; get_mtime '$TEST_CACHE/latest/index.txt'")"

  run env OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$BUILD_INDEX_SH" build

  [ "$status" -eq 0 ]
  local after_mtime
  after_mtime="$(bash -c "source '$LIB_SH'; get_mtime '$TEST_CACHE/latest/index.txt'")"
  [ "$before_mtime" = "$after_mtime" ]
}

# ---------------------------------------------------------------------------
# BUG-16 — fetch progress should not leave path suffix garbage behind
# ---------------------------------------------------------------------------

@test "BUG-16: fetch progress does not leave suffix garbage when a shorter path follows a longer one" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/providers/very-long-provider-name"
  mkdir -p "$src/providers"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"tabs":[{"groups":[{"pages":["providers/very-long-provider-name/troubleshooting","providers/discord"]}]}]}}
JSON
  cat > "$src/providers/very-long-provider-name/troubleshooting.md" <<'MD'
# Long
Long path page
MD
  cat > "$src/providers/discord.md" <<'MD'
# Discord
Discord page
MD

  run env \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    OPENCLAW_SAGE_SOURCE="local:$src" \
    OPENCLAW_SAGE_FETCH_JOBS="1" \
    "$BUILD_INDEX_SH" fetch

  [ "$status" -eq 0 ]
  [[ "$output" == *"[done] providers/very-long-provider-name/troubleshooting"* ]]
  [[ "$output" == *"[done] providers/discord"* ]]
  [[ "$output" != *"[1/2]"* ]]
  # Each done line should contain the exact path and nothing extra
  [[ "$output" != *"[done] providers/discordtroubleshooting"* ]]
  [[ "$output" != *"[done] providers/discord/troubleshooting"* ]]
}

# ---------------------------------------------------------------------------
# BUG-17 — hardcoded URL regression in build-index.sh
# ---------------------------------------------------------------------------

@test "BUG-17: build-index search output uses DOCS_BASE_URL not hardcoded URL" {
  mkdir -p "$TEST_CACHE/latest"
  echo "searchterm in doc content" > "$TEST_CACHE/latest/doc_test_page.txt"
  printf 'test/page|searchterm in doc content\n' > "$TEST_CACHE/latest/index.txt"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run bash -c "OPENCLAW_SAGE_DOCS_BASE_URL='https://custom.example.com' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$BUILD_INDEX_SH' search searchterm 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom.example.com"* ]]
}

@test "ENH-09: build-index search --max-results requires a positive integer" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'test/page|searchterm in doc content\n' > "$TEST_CACHE/latest/index.txt"
  run "$BUILD_INDEX_SH" search --max-results nope searchterm
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: build-index.sh search [--max-results N] <query>"* ]]
}

@test "ENH-09: build-index search --max-results limits BM25 output" {
  mkdir -p "$TEST_CACHE/latest"
  printf 'alpha/doc|searchkeyword searchkeyword searchkeyword\nbeta/doc|searchkeyword\n' > "$TEST_CACHE/latest/index.txt"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run env OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$BUILD_INDEX_SH" search --max-results 1 searchkeyword
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha/doc"* ]]
  [[ "$output" != *"beta/doc"* ]]
}

# ---------------------------------------------------------------------------
# ENH-20 — fetch runs via xargs -P and reports per-doc completion lines
# ---------------------------------------------------------------------------

@test "ENH-20: fetch uses xargs parallel workers and prints done lines" {
  local real_xargs
  real_xargs="$(command -v xargs)"
  [ -n "$real_xargs" ]

  local src="$TEST_CACHE/src"
  mkdir -p "$src/providers" "$src/gateway"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"tabs":[{"groups":[{"pages":["providers/discord","gateway/configuration"]}]}]}}
JSON
  cat > "$src/providers/discord.md" <<'MD'
# Discord
Discord setup
MD
  cat > "$src/gateway/configuration.md" <<'MD'
# Gateway
Gateway config
MD

  cat > "$TEST_BIN/xargs" <<EOF
#!/bin/bash
printf '%s\n' "\$*" > "$TEST_CACHE/xargs_args.txt"
exec "$real_xargs" "\$@"
EOF
  chmod +x "$TEST_BIN/xargs"

  run env PATH="$TEST_BIN:$PATH" \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    OPENCLAW_SAGE_SOURCE="local:$src" \
    OPENCLAW_SAGE_FETCH_JOBS="2" \
    "$BUILD_INDEX_SH" fetch

  [ "$status" -eq 0 ]
  grep -q -- "-P 2" "$TEST_CACHE/xargs_args.txt"
  [[ "$output" == *"[done] providers/discord"* ]]
  [[ "$output" == *"[done] gateway/configuration"* ]]
  [[ "$output" != *"[1/2]"* ]]
  [ -f "$TEST_CACHE/local/doc_providers_discord.txt" ]
  [ -f "$TEST_CACHE/local/doc_gateway_configuration.txt" ]
}

@test "ENH-20: fetch announces sequential fallback when xargs is unavailable or fails" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/providers"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"tabs":[{"groups":[{"pages":["providers/discord"]}]}]}}
JSON
  cat > "$src/providers/discord.md" <<'MD'
# Discord
Discord setup
MD

  cat > "$TEST_BIN/xargs" <<'EOF'
#!/bin/bash
exit 127
EOF
  chmod +x "$TEST_BIN/xargs"

  run env PATH="$TEST_BIN:$PATH" \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    OPENCLAW_SAGE_SOURCE="local:$src" \
    "$BUILD_INDEX_SH" fetch

  [ "$status" -eq 0 ]
  [[ "$output" == *"xargs unavailable or failed; falling back to sequential fetch."* ]]
  [[ "$output" == *"[done] providers/discord"* ]]
}

# ---------------------------------------------------------------------------
# build-index status
# ---------------------------------------------------------------------------

@test "BUG-07: build-index status shows correct doc count after fetch" {
  # Seed two pre-fetched docs (simulating what a successful fetch would produce)
  mkdir -p "$TEST_CACHE/latest"
  echo "Doc one" > "$TEST_CACHE/latest/doc_providers_discord.txt"
  echo "Doc two" > "$TEST_CACHE/latest/doc_gateway_config.txt"

  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' '$BUILD_INDEX_SH' status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
}

# ---------------------------------------------------------------------------
# ENH-26 — docs.json discovery and versioned cache
# ---------------------------------------------------------------------------

@test "build-index fetch: uses docs.json from local source" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/gateway"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[{"tab":"Docs","groups":[{"group":"Gateway","pages":["gateway/configuration"]}]}]}]}}
JSON
  cat > "$src/gateway/configuration.md" <<'MD'
---
title: "Configuration"
---
# Config heading
Some config text.
MD

  export OPENCLAW_SAGE_SOURCE="local:$src"
  run "$REPO_ROOT/scripts/build-index.sh" fetch
  [ "$status" -eq 0 ]
  [ -f "$TEST_CACHE/local/doc_gateway_configuration.txt" ]
  [ -f "$TEST_CACHE/local/doc_gateway_configuration.md" ]
  run cat "$TEST_CACHE/local/doc_gateway_configuration.txt"
  [[ "$output" == *"Config heading"* ]]
}

@test "build-index fetch: caches into versioned subdirectory (local mode uses 'local' label)" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/gateway"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[{"tab":"Docs","groups":[{"group":"Gateway","pages":["gateway/configuration"]}]}]}]}}
JSON
  cat > "$src/gateway/configuration.md" <<'MD'
# Config
MD
  export OPENCLAW_SAGE_SOURCE="local:$src"
  run "$REPO_ROOT/scripts/build-index.sh" fetch
  [ "$status" -eq 0 ]
  [ -d "$TEST_CACHE/local" ]
}

@test "build-index fetch: exits 1 when offline and source is github" {
  export OPENCLAW_SAGE_SOURCE="github"
  curl() { return 1; }
  export -f curl
  run "$REPO_ROOT/scripts/build-index.sh" fetch
  [ "$status" -eq 1 ]
  [[ "$output" == *"Offline"* || "$output" == *"offline"* ]]
}
