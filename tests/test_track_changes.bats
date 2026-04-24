#!/usr/bin/env bats
# Tests for scripts/track-changes.sh
#
# get_current_pages now reads paths from docs.json (not sitemap.xml).
# Tests that previously seeded sitemap.xml now seed docs.json instead.
# Snapshots live in $VERSION_CACHE_DIR/snapshots (= $CACHE_DIR/local/snapshots
# when using local source).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TRACK_SH="$REPO_ROOT/scripts/track-changes.sh"

setup() {
  export TEST_CACHE
  TEST_CACHE="$(mktemp -d)"
  export OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE"
  # Use local source so check_online passes without network
  export TEST_SRC="$TEST_CACHE/src"
  mkdir -p "$TEST_SRC"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_SRC"
  # VERSION_CACHE_DIR will be $TEST_CACHE/local (local source → VERSION=local)
  export TEST_VERSION_CACHE="$TEST_CACHE/local"
  mkdir -p "$TEST_VERSION_CACHE/snapshots"
}

teardown() {
  rm -rf "$TEST_CACHE"
}

_seed_snapshot() {
  # _seed_snapshot <name> <newline-separated paths>
  # comm requires sorted input — sort here to match what get_current_pages produces
  local name="$1"
  shift
  printf '%s\n' "$@" | sort > "$TEST_VERSION_CACHE/snapshots/${name}.txt"
}

# Seed a docs.json in the version cache dir with the given paths
_seed_docs_json() {
  local pages_json=""
  for p in "$@"; do
    pages_json+="\"$p\","
  done
  # trim trailing comma
  pages_json="${pages_json%,}"
  cat > "$TEST_VERSION_CACHE/docs.json" <<JSON
{
  "navigation": {
    "pages": [$pages_json]
  }
}
JSON
}

# --- Argument validation ---

@test "no args prints usage and exits 1" {
  run "$TRACK_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "unknown subcommand prints usage and exits 1" {
  run "$TRACK_SH" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# --- list ---

@test "list: no snapshots exits 0 with message" {
  run "$TRACK_SH" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No snapshots"* ]]
}

@test "list: shows formatted date for each seeded snapshot" {
  _seed_snapshot "20260101_120000" "providers/discord"
  _seed_snapshot "20260201_130000" "providers/telegram"
  run "$TRACK_SH" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-01-01"* ]]
  [[ "$output" == *"2026-02-01"* ]]
}

@test "list: shows snapshots in chronological order" {
  _seed_snapshot "20260201_130000" "providers/telegram"
  _seed_snapshot "20260101_120000" "providers/discord"
  run "$TRACK_SH" list
  [ "$status" -eq 0 ]
  [[ "$output" =~ 2026-01-01[[:print:][:space:]]*2026-02-01 ]]
}

@test "list: shows page count for each snapshot" {
  _seed_snapshot "20260101_120000" "providers/discord" "providers/telegram"
  run "$TRACK_SH" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 pages"* ]]
}

# --- diff ---

@test "diff: requires two snapshot names" {
  run "$TRACK_SH" diff
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "diff: missing first snapshot exits 1" {
  _seed_snapshot "20260201_000000" "providers/discord"
  run "$TRACK_SH" diff nonexistent 20260201_000000
  [ "$status" -eq 1 ]
}

@test "diff: missing second snapshot exits 1" {
  _seed_snapshot "20260101_000000" "providers/discord"
  run "$TRACK_SH" diff 20260101_000000 nonexistent
  [ "$status" -eq 1 ]
}

@test "diff: shows added page between two snapshots" {
  _seed_snapshot "20260101_000000" "providers/discord"
  _seed_snapshot "20260201_000000" "providers/discord" "providers/telegram"
  run "$TRACK_SH" diff 20260101_000000 20260201_000000
  [ "$status" -eq 0 ]
  [[ "$output" == *"providers/telegram"* ]]
  [[ "$output" == *"+"* ]]
}

@test "diff: shows removed page between two snapshots" {
  _seed_snapshot "20260101_000000" "providers/discord" "providers/telegram"
  _seed_snapshot "20260201_000000" "providers/discord"
  run "$TRACK_SH" diff 20260101_000000 20260201_000000
  [ "$status" -eq 0 ]
  [[ "$output" == *"providers/telegram"* ]]
  [[ "$output" == *"-"* ]]
}

@test "diff: no changes between identical snapshots exits 0" {
  _seed_snapshot "20260101_000000" "providers/discord"
  _seed_snapshot "20260201_000000" "providers/discord"
  run "$TRACK_SH" diff 20260101_000000 20260201_000000
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Added ==="* ]]
  [[ "$output" == *"=== Removed ==="* ]]
}

# --- since ---

@test "since: missing date arg exits 1 with usage" {
  run "$TRACK_SH" since
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "since: no snapshots exits 1" {
  run "$TRACK_SH" since 2026-01-01
  [ "$status" -eq 1 ]
  [[ "$output" == *"No snapshots"* ]]
}

@test "since: exits 1 with offline message when host unreachable (BUG-06 regression)" {
  # Verifies that when source is unavailable, since exits cleanly with a clear message.
  # Use local source pointing at a non-existent directory so check_online returns 1.
  _seed_snapshot "20260101_000000" "providers/discord"
  run bash -c "OPENCLAW_SAGE_SOURCE='local:/nonexistent' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$TRACK_SH' since 2026-01-01 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Offline"* ]]
}

@test "since: uses oldest snapshot when the requested date predates all snapshots" {
  _seed_snapshot "20260101_000000" "providers/discord"
  _seed_snapshot "20260201_000000" "providers/discord" "providers/telegram"

  # Seed docs.json so get_current_pages can read paths
  _seed_docs_json "providers/discord" "providers/telegram"

  run env OPENCLAW_SAGE_CACHE_DIR="$TEST_CACHE" \
      OPENCLAW_SAGE_SOURCE="local:$TEST_SRC" \
      "$TRACK_SH" since 2025-01-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"oldest snapshot (20260101_000000)"* ]]
  [[ "$output" == *"+ providers/telegram"* ]]
}

# --- snapshot ---

@test "snapshot: exits 1 with offline message when host unreachable" {
  # Use local source pointing at a non-existent directory so check_online returns 1.
  run bash -c "OPENCLAW_SAGE_SOURCE='local:/nonexistent' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$TRACK_SH' snapshot 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Offline"* ]]
}

@test "snapshot: does not create snapshot file when offline" {
  run bash -c "OPENCLAW_SAGE_SOURCE='local:/nonexistent' \
               OPENCLAW_SAGE_CACHE_DIR='$TEST_CACHE' \
               '$TRACK_SH' snapshot 2>&1"
  [ "$status" -eq 1 ]
  # No snapshot files should have been created
  local count
  count=$(find "$TEST_CACHE" -name "*.txt" -path "*/snapshots/*" | wc -l)
  [ "$count" -eq 0 ]
}
