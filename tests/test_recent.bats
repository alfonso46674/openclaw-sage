#!/usr/bin/env bats
# Tests for scripts/recent.sh
# Covers: BUG-08 (TTL-based sitemap refresh) and BUG-09 ($DAYS argument validation)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RECENT_SH="$REPO_ROOT/scripts/recent.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  # Point at an unreachable host so no real network calls happen
  export OPENCLAW_SAGE_DOCS_BASE_URL="http://127.0.0.1:1"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# Minimal valid sitemap XML with one recent and one old entry
_seed_sitemap() {
  cat > "$TEST_CACHE/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://docs.openclaw.ai/gateway/configuration</loc>
    <lastmod>2099-01-01</lastmod>
  </url>
  <url>
    <loc>https://docs.openclaw.ai/providers/discord</loc>
    <lastmod>2000-01-01</lastmod>
  </url>
</urlset>
XML
}

# ---------------------------------------------------------------------------
# BUG-09 — $DAYS validation
# ---------------------------------------------------------------------------

@test "BUG-09: non-numeric argument exits 1 with usage message" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' '$RECENT_SH' foo 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "BUG-09: float argument exits 1 with usage message" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' '$RECENT_SH' 3.5 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "BUG-09: numeric argument is accepted" {
  _seed_sitemap
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' '$RECENT_SH' 14 2>&1"
  [ "$status" -eq 0 ]
}

@test "BUG-09: default (no argument) runs without error" {
  _seed_sitemap
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' '$RECENT_SH' 2>&1"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# BUG-08 — TTL-based sitemap refresh
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# BUG-17 — hardcoded URL regression in recent.sh
# ---------------------------------------------------------------------------

@test "BUG-17: recent.sh uses DOCS_BASE_URL not hardcoded URL for path extraction" {
  # Seed a sitemap with a custom base URL
  cat > "$TEST_CACHE/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://custom.example.com/gateway/configuration</loc>
    <lastmod>2099-01-01</lastmod>
  </url>
</urlset>
XML
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               OPENCLAW_SAGE_DOCS_BASE_URL='https://custom.example.com' \
               '$RECENT_SH' 9999 2>&1"
  [ "$status" -eq 0 ]
  # The path should be extracted correctly (not contain the full URL or wrong prefix)
  [[ "$output" == *"gateway/configuration"* ]]
  # Should NOT still contain the old hardcoded URL residue
  [[ "$output" != *"https://custom.example.com/gateway/configuration"* ]]
}

# ---------------------------------------------------------------------------
# BUG-08 — TTL-based sitemap refresh
# ---------------------------------------------------------------------------

@test "BUG-08: stale sitemap triggers re-fetch attempt when online" {
  _seed_sitemap
  # Make the file appear older than SITEMAP_TTL (1 hour = 3600s) by setting mtime to 2 hours ago
  touch -t "$(date -d '2 hours ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-2H '+%Y%m%d%H%M.%S')" \
    "$TEST_CACHE/sitemap.xml" 2>/dev/null || true

  # Point at unreachable host — we just want to confirm the fetch attempt happened (Fetching sitemap...)
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' OPENCLAW_SAGE_SITEMAP_TTL=1 '$RECENT_SH' 2>&1"
  # Script should attempt a fetch (offline message or "Fetching sitemap..." expected)
  # Either way it should still succeed (serves stale cache)
  [[ "$output" == *"Offline"* ]] || [[ "$output" == *"Fetching"* ]]
}

@test "BUG-08: fresh sitemap is served without re-fetching" {
  _seed_sitemap
  # File just written — should be fresh with default TTL
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' '$RECENT_SH' 2>&1"
  [ "$status" -eq 0 ]
  # No fetch attempt since sitemap is fresh — no "Fetching sitemap..." in output
  [[ "$output" != *"Fetching sitemap"* ]]
}

@test "BUG-08: sitemap with TTL=1 triggers refresh on second run" {
  _seed_sitemap
  # First run with TTL=1 — file is fresh, no fetch
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' OPENCLAW_SAGE_SITEMAP_TTL=1 '$RECENT_SH' 2>&1"
  [ "$status" -eq 0 ]
  sleep 2
  # Second run — TTL expired, should attempt re-fetch
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' OPENCLAW_SAGE_DOCS_BASE_URL='http://127.0.0.1:1' OPENCLAW_SAGE_SITEMAP_TTL=1 '$RECENT_SH' 2>&1"
  [[ "$output" == *"Offline"* ]] || [[ "$output" == *"Fetching"* ]]
}
