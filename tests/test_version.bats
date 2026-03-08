#!/usr/bin/env bats
# Version consistency checks across package.json, _meta.json, and CHANGELOG.md

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "package.json and _meta.json versions match" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  PKG_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/package.json'))['version'])")
  META_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/_meta.json'))['version'])")
  [ "$PKG_VERSION" = "$META_VERSION" ]
}

@test "package.json version has an entry in CHANGELOG.md" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  PKG_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/package.json'))['version'])")
  grep -qF "[$PKG_VERSION]" "$REPO_ROOT/CHANGELOG.md"
}

@test "package.json version field is a valid semver string" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  PKG_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/package.json'))['version'])")
  [[ "$PKG_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "_meta.json slug matches name field" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  SLUG=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/_meta.json'))['slug'])")
  NAME=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/_meta.json'))['name'])")
  [ "$SLUG" = "$NAME" ]
}

@test "all scripts source lib.sh" {
  for script in "$REPO_ROOT"/scripts/*.sh; do
    grep -q 'source.*lib\.sh' "$script" || {
      echo "FAIL: $script does not source lib.sh"
      return 1
    }
  done
}
