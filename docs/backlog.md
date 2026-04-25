# openclaw-sage — Backlog

Last audited: 2026-04-23

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

#### BUG-17 — Additional hardcoded `docs.openclaw.ai` URLs missed by BUG-01 fix
- **Files:** `scripts/recent.sh:47`, `scripts/build-index.sh:32,52,72`
- **Status:** done — 1160746
- **Description:** Same class as BUG-01 but in different code paths not covered by the original fix:
  1. `recent.sh:47` — Python heredoc has `path = loc.text.replace('https://docs.openclaw.ai/', '')` instead of using `$DOCS_BASE_URL` passed via `sys.argv`.
  2. `build-index.sh:32,52` — awk language detection blocks use literal `sub(/https:\/\/docs\.openclaw\.ai\//, "", path)` instead of `-v base_url="$DOCS_BASE_URL"`.
  3. `build-index.sh:72` — sed path extraction uses literal `sed 's|https://docs\.openclaw\.ai/||'` instead of `sed "s|${DOCS_BASE_URL}/||"`.
  All produce wrong output when `$DOCS_BASE_URL` is overridden.
- **Fix:** Pass `$DOCS_BASE_URL` into each context: as `sys.argv` for the Python block, as `-v base_url=` for awk, and as a variable in the double-quoted sed.

---

### Important

#### BUG-06 — `get_current_pages` ignores `$SITEMAP_TTL`, corrupts shared cache on failure
- **File:** `scripts/track-changes.sh:10-17`
- **Status:** done — ac0efe1
- **Description:** The function unconditionally overwrites `$CACHE_DIR/sitemap.xml` on every call with a live `curl` request. (1) It ignores `$SITEMAP_TTL`, hammering the server even when the cached sitemap is fresh. (2) If `curl` fails silently (network down, `-sf` suppresses output), it truncates `sitemap.xml` to an empty file, corrupting the shared cache used by `sitemap.sh`, `recent.sh`, and `build-index.sh`.
- **Fix:** Wrap the fetch in an `is_cache_fresh "$SITEMAP_XML" "$SITEMAP_TTL"` check. If curl fails, do not overwrite the existing file (use a temp file + `mv` only on success).

#### BUG-07 — `build-index.sh fetch` never populates the HTML cache
- **File:** `scripts/build-index.sh:79`
- **Status:** done — 5714ca0
- **Description:** Uses `fetch_text "$url" > "$cache_file"` which writes only the `.txt` file. The `.html` file is never created. Subsequent calls to `info.sh`, `fetch-doc.sh --toc`, or `fetch-doc.sh --section` on bulk-fetched docs will trigger a second network round-trip to backfill HTML, or fail entirely if offline.
- **Fix:** Mirror the dual-write pattern from `fetch-doc.sh`: fetch raw HTML to `doc_<safe>.html` first, then convert to `doc_<safe>.txt`. Centralise this into a shared `fetch_and_cache <url> <safe_path>` function in `lib.sh`.

#### BUG-08 — `recent.sh` uses file-existence check instead of TTL for sitemap
- **File:** `scripts/recent.sh:10`
- **Status:** done — 5714ca0
- **Description:** `if [ ! -f "$SITEMAP_XML" ]` only fetches if the file is completely absent. A stale-but-existing sitemap is served without re-validation. Every other script uses `is_cache_fresh "$SITEMAP_XML" "$SITEMAP_TTL"`.
- **Fix:** Replace the existence check with `if ! is_cache_fresh "$SITEMAP_XML" "$SITEMAP_TTL"`.

#### BUG-09 — `recent.sh` does not validate `$DAYS` argument
- **File:** `scripts/recent.sh:3`
- **Status:** done — 5714ca0
- **Description:** `DAYS=${1:-7}` is captured before `lib.sh` is sourced, with no integer validation. A non-numeric argument like `recent.sh foo` is passed to `find -mtime` (immediate error) and Python `int()` (unhandled exception), with no usage message shown to the user.
- **Fix:** After sourcing `lib.sh`, validate `$DAYS` with `[[ "$DAYS" =~ ^[0-9]+$ ]]` and print usage + exit 1 if invalid. Add a `Usage: recent.sh [days]` line.

