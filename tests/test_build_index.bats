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
  export TEST_BIN
  TEST_BIN="$TEST_CACHE/bin"
  mkdir -p "$TEST_BIN"
  # Seed a local HTML file — used as a file:// URL so no HTTP server is needed
  echo "<html><body><h1>Hello</h1><p>World</p></body></html>" > "$TEST_CACHE/fixture.html"
  cat > "$TEST_CACHE/noisy_fixture.html" <<'HTML'
<html>
  <body>
    <header>Header links</header>
    <nav>Docs nav</nav>
    <main>
      <h1>Guide Title</h1>
      <p>Useful body text.</p>
      <script>
        const shouldNotAppear = "script noise";
      </script>
      <style>
        .hidden { display: none; }
      </style>
    </main>
    <footer>Footer links</footer>
  </body>
</html>
HTML
}

teardown() {
  rm -rf "$TEST_CACHE"
}

# ---------------------------------------------------------------------------
# BUG-07 — fetch_and_cache writes both .html and .txt
# ---------------------------------------------------------------------------

@test "BUG-07: fetch_and_cache writes .txt file" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' source '$LIB_SH'; fetch_and_cache 'file://$TEST_CACHE/fixture.html' 'test_page'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_CACHE/doc_test_page.txt" ]
}

@test "BUG-07: fetch_and_cache writes .html file (regression — was never written before fix)" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' source '$LIB_SH'; fetch_and_cache 'file://$TEST_CACHE/fixture.html' 'test_page'"
  [ "$status" -eq 0 ]
  # Key regression: before BUG-07 fix, the .html file was never created
  [ -f "$TEST_CACHE/doc_test_page.html" ]
}

@test "BUG-07: fetch_and_cache returns 1 and writes nothing on unreachable URL" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' source '$LIB_SH'; fetch_and_cache 'http://127.0.0.1:1/nope' 'missing_page'"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_CACHE/doc_missing_page.txt" ]
  [ ! -f "$TEST_CACHE/doc_missing_page.html" ]
}

@test "BUG-10: fetch_and_cache strips chrome/script/style noise while preserving content headings" {
  run bash -c "OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' source '$LIB_SH'; fetch_and_cache 'file://$TEST_CACHE/noisy_fixture.html' 'clean_page'"
  [ "$status" -eq 0 ]

  [ -f "$TEST_CACHE/doc_clean_page.html" ]
  [ -f "$TEST_CACHE/doc_clean_page.txt" ]

  grep -q "<h1>Guide Title</h1>" "$TEST_CACHE/doc_clean_page.html"
  ! grep -qi "<header" "$TEST_CACHE/doc_clean_page.html"
  ! grep -qi "<nav" "$TEST_CACHE/doc_clean_page.html"
  ! grep -qi "<footer" "$TEST_CACHE/doc_clean_page.html"
  ! grep -qi "<script" "$TEST_CACHE/doc_clean_page.html"
  ! grep -qi "<style" "$TEST_CACHE/doc_clean_page.html"

  grep -q "Guide Title" "$TEST_CACHE/doc_clean_page.txt"
  grep -q "Useful body text" "$TEST_CACHE/doc_clean_page.txt"
  ! grep -q "Header links" "$TEST_CACHE/doc_clean_page.txt"
  ! grep -q "Docs nav" "$TEST_CACHE/doc_clean_page.txt"
  ! grep -q "Footer links" "$TEST_CACHE/doc_clean_page.txt"
  ! grep -q "shouldNotAppear" "$TEST_CACHE/doc_clean_page.txt"
  ! grep -q "display: none" "$TEST_CACHE/doc_clean_page.txt"
}

# ---------------------------------------------------------------------------
# BUG-20 — error message goes to stderr, not stdout
# ---------------------------------------------------------------------------

