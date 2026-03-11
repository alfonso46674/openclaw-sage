# Code Quality Audit

Last run: 2026-03-11
Tool: `shellcheck --severity=info scripts/*.sh`, manual code review, `bats tests/`, `pytest tests/test_bm25.py`

---

## Findings

Organized by severity. Each finding links to a backlog item where applicable.

### Important

#### I-1. `build-index.sh:100` — bare redirection without command (SC2188)
- **Script:** `scripts/build-index.sh`
- **Line:** `> "$INDEX_FILE"`
- **Issue:** Truncates the index file using a bare redirection, which works but is a shellcheck warning and confusing to read.
- **Fix:** `: > "$INDEX_FILE"` or `true > "$INDEX_FILE"`.
- **Status:** resolved — 9f08276

#### I-2. Hardcoded `docs.openclaw.ai` in `recent.sh` Python block
- **Script:** `scripts/recent.sh:47`
- **Line:** `path = loc.text.replace('https://docs.openclaw.ai/', '')`
- **Issue:** Same class as BUG-01. `$DOCS_BASE_URL` is not passed into the Python heredoc. Produces wrong paths when the base URL is overridden.
- **Backlog:** BUG-17
- **Status:** resolved — 1160746

#### I-3. Hardcoded URL in `build-index.sh` fetch loop
- **Script:** `scripts/build-index.sh:72`
- **Line:** `path=$(echo "$url" | sed 's|https://docs\.openclaw\.ai/||')`
- **Issue:** Same class as BUG-01. Should use `$DOCS_BASE_URL`.
- **Backlog:** BUG-17
- **Status:** resolved — 1160746

#### I-4. Hardcoded URLs in `build-index.sh` awk language detection
- **Script:** `scripts/build-index.sh:32,52`
- **Lines:** `sub(/https:\/\/docs\.openclaw\.ai\//, "", path)`
- **Issue:** Two awk blocks use literal URL instead of `-v base_url="$DOCS_BASE_URL"`.
- **Backlog:** BUG-17
- **Status:** resolved — 1160746

#### I-5. `fetch-doc.sh` local `fetch_and_cache` shadows `lib.sh` shared version
- **Script:** `scripts/fetch-doc.sh:39-69`
- **Issue:** Defines a local function with the same name as the shared `lib.sh` version. References outer-scope variables instead of arguments. Risk of silent shadowing and drift.
- **Backlog:** BUG-18
- **Status:** resolved — 5520b39

#### I-6. Hardcoded fallback sitemap lists duplicated in `sitemap.sh`
- **Script:** `scripts/sitemap.sh:62-79` and `scripts/sitemap.sh:126-139`
- **Issue:** The offline fallback contains a hardcoded list of categories/paths duplicated in two places (JSON and human-readable). When docs.openclaw.ai adds new pages, both lists silently become stale with no way to detect drift.
- **Recommendation:** Extract to a single data source (e.g. a shared variable or file), or add a comment noting the lists must be updated together.

---

### Minor

#### M-1. `ls | wc -l` anti-pattern (SC2012)
- **Scripts:** `build-index.sh:88,178`, `cache.sh:22,45`
- **Issue:** `ls ... | wc -l` breaks on filenames with newlines and gives wrong counts when glob doesn't match. Should use `find ... | wc -l` or a glob-based approach.

#### M-2. `for f in $(ls ... | sort)` anti-pattern (SC2012)
- **Scripts:** `track-changes.sh:59,85,106`
- **Issue:** Parsing `ls` output is fragile. Snapshot filenames use `YYYYMMDD_HHMMSS.txt` so glob sorts correctly.
- **Backlog:** BUG-13

#### M-3. Mtime OS detection duplicated
- **Scripts:** `cache.sh:12-17`, `info.sh:127-128`
- **Issue:** The `stat -f %m` (macOS) vs `stat -c %Y` (Linux) branch is copy-pasted from `lib.sh` instead of being centralized.
- **Backlog:** BUG-14

#### M-4. `search.sh` sends "Tip:" diagnostic to stdout
- **Script:** `scripts/search.sh:181-183`
- **Issue:** Non-result text ("Tip: For comprehensive ranked results...") always goes to stdout, polluting agent-parseable output.
- **Backlog:** BUG-19
- **Status:** resolved — 923fc02

#### M-5. `build-index.sh` error to stdout
- **Script:** `scripts/build-index.sh:63`
- **Issue:** Error message goes to stdout instead of stderr.
- **Backlog:** BUG-20
- **Status:** resolved — 9ebb8b7

#### M-6. Outdated model name in `snippets/common-configs.md`
- **Script:** `snippets/common-configs.md:104`
- **Issue:** References `claude-sonnet-4-5` instead of `claude-sonnet-4-6`.
- **Backlog:** BUG-15
- **Status:** resolved — e21b067

---

### Nitpick

#### N-1. Shellcheck false positives for lib.sh variables (SC2034)
- **Script:** `scripts/lib.sh:4-6`
- **Issue:** `SITEMAP_TTL`, `DOC_TTL`, `LANGS` trigger "appears unused" because shellcheck doesn't follow `source`. Using `shellcheck -x` or adding `# shellcheck source=lib.sh` directives would suppress these.

#### N-2. BM25 meta recomputed fully on every build
- **Script:** `scripts/bm25_search.py` (`build_meta`)
- **Issue:** `build_meta` recomputes all doc statistics even when only one doc changed. Low impact now, but would become relevant with incremental index builds (ENH-15).

---

## Convention Compliance

| Convention | Status | Violating Scripts |
|---|---|---|
| Source `lib.sh` first | **Pass** | -- |
| Use `$CACHE_DIR` / `$DOCS_BASE_URL` (no hardcoding) | **Pass** | -- (BUG-17 fixed in 1160746) |
| stdout is data, stderr is diagnostics | **Pass** | -- (BUG-19 fixed in 923fc02, BUG-20 fixed in 9ebb8b7) |
| Use Python for JSON (never bash string concatenation) | **Pass** | -- |
| No uncached network requests | **Pass** | -- |
| Trap with single quotes | **Pass** | -- |
| No `grep -P` (PCRE) | **Pass** | -- |
| Use `is_cache_fresh` for TTL checks (no bare existence checks) | **Pass** | -- |
| No duplicate function definitions | **Pass** | -- (BUG-18 fixed in 5520b39) |

---

## Test Suite Summary

```
bats tests/   → 105/105 passed
pytest tests/  → 24/24 passed
shellcheck --severity=error → 0 errors
shellcheck --severity=info  → 12 findings (see above; 8 resolved in v0.2.4)
```

See backlog "Test Coverage Gaps" section for per-script gap analysis.