#### BUG-10 — Fetched HTML is not cleaned before caching; noise bleeds into `.txt` and search
- **Files:** `scripts/lib.sh` (`fetch_and_cache`, `fetch_text`)
- **Status:** superseded — replaced by ENH-26 (GitHub/local Markdown source). The HTML cleaning pipeline is removed entirely in v0.3.1; there is no HTML to clean.
- **Description:** Raw HTML is stored as-is. `<script>`, `<style>`, and structural chrome (`<nav>`, `<header>`, `<footer>`) are never removed. Two downstream problems:
  1. The `sed` fallback in `fetch_text` and `fetch_and_cache` processes HTML one line at a time, so multi-line `<script>`/`<style>` blocks (the norm) are not stripped — raw JS and CSS end up in `.txt`, polluting search and BM25 results.
  2. Even with `lynx`/`w3m`, navigation and footer text is included in the `.txt`, adding irrelevant tokens to the search index.
- **Fix:** Superseded — ENH-26 removes the HTML fetch pipeline entirely and replaces it with Markdown source fetching.

#### BUG-15 — `snippets/common-configs.md` references outdated model name
- **File:** `snippets/common-configs.md`
- **Status:** done — e21b067
- **Description:** Line 105 uses `"anthropic/claude-sonnet-4-5"` while `SKILL.md` references `"anthropic/claude-sonnet-4-6"`. Both documents should reference the same current model.
- **Fix:** Update `snippets/common-configs.md` to use `claude-sonnet-4-6`.

#### BUG-18 — `fetch-doc.sh` local `fetch_and_cache` duplicates the `lib.sh` shared version
- **File:** `scripts/fetch-doc.sh:39-69`
- **Status:** done — 5520b39
- **Description:** `fetch-doc.sh` defines its own `fetch_and_cache()` (lines 39–69) that is nearly identical to the shared version added to `lib.sh` during the BUG-07 fix. The local version references outer-scope variables (`$URL`, `$HTML_CACHE`, `$CACHE_FILE`) instead of accepting arguments. Two functions with the same name in the same call chain is confusing and risks silent shadowing if `lib.sh`'s version is expected.
- **Fix:** Remove the local `fetch_and_cache` definition. Call the `lib.sh` version: `fetch_and_cache "$URL" "$SAFE_PATH"`. The existing error messages ("Failed to fetch", "Empty response") should move to the caller since the lib version is intentionally generic.

#### BUG-19 — `search.sh` sends diagnostic text to stdout
- **File:** `scripts/search.sh:181-183`
- **Status:** done — 923fc02
- **Description:** The "Tip: For comprehensive ranked results..." lines are always printed to stdout even when results were found. Agents parsing stdout receive unexpected non-result text. Violates the "stdout is data, stderr is diagnostics" convention.
- **Fix:** Redirect the "Tip:" block to `>&2`, or omit it entirely when results were found (only print as guidance when `found=0`).

#### BUG-21 — `track-changes.sh diff/list/since` cannot cross version boundaries
- **File:** `scripts/track-changes.sh:162-163`
- **Status:** done — see fix below
- **Description:** `diff`, `list`, and `since` resolve snapshot paths relative to `$VERSION_CACHE_DIR/snapshots/` (set by `--version` or defaulting to `latest`). There is no way to reference a snapshot from a different version's directory — `diff <snap1> <snap2>` silently exits with "Snapshot not found" when either snapshot lives in a different version's cache. The use case of comparing a snapshot taken against `v2026.4.9` with one taken against `v2026.4.22` is entirely blocked.
- **Workaround:** Use `diff <absolute_path1> <absolute_path2>` directly on the snapshot files.
- **Fix (Option A):** In the `diff` subcommand, check whether each argument starts with `/`. If so, treat it as an absolute path; otherwise resolve it relative to `$SNAPSHOTS_DIR`. Zero new flags, fully backward-compatible.

#### BUG-20 — `build-index.sh` error message goes to stdout instead of stderr
- **File:** `scripts/build-index.sh:63`
- **Status:** done — 9ebb8b7
- **Description:** `echo "Error: Could not get URL list from sitemap..."` is written to stdout. Should go to stderr per output conventions.
- **Fix:** Add `>&2` to the echo.

---

### Medium / Tech Debt

#### BUG-11 — `curl` exit code not checked after sitemap fetch in `build-index.sh`
- **File:** `scripts/build-index.sh:20-25`
- **Status:** done — 02b02bf
- **Description:** `curl -sf ... -o "$SITEMAP_XML"` failure is silently ignored. If the fetch fails, `grep` on an empty/absent file produces no output, and the subsequent "Could not get URL list from sitemap. Run sitemap.sh first" message blames the wrong thing.
- **Fix:** Check `$?` after the curl call and emit "Error: failed to fetch sitemap (network unreachable?)" with exit 1.

