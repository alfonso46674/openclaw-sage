# ENH-26: GitHub/Local Markdown Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the HTML fetch pipeline with Markdown-source fetching from GitHub or a local repo clone, adding `--version <tag>` support to all scripts.

**Architecture:** Thin adapter layer — replace fetch internals in `lib.sh` (`fetch_and_cache`, `fetch_text`, `clean_html_file`, `html_to_text`) with `fetch_markdown`, `resolve_source`, and `clean_markdown`. All consumer scripts gain `--version` flag support via a shared `parse_version_flag` helper that sets `VERSION_CACHE_DIR`. Cache layout changes from flat `$CACHE_DIR/doc_*.txt` to `$CACHE_DIR/<version>/doc_*.{md,txt}`.

**Tech Stack:** bash, python3 (stdlib: `re`, `json`, `urllib`), bats (tests), `curl` (github mode only)

**Spec:** `docs/superpowers/specs/2026-04-23-github-source-design.md`

---

## File Map

| File | Action | What changes |
| --- | --- | --- |
| `scripts/lib.sh` | Modify | Replace HTML pipeline with `resolve_source`, `fetch_markdown`, `clean_markdown`. Add `VERSION_CACHE_DIR`, `OPENCLAW_SAGE_SOURCE`, `parse_version_flag`. Remove `clean_html_file`, `html_to_text`, `fetch_and_cache`, `fetch_text`, `SITEMAP_TTL`. Update `check_online`. |
| `scripts/build-index.sh` | Modify | `fetch`: use `docs.json` discovery + `fetch_markdown`. All subcommands: call `parse_version_flag`, use `VERSION_CACHE_DIR`. |
| `scripts/sitemap.sh` | Modify | Parse `docs.json` instead of `sitemap.xml`. Add `parse_version_flag`. Remove `SITEMAP_TTL` references. |
| `scripts/cache.sh` | Modify | `status`: list version subdirs. `clear-docs`: scope to version or all. `refresh`: remove sitemap.xml logic. Add `tags` subcommand. Remove `SITEMAP_TTL` references. |
| `scripts/fetch-doc.sh` | Modify | Add `parse_version_flag`. Use `VERSION_CACHE_DIR`. Replace HTML `--toc`/`--section` parser with markdown `#` heading parser. Remove HTML backfill logic. |
| `scripts/info.sh` | Modify | Add `parse_version_flag`. Use `VERSION_CACHE_DIR`. Extract title from YAML frontmatter in `.md` instead of HTML `<title>`. Remove HTML backfill. |
| `scripts/search.sh` | Modify | Add `parse_version_flag`. Use `VERSION_CACHE_DIR`. |
| `scripts/recent.sh` | Modify | Add `parse_version_flag`. Use `VERSION_CACHE_DIR`. Remove sitemap lastmod section. Keep local mtime section. |
| `scripts/track-changes.sh` | Modify | Add `parse_version_flag`. Use `VERSION_CACHE_DIR`. Remove sitemap fetch. |
| `tests/test_lib.bats` | Modify | Replace HTML-pipeline tests with `fetch_markdown`, `clean_markdown`, `resolve_source` tests. |
| `tests/test_cache.bats` | Modify | Update `status` tests for versioned layout. Add `tags` subcommand tests. |
| `tests/test_sitemap.bats` | Modify | Replace sitemap.xml fixture tests with `docs.json` fixture tests. |
| `tests/test_fetch_doc.bats` | Modify | Replace HTML heading fixture tests with markdown fixture tests. Add `--version` flag tests. |
| `tests/test_info.bats` | Modify | Replace HTML title fixture with frontmatter fixture. Add `--version` tests. |
| `tests/test_build_index.bats` | Modify | Update `fetch` tests to use `docs.json` + `file://` markdown source. Add `--version` tests. |
| `tests/test_search.bats` | Modify | Add `--version` flag tests. |
| `tests/test_recent.bats` | Modify | Remove lastmod tests. Update for new "updated at source" removal. |
| `README.md` | Modify | New env var, new `--version` flag, remove `lynx`/`w3m`, update cache table. |
| `SKILL.md` | Modify | Update tool descriptions for `--version` flag and source modes. |

---

## Task 1: Replace lib.sh fetch pipeline + add version infrastructure

This is the foundation. Everything else depends on it.

**Files:**
- Modify: `scripts/lib.sh`
- Modify: `tests/test_lib.bats`

- [ ] **Step 1: Write failing tests for `clean_markdown`**

Add to `tests/test_lib.bats`:

```bash
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
\`\`\`json
{ "key": "<Value>" }
\`\`\`
After code.
MD
  source "$REPO_ROOT/scripts/lib.sh"
  clean_markdown "$TEST_CACHE/input.md" "$TEST_CACHE/output.txt"
  run cat "$TEST_CACHE/output.txt"
  [[ "$output" == *'"key": "<Value>"'* ]]
}

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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/test_lib.bats 2>&1 | tail -20
```

Expected: multiple failures — functions don't exist yet.

- [ ] **Step 3: Replace lib.sh fetch pipeline**

In `scripts/lib.sh`, make these changes:

1. Replace the `SITEMAP_TTL` line with `SOURCE`:
```bash
SOURCE="${OPENCLAW_SAGE_SOURCE:-github}"   # "github" or "local:/path/to/docs"
GITHUB_REPO="openclaw/openclaw"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}"
```

