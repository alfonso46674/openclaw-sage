#!/usr/bin/env bats
# Tests for scripts/sitemap.sh
# Also serves as a BUG-02 regression test: verifies the POSIX grep -o + sed
# replacement for grep -oP works correctly on both Linux and macOS.

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

_seed_sitemap_xml() {
  cat > "$TEST_CACHE/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://docs.openclaw.ai/gateway/configuration</loc></url>
  <url><loc>https://docs.openclaw.ai/gateway/security</loc></url>
  <url><loc>https://docs.openclaw.ai/providers/discord</loc></url>
  <url><loc>https://docs.openclaw.ai/providers/telegram</loc></url>
</urlset>
XML
}

# --- Human output ---

@test "human: serves fresh sitemap.txt from cache without fetching" {
  printf '📁 /gateway/\n  - gateway/configuration\n' > "$TEST_CACHE/sitemap.txt"
  run "$SITEMAP_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gateway"* ]]
}

@test "human: offline fallback is shown when no cache and host unreachable" {
  run bash -c "OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' '$SITEMAP_SH' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"automation"* ]]
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

@test "--json with seeded sitemap.xml returns a valid JSON array" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_sitemap_xml
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert isinstance(d,list)" "$output"
}

@test "--json extracts correct categories and paths from sitemap.xml (BUG-02 regression)" {
  # Verifies the POSIX grep -o + sed replacement for grep -oP works correctly.
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_sitemap_xml
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
  _seed_sitemap_xml
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"category"'* ]]
  [[ "$output" == *'"paths"'* ]]
}

@test "OPENCLAW_SAGE_OUTPUT=json works as --json alternative" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  _seed_sitemap_xml
  run env OPENCLAW_SAGE_OUTPUT=json OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
      OPENCLAW_SAGE_DOCS_BASE_URL="https://docs.openclaw.ai" "$SITEMAP_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"category"'* ]]
}

@test "--json with sitemap.xml containing multiple categories parses all of them" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  cat > "$TEST_CACHE/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://docs.openclaw.ai/gateway/configuration</loc></url>
  <url><loc>https://docs.openclaw.ai/cli/update</loc></url>
  <url><loc>https://docs.openclaw.ai/install/docker</loc></url>
</urlset>
XML
  run "$SITEMAP_SH" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gateway"'* ]]
  [[ "$output" == *'"cli"'* ]]
  [[ "$output" == *'"install"'* ]]
}