#### BUG-12 — `build-index.sh build` does not check `build-meta` exit code
- **File:** `scripts/build-index.sh:117`
- **Status:** done — f7a37b7
- **Description:** `python3 ... build-meta ...` failure (e.g. disk full writing `index_meta.json`) is not detected. The script continues and prints "Location: $INDEX_FILE" implying success.
- **Fix:** Add `|| { echo "Error: build-meta failed" >&2; exit 1; }` after the python3 call.

#### BUG-13 — `for f in $(ls ... | sort)` anti-pattern in `track-changes.sh`
- **File:** `scripts/track-changes.sh:49,75`
- **Status:** done — 5666878
- **Description:** Parsing `ls` output is fragile and unnecessary. Snapshot filenames are always `YYYYMMDD_HHMMSS.txt` so glob sorts correctly.
- **Fix:** Replace `for f in $(ls "$SNAPSHOTS_DIR"/*.txt | sort)` with `for f in "$SNAPSHOTS_DIR"/*.txt`.

#### BUG-14 — Mtime OS detection logic duplicated across three files
- **Files:** `scripts/lib.sh:20-25`, `scripts/cache.sh:12-17`, `scripts/info.sh:124-126`
- **Status:** done — 76c29ca
- **Description:** The macOS (`stat -f %m`) vs Linux (`stat -c %Y`) branch is copy-pasted in three places. The canonical version is in `lib.sh`; the others exist because they need the raw mtime integer for display (not just a freshness boolean). `is_cache_fresh` doesn't expose the value.
- **Fix:** Add a `get_mtime <file>` helper to `lib.sh` that returns the epoch integer. Call it from all three sites.

#### BUG-16 — Progress display garbles when a shorter path follows a longer one
- **File:** `scripts/build-index.sh:76`
- **Status:** done — 81fc8f4
- **Description:** The fetch progress line uses `printf "\r  [%d/%d] %s          "` with a fixed number of trailing spaces. When a shorter path follows a longer one, the carriage return moves the cursor to column 0 but the spaces don't fully overwrite the leftover characters, leaving garbage visible (e.g., `zh-CN                         s          ubleshooting`). Cosmetic only — fetching is correct.
- **Fix:** Pad the path field to a fixed width using `printf "\r  [%d/%d] %-40s" "$count" "$total" "$path"` so the column is always fully overwritten, or truncate long paths to a maximum width with a trailing `…`.

---

## Enhancements

Grouped by effort and value. Items within each tier are ordered by agent/user value (highest first).

### Tier 2 (high value — next up after critical bugs)

#### ENH-07 — `ask.sh <question>` — one-shot answer tool
- **Status:** planned
- **Description:** Combines search + fetch into a single call. BM25-searches the question, fetches the top 2-3 relevant doc sections, and returns sources + concatenated excerpts. Eliminates the search → read → decide → fetch → read agent loop. **Highest-value enhancement — transforms the skill from "doc access" to "doc expert."**
- **Inputs:** `<question text...>` (multi-word, no quotes needed), `[--json]`, `[--max-sections N]`
- **Output:** Labelled source blocks with doc path, section heading, excerpt. JSON mode: `{"question", "sources": [{"path", "section", "excerpt", "url"}]}`
- **Dependencies:** requires BM25 search + `fetch-doc.sh --section` to work correctly.