2. Add `parse_version_flag` after the variable declarations:
```bash
# parse_version_flag [args...] — extracts --version <tag> from args,
# sets VERSION and VERSION_CACHE_DIR, returns remaining args in REMAINING_ARGS
parse_version_flag() {
  VERSION="latest"
  REMAINING_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --version)
        shift
        VERSION="${1:?--version requires a tag argument}"
        shift   # consume the tag value; outer shift would advance past next real arg
        continue
        ;;
      *)
        REMAINING_ARGS+=("$1")
        ;;
    esac
    shift
  done
  # local mode always uses "local" as the version label
  if [[ "$SOURCE" == local:* ]]; then
    VERSION="local"
  fi
  VERSION_CACHE_DIR="${CACHE_DIR}/${VERSION}"
  mkdir -p "$VERSION_CACHE_DIR"
}
```

3. Add `resolve_source`:
```bash
# resolve_source <doc_path> <ref> — returns URL or filesystem path for a doc
resolve_source() {
  local doc_path="$1" ref="${2:-main}"
  if [[ "$SOURCE" == local:* ]]; then
    local local_path="${SOURCE#local:}"
    echo "${local_path}/${doc_path}.md"
  else
    echo "${GITHUB_RAW}/${ref}/docs/${doc_path}.md"
  fi
}
```

4. Add `clean_markdown` (Python heredoc):
```bash
# clean_markdown <input.md> <output.txt> — strip frontmatter/MDX, write plain text
clean_markdown() {
  local input="$1" output="$2"
  python3 - "$input" "$output" <<'PYEOF'
import sys, re

input_path, output_path = sys.argv[1], sys.argv[2]
with open(input_path, encoding='utf-8', errors='replace') as f:
    text = f.read()

# Extract frontmatter title/summary before stripping
title, summary = '', ''
fm_match = re.match(r'^---\s*\n(.*?)\n---\s*(?:\n|$)', text, re.S)
if fm_match:
    fm = fm_match.group(1)
    m = re.search(r'^title:\s*["\']?(.*?)["\']?\s*$', fm, re.M)
    if m: title = m.group(1).strip()
    m = re.search(r'^summary:\s*["\']?(.*?)["\']?\s*$', fm, re.M)
    if m: summary = m.group(1).strip()
    text = text[fm_match.end():]

# Protect fenced code blocks from tag stripping
fences = {}
def protect(m):
    key = f'\x00FENCE{len(fences)}\x00'
    fences[key] = m.group(0)
    return key
text = re.sub(r'```.*?```', protect, text, flags=re.S)
text = re.sub(r'`[^`]+`', protect, text)

# Strip self-closing MDX tags: <Tag ... />
text = re.sub(r'<[A-Z][A-Za-z]*[^>]*/>', '', text)
# Strip paired MDX tags, keep inner text: <Tag ...>content</Tag>
# Loop until stable to handle nested tags (e.g. <CardGroup><Card>text</Card></CardGroup>)
prev = None
while prev != text:
    prev = text
    text = re.sub(r'<([A-Z][A-Za-z]*)[^>]*>(.*?)</\1>', r'\2', text, flags=re.S)

# Restore fenced code blocks
for key, val in fences.items():
    text = text.replace(key, val)

header = '\n'.join(filter(None, [title, summary]))
if header:
    text = header + '\n\n' + text

with open(output_path, 'w', encoding='utf-8') as f:
    f.write(text.strip() + '\n')
PYEOF
}
```

5. Add `fetch_markdown`:
```bash
# fetch_markdown <safe_path> <ref> — fetch .md from source, clean to .txt
# Writes: $VERSION_CACHE_DIR/doc_<safe_path>.md
#         $VERSION_CACHE_DIR/doc_<safe_path>.txt
# Returns 0 on success, 1 on failure.
fetch_markdown() {
  local safe="$1" ref="${2:-main}"
  local doc_path
  doc_path="$(echo "$safe" | tr '_' '/')"
  local source
  source="$(resolve_source "$doc_path" "$ref")"
  local md_file="${VERSION_CACHE_DIR}/doc_${safe}.md"
  local txt_file="${VERSION_CACHE_DIR}/doc_${safe}.txt"
  local tmp_md
  tmp_md=$(mktemp)
  trap 'rm -f "$tmp_md"' RETURN

  if [[ "$SOURCE" == local:* ]]; then
    if [ ! -f "$source" ]; then
      rm -f "$tmp_md"
      return 1
    fi
    cp "$source" "$tmp_md"
  else
    if ! curl -sf --max-time 15 "$source" -o "$tmp_md" 2>/dev/null || [ ! -s "$tmp_md" ]; then
      rm -f "$tmp_md"
      return 1
    fi
  fi

  mv "$tmp_md" "$md_file"
  clean_markdown "$md_file" "$txt_file"

  if [ ! -s "$txt_file" ]; then
    rm -f "$txt_file"
    return 1
  fi
}
```

6. Update `check_online`:
```bash
check_online() {
  if [[ "$SOURCE" == local:* ]]; then
    local local_path="${SOURCE#local:}"
    [ -d "$local_path" ]
  else
    curl -sf --max-time 2 -o /dev/null -I "https://raw.githubusercontent.com" 2>/dev/null
  fi
}
```

7. **Remove** these functions entirely: `clean_html_file`, `html_to_text`, `fetch_and_cache`, `fetch_text`.

8. **Remove** the `SITEMAP_TTL` variable declaration line.

- [ ] **Step 4: Run tests**

```bash
bats tests/test_lib.bats
```

Expected: all new tests pass. Some old HTML-pipeline tests will now fail — remove them (they tested `fetch_text`/`clean_html_file` which are gone).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib.sh tests/test_lib.bats
git commit -m "feat(lib): replace HTML fetch pipeline with markdown source (ENH-26)

- Add resolve_source, fetch_markdown, clean_markdown, parse_version_flag
- Add VERSION_CACHE_DIR per-version cache layout
- Add OPENCLAW_SAGE_SOURCE env var (github|local:path)
- Remove clean_html_file, html_to_text, fetch_and_cache, fetch_text
- Remove SITEMAP_TTL"
```

