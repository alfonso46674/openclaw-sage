#!/usr/bin/env bats
# Tests for scripts/search.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SEARCH_SH="$REPO_ROOT/scripts/search.sh"

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
  run "$SEARCH_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# --- No cache behaviour ---

@test "single keyword with no cache exits 0 and shows instructions" {
  run "$SEARCH_SH" webhook
  [ "$status" -eq 0 ]
  [[ "$output" == *"fetch"* ]]
}

@test "--json with no cache exits 0 and returns valid JSON envelope" {
  run "$SEARCH_SH" --json webhook
  [ "$status" -eq 0 ]
  [[ "$output" == *'"query"'* ]]
  [[ "$output" == *'"results"'* ]]
}

# --- Multi-word query handling ---

@test "multi-word query without quotes is joined correctly" {
  # Searching echo the query back in 'Searching docs for: <keyword>'
  run "$SEARCH_SH" webhook retry
  [ "$status" -eq 0 ]
  [[ "$output" == *"webhook retry"* ]]
}

@test "--json multi-word query reports both words in query field" {
  run "$SEARCH_SH" --json webhook retry
  [ "$status" -eq 0 ]
  [[ "$output" == *'"query"'* ]]
  [[ "$output" == *'webhook retry'* ]]
}

@test "flag before keyword still joins remaining args as query" {
  run "$SEARCH_SH" --json retry timeout error
  [ "$status" -eq 0 ]
  [[ "$output" == *'retry timeout error'* ]]
}

# --- Match in cached doc ---

@test "finds keyword in seeded cached doc" {
  echo "webhook retry configuration guide" > "$TEST_CACHE/doc_automation_webhook.txt"
  run "$SEARCH_SH" webhook
  [ "$status" -eq 0 ]
  [[ "$output" == *"automation/webhook"* ]]
}

@test "multi-word query finds doc containing both words" {
  echo "webhook retry configuration guide" > "$TEST_CACHE/doc_automation_webhook.txt"
  run "$SEARCH_SH" webhook retry
  [ "$status" -eq 0 ]
  [[ "$output" == *"automation/webhook"* ]]
}

@test "--json finds match in seeded doc" {
  echo "discord bot token setup" > "$TEST_CACHE/doc_providers_discord.txt"
  run "$SEARCH_SH" --json discord
  [ "$status" -eq 0 ]
  [[ "$output" == *"providers/discord"* ]]
}

# --- Sitemap path matches ---

@test "finds sitemap path match when sitemap.txt is seeded" {
  printf '📁 /providers/\n  - providers/discord\n  - providers/telegram\n' \
    > "$TEST_CACHE/sitemap.txt"
  run "$SEARCH_SH" discord
  [ "$status" -eq 0 ]
  [[ "$output" == *"providers/discord"* ]]
}

# --- BUG-01 regression: DOCS_BASE_URL respected in search output ---

@test "search output uses OPENCLAW_SAGE_DOCS_BASE_URL not a hardcoded URL (BUG-01 regression)" {
  # With an index and python3, the human BM25 path formats URLs using $DOCS_BASE_URL.
  # This catches any regression where the URL is hardcoded again.
  printf 'test/page|line containing searchkeyword here\n' > "$TEST_CACHE/index.txt"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run env OPENCLAW_SAGE_DOCS_BASE_URL="https://custom.example.com" \
      OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$SEARCH_SH" searchkeyword
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom.example.com"* ]]
}

# --- BUG-19 regression: diagnostic tip must not appear on stdout ---

@test "BUG-19: Tip text does not appear on stdout" {
  echo "webhook retry guide" > "$TEST_CACHE/doc_automation_webhook.txt"
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' '$SEARCH_SH' webhook 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Tip:"* ]]
}

@test "--json search output uses OPENCLAW_SAGE_DOCS_BASE_URL (BUG-01 regression)" {
  printf 'test/page|line containing searchkeyword here\n' > "$TEST_CACHE/index.txt"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run env OPENCLAW_SAGE_DOCS_BASE_URL="https://custom.example.com" \
      OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" "$SEARCH_SH" --json searchkeyword
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom.example.com"* ]]
}