#### ENH-20 — Parallel doc fetching in `build-index.sh fetch`
- **Status:** done — 9eed1bb
- **Description:** The fetch loop is strictly sequential: one HTTP request must complete before the next starts, plus a 0.3s courtesy sleep per request. With 100+ docs each taking 1–3 seconds, a cold cache takes 10–15 minutes. Parallelising with `xargs -P` brings this down to roughly `total_time / N` without adding any new dependencies.
- **New env var:** `OPENCLAW_SAGE_FETCH_JOBS` (default `8`, set to `1` to restore sequential behaviour). Add to `lib.sh` alongside the other `OPENCLAW_SAGE_*` vars and document in `README.md`.
- **Implementation notes:**

  **1. Input preparation — null-delimited for cross-platform safety**
  ```bash
  # -d '\n' is GNU xargs only; -0 (null-delimited) works on both macOS BSD and Linux GNU xargs
  URLS_NULL=$(printf '%s\0' $(echo "$URLS"))   # or: echo "$URLS" | tr '\n' '\0'
  ```

  **2. Marker directory for counting successful fetches**
  Parallel subshells cannot update parent shell variables (`new`, `count`). Each worker touches a marker file on success; the parent counts them at the end.
  ```bash
  MARKER_DIR=$(mktemp -d)
  trap 'rm -rf "$MARKER_DIR"' EXIT
  ```

  **3. The xargs worker — sources lib.sh inline, no new wrapper script**
  ```bash
  export OPENCLAW_SAGE_CACHE_DIR OPENCLAW_SAGE_DOCS_BASE_URL OPENCLAW_SAGE_DOC_TTL LIB_SH MARKER_DIR
  echo "$URLS" | tr '\n' '\0' | xargs -0 -P "${OPENCLAW_SAGE_FETCH_JOBS:-8}" bash -c '
    source "$LIB_SH"
    url="$1"
    [ -z "$url" ] && exit 0
    safe=$(echo "$url" | sed "s|${DOCS_BASE_URL}/||" | tr "/" "_")
    cache_file="${CACHE_DIR}/doc_${safe}.txt"
    if [ ! -f "$cache_file" ] || ! is_cache_fresh "$cache_file" "$DOC_TTL"; then
      if fetch_and_cache "$url" "$safe"; then
        touch "${MARKER_DIR}/${safe}"
      fi
      sleep 0.3
    fi
  ' --
  new=$(ls "$MARKER_DIR" | wc -l)
  ```
  Key points:
  - All `OPENCLAW_SAGE_*` vars and `LIB_SH`/`MARKER_DIR` must be `export`ed before the xargs call so subshells inherit them.
  - The worker arg is `$1` (positional), not `{}` substitution — avoids shell injection if a URL ever contains special characters.
  - `sleep 0.3` is per worker, so effective request rate is approximately `FETCH_JOBS / 0.3` req/s. At 8 workers that is ~26 req/s, which is polite. Consider exposing `OPENCLAW_SAGE_FETCH_DELAY` (default `0.3`) as a separate tunable.

  **4. Progress display — drop the `\r` overwrite, print one line per completed doc**
  The carriage-return trick only works when output is strictly sequential. With parallel workers, lines interleave and corrupt the display. Replace with a simple per-completion line:
  ```bash
  echo "  [done] $path" >&2
  ```
  Print the summary count only after `wait` / xargs returns:
  ```bash
  cached=$(ls "$CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
  echo "Done. $new new docs fetched, $cached total cached." >&2
  ```

  **5. Edge cases**
  - `OPENCLAW_SAGE_FETCH_JOBS=0`: `xargs -P 0` is valid on GNU xargs (means "unlimited") but errors on BSD xargs. Guard with `[ "$FETCH_JOBS" -gt 0 ] || FETCH_JOBS=8`.
  - `OPENCLAW_SAGE_FETCH_JOBS=1`: restores sequential behaviour; useful for debugging or very polite fetching.
  - If `xargs -P` is unavailable (unlikely but theoretically possible in minimal environments), fall back to the existing sequential loop.

  **6. Files to change**
  - `scripts/lib.sh` — add `OPENCLAW_SAGE_FETCH_JOBS` and optionally `OPENCLAW_SAGE_FETCH_DELAY`.
  - `scripts/build-index.sh` — replace the `while IFS= read` loop with the `xargs -P` block above.
  - `README.md` — document the new env var in the environment variables table.
  - `SKILL.md` — update `build-index.sh fetch` entry to mention parallelism and the env var.

---

### Tier 3 (significant effort — planned)

#### ENH-26 — GitHub/local Markdown source + doc versioning
- **Status:** done — 2b618e2
- **Description:** Replace the Mintlify HTML scraping pipeline with a direct Markdown source (GitHub raw or local clone). Cache layout becomes `$CACHE_DIR/<version>/`, supporting multiple coexisting doc versions. All scripts gain a `--version <tag>` flag. `cache.sh tags` lists available GitHub releases. `sitemap.sh` reads `docs.json` instead of `sitemap.xml`. Breaks `lynx`/`w3m` and `OPENCLAW_SAGE_SITEMAP_TTL` dependencies.
- **Files changed:** `scripts/lib.sh`, `scripts/build-index.sh`, `scripts/sitemap.sh`, `scripts/fetch-doc.sh`, `scripts/info.sh`, `scripts/cache.sh`, `scripts/recent.sh`, `scripts/search.sh`, `scripts/track-changes.sh`, `README.md`, `SKILL.md`
- **Breaking changes:** Old flat cache (`doc_*.txt`, `sitemap.xml`) abandoned; `lynx`/`w3m` no longer used; `OPENCLAW_SAGE_SITEMAP_TTL` removed.
- **New env var:** `OPENCLAW_SAGE_SOURCE` — `github` (default) or `local:/path/to/openclaw/docs`