---

## Task 2: Update build-index.sh fetch to use docs.json + fetch_markdown

**Files:**
- Modify: `scripts/build-index.sh`
- Modify: `tests/test_build_index.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_build_index.bats`:

```bash
@test "build-index fetch: uses docs.json from local source" {
  # Set up local source with a minimal docs.json and one markdown file
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

@test "build-index fetch --version: caches into versioned subdirectory" {
  local src="$TEST_CACHE/src"
  mkdir -p "$src/gateway"
  cat > "$src/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[{"tab":"Docs","groups":[{"group":"Gateway","pages":["gateway/configuration"]}]}]}]}}
JSON
  cat > "$src/gateway/configuration.md" <<'MD'
# Config
MD
  export OPENCLAW_SAGE_SOURCE="local:$src"
  # --version is ignored in local mode (uses "local" label), so just verify layout
  run "$REPO_ROOT/scripts/build-index.sh" fetch
  [ "$status" -eq 0 ]
  [ -d "$TEST_CACHE/local" ]
}

@test "build-index fetch: exits 1 when offline and source is github" {
  export OPENCLAW_SAGE_SOURCE="github"
  # Stub curl to always fail, simulating no network
  curl() { return 1; }
  export -f curl
  run "$REPO_ROOT/scripts/build-index.sh" fetch
  [ "$status" -eq 1 ]
  [[ "$output" == *"Offline"* || "$stderr" == *"Offline"* ]]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/test_build_index.bats 2>&1 | tail -20
```

- [ ] **Step 3: Update build-index.sh fetch subcommand**

Replace the `fetch)` case in `scripts/build-index.sh`:

1. At the top of the script (after `source lib.sh`), add:
```bash
parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"
```
Wrap this inside each `case` branch, not globally — because `build-index.sh` uses `$1` for subcommand dispatch. Instead, parse version per-subcommand. Use the pattern:
```bash
case "$1" in
  fetch)
    shift
    parse_version_flag "$@"
    REF="$VERSION"
    [ "$VERSION" = "latest" ] && REF="main"
    ...
```

2. Replace the sitemap.xml discovery block with `docs.json` discovery:
```bash
DOCS_JSON_CACHE="${VERSION_CACHE_DIR}/docs.json"
DOCS_JSON_SOURCE="$(resolve_source_raw "docs.json" "$REF")"

# Fetch docs.json if not cached or stale
if ! is_cache_fresh "$DOCS_JSON_CACHE" "$DOC_TTL"; then
  if [[ "$SOURCE" == local:* ]]; then
    local_path="${SOURCE#local:}"
    if [ ! -f "${local_path}/docs.json" ]; then
      echo "Error: docs.json not found at ${local_path}/docs.json" >&2
      exit 1
    fi
    cp "${local_path}/docs.json" "$DOCS_JSON_CACHE"
  else
    if ! check_online; then
      echo "Offline: cannot reach GitHub" >&2
      exit 1
    fi
    if ! curl -sf --max-time 10 "$DOCS_JSON_SOURCE" -o "$DOCS_JSON_CACHE" 2>/dev/null; then
      echo "Error: failed to fetch docs.json" >&2
      exit 1
    fi
  fi
fi

# Extract all doc paths from docs.json navigation tree
PATHS=$(python3 - "$DOCS_JSON_CACHE" <<'PYEOF'
import sys, json

def collect(node, paths):
    if isinstance(node, str):
        paths.append(node)
    elif isinstance(node, dict):
        for v in node.values():
            collect(v, paths)
    elif isinstance(node, list):
        for item in node:
            collect(item, paths)

with open(sys.argv[1]) as f:
    data = json.load(f)

paths = []
nav = data.get('navigation', {})
collect(nav.get('languages', []), paths)
# Filter to actual page paths (skip group names, tab names, etc.)
# Pages are strings without spaces that look like paths
paths = [p for p in paths if '/' in p or (p and ' ' not in p and p != 'en')]
for p in sorted(set(paths)):
    print(p)
PYEOF
)

if [ -z "$PATHS" ]; then
  echo "Error: Could not extract doc paths from docs.json" >&2
  exit 1
fi
```

3. Update the parallel fetch loop — replace `fetch_and_cache "$url" "$safe"` with `fetch_markdown "$safe" "$REF"`:
```bash
export OPENCLAW_SAGE_CACHE_DIR OPENCLAW_SAGE_SOURCE LIB_SH MARKER_DIR
export VERSION_CACHE_DIR REF

echo "$PATHS" | tr '\n' '\0' | xargs -0 -n 1 -P "$fetch_jobs" bash -c '
  source "$LIB_SH"
  path="$1"
  [ -z "$path" ] && exit 0
  safe=$(echo "$path" | tr "/" "_")
  txt_file="${VERSION_CACHE_DIR}/doc_${safe}.txt"
  if [ ! -f "$txt_file" ] || ! is_cache_fresh "$txt_file" "$DOC_TTL"; then
    if fetch_markdown "$safe" "$REF"; then
      touch "${MARKER_DIR}/${safe}"
      echo "  [done] $path" >&2
    fi
    sleep 0.3
  fi
' --
```

