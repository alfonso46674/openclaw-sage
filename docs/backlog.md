# openclaw-sage — Backlog

Last audited: 2026-03-08

This file tracks known bugs, tech debt, and planned enhancements. Any agent or developer picking up work here should read `docs/coding-conventions.md` first, then implement the item, update its status, and note the commit SHA.

---

## Bugs

Bugs are ordered by severity. Fix critical issues before any new feature work.

### Critical

#### BUG-01 — Hardcoded `docs.openclaw.ai` URL in awk fallback
- **Files:** `scripts/search.sh:141`, `scripts/build-index.sh:159`
- **Status:** done — faf8340
- **Description:** Both files construct result lines with a literal `https://docs.openclaw.ai/` in an awk block instead of using `$DOCS_BASE_URL`. Violates the critical rule and silently produces wrong output when `$DOCS_BASE_URL` is overridden.
- **Fix:** Pass the variable into awk with `-v base_url="$DOCS_BASE_URL"` and use `base_url` inside the block.

#### BUG-02 — `grep -oP` (PCRE) not available on macOS/BSD — silent failure
- **Files:** `scripts/sitemap.sh:105`, `scripts/build-index.sh:25`, `scripts/track-changes.sh:13`
- **Status:** done — b910b4f
- **Description:** BSD grep (macOS) does not support `-P`. All three scripts use `grep -oP '(?<=<loc>)[^<]+'` to extract URLs from `sitemap.xml`. On macOS this silently returns nothing, leading to misleading "Could not get URL list from sitemap" errors downstream. The macOS CI runner will fail these paths.
- **Fix:** Replace with a POSIX-safe alternative — either `grep -o '<loc>[^<]*</loc>' | sed 's/<[^>]*>//g'` or a Python one-liner consistent with how the rest of the codebase handles XML (e.g. `python3 -c "import sys,re; [print(m) for m in re.findall(r'<loc>([^<]+)</loc>', sys.stdin.read())]"`).

#### BUG-03 — `trap` with unquoted variable in `track-changes.sh`
- **File:** `scripts/track-changes.sh:85`
- **Status:** done — 00374b1
- **Description:** `trap "rm -f $AFTER_TMP" EXIT` expands `$AFTER_TMP` immediately when the trap is registered. If `TMPDIR` contains spaces, the path is word-split and `rm` receives incorrect arguments. The coding conventions prescribe single-quoted trap strings so the variable expands at exit time.
- **Fix:** `trap 'rm -f "$AFTER_TMP"' EXIT`

