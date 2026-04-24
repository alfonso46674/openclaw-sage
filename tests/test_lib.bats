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

@test "get_mtime: returns 1 for missing file" {
  run get_mtime "$TEST_CACHE/nonexistent.txt"
  [ "$status" -eq 1 ]
}

@test "get_mtime: returns an epoch integer for an existing file" {
  touch "$TEST_CACHE/existing.txt"
  run get_mtime "$TEST_CACHE/existing.txt"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

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

@test "DOC_TTL is a positive integer" {
  [[ "$DOC_TTL" =~ ^[0-9]+$ ]]
  [ "$DOC_TTL" -gt 0 ]
}

@test "FETCH_JOBS is a positive integer" {
  [[ "$FETCH_JOBS" =~ ^[0-9]+$ ]]
  [ "$FETCH_JOBS" -gt 0 ]
}

@test "DOC_TTL can be overridden via env var" {
  OPENCLAW_SAGE_DOC_TTL=42 source "$REPO_ROOT/scripts/lib.sh"
  [ "$DOC_TTL" -eq 42 ]
}

@test "FETCH_JOBS can be overridden via env var" {
  OPENCLAW_SAGE_FETCH_JOBS=3 source "$REPO_ROOT/scripts/lib.sh"
  [ "$FETCH_JOBS" -eq 3 ]
}

@test "CACHE_DIR is created on source" {
  NEW_CACHE="$(mktemp -d)"
  rm -rf "$NEW_CACHE"
  OPENCLAW_SAGE_CACHE_DIR="$NEW_CACHE" source "$REPO_ROOT/scripts/lib.sh"
  [ -d "$NEW_CACHE" ]
  rm -rf "$NEW_CACHE"
}

# --- clean_markdown ---

@test "clean_markdown: strips YAML frontmatter" {
  cat > "$TEST_CACHE/input.md" <<'MD'
---
title: "My Doc"
summary: "A summary"
---
# Real content
MD
  source "$REPO_ROOT/scripts/lib.sh"
  clean_markdown "$TEST_CACHE/input.md" "$TEST_CACHE/output.txt"
  [ -f "$TEST_CACHE/output.txt" ]
  run cat "$TEST_CACHE/output.txt"
  [[ "$output" == *"Real content"* ]]
  [[ "$output" != *"title:"* ]]
  [[ "$output" != *"---"* ]]
}

@test "clean_markdown: strips self-closing MDX tags" {
  cat > "$TEST_CACHE/input.md" <<'MD'
Some text <Icon name="star" /> more text
MD
  source "$REPO_ROOT/scripts/lib.sh"
  clean_markdown "$TEST_CACHE/input.md" "$TEST_CACHE/output.txt"
  run cat "$TEST_CACHE/output.txt"
  [[ "$output" == *"Some text"* ]]
  [[ "$output" == *"more text"* ]]
  [[ "$output" != *"<Icon"* ]]
}

@test "clean_markdown: strips paired MDX tags, keeps inner text" {
  cat > "$TEST_CACHE/input.md" <<'MD'
<Tip>
Important advice here.
</Tip>
MD
  source "$REPO_ROOT/scripts/lib.sh"
  clean_markdown "$TEST_CACHE/input.md" "$TEST_CACHE/output.txt"
  run cat "$TEST_CACHE/output.txt"
  [[ "$output" == *"Important advice here."* ]]
  [[ "$output" != *"<Tip>"* ]]
}

@test "clean_markdown: prepends title and summary from frontmatter" {
  cat > "$TEST_CACHE/input.md" <<'MD'
---
title: "Gateway Config"
summary: "Configure the gateway"
---
# Heading
MD
  source "$REPO_ROOT/scripts/lib.sh"
  clean_markdown "$TEST_CACHE/input.md" "$TEST_CACHE/output.txt"
  run cat "$TEST_CACHE/output.txt"
  [[ "$output" == *"Gateway Config"* ]]
  [[ "$output" == *"Configure the gateway"* ]]
}

@test "clean_markdown: preserves fenced code blocks untouched" {
  cat > "$TEST_CACHE/input.md" <<'MD'
Before code.
```json
{ "key": "<Value>" }
```
After code.
MD
  source "$REPO_ROOT/scripts/lib.sh"
  clean_markdown "$TEST_CACHE/input.md" "$TEST_CACHE/output.txt"
  run cat "$TEST_CACHE/output.txt"
  [[ "$output" == *'"key": "<Value>"'* ]]
}

# --- resolve_source ---

@test "resolve_source: github mode returns raw.githubusercontent.com URL" {
  export OPENCLAW_SAGE_SOURCE="github"
  source "$REPO_ROOT/scripts/lib.sh"
  result=$(resolve_source "gateway/configuration" "main")
  [[ "$result" == "https://raw.githubusercontent.com/openclaw/openclaw/main/docs/gateway/configuration.md" ]]
}

@test "resolve_source: github mode uses tag ref when provided" {
  export OPENCLAW_SAGE_SOURCE="github"
  source "$REPO_ROOT/scripts/lib.sh"
  result=$(resolve_source "gateway/configuration" "v2026.4.9")
  [[ "$result" == "https://raw.githubusercontent.com/openclaw/openclaw/v2026.4.9/docs/gateway/configuration.md" ]]
}

@test "resolve_source: local mode returns filesystem path" {
  export OPENCLAW_SAGE_SOURCE="local:/tmp/myrepo/docs"
  source "$REPO_ROOT/scripts/lib.sh"
  result=$(resolve_source "gateway/configuration" "")
  [[ "$result" == "/tmp/myrepo/docs/gateway/configuration.md" ]]
}

# --- fetch_markdown ---

@test "fetch_markdown: fetches local file and writes .md and .txt" {
  cat > "$TEST_CACHE/source.md" <<'MD'
---
title: "Test Doc"
---
# Test heading
Some content.
MD
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  source "$REPO_ROOT/scripts/lib.sh"
  VERSION_CACHE_DIR="$TEST_CACHE/latest"
  mkdir -p "$VERSION_CACHE_DIR"
  fetch_markdown "source" "latest"
  [ -f "$VERSION_CACHE_DIR/doc_source.md" ]
  [ -f "$VERSION_CACHE_DIR/doc_source.txt" ]
}

# --- parse_version_flag ---

@test "parse_version_flag: sets VERSION to latest when no --version given" {
  source "$REPO_ROOT/scripts/lib.sh"
  parse_version_flag   # no args
  [[ "$VERSION" == "latest" ]]
  [[ "$VERSION_CACHE_DIR" == "$CACHE_DIR/latest" ]]
}

@test "parse_version_flag: sets VERSION from --version flag" {
  source "$REPO_ROOT/scripts/lib.sh"
  parse_version_flag --version v2026.4.9
  [[ "$VERSION" == "v2026.4.9" ]]
  [[ "$VERSION_CACHE_DIR" == "$CACHE_DIR/v2026.4.9" ]]
}

@test "parse_version_flag: trailing args after --version are preserved in REMAINING_ARGS" {
  source "$REPO_ROOT/scripts/lib.sh"
  parse_version_flag --version v2026.4.9 gateway/configuration --toc
  [[ "$VERSION" == "v2026.4.9" ]]
  [[ "${REMAINING_ARGS[0]}" == "gateway/configuration" ]]
  [[ "${REMAINING_ARGS[1]}" == "--toc" ]]
}
