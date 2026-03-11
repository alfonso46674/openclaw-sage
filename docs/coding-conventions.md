# Coding Conventions

Conventions for contributing to openclaw-sage. See [`CLAUDE.md`](../CLAUDE.md) for the short version.

---

## Architecture

```
scripts/
  lib.sh            # Shared constants and functions — sourced by all scripts
  bm25_search.py    # BM25 ranking engine — called by build-index.sh and search.sh
  sitemap.sh        # Fetch/display available docs by category
  fetch-doc.sh      # Fetch a specific doc (text, toc, section, max-lines)
  search.sh         # Keyword search over cached docs
  build-index.sh    # Bulk fetch, index build, BM25 search, status
  recent.sh         # Docs updated recently (sitemap lastmod + local mtime)
  cache.sh          # Cache management (status, refresh, clear-docs, dir)
  track-changes.sh  # Sitemap snapshot diffing
snippets/
  common-configs.md # Inline config examples for agents
docs/               # Developer documentation
.cache/             # Runtime cache — gitignored, created automatically
SKILL.md            # Agent-facing tool reference
AGENTS.md           # Quick-reference for AI agents using this skill
```

---

## Adding a New Script — Checklist

1. **Source lib.sh first** (after setting `SCRIPT_DIR`):
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   source "$SCRIPT_DIR/lib.sh"
   ```

2. **Use shared variables** — never define your own values for these:
   - `$CACHE_DIR`, `$DOCS_BASE_URL`, `$SITEMAP_TTL`, `$DOC_TTL`, `$LANGS`

3. **Use `is_cache_fresh <file> <ttl>`** for cache checks. Do not reimplement it.

4. **Use `fetch_text <url>`** for plain-text HTML conversion. Do not reimplement it.

5. **Cache everything you fetch.** No script should make a network request without writing the result to `$CACHE_DIR`.

6. **Support `--json`** if the script produces structured results. See [JSON conventions](#json-output) below.

7. **Write to stdout, diagnostics to stderr.** Progress messages and warnings go to `>&2` only.

8. **Add the script to `SKILL.md`** with: purpose, when to use, input, output format, errors.

9. **Add the script to `CHANGELOG.md`** under the next version.

---

## lib.sh — What Belongs There

**Add to lib.sh:**
- Constants shared by 3+ scripts
- Functions used by 3+ scripts
- New env var overrides (use the `OPENCLAW_SAGE_*` prefix)

**Do not add to lib.sh:**
- Script-specific logic
- Functions used by only one script
- Anything with side effects beyond `mkdir -p "$CACHE_DIR"`

---

## Cache Conventions

### File naming

| Content | Pattern | Example |
|---|---|---|
| Doc plain text | `doc_<path_underscored>.txt` | `doc_gateway_configuration.txt` |
| Doc raw HTML | `doc_<path_underscored>.html` | `doc_gateway_configuration.html` |
| Sitemap XML | `sitemap.xml` | |
| Sitemap text | `sitemap.txt` | |
| Full-text index | `index.txt` | |
| BM25 meta | `index_meta.json` | |
| Snapshots | `snapshots/<YYYYMMDD_HHMMSS>.txt` | |

Path construction pattern:
```bash
SAFE_PATH="$(echo "$DOC_PATH" | tr '/' '_')"
CACHE_FILE="${CACHE_DIR}/doc_${SAFE_PATH}.txt"
```

### TTL usage

Always pass TTL explicitly — never hardcode seconds in a script body:
```bash
is_cache_fresh "$CACHE_FILE" "$DOC_TTL"
is_cache_fresh "$SITEMAP_CACHE" "$SITEMAP_TTL"
```

If you need a new TTL, add it to `lib.sh` as an `OPENCLAW_SAGE_*` variable.

### Dual-cache design (`.html` + `.txt`)

Every fetched doc is stored as two files:

| File | Used by |
|---|---|
| `doc_<safe>.html` | `fetch-doc.sh --toc`, `fetch-doc.sh --section`, `info.sh` (title + headings) |
| `doc_<safe>.txt` | `fetch-doc.sh` (text mode), `search.sh`, `build-index.sh build` |

**Why both?** HTML→text conversion is lossy: tags are stripped and structure is gone. Once flattened to `.txt`, you can no longer tell which lines were headings — so `--toc` and `--section` can't work. Storing `.html` preserves the DOM structure needed for Python-based heading/section extraction.

Storing `.txt` separately means every plain-text read (fetch, search, index build) is a direct `cat` or `grep` — no conversion cost at read time. The cost is paid once at fetch time via `fetch_and_cache`.

**Do not store only `.html`** — every search and text read would pay the HTML→text conversion cost. **Do not store only `.txt`** — `--toc`, `--section`, and `info.sh` headings stop working.

Use `fetch_and_cache <url> <safe_path>` (defined in `lib.sh`) for all doc fetches — it handles both files in a single HTTP request.

### Temp files

Always clean up with `trap`. Use single quotes so the variable expands at exit time, not when the trap is registered:
```bash
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT   # correct — single-quoted, expands at exit
trap "rm -f $TMP" EXIT     # wrong  — double-quoted, expands now; breaks if TMPDIR has spaces
```

---

## Output Conventions

### stdout vs stderr

- **stdout** — the script's actual output (text, JSON, results)
- **stderr** — progress, "Fetching...", warnings, diagnostics

```bash
echo "Fetching: $URL" >&2   # correct
echo "Fetching: $URL"       # wrong — pollutes stdout
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Usage error or unrecoverable failure |

