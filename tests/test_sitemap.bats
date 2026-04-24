#!/usr/bin/env bats
# Tests for scripts/sitemap.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SITEMAP_SH="$REPO_ROOT/scripts/sitemap.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  export OPENCLAW_SAGE_DOCS_BASE_URL="https://docs.openclaw.ai"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

_seed_docs_json() {
  mkdir -p "$TEST_CACHE/latest"
  cat > "$TEST_CACHE/latest/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[
  {"tab":"Docs","groups":[
    {"group":"Gateway","pages":["gateway/configuration","gateway/security"]},
    {"group":"Providers","pages":["providers/discord","providers/telegram"]}
  ]}
]}]}}
JSON
}

# --- Human output ---

@test "human: serves categories from cached docs.json" {
  _seed_docs_json
  run "$SITEMAP_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gateway"* ]]
}

@test "human: missing docs.json with unreachable local source exits with error" {
  run bash -c "OPENCLAW_SAGE_SOURCE='local:/tmp/no-such-dir-$$' OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' '$SITEMAP_SH' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error"* ]]
}

# --- JSON output ---

@test "--json requires python3" {
  if command -v python3 &>/dev/null; then
    skip "python3 is available"
  fi
  run bash -c "\"$SITEMAP_SH\" --json 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"python3"* ]]
}

@test "--json with seeded docs.json returns a valid JSON array" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_docs_json
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert isinstance(d,list)" "$output"
}

@test "--json extracts correct categories and paths from docs.json" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_docs_json
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gateway"'* ]]
  [[ "$output" == *'"providers"'* ]]
  [[ "$output" == *'gateway/configuration'* ]]
  [[ "$output" == *'providers/discord'* ]]
}

@test "--json each entry has category and paths keys" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_docs_json
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"category"'* ]]
  [[ "$output" == *'"paths"'* ]]
}

@test "OPENCLAW_SAGE_OUTPUT=json works as --json alternative" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_docs_json
  run env OPENCLAW_SAGE_OUTPUT=json OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
      OPENCLAW_SAGE_DOCS_BASE_URL="https://docs.openclaw.ai" "$SITEMAP_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"category"'* ]]
}

@test "--json with docs.json containing multiple categories parses all of them" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  mkdir -p "$TEST_CACHE/latest"
  cat > "$TEST_CACHE/latest/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[
  {"tab":"Docs","groups":[
    {"group":"Gateway","pages":["gateway/configuration"]},
    {"group":"CLI","pages":["cli/update"]},
    {"group":"Install","pages":["install/docker"]}
  ]}
]}]}}
JSON
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gateway"'* ]]
  [[ "$output" == *'"cli"'* ]]
  [[ "$output" == *'"install"'* ]]
}

@test "sitemap: reads category structure from local docs.json" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[
  {"tab":"Docs","groups":[
    {"group":"Gateway","pages":["gateway/configuration","gateway/troubleshooting"]},
    {"group":"Install","pages":["install/docker"]}
  ]}
]}]}}
JSON
  export OPENCLAW_SAGE_SOURCE="local:$src"
  run "$REPO_ROOT/scripts/sitemap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gateway"* ]]
  [[ "$output" == *"gateway/configuration"* ]]
  [[ "$output" == *"install"* ]]
}

@test "sitemap --json: returns valid JSON with category/paths structure" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[
  {"tab":"Docs","groups":[
    {"group":"Gateway","pages":["gateway/configuration"]}
  ]}
]}]}}
JSON
  export OPENCLAW_SAGE_SOURCE="local:$src"
  run "$REPO_ROOT/scripts/sitemap.sh" --json
  [ "$status" -eq 0 ]
  python3 -c "import sys,json; d=json.loads('''$output'''); assert d[0]['category'] == 'gateway'"
}

@test "sitemap: uses cached docs.json when fresh" {
  mkdir -p "$TEST_CACHE/local"
  cat > "$TEST_CACHE/local/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[
  {"tab":"Docs","groups":[{"group":"Start","pages":["start/index"]}]}
]}]}}
JSON
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/nonexistent"
  export OPENCLAW_SAGE_DOC_TTL=99999
  run "$REPO_ROOT/scripts/sitemap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"start/index"* ]]
}