4. Update the `build`, `search`, and `status` subcommands to call `parse_version_flag` and use `VERSION_CACHE_DIR` instead of `CACHE_DIR` for doc/index paths:
```bash
  build)
    shift
    parse_version_flag "$@"
    INDEX_FILE="${VERSION_CACHE_DIR}/index.txt"
    META_FILE="${VERSION_CACHE_DIR}/index_meta.json"
    # rest of build logic unchanged, using VERSION_CACHE_DIR
    ...
  search)
    shift
    parse_version_flag "$@"
    set -- "${REMAINING_ARGS[@]}"
    INDEX_FILE="${VERSION_CACHE_DIR}/index.txt"
    ...
  status)
    shift
    parse_version_flag "$@"
    doc_count=$(ls "$VERSION_CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
    ...
```

Also add a helper to `lib.sh` for fetching docs.json URL (to avoid duplicating the URL construction):
```bash
# resolve_source_raw <relative_path> <ref> — like resolve_source but for non-doc paths
resolve_source_raw() {
  local rel_path="$1" ref="${2:-main}"
  if [[ "$SOURCE" == local:* ]]; then
    echo "${SOURCE#local:}/${rel_path}"
  else
    echo "${GITHUB_RAW}/${ref}/docs/${rel_path}"
  fi
}
```

- [ ] **Step 4: Run tests**

```bash
bats tests/test_build_index.bats
```

Expected: new tests pass. Remove or update any existing tests that referenced `sitemap.xml` fetch.

- [ ] **Step 5: Smoke test manually**

```bash
export OPENCLAW_SAGE_SOURCE="local:/home/alfonso/WebProjects/openclaw/docs"
./scripts/build-index.sh fetch
ls .cache/openclaw-sage/local/ | head -10
cat .cache/openclaw-sage/local/doc_gateway_configuration.txt | head -20
```

- [ ] **Step 6: Commit**

```bash
git add scripts/build-index.sh tests/test_build_index.bats
git commit -m "feat(build-index): use docs.json discovery and fetch_markdown (ENH-26)

- fetch: read doc list from docs.json instead of sitemap.xml
- All subcommands: call parse_version_flag, use VERSION_CACHE_DIR
- Parallel xargs loop preserved, now calls fetch_markdown"
```

---

## Task 3: Update sitemap.sh to parse docs.json

**Files:**
- Modify: `scripts/sitemap.sh`
- Modify: `tests/test_sitemap.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_sitemap.bats`:

```bash
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
  run python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['category'])" <<< "$output"
  [[ "$output" == *"gateway"* ]]
}

@test "sitemap: uses cached docs.json when fresh" {
  mkdir -p "$TEST_CACHE/local"
  cat > "$TEST_CACHE/local/docs.json" <<'JSON'
{"navigation":{"languages":[{"language":"en","tabs":[
  {"tab":"Docs","groups":[{"group":"Start","pages":["start/index"]}]}
]}]}}
JSON
  # Use a non-existent local path so any miss would fail; TTL ensures cache hit
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/nonexistent"
  export OPENCLAW_SAGE_DOC_TTL=99999
  run "$REPO_ROOT/scripts/sitemap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"start/index"* ]]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/test_sitemap.bats 2>&1 | tail -20
```

- [ ] **Step 3: Rewrite sitemap.sh**

Replace the full content of `scripts/sitemap.sh`:

```bash
#!/bin/bash
# Sitemap generator — reads doc list from docs.json (local or GitHub)
# Usage: sitemap.sh [--version <tag>] [--json]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

JSON=false
[[ "${OPENCLAW_SAGE_OUTPUT}" == "json" ]] && JSON=true

parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"
for arg in "$@"; do
  [ "$arg" = "--json" ] && JSON=true
done

REF="$VERSION"
[ "$VERSION" = "latest" ] && REF="main"
DOCS_JSON_CACHE="${VERSION_CACHE_DIR}/docs.json"

# Ensure docs.json is cached
if ! is_cache_fresh "$DOCS_JSON_CACHE" "$DOC_TTL"; then
  if [[ "$SOURCE" == local:* ]]; then
    local_path="${SOURCE#local:}"
    cp "${local_path}/docs.json" "$DOCS_JSON_CACHE" 2>/dev/null || true
  else
    if check_online; then
      src_url="$(resolve_source_raw "docs.json" "$REF")"
      curl -sf --max-time 10 "$src_url" -o "$DOCS_JSON_CACHE" 2>/dev/null
    else
      echo "Offline: cannot reach GitHub" >&2
      [ -f "$DOCS_JSON_CACHE" ] && echo "Using stale cached docs.json." >&2
    fi
  fi
fi

if [ ! -f "$DOCS_JSON_CACHE" ]; then
  echo "Error: docs.json not available. Run build-index.sh fetch first." >&2
  exit 1
fi

if $JSON; then
  if ! command -v python3 &>/dev/null; then
    echo '{"error": "python3 required for --json output"}' >&2
    exit 1
  fi
  python3 - "$DOCS_JSON_CACHE" <<'PYEOF'
import sys, json
from collections import defaultdict

with open(sys.argv[1]) as f:
    data = json.load(f)

def collect_pages(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for item in node:
            yield from collect_pages(item)
    elif isinstance(node, dict):
        if 'pages' in node:
            yield from collect_pages(node['pages'])
        else:
            for v in node.values():
                yield from collect_pages(v)

categories = defaultdict(list)
for path in collect_pages(data.get('navigation', {})):
    if '/' not in path:
        continue
    cat = path.split('/')[0]
    if cat:
        categories[cat].append(path)

result = [{'category': cat, 'paths': sorted(paths)}
          for cat, paths in sorted(categories.items())]
print(json.dumps(result, indent=2))
PYEOF
else
  python3 - "$DOCS_JSON_CACHE" <<'PYEOF'
import sys, json
from collections import defaultdict

with open(sys.argv[1]) as f:
    data = json.load(f)

def collect_pages(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for item in node:
            yield from collect_pages(item)
    elif isinstance(node, dict):
        if 'pages' in node:
            yield from collect_pages(node['pages'])
        else:
            for v in node.values():
                yield from collect_pages(v)

categories = defaultdict(list)
for path in collect_pages(data.get('navigation', {})):
    if '/' not in path:
        continue
    cat = path.split('/')[0]
    if cat:
        categories[cat].append(path)

for cat in sorted(categories):
    print(f"📁 /{cat}/")
    for path in sorted(categories[cat]):
        print(f"  - {path}")
    print()
PYEOF
fi
```