Do not use codes >1.

### Human-readable output

- Plain ASCII for anything agents might parse. Emoji are acceptable in category headers (e.g. `📁 /gateway/`) but must never appear in JSON or in structured result lines.
- Consistent result line format: `[score] path  ->  url` with an indented excerpt on the next line.

### JSON output

Support both `--json` flag and `OPENCLAW_SAGE_OUTPUT=json` env var:

```bash
JSON=false
[[ "${OPENCLAW_SAGE_OUTPUT}" == "json" ]] && JSON=true
for arg in "$@"; do
  [ "$arg" = "--json" ] && JSON=true
done
```

Use Python for all JSON serialization. Never build JSON with bash string concatenation:

```bash
if $JSON; then
  python3 - "$arg1" "$arg2" <<'PYEOF'
import sys, json
# build result dict/list
print(json.dumps(result, indent=2))
PYEOF
  exit 0
fi
```

JSON output must be the only thing on stdout. Error messages go to stderr as plain text (not JSON).

---

## Python Conventions

### When to use Python

- JSON serialization (always — never build JSON with bash string ops)
- XML parsing (`sitemap.xml`, HTML heading extraction)
- BM25 math and ranking
- Date arithmetic

### When NOT to use Python (keep it in bash)

Calling `python3` has overhead and adds an optional dependency. Do not invoke it for operations bash handles natively:

- String manipulation (`tr`, `sed`, `awk`, parameter expansion)
- Simple arithmetic (`$(( ))`)
- File existence and size checks
- Emitting a plain-text error message

When a code path needs to emit JSON **and** `python3` may not be available, prefer a `command -v python3` guard with a plain-text fallback rather than forcing the Python call:

```bash
# Correct — JSON when possible, plain text when not
if $JSON && command -v python3 &>/dev/null; then
  python3 - "$value" <<'PYEOF'
import sys, json
print(json.dumps({"key": sys.argv[1]}))
PYEOF
else
  echo "Error: $value"
fi

# Wrong — unconditional python3 call for a trivial error string
python3 - "$value" <<'PYEOF'
import sys, json
print(json.dumps({"error": sys.argv[1]}))
PYEOF
```

### Inline heredoc vs separate file

- **Inline heredoc** — use for single-purpose logic under ~30 lines.
- **Separate `.py` file** — use when logic is reused by multiple scripts or exceeds ~30 lines.

### Heredoc quoting

Always quote the delimiter to prevent bash variable expansion inside Python:
```bash
python3 - "$arg" <<'PYEOF'   # correct
python3 - "$arg" <<PYEOF     # wrong — bash expands $vars inside
PYEOF
```

### Pass data via `sys.argv`, not heredoc interpolation

```bash
# Correct — safe with any input including special characters
python3 - "$url" "$path" <<'PYEOF'
import sys
url, path = sys.argv[1], sys.argv[2]
PYEOF

# Wrong — breaks on quotes, spaces, injection risk
python3 <<PYEOF
url = "$url"
PYEOF
```

---

## What NOT To Do

| Don't | Why |
|---|---|
| Define `is_cache_fresh` or `fetch_text` in a script | Already in `lib.sh`; duplication causes drift |
| Hardcode `~/.cache/...` or `https://docs.openclaw.ai` | Use `$CACHE_DIR` and `$DOCS_BASE_URL` |
| Make uncached `curl` requests | Every fetch must be written to `$CACHE_DIR` |
| Add a new required dependency | `bash` and `curl` are the only hard requirements |
| Write diagnostic text to stdout | Agents parse stdout; mix-ins cause silent failures |
| Put emoji in JSON output or structured result lines | Breaks machine parsing |
| Build JSON with bash string concatenation | Escaping is unreliable; use Python |
| Skip sourcing `lib.sh` | Cache dir won't be set, shared functions unavailable |
| Call `python3` for trivial string or error output | Adds latency and an optional dependency; use bash natively |
| Use double-quoted `trap "rm -f $TMP" EXIT` | Variable expands at registration, not at exit; use single quotes |
| Use `grep -P` (PCRE) | Not available on macOS/BSD grep; use `grep -o` + `sed` instead |

---

## Testing a New Script

1. **Happy path** — normal invocation produces correct output.
2. **Cache hit** — running twice uses the cache (no "Fetching..." on second run).
3. **TTL override** — `OPENCLAW_SAGE_DOC_TTL=1` forces a re-fetch after 1 second.
4. **Offline** — disconnect network; script falls back gracefully without hanging.
5. **JSON output** — `--json` produces valid JSON:
   ```bash
   ./scripts/your-script.sh --json | python3 -c "import json,sys; json.load(sys.stdin); print('valid')"
   ```
6. **Temp file cleanup** — any `mktemp` files are removed via `trap` even on failure.
7. **SKILL.md updated** — new tool documented with purpose, input, output, and errors.