#### BUG-04 — `info.sh` builds JSON error with `printf` + user-interpolated input
- **File:** `scripts/info.sh:32`
- **Status:** done — 85ff911
- **Description:** `printf '{"error":"not_cached","path":"%s","url":"%s"}\n' "$DOC_PATH" "$URL"` interpolates user-supplied path values directly into a JSON string. A path containing `"` or `\` produces invalid JSON. Violates the "Use Python for JSON" convention.
- **Fix:** Emit the not-cached JSON error via a Python heredoc, passing `$DOC_PATH` and `$URL` as `sys.argv` arguments.

#### BUG-05 — Offline + `--toc`/`--section` shows wrong error message
- **File:** `scripts/fetch-doc.sh:73-94`
- **Status:** done — cb02389
- **Description:** When offline with a stale `.txt` cache but no `.html` cache, the script emits "Using stale cached content" on stderr and continues. The `toc`/`section` branches then fail with "run without --toc first" — which correctly states the symptom but hides the real cause (no HTML because the network is unreachable). The user/agent has no way to know this is an offline issue.
- **Fix:** In the `toc`/`section` branches, before the "html required" exit, check whether `check_online` would fail and surface "Offline: HTML cache unavailable — fetch with network access first."

---

### Important

#### BUG-06 — `get_current_pages` ignores `$SITEMAP_TTL`, corrupts shared cache on failure
- **File:** `scripts/track-changes.sh:10-17`
- **Status:** done — ac0efe1
- **Description:** The function unconditionally overwrites `$CACHE_DIR/sitemap.xml` on every call with a live `curl` request. (1) It ignores `$SITEMAP_TTL`, hammering the server even when the cached sitemap is fresh. (2) If `curl` fails silently (network down, `-sf` suppresses output), it truncates `sitemap.xml` to an empty file, corrupting the shared cache used by `sitemap.sh`, `recent.sh`, and `build-index.sh`.
- **Fix:** Wrap the fetch in an `is_cache_fresh "$SITEMAP_XML" "$SITEMAP_TTL"` check. If curl fails, do not overwrite the existing file (use a temp file + `mv` only on success).

#### BUG-07 — `build-index.sh fetch` never populates the HTML cache
- **File:** `scripts/build-index.sh:79`
- **Status:** open
- **Description:** Uses `fetch_text "$url" > "$cache_file"` which writes only the `.txt` file. The `.html` file is never created. Subsequent calls to `info.sh`, `fetch-doc.sh --toc`, or `fetch-doc.sh --section` on bulk-fetched docs will trigger a second network round-trip to backfill HTML, or fail entirely if offline.
- **Fix:** Mirror the dual-write pattern from `fetch-doc.sh`: fetch raw HTML to `doc_<safe>.html` first, then convert to `doc_<safe>.txt`. Centralise this into a shared `fetch_and_cache <url> <safe_path>` function in `lib.sh`.

#### BUG-08 — `recent.sh` uses file-existence check instead of TTL for sitemap
- **File:** `scripts/recent.sh:10`
- **Status:** open
- **Description:** `if [ ! -f "$SITEMAP_XML" ]` only fetches if the file is completely absent. A stale-but-existing sitemap is served without re-validation. Every other script uses `is_cache_fresh "$SITEMAP_XML" "$SITEMAP_TTL"`.
- **Fix:** Replace the existence check with `if ! is_cache_fresh "$SITEMAP_XML" "$SITEMAP_TTL"`.

#### BUG-09 — `recent.sh` does not validate `$DAYS` argument
- **File:** `scripts/recent.sh:3`
- **Status:** open
- **Description:** `DAYS=${1:-7}` is captured before `lib.sh` is sourced, with no integer validation. A non-numeric argument like `recent.sh foo` is passed to `find -mtime` (immediate error) and Python `int()` (unhandled exception), with no usage message shown to the user.
- **Fix:** After sourcing `lib.sh`, validate `$DAYS` with `[[ "$DAYS" =~ ^[0-9]+$ ]]` and print usage + exit 1 if invalid. Add a `Usage: recent.sh [days]` line.

---

### Medium / Tech Debt

#### BUG-10 — Single-line `sed` strips only single-line `<script>`/`<style>` tags
- **File:** `scripts/lib.sh:41-42`
- **Status:** open
- **Description:** The sed fallback HTML-to-text converter uses `sed 's/<script[^>]*>.*<\/script>//gI'`. Because `sed` processes one line at a time, multi-line script/style blocks (the norm in real HTML) are not stripped, leaving raw JavaScript and CSS in the `.txt` output.
- **Fix:** Replace with a Python heredoc that uses `re.sub` with `re.S` flag, consistent with the section/toc extraction already in `fetch-doc.sh`.

#### BUG-11 — `curl` exit code not checked after sitemap fetch in `build-index.sh`
- **File:** `scripts/build-index.sh:20-25`
- **Status:** open
- **Description:** `curl -sf ... -o "$SITEMAP_XML"` failure is silently ignored. If the fetch fails, `grep` on an empty/absent file produces no output, and the subsequent "Could not get URL list from sitemap. Run sitemap.sh first" message blames the wrong thing.
- **Fix:** Check `$?` after the curl call and emit "Error: failed to fetch sitemap (network unreachable?)" with exit 1.

#### BUG-12 — `build-index.sh build` does not check `build-meta` exit code
- **File:** `scripts/build-index.sh:117`
- **Status:** open
- **Description:** `python3 ... build-meta ...` failure (e.g. disk full writing `index_meta.json`) is not detected. The script continues and prints "Location: $INDEX_FILE" implying success.
- **Fix:** Add `|| { echo "Error: build-meta failed" >&2; exit 1; }` after the python3 call.

#### BUG-13 — `for f in $(ls ... | sort)` anti-pattern in `track-changes.sh`
- **File:** `scripts/track-changes.sh:49,75`
- **Status:** open
- **Description:** Parsing `ls` output is fragile and unnecessary. Snapshot filenames are always `YYYYMMDD_HHMMSS.txt` so glob sorts correctly.
- **Fix:** Replace `for f in $(ls "$SNAPSHOTS_DIR"/*.txt | sort)` with `for f in "$SNAPSHOTS_DIR"/*.txt`.

#### BUG-14 — Mtime OS detection logic duplicated across three files
- **Files:** `scripts/lib.sh:20-25`, `scripts/cache.sh:12-17`, `scripts/info.sh:124-126`
- **Status:** open
- **Description:** The macOS (`stat -f %m`) vs Linux (`stat -c %Y`) branch is copy-pasted in three places. The canonical version is in `lib.sh`; the others exist because they need the raw mtime integer for display (not just a freshness boolean). `is_cache_fresh` doesn't expose the value.
- **Fix:** Add a `get_mtime <file>` helper to `lib.sh` that returns the epoch integer. Call it from all three sites.

#### BUG-15 — `snippets/common-configs.md` references outdated model name
- **File:** `snippets/common-configs.md`
- **Status:** open
- **Description:** Line 105 uses `"anthropic/claude-sonnet-4-5"` while `SKILL.md` references `"anthropic/claude-sonnet-4-6"`. Both documents should reference the same current model.
- **Fix:** Update `snippets/common-configs.md` to use `claude-sonnet-4-6`.

---

## Enhancements

Grouped by effort. Items within each tier are ordered by agent value.

### Tier 3 (planned — not yet started)

#### ENH-07 — `ask.sh <question>` — one-shot answer tool
- **Status:** planned
- **Description:** Combines search + fetch into a single call. BM25-searches the question, fetches the top 2-3 relevant doc sections, and returns sources + concatenated excerpts. Eliminates the search → read → decide → fetch → read agent loop.
- **Inputs:** `<question text...>` (multi-word, no quotes needed), `[--json]`, `[--max-sections N]`
- **Output:** Labelled source blocks with doc path, section heading, excerpt. JSON mode: `{"question", "sources": [{"path", "section", "excerpt", "url"}]}`
- **Dependencies:** requires BM25 search + `fetch-doc.sh --section` to work correctly.

#### ENH-08 — Passage-level BM25 (chunked index)
- **Status:** planned
- **Description:** The current index scores whole documents. Split docs into overlapping ~10-line passages and index passages instead. Returns targeted excerpts rather than whole-doc scores. Critical for long docs.
- **Implementation notes:** `build-index.sh build` generates passages in `index.txt` (format: `path:chunk_id|passage_text`). `bm25_search.py` scores and returns `path:chunk_id` with passage excerpt. `search.sh` resolves chunk line offsets back to path.

---

### Tier 4 (new — proposed from 2026-03-08 audit)

#### ENH-09 — `search.sh --max-results N`
- **Status:** proposed
- **Description:** BM25 caps results at 20 internally but exposes no CLI control. Agents doing narrow queries want top-3; broad exploration queries want more. Simple one-line addition.
- **Implementation notes:** Pass `N` as a fourth argument to `bm25_search.py search` and slice the results list. Default `N=10`.

#### ENH-10 — `fetch-doc.sh --grep <pattern>`
- **Status:** proposed
- **Description:** Return only lines from the cached `.txt` matching a grep pattern. Simpler than `--section` for quick keyword-in-context lookups. Does not require HTML cache.
- **Example:** `fetch-doc.sh gateway/configuration --grep "timeout"`
- **Implementation notes:** Pipe `cat $CACHE_FILE` through `grep -i "$PATTERN"`. Exit 1 with "No matches" if grep returns nothing.

#### ENH-11 — `info.sh --batch <path1> <path2> ...`
- **Status:** proposed
- **Description:** Accept multiple paths and return metadata for all at once. Agents evaluating several candidate docs before fetching benefit from one call instead of N sequential calls.
- **Implementation notes:** Loop existing info logic over all positional args. JSON mode: return a JSON array. Human mode: print one block per doc separated by `---`.

#### ENH-12 — `cache pin <path>` / `cache unpin <path>`
- **Status:** proposed
- **Description:** Pin specific docs to prevent TTL-based eviction. Pinned docs are never considered stale by `is_cache_fresh`. Useful when an agent is actively working with a specific integration's docs across a long session.
- **Implementation notes:** Write pinned paths to `$CACHE_DIR/pinned.txt` (one path per line). Modify `is_cache_fresh` to check this file and return 0 (fresh) unconditionally for pinned paths.

#### ENH-13 — `fetch-doc.sh --format json`
- **Status:** proposed
- **Description:** Return doc content as a JSON object: `{"path", "title", "url", "word_count", "content"}`. Consistent with the `--json` pattern on other scripts and enables structured agent pipelines.
- **Implementation notes:** Reuse HTML title extraction from `info.sh`. Content is the plain `.txt` file contents. Only valid in `text` mode (not combinable with `--toc`/`--section`).

#### ENH-14 — Language-aware search
- **Status:** proposed
- **Description:** `$LANGS` filters doc fetching but `search.sh` scans all cached `.txt` files regardless. Add a `--lang <code>` flag that restricts BM25 and grep search to docs whose path includes the lang prefix.
- **Example:** `search.sh --lang fr webhook`

#### ENH-15 — Incremental index builds
- **Status:** proposed
- **Description:** `build-index.sh build` always rebuilds `index.txt` from scratch. For large corpora, a delta build that only reprocesses `.txt` files newer than `index.txt` would be significantly faster.
- **Implementation notes:** Compare `stat` mtime of each `doc_*.txt` against `index.txt`. Only rewrite changed doc's lines in `index.txt`. Rebuild `index_meta.json` after any change.

#### ENH-16 — `get_mtime` helper in `lib.sh` (supports BUG-14 fix)
- **Status:** proposed
- **Description:** Expose the raw epoch mtime integer from `lib.sh` so scripts can format timestamps without re-implementing the OS detection branch. Resolves the three-way duplication in BUG-14.
- **Implementation notes:** `get_mtime <file>` → prints integer epoch to stdout. Returns 1 if file does not exist.

#### ENH-17 — Query history log
- **Status:** proposed
- **Description:** Append each `search.sh` query to `$CACHE_DIR/query_history.log` (format: `<ISO8601_timestamp> <query>`). Useful for debugging what agents searched, and as future input for BM25 parameter tuning.
- **Implementation notes:** Single `printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$KEYWORD" >> "$QUERY_LOG"` in `search.sh`. No new dependencies.

#### ENH-18 — `prefetch.sh <topic>`
- **Status:** proposed
- **Description:** Search for a topic, then bulk-fetch the top N results in one call. Warms the cache for an entire subject area without requiring the agent to orchestrate search → loop → fetch.
- **Example:** `prefetch.sh webhook retry --top 5`
- **Dependencies:** Requires BUG-07 fix so fetched docs populate the HTML cache too.

---

## Test Coverage Gaps

The following scripts have no bats tests. Adding coverage for at least the offline fallback paths would prevent regressions.

| Script | Priority | Key scenarios to cover |
|--------|----------|----------------------|
| `scripts/sitemap.sh` | High | offline fallback (human + JSON), cached sitemap served, `--json` structure |
| `scripts/recent.sh` | Medium | no-sitemap path, `$DAYS` validation, `--json` output |
| `scripts/track-changes.sh` | Medium | `snapshot` creates file, `list` output, `diff` between two snapshots |

---

## How to pick up an item

1. Read `docs/coding-conventions.md` before writing any code.
2. Choose an item, set its `**Status:**` to `in_progress` and note your session/branch.
3. Implement, test locally with `bats tests/` and `pytest tests/test_bm25.py`.
4. Run `shellcheck --severity=error scripts/*.sh`.
5. Update `**Status:**` to `done — <commit SHA>`.
6. Update `CHANGELOG.md` under `[Unreleased]`.