- [ ] **Step 4: Run tests**

```bash
bats tests/test_sitemap.bats
```

- [ ] **Step 5: Commit**

```bash
git add scripts/sitemap.sh tests/test_sitemap.bats
git commit -m "feat(sitemap): parse docs.json instead of sitemap.xml (ENH-26)"
```

---

## Task 4: Update fetch-doc.sh — version flag + markdown heading parser

**Files:**
- Modify: `scripts/fetch-doc.sh`
- Modify: `tests/test_fetch_doc.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_fetch_doc.bats`:

```bash
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
  # H1 has no indent, H2 has 2 spaces, H3 has 4 spaces
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
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/fetch-doc.sh" --version v2026.4.9 gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"Old config text"* ]]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/test_fetch_doc.bats 2>&1 | tail -20
```

- [ ] **Step 3: Update fetch-doc.sh**

Key changes:

1. Parse `--version` first (before `DOC_PATH`):
```bash
parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"
```

2. Change cache file vars to use `VERSION_CACHE_DIR`:
```bash
SAFE_PATH="$(echo "$DOC_PATH" | tr '/' '_')"
CACHE_FILE="${VERSION_CACHE_DIR}/doc_${SAFE_PATH}.txt"
MD_CACHE="${VERSION_CACHE_DIR}/doc_${SAFE_PATH}.md"   # .md replaces .html
```

3. Update `_do_fetch` to call `fetch_markdown`:
```bash
_do_fetch() {
  echo "Fetching: $DOC_PATH" >&2
  REF="$VERSION"; [ "$VERSION" = "latest" ] && REF="main"
  if ! fetch_markdown "$SAFE_PATH" "$REF"; then
    echo "Error: Failed to fetch: $DOC_PATH" >&2
    echo "Check the path is valid. Run ./scripts/sitemap.sh to see available docs." >&2
    exit 1
  fi
}
```

4. Replace the `--toc` and `--section` HTML parsers with markdown `#` parsers:

```bash
  toc)
    if [ ! -f "$MD_CACHE" ]; then
      echo "Error: --toc requires a fetched cache (run without --toc first)." >&2
      exit 1
    fi
    grep '^#' "$MD_CACHE" | while IFS= read -r line; do
      hashes=$(echo "$line" | sed 's/[^#].*//')
      level=${#hashes}
      text=$(echo "$line" | sed 's/^#* *//')
      printf '%*s%s\n' "$(( (level - 1) * 2 ))" '' "$text"
    done
    ;;

  section)
    if [ -z "$SECTION" ]; then
      echo "Error: --section requires a heading name." >&2; exit 1
    fi
    if [ ! -f "$MD_CACHE" ]; then
      echo "Error: --section requires a fetched cache (run without flags first)." >&2; exit 1
    fi
    python3 - "$MD_CACHE" "$SECTION" <<'PYEOF'
import sys, re

with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
    text = f.read()
query = sys.argv[2].lower()

headings = [(m.start(), len(m.group(1)), m.group(2).strip())
            for m in re.finditer(r'^(#{1,6})\s+(.+)$', text, re.M)]

if not headings:
    print("No headings found.", file=sys.stderr); sys.exit(1)

match_idx = next((i for i, (_, _, txt) in enumerate(headings)
                  if query in txt.lower()), None)
if match_idx is None:
    print(f"Section not found: {sys.argv[2]}", file=sys.stderr)
    for _, lvl, txt in headings:
        print(f"  {'  '*(lvl-1)}{txt}", file=sys.stderr)
    sys.exit(1)

start = headings[match_idx][0]
level = headings[match_idx][1]
end = next((headings[i][0] for i in range(match_idx+1, len(headings))
            if headings[i][1] <= level), len(text))
print(text[start:end].strip())
PYEOF
    ;;
```

5. Remove the HTML backfill block (lines checking `[ ! -f "$HTML_CACHE" ]`).

- [ ] **Step 4: Run tests**

```bash
bats tests/test_fetch_doc.bats
```

- [ ] **Step 5: Commit**

```bash
git add scripts/fetch-doc.sh tests/test_fetch_doc.bats
git commit -m "feat(fetch-doc): markdown heading parser, --version flag (ENH-26)

- Replace HTML toc/section parser with markdown # heading parser
- Add --version flag via parse_version_flag
- Remove HTML backfill logic (.html cache replaced by .md)"
```