#### ENH-19 — Content-change tracking (page-level diffing)
- **Status:** proposed
- **Description:** `track-changes.sh` tracks structural changes (pages added/removed from sitemap). It cannot detect when an existing page's *content* changes. This enhancement adds content-change awareness by storing a checksum for each cached doc and comparing on re-fetch.
- **Context:** docs.openclaw.ai is a **living single-version** documentation site (confirmed by research — no versioned URLs, no version metadata in HTML, no changelog page). There is no concept of "docs for v1.0 vs v2.0". Content evolves continuously and is only distinguishable via timestamps and checksums.
- **Implementation notes:**
  - On each doc fetch (in `fetch_and_cache` / `build-index.sh fetch`), compute `sha256sum doc_<path>.txt` and store to `doc_<path>.sha256` in `$CACHE_DIR`.
  - Before overwriting the `.txt`, compare the new checksum against the stored one.
  - `build-index.sh fetch` or a new `cache.sh diff-content` subcommand can report which docs changed content since last fetch.
  - Output format: `[changed] gateway/configuration`, `[unchanged] providers/discord`, `[new] automation/webhook`.
- **Agent value:** Allows an agent to run `build-index.sh fetch` and immediately know which specific docs have been updated — not just which pages exist. Useful for "what changed in the docs since I last checked?" workflows.

#### ENH-08 — Passage-level BM25 (chunked index)
- **Status:** planned
- **Description:** The current index scores whole documents. Split docs into overlapping ~10-line passages and index passages instead. Returns targeted excerpts rather than whole-doc scores. Critical for long docs.
- **Implementation notes:** `build-index.sh build` generates passages in `index.txt` (format: `path:chunk_id|passage_text`). `bm25_search.py` scores and returns `path:chunk_id` with passage excerpt. `search.sh` resolves chunk line offsets back to path.

#### ENH-21 — Config validation tool (`validate-config.sh`)
- **Status:** proposed
- **Description:** A `validate-config.sh <config.json>` command that checks a user's OpenClaw configuration against known schema requirements extracted from the docs. "Is my config correct?" is one of the most common support questions for any platform. The skill already contains config snippets — this extends them into a validation tool.
- **Implementation notes:**
  - Accept a JSON file path as input.
  - Use Python to parse the JSON and validate against a schema derived from `snippets/common-configs.md` and the gateway/configuration doc.
  - Check: required fields present, correct types, known provider names, valid model format, port ranges, etc.
  - Output: list of issues found, or "Config is valid" on success. JSON mode: `{"valid": true/false, "issues": [{"field": "...", "message": "..."}]}`.
  - The schema definition could live in `snippets/config-schema.json` or be derived from the docs at runtime.
- **Limitation:** Schema will lag behind docs.openclaw.ai unless manually maintained. Consider generating it from the fetched configuration doc.

#### ENH-22 — Offline-first background refresh (`auto-refresh`)
- **Status:** proposed
- **Description:** A cron-compatible background refresh mode that periodically updates the cache so the skill is always ready. Currently the cache is populated on-demand, meaning the first request after a cold cache or TTL expiry incurs a network wait. A `build-index.sh auto-refresh` (or a dedicated `auto-refresh.sh`) subcommand would: re-fetch stale docs, rebuild the index if any docs changed, and exit. Designed to be run via system cron or agent cron jobs.
- **Implementation notes:**
  - Reuse `build-index.sh fetch` logic but only re-fetch docs whose TTL has expired (already does this).
  - After fetch, if any docs were updated, automatically run `build-index.sh build`.
  - Output a summary: `Auto-refresh complete: 3 docs updated, index rebuilt.` or `Auto-refresh complete: all docs fresh, no changes.`
  - Provide a sample crontab entry in the README: `0 */6 * * * /path/to/build-index.sh auto-refresh`.
- **Agent value:** Persistent agents (long-running sessions, CI-integrated agents) always have a warm, current cache. Eliminates the "first query is slow" problem.

#### ENH-25 — Doc archive snapshots with full-content diff
- **Status:** proposed
- **Description:** `track-changes.sh` can snapshot and diff the doc *list* (added/removed pages) but cannot snapshot page *contents* at a point in time. This means release comparisons are limited: we can detect structural changes but cannot answer "what changed inside pages?" across two points in time because the cache drifts forward and stores no historical versions. This enhancement adds immutable content-archiving on top of the existing snapshot mechanism.
- **New subcommands:**
  - `track-changes.sh snapshot --archive` — fetches the current sitemap (honoring `OPENCLAW_SAGE_LANGS`, default `en`), retrieves extracted markdown/text for every doc (same canonical extraction as `fetch-doc.sh`), and writes an immutable content snapshot to a timestamped directory alongside the existing list snapshot.
  - `track-changes.sh diff-archive <snapshot-A> <snapshot-B>` — compares two archive snapshots and reports Added / Removed / Changed / Unchanged pages. Supports `--summary` (counts + changed path list), `--write-diffs` (write unified diffs to `diffs/<A>__<B>/`), and `--max-diffs N` (limit console diff output).