@test "BUG-20: fetch empty-URL error goes to stderr not stdout" {
  # Seed a sitemap with URLs that won't match the LANGS filter
  cat > "$TEST_CACHE/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://docs.openclaw.ai/xx/nonexistent</loc></url>
</urlset>
XML
  # Use a wrapper that stubs check_online so the script gets past the online check
  local stderr_file="$TEST_CACHE/stderr.txt"
  local stdout_file="$TEST_CACHE/stdout.txt"
  bash -c "
    export OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE'
    export OPENCLAW_SAGE_DOCS_BASE_URL='https://docs.openclaw.ai'
    export OPENCLAW_SAGE_LANGS='en'
    # Stub check_online in lib.sh by defining it after sourcing
    source '$REPO_ROOT/scripts/lib.sh'
    check_online() { return 0; }
    # Source the script to get the case block, passing 'fetch' as \$1
    set -- fetch
    source '$BUILD_INDEX_SH'
  " >"$stdout_file" 2>"$stderr_file" || true
  # Error should be in stderr
  grep -q "Error: Could not get URL list" "$stderr_file"
  # Error should NOT be in stdout
  ! grep -q "Error: Could not get URL list" "$stdout_file"
}

# ---------------------------------------------------------------------------
# BUG-11 — sitemap fetch failures should be reported directly
# ---------------------------------------------------------------------------

@test "BUG-11: fetch stops with sitemap fetch error when sitemap curl fails" {
  cat > "$TEST_BIN/curl" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  if [ "$arg" = "-I" ]; then
    exit 0
  fi
done
exit 7
EOF
  chmod +x "$TEST_BIN/curl"

  run env PATH="$TEST_BIN:$PATH" \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    OPENCLAW_SAGE_DOCS_BASE_URL="https://docs.openclaw.ai" \
    "$BUILD_INDEX_SH" fetch

  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: failed to fetch sitemap"* ]]
  [[ "$output" != *"Error: Could not get URL list from sitemap"* ]]
}

# ---------------------------------------------------------------------------
# BUG-12 — build must stop if build-meta fails
# ---------------------------------------------------------------------------

@test "BUG-12: build stops with error when build-meta fails" {
  echo "searchterm in doc content" > "$TEST_CACHE/doc_test_page.txt"

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
# BUG-16 — progress rendering should fully overwrite prior paths
# ---------------------------------------------------------------------------

@test "BUG-16: fetch progress does not leave suffix garbage when a shorter path follows a longer one" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi

  cat > "$TEST_CACHE/sitemap.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://docs.openclaw.ai/providers/very-long-provider-name/troubleshooting</loc></url>
  <url><loc>https://docs.openclaw.ai/providers/discord</loc></url>
</urlset>
XML

  echo "cached content" > "$TEST_CACHE/doc_providers_very-long-provider-name_troubleshooting.txt"
  echo "cached content" > "$TEST_CACHE/doc_providers_discord.txt"

  cat > "$TEST_BIN/curl" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  if [ "$arg" = "-I" ]; then
    exit 0
  fi
done
exit 7
EOF
  chmod +x "$TEST_BIN/curl"

  run env PATH="$TEST_BIN:$PATH" \
    OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
    OPENCLAW_SAGE_DOCS_BASE_URL="https://docs.openclaw.ai" \
    "$BUILD_INDEX_SH" fetch

  [ "$status" -eq 0 ]

  local rendered
  rendered="$(python3 - "$output" <<'PYEOF'
import sys
text = sys.argv[1]
lines = []
line = []
cursor = 0

for ch in text:
    if ch == '\r':
        cursor = 0
    elif ch == '\n':
        lines.append(''.join(line))
        line = []
        cursor = 0
    else:
        if cursor >= len(line):
            line.extend(' ' * (cursor - len(line) + 1))
        line[cursor] = ch
        cursor += 1

if line:
    lines.append(''.join(line))

print('\n'.join(lines))
PYEOF
)"

  [[ "$rendered" == *"[2/2] providers/discord"* ]]
  [[ "$rendered" != *"providers/discord"*troubleshooting* ]]
}

# ---------------------------------------------------------------------------
# BUG-17 — hardcoded URL regression in build-index.sh
# ---------------------------------------------------------------------------

@test "BUG-17: build-index search output uses DOCS_BASE_URL not hardcoded URL" {
  echo "searchterm in doc content" > "$TEST_CACHE/doc_test_page.txt"
  printf 'test/page|searchterm in doc content\n' > "$TEST_CACHE/index.txt"
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  run bash -c "OPENCLAW_SAGE_DOCS_BASE_URL='https://custom.example.com' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$BUILD_INDEX_SH' search searchterm 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom.example.com"* ]]
}

# ---------------------------------------------------------------------------
# build-index status
# ---------------------------------------------------------------------------

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