---

## Task 5: Update cache.sh — versioned status + tags subcommand

**Files:**
- Modify: `scripts/cache.sh`
- Modify: `tests/test_cache.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_cache.bats`:

```bash
@test "status: lists version subdirectories with doc counts" {
  mkdir -p "$TEST_CACHE/latest" "$TEST_CACHE/v2026.4.9"
  touch "$TEST_CACHE/latest/doc_a.txt" "$TEST_CACHE/latest/doc_b.txt"
  touch "$TEST_CACHE/v2026.4.9/doc_a.txt"
  run "$REPO_ROOT/scripts/cache.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest"* ]]
  [[ "$output" == *"v2026.4.9"* ]]
  [[ "$output" == *"2"* ]]
}

@test "tags: prints message when source is local" {
  export OPENCLAW_SAGE_SOURCE="local:/tmp/myrepo"
  run "$REPO_ROOT/scripts/cache.sh" tags
  [ "$status" -eq 0 ]
  [[ "$output" == *"not available"* || "$output" == *"local"* ]]
}

@test "clear-docs: removes docs only from active version dir" {
  mkdir -p "$TEST_CACHE/latest" "$TEST_CACHE/v2026.4.9"
  touch "$TEST_CACHE/latest/doc_a.txt" "$TEST_CACHE/latest/index.txt"
  touch "$TEST_CACHE/v2026.4.9/doc_a.txt"
  run "$REPO_ROOT/scripts/cache.sh" clear-docs
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_CACHE/latest/doc_a.txt" ]
  # other version untouched
  [ -f "$TEST_CACHE/v2026.4.9/doc_a.txt" ]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/test_cache.bats 2>&1 | tail -20
```

- [ ] **Step 3: Update cache.sh**

Rewrite `scripts/cache.sh`:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"