- **Storage layout:**
  ```
  $CACHE_DIR/snapshots/
    20260422_183752.txt          # existing: list snapshot (unchanged)
    20260422_183752/             # new: content snapshot directory
      manifest.json
      docs/
        concepts/memory.md
        cli/memory.md
        tools/plugin.md
        ...
  ```
- **`manifest.json` fields:** snapshot id + timestamp, base URL + language(s), doc count + fetched OK/failed counts, per-doc entry with path + sha256(content) + fetch status/error, tool version, active config knobs (langs, extraction mode, etc.).
- **Diff method:** `diff -u` on stored `.md` files; normalize newlines before comparing.
- **Performance / safety knobs:**
  - `OPENCLAW_SAGE_FETCH_CONCURRENCY` (default 4–8, complements ENH-20's `OPENCLAW_SAGE_FETCH_JOBS`)
  - `OPENCLAW_SAGE_FETCH_DELAY_MS` (politeness delay between requests)
  - `--max-pages N` (cap for testing)
  - `--best-effort` (default) vs `--fail-on-error`
- **Implementation notes:**
  - Reuse `fetch_and_cache` from `lib.sh`; do not duplicate fetch logic.
  - The archive directory is write-once — never overwrite an existing snapshot directory.
  - sha256 computation uses Python (`hashlib.sha256`) to stay cross-platform.
  - Parallel fetching should delegate to ENH-20's `xargs -P` infrastructure when available.
  - Use Python for all JSON generation (manifest, diff metadata) — no bash string concatenation.
- **Dependencies:** ENH-19 (checksum infrastructure, ships in same release); ENH-20 (parallel fetch, ships in v0.3.0) is a soft dependency for performance.
- **Agent value:** Enables "create a snapshot before a release, create another after, diff them" workflows. Agents and developers can answer "what changed in the docs between version X and version Y?" with actual text diffs, not just a list of touched pages.

#### ENH-23 — Doc version awareness (builds on ENH-19)
- **Status:** proposed — superseded in scope by ENH-26. ENH-26 enables fetching docs at any git tag directly; ENH-23's "what changed between two points in time?" workflow is now answered by fetching two tags and diffing. Retain only if per-file commit-date history is still wanted.
- **Description:** Building on ENH-19's checksum storage, add the ability to answer "what changed in the docs between two points in time?" Currently `track-changes.sh` only tracks structural changes (pages added/removed). This enhancement stores checksums over time and can diff content changes between any two fetches.
- **Implementation notes:**
  - Store checksums with timestamps: `doc_<path>.sha256` contains `<sha256> <ISO8601_timestamp>` per line (append-only log).
  - A `track-changes.sh content-diff <date1> [date2]` subcommand finds checksums closest to each date and reports which docs changed.
  - Output format: `[changed] gateway/configuration (2 revisions since 2026-03-01)`, `[stable] providers/discord`.
  - Optional: store the old `.txt` before overwriting so the actual text diff can be shown.
- **Dependencies:** ENH-19 (checksum infrastructure).

#### ENH-26 — GitHub/local Markdown source (replaces HTML fetch pipeline)
- **Status:** planned — v0.3.1
- **Spec:** `docs/superpowers/specs/2026-04-23-github-source-design.md`
- **Description:** Replace the HTML fetch pipeline (`fetch_and_cache`, `fetch_text`, `clean_html_file`, `html_to_text`, sitemap.xml) with a Markdown-source pipeline that fetches docs from the OpenClaw GitHub repo or a local clone. Eliminates HTML cleaning noise, enables per-tag doc fetching, and adds a `--version` flag to all scripts for querying docs at any OpenClaw release.
- **New env var:** `OPENCLAW_SAGE_SOURCE` (`github` default, or `local:/path/to/docs`).
- **New CLI flag:** `--version <tag>` on all scripts (default: `latest`, fetched from `main`).
- **New subcommand:** `cache.sh tags` — lists available OpenClaw release tags from GitHub API.
- **Implementation notes:**
  - `lib.sh`: replace `fetch_and_cache`/`fetch_text`/`clean_html_file`/`html_to_text` with `fetch_markdown`/`resolve_source`/`clean_markdown`. Add `VERSION_CACHE_DIR` derived from `--version` flag. Remove `SITEMAP_TTL`.
  - `build-index.sh fetch`: use `docs.json` for discovery (replaces sitemap.xml); call `fetch_markdown` per path; preserve `xargs -P` parallel loop.
  - `sitemap.sh`: parse `docs.json` navigation tree instead of sitemap.xml. Output format unchanged.
  - `fetch-doc.sh --toc`/`--section`: parse `#` headings from cached `.md` file (simpler than HTML heading parser).
  - `info.sh`: extract title from YAML frontmatter in `.md` instead of HTML `<title>`.
  - `recent.sh`: remove "updated at source" section (no `lastmod` in `docs.json`); keep local mtime section.
  - All scripts: use `VERSION_CACHE_DIR` scoped to active `--version`.
  - Cache layout: `$CACHE_DIR/<version>/doc_<path>.{md,txt}` per version. Old flat cache abandoned (clean break).
  - MDX components stripped with Python regex (stdlib); YAML frontmatter `title`/`summary` prepended to `.txt`.
- **Supersedes:** BUG-10 (HTML cleaning — no longer needed).
- **Agent value:** Agents can fetch and search docs at any OpenClaw release tag. Comparing two versions is `fetch --version v1 && fetch --version v2`, then diff outputs of `fetch-doc.sh --version`.

#### ENH-27 — `recent.sh` per-file commit dates via GitHub API (post-ENH-26)
- **Status:** proposed
- **Description:** ENH-26 removes the sitemap `<lastmod>` "updated at source" section from `recent.sh` because `docs.json` has no equivalent dates. This enhancement restores that capability by querying the GitHub API for the last-commit date of each doc file. Requires a `GITHUB_TOKEN` env var for practical use (60 req/hr unauthenticated is too low for 500+ files).
- **Implementation notes:**
  - `GET /repos/openclaw/openclaw/commits?path=docs/<path>.md&per_page=1` returns the latest commit for a file.
  - Cache commit dates in `$VERSION_CACHE_DIR/commit_dates.json` (TTL: `SITEMAP_TTL` or a new `OPENCLAW_SAGE_COMMIT_DATES_TTL`).
  - `recent.sh` compares cached commit dates against the requested `--days` window.
- **Dependencies:** ENH-26 (ships first).

---

### Tier 4 (small effort — proposed)

#### ENH-09 — `search.sh --max-results N`
- **Status:** done — 4d4652e
- **Description:** BM25 caps results at 20 internally but exposes no CLI control. Agents doing narrow queries want top-3; broad exploration queries want more. Simple one-line addition.
- **Implementation notes:** Pass `N` as a fourth argument to `bm25_search.py search` and slice the results list. Default `N=10`.

#### ENH-18 — `prefetch.sh <topic>`
- **Status:** proposed
- **Description:** Search for a topic, then bulk-fetch the top N results in one call. Warms the cache for an entire subject area without requiring the agent to orchestrate search → loop → fetch.
- **Example:** `prefetch.sh webhook retry --top 5`
- **Dependencies:** Requires BUG-07 fix (done) so fetched docs populate the HTML cache too.

#### ENH-10 — `fetch-doc.sh --grep <pattern>`
- **Status:** proposed
- **Description:** Return only lines from the cached `.txt` matching a grep pattern. Simpler than `--section` for quick keyword-in-context lookups. Does not require HTML cache.
- **Example:** `fetch-doc.sh gateway/configuration --grep "timeout"`
- **Implementation notes:** Pipe `cat $CACHE_FILE` through `grep -i "$PATTERN"`. Exit 1 with "No matches" if grep returns nothing.

#### ENH-11 — `info.sh --batch <path1> <path2> ...`
- **Status:** proposed
- **Description:** Accept multiple paths and return metadata for all at once. Agents evaluating several candidate docs before fetching benefit from one call instead of N sequential calls.
- **Implementation notes:** Loop existing info logic over all positional args. JSON mode: return a JSON array. Human mode: print one block per doc separated by `---`.

#### ENH-13 — `fetch-doc.sh --format json`
- **Status:** proposed
- **Description:** Return doc content as a JSON object: `{"path", "title", "url", "word_count", "content"}`. Consistent with the `--json` pattern on other scripts and enables structured agent pipelines.
- **Implementation notes:** Reuse HTML title extraction from `info.sh`. Content is the plain `.txt` file contents. Only valid in `text` mode (not combinable with `--toc`/`--section`).

#### ENH-14 — Language-aware search
- **Status:** proposed
- **Description:** `$LANGS` filters doc fetching but `search.sh` scans all cached `.txt` files regardless. Add a `--lang <code>` flag that restricts BM25 and grep search to docs whose path includes the lang prefix.
- **Example:** `search.sh --lang fr webhook`

#### ENH-15 — Incremental index builds
- **Status:** done — 0ecda5c
- **Description:** `build-index.sh build` always rebuilds `index.txt` from scratch. For large corpora, a delta build that only reprocesses `.txt` files newer than `index.txt` would be significantly faster.
- **Implementation notes:** Compare `stat` mtime of each `doc_*.txt` against `index.txt`. Only rewrite changed doc's lines in `index.txt`. Rebuild `index_meta.json` after any change.

#### ENH-24 — Semantic search / synonym expansion
- **Status:** proposed
- **Description:** BM25 is keyword-based. A user asking "how do I handle rate limiting" won't match docs using "retry" and "maxAttempts" but never the words "rate limiting." A lightweight synonym/expansion table would improve search recall without adding heavy dependencies.
- **Implementation notes:**
  - Create a `synonyms.txt` file mapping common terms: `rate limiting → retry, maxAttempts, throttle`, `auth → authentication, token, credentials`, etc.
  - At search time, expand the query terms using the synonym table before running BM25.
  - Keep the table small and manually curated (domain-specific synonyms, not a general thesaurus).
  - Full embeddings-based search would be a Tier 2 effort requiring an external model — this is the lightweight alternative.

---

### Tier 5 (deprioritized — low value or niche)

#### ENH-12 — `cache pin <path>` / `cache unpin <path>`
- **Status:** proposed
- **Description:** Pin specific docs to prevent TTL-based eviction. Pinned docs are never considered stale by `is_cache_fresh`. Useful when an agent is actively working with a specific integration's docs across a long session.
- **Implementation notes:** Write pinned paths to `$CACHE_DIR/pinned.txt` (one path per line). Modify `is_cache_fresh` to check this file and return 0 (fresh) unconditionally for pinned paths.

#### ENH-16 — `get_mtime` helper in `lib.sh` (supports BUG-14 fix)
- **Status:** done — 76c29ca
- **Description:** Expose the raw epoch mtime integer from `lib.sh` so scripts can format timestamps without re-implementing the OS detection branch. Resolves the three-way duplication in BUG-14.
- **Implementation notes:** `get_mtime <file>` → prints integer epoch to stdout. Returns 1 if file does not exist.

#### ENH-17 — Query history log
- **Status:** proposed
- **Description:** Append each `search.sh` query to `$CACHE_DIR/query_history.log` (format: `<ISO8601_timestamp> <query>`). Useful for debugging what agents searched, and as future input for BM25 parameter tuning.
- **Implementation notes:** Single `printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$KEYWORD" >> "$QUERY_LOG"` in `search.sh`. No new dependencies.

---

## Test Coverage Gaps

| Script | Test File | Priority | Key gaps |
|--------|-----------|----------|----------|
| `scripts/build-index.sh` | `test_build_index.bats` (6) | **High** | `build` and `search` subcommands untested (80+ lines). Only `status`, `fetch_and_cache`, and error routing covered. |
| `scripts/search.sh` | `test_search.bats` (13) | **Medium** | BM25-ranked path not tested (requires seeded index). `OPENCLAW_SAGE_OUTPUT=json` not tested for search. |
| `scripts/lib.sh` | `test_lib.bats` (11) | **Medium** | `fetch_text` not tested. `check_online` not tested. `fetch_and_cache` only tested via `test_build_index.bats` with file:// URLs. |
| `scripts/info.sh` | `test_info.bats` (9) | **Medium** | `python3` unavailable fallback not tested. HTML backfill path not tested. |
| `scripts/recent.sh` | `test_recent.bats` (8) | **Low** | `find -mtime` section not tested with seeded docs. |
| `scripts/sitemap.sh` | `test_sitemap.bats` (8) | **Low** | Offline fallback with stale cache. JSON error when python3 missing. |
| `scripts/fetch-doc.sh` | `test_fetch_doc.bats` (13) | **Low** | Offline fallback with stale `.txt` cache. `--max-lines 0` edge case. |
| `scripts/cache.sh` | `test_cache.bats` (12) | -- | Good coverage. |
| `scripts/track-changes.sh` | `test_track_changes.bats` (11) | -- | Good coverage. |
| `scripts/bm25_search.py` | `test_bm25.py` (24) | -- | Good coverage. |

---

## How to pick up an item

1. Read `docs/coding-conventions.md` before writing any code.
2. Choose an item, set its `**Status:**` to `in_progress` and note your session/branch.
3. Implement, test locally with `bats tests/` and `pytest tests/test_bm25.py`.
4. Run `shellcheck --severity=error scripts/*.sh`.
5. Update `**Status:**` to `done — <commit SHA>`.
6. Update `CHANGELOG.md` under `[Unreleased]`.