case "$1" in
  status)
    echo "Cache location: $CACHE_DIR"
    echo ""
    echo "Cached versions:"
    found=0
    for d in "$CACHE_DIR"/*/; do
      [ -d "$d" ] || continue
      ver=$(basename "$d")
      doc_count=$(ls "$d"doc_*.txt 2>/dev/null | wc -l | tr -d ' ')
      if [ -f "${d}index.txt" ]; then
        idx="index: built"
      else
        idx="index: not built"
      fi
      printf "  %-16s  %s docs   %s\n" "$ver" "$doc_count" "$idx"
      found=1
    done
    [ "$found" -eq 0 ] && echo "  (none — run build-index.sh fetch)"
    echo ""
    echo "TTL config (override with env vars):"
    echo "  Docs:  ${DOC_TTL}s  (OPENCLAW_SAGE_DOC_TTL)"
    echo "  Dir:   ${CACHE_DIR}  (OPENCLAW_SAGE_CACHE_DIR)"
    echo "  Source: ${SOURCE}  (OPENCLAW_SAGE_SOURCE)"
    ;;

  refresh)
    echo "Clearing docs.json cache for version: $VERSION"
    rm -f "${VERSION_CACHE_DIR}/docs.json"
    echo "docs.json cleared. Next sitemap.sh or build-index.sh fetch will re-fetch."
    ;;

  clear-docs)
    count=$(ls "$VERSION_CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l | tr -d ' ')
    rm -f "${VERSION_CACHE_DIR}"/doc_*.txt \
          "${VERSION_CACHE_DIR}"/doc_*.md \
          "${VERSION_CACHE_DIR}/index.txt" \
          "${VERSION_CACHE_DIR}/index_meta.json"
    echo "Cleared $count cached docs and index from version: $VERSION"
    ;;

  tags)
    if [[ "$SOURCE" == local:* ]]; then
      echo "Tag listing not available for local source mode."
      echo "The local repo on disk is the only available version."
      exit 0
    fi
    TAGS_CACHE="${CACHE_DIR}/github_tags.json"
    if ! is_cache_fresh "$TAGS_CACHE" "$DOC_TTL"; then
      echo "Fetching available OpenClaw release tags..." >&2
      if ! curl -sf --max-time 10 \
          -H "Accept: application/vnd.github+json" \
          -H "User-Agent: openclaw-sage" \
          "https://api.github.com/repos/openclaw/openclaw/tags?per_page=30" \
          -o "$TAGS_CACHE" 2>/dev/null; then
        echo "Error: failed to fetch tags from GitHub API" >&2
        exit 1
      fi
    fi
    python3 - "$TAGS_CACHE" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    tags = json.load(f)
print("Available OpenClaw releases (most recent first):")
for t in tags:
    print(f"  {t['name']}")
print()
print("Fetch a version: ./scripts/build-index.sh fetch --version <tag>")
PYEOF
    ;;

  dir)
    echo "$VERSION_CACHE_DIR"
    ;;

  *)
    echo "Usage: cache.sh {status|refresh|clear-docs|tags|dir} [--version <tag>]"
    ;;
esac
```

- [ ] **Step 4: Run tests**

```bash
bats tests/test_cache.bats
```

- [ ] **Step 5: Commit**

```bash
git add scripts/cache.sh tests/test_cache.bats
git commit -m "feat(cache): versioned status, tags subcommand, clear-docs scoped to version (ENH-26)"
```

---

## Task 6: Update info.sh — frontmatter title + version flag

**Files:**
- Modify: `scripts/info.sh`
- Modify: `tests/test_info.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_info.bats`:

```bash
@test "info: extracts title from YAML frontmatter in .md cache" {
  mkdir -p "$TEST_CACHE/local"
  cat > "$TEST_CACHE/local/doc_gateway_configuration.md" <<'MD'
---
title: "Gateway Configuration"
summary: "Config overview"
---
# Config
MD
  echo "word content here" > "$TEST_CACHE/local/doc_gateway_configuration.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/info.sh" gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gateway Configuration"* ]]
}

@test "info --version: reads from versioned cache dir" {
  mkdir -p "$TEST_CACHE/v2026.4.9"
  cat > "$TEST_CACHE/v2026.4.9/doc_gateway_configuration.md" <<'MD'
---
title: "Old Config"
---
MD
  echo "words" > "$TEST_CACHE/v2026.4.9/doc_gateway_configuration.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/info.sh" --version v2026.4.9 gateway/configuration
  [ "$status" -eq 0 ]
  [[ "$output" == *"Old Config"* ]]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/test_info.bats 2>&1 | tail -20
```

- [ ] **Step 3: Update info.sh**

Key changes:

1. Add `parse_version_flag` before arg parsing (but after the first arg check, since `$1` is the path). Parse version from all args first, then re-parse path from `REMAINING_ARGS`:
```bash
parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"

if [ -z "$1" ] || [[ "$1" == --* ]]; then
  echo "Usage: info.sh [--version <tag>] <path> [--json]"
  exit 1
fi
DOC_PATH="${1#/}"; shift
```

2. Change cache paths to use `VERSION_CACHE_DIR`:
```bash
CACHE_FILE="${VERSION_CACHE_DIR}/doc_${SAFE_PATH}.txt"
MD_CACHE="${VERSION_CACHE_DIR}/doc_${SAFE_PATH}.md"
```

3. Replace the existence check and HTML backfill:
```bash
if [ ! -f "$CACHE_FILE" ] && [ ! -f "$MD_CACHE" ]; then
  # not cached
  ...
fi
# remove the HTML backfill block entirely
```

4. In the Python block, replace HTML title extraction with frontmatter extraction:
```python
# Title from .md frontmatter
if os.path.exists(md_cache):
    with open(md_cache, encoding='utf-8', errors='replace') as f:
        md = f.read()
    fm = re.match(r'^---\s*\n(.*?)\n---', md, re.S)
    if fm:
        m = re.search(r'^title:\s*["\']?(.*?)["\']?\s*$', fm.group(1), re.M)
        if m: title = m.group(1).strip()
    # Headings from markdown
    headings = [m.group(2).strip()
                for m in re.finditer(r'^#{1,6}\s+(.+)$', md, re.M)]
```

Pass `md_cache` instead of `html_cache` to the Python invocation.

- [ ] **Step 4: Run tests**

```bash
bats tests/test_info.bats
```

- [ ] **Step 5: Commit**

```bash
git add scripts/info.sh tests/test_info.bats
git commit -m "feat(info): frontmatter title extraction, --version flag (ENH-26)"
```

---

## Task 7: Update search.sh, recent.sh, track-changes.sh — version flag

**Files:**
- Modify: `scripts/search.sh`
- Modify: `scripts/recent.sh`
- Modify: `scripts/track-changes.sh`
- Modify: `tests/test_search.bats`
- Modify: `tests/test_recent.bats`
- Modify: `tests/test_track_changes.bats`

These are mechanical: add `parse_version_flag`, use `VERSION_CACHE_DIR`. `recent.sh` also drops the sitemap lastmod section.

- [ ] **Step 1: Write failing tests for search.sh --version**

Add to `tests/test_search.bats`:

```bash
@test "search --version: searches index in versioned cache dir" {
  mkdir -p "$TEST_CACHE/v2026.4.9"
  echo "gateway/configuration|Configure retry settings" > "$TEST_CACHE/v2026.4.9/index.txt"
  export OPENCLAW_SAGE_SOURCE="local:$TEST_CACHE/src"
  run "$REPO_ROOT/scripts/search.sh" --version v2026.4.9 retry
  [ "$status" -eq 0 ]
  [[ "$output" == *"gateway/configuration"* ]]
}
```

- [ ] **Step 2: Write failing test for recent.sh**

Add to `tests/test_recent.bats`:

```bash
@test "recent: does not show 'updated at source' section" {
  run "$REPO_ROOT/scripts/recent.sh"
  [[ "$output" != *"updated at source"* ]]
  [[ "$output" == *"Recently accessed locally"* ]]
}

@test "recent: shows cache.sh status hint" {
  run "$REPO_ROOT/scripts/recent.sh"
  [[ "$output" == *"cache.sh status"* ]]
}

@test "recent --version: accepts --version flag without erroring" {
  run "$REPO_ROOT/scripts/recent.sh" --version v2026.4.9
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recently accessed locally"* ]]
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
bats tests/test_search.bats tests/test_recent.bats 2>&1 | tail -20
```

- [ ] **Step 4: Update search.sh**

In `scripts/search.sh`, after `source lib.sh`:

1. Parse `--version` before the other flags:
```bash
parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"
```

2. Change `INDEX_FILE` and `doc_*.txt` glob to use `VERSION_CACHE_DIR`:
```bash
INDEX_FILE="${VERSION_CACHE_DIR}/index.txt"
```

And in the grep fallback section, change `"$CACHE_DIR"/doc_*.txt` to `"$VERSION_CACHE_DIR"/doc_*.txt`.

- [ ] **Step 5: Update recent.sh**

Replace the sitemap lastmod section with a hint. New `recent.sh`:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_version_flag "$@"
set -- "${REMAINING_ARGS[@]}"
DAYS=${1:-7}

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "Usage: recent.sh [--version <tag>] [days]" >&2
  echo "  days must be a positive integer (default: 7)" >&2
  exit 1
fi

echo "=== Recently accessed locally (last $DAYS days) ==="
echo ""

found=0
while IFS= read -r f; do
  path=$(basename "$f" .txt | sed 's/^doc_//; s/_/\//g')
  echo "  $path"
  found=1
done < <(find "$VERSION_CACHE_DIR" -name "doc_*.txt" -mtime "-${DAYS}" 2>/dev/null)

if [ "$found" -eq 0 ]; then
  echo "  (none — fetch docs with ./scripts/build-index.sh fetch)"
fi

echo ""
echo "Note: Source-level change dates are not available from docs.json."
echo "Run ./scripts/cache.sh status to see cached versions and fetch dates."
echo "Run ./scripts/cache.sh tags to list available OpenClaw release tags."
```

- [ ] **Step 6: Update track-changes.sh**

Add `parse_version_flag` at the top (after `source lib.sh`). Change all `$CACHE_DIR` references for doc/snapshot paths to `$VERSION_CACHE_DIR`. Remove the sitemap fetch block (the `get_current_pages` function that fetched `sitemap.xml`) — replace it with a `docs.json`-based page lister using the same Python tree-walk as `sitemap.sh`.

- [ ] **Step 7: Run tests**

```bash
bats tests/test_search.bats tests/test_recent.bats tests/test_track_changes.bats
```

- [ ] **Step 8: Commit**

```bash
git add scripts/search.sh scripts/recent.sh scripts/track-changes.sh \
        tests/test_search.bats tests/test_recent.bats tests/test_track_changes.bats
git commit -m "feat: add --version flag to search, recent, track-changes (ENH-26)

- All scripts use VERSION_CACHE_DIR from parse_version_flag
- recent.sh: remove sitemap lastmod section, add cache.sh status hint"
```

---

## Task 8: Update README.md and SKILL.md

**Files:**
- Modify: `README.md`
- Modify: `SKILL.md`

- [ ] **Step 1: Update README.md**

In the Environment Variables table:

1. Remove `OPENCLAW_SAGE_SITEMAP_TTL` row.
2. Add `OPENCLAW_SAGE_SOURCE` row: `| \`OPENCLAW_SAGE_SOURCE\` | \`github\` | Doc source: \`github\` or \`local:/path/to/openclaw/docs\` |`

In the Requirements section:
- Remove `lynx` and `w3m` optional deps (no longer used).

In the Cache section, update the table:
- Remove `sitemap.xml` and `sitemap.txt` rows.
- Add `<version>/docs.json`, `<version>/doc_<path>.md`, `<version>/doc_<path>.txt` rows.
- Note that each version gets its own subdirectory.

Add a new **Version Support** section after Environment Variables showing the `--version` flag examples.

- [ ] **Step 2: Update SKILL.md**

In the `build-index.sh fetch` entry, add:
```
**Version:** `--version <tag>` fetches docs at that OpenClaw git tag (default: latest from `main`).
```

In the `sitemap.sh` entry, add:
```
**Source:** reads from `docs.json` (GitHub or local repo, per `OPENCLAW_SAGE_SOURCE`).
```

Add `cache.sh tags` entry.

Update all script descriptions to mention `--version` flag support.

- [ ] **Step 3: Commit**

```bash
git add README.md SKILL.md
git commit -m "docs: update README and SKILL.md for ENH-26 (github source, --version flag)"
```

---

## Task 9: Full test suite pass + shellcheck

- [ ] **Step 1: Run the full bats test suite**

```bash
bats tests/
```

Expected: all tests pass. Fix any failures before proceeding.

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck --severity=error scripts/*.sh
```

Expected: clean. Fix any errors.

- [ ] **Step 3: Run pytest**

```bash
pytest tests/test_bm25.py -v
```

Expected: all pass (bm25_search.py is unchanged).

- [ ] **Step 4: End-to-end smoke test with local source**

```bash
export OPENCLAW_SAGE_SOURCE="local:/home/alfonso/WebProjects/openclaw/docs"
./scripts/build-index.sh fetch
./scripts/build-index.sh build
./scripts/search.sh webhook
./scripts/fetch-doc.sh gateway/configuration --toc
./scripts/sitemap.sh | head -20
./scripts/cache.sh status
```

- [ ] **Step 5: End-to-end smoke test with github source**

```bash
unset OPENCLAW_SAGE_SOURCE   # defaults to github
./scripts/cache.sh tags
./scripts/build-index.sh fetch --version v2026.4.22
./scripts/fetch-doc.sh --version v2026.4.22 gateway/configuration | head -20
```

- [ ] **Step 6: Update backlog and spec**

In `docs/backlog.md`, mark ENH-26 status as `done — <commit SHA>`.
In `docs/superpowers/specs/2026-04-23-github-source-design.md`, change `**Status:** Draft` to `**Status:** Implemented`.

- [ ] **Step 7: Update CHANGELOG.md**

Add ENH-26 under `[Unreleased]` with a summary of all changes.

- [ ] **Step 8: Final commit**

```bash
git add docs/backlog.md docs/superpowers/specs/2026-04-23-github-source-design.md CHANGELOG.md
git commit -m "chore: mark ENH-26 complete, update backlog and changelog"
```
