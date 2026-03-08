# Changelog

All notable changes to openclaw-sage are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.3.0] - 2026-03-08

### Added

- **`scripts/info.sh`** — lightweight doc metadata from cache only (no network request). Returns title (from `<title>` HTML tag), headings list, word count, cache age/freshness, and URL. Exits 1 with a clear `not_cached` message if the doc hasn't been fetched yet. Supports `--json` and `OPENCLAW_SAGE_OUTPUT=json`. Degrades gracefully when HTML cache or `python3` is unavailable (falls back to word count and cache age from `.txt` file).

---

## [0.2.0] - 2026-03-07

### Fixed

- **Critical domain bug** in `build-index.sh` — cache file paths were built from `docs.clawd.bot` instead of `docs.openclaw.ai`, producing malformed filenames and fetching from the wrong host.

### Added

- **`scripts/lib.sh`** — shared library sourced by all scripts. Provides `is_cache_fresh()`, `fetch_text()`, `DOCS_BASE_URL`, `CACHE_DIR`, `SITEMAP_TTL`, `DOC_TTL`, and `LANGS`. All values are overridable via env vars.
- **`scripts/bm25_search.py`** — BM25 ranked full-text search over the doc index. Two modes: `search` (outputs `score | path | excerpt`) and `build-meta` (writes `index_meta.json` for faster repeated searches). Falls back to simple term frequency on small corpora.
- **`fetch-doc.sh --toc`** — extract and display the heading tree of a doc without fetching the full body. Parses `<h1>`–`<h6>` from the cached HTML.
- **`fetch-doc.sh --section <heading>`** — extract a specific section by heading name (case-insensitive partial match). On a miss, lists all available headings so the caller can correct the query.
- **`fetch-doc.sh --max-lines <n>`** — truncate doc output to N lines.
- **`search.sh --json`** — structured JSON output: `{query, mode, results[], sitemap_matches[]}`. `mode` is `"bm25"`, `"grep"`, or `"sitemap-only"` so callers know result quality. BM25 scores are floats; grep fallback scores are `null`.
- **`sitemap.sh --json`** — structured JSON output: `[{category, paths[]}]`.
- **`OPENCLAW_SAGE_OUTPUT=json`** env var — global JSON mode flag respected by `search.sh` and `sitemap.sh`.
- **`OPENCLAW_SAGE_LANGS`** env var — filter which language docs to download during `build-index.sh fetch`. Defaults to `en`. Accepts comma-separated language base codes (`en,zh`) or `all`. Correctly handles locale variants like `zh-CN`, `pt-BR`.
- **Language detection** in `build-index.sh fetch` — prints all languages found in the sitemap with doc counts before filtering, so users know what `OPENCLAW_SAGE_LANGS` values are available.
- **HTML caching** (`doc_<path>.html`) alongside plain text — a single HTTP request now caches both. Required for `--toc` and `--section`. Older `.txt`-only cache entries are backfilled on demand.
- **`index_meta.json`** — pre-computed BM25 statistics (doc lengths, term–document frequencies) written by `build-index.sh build`. Used by `bm25_search.py` to skip recomputing on every search.
- iMessage and MS Teams provider snippets in `snippets/common-configs.md`.

### Changed

- **Default cache directory** moved from `~/.cache/openclaw-sage` to `<skill_root>/.cache/openclaw-sage`. Agents sandboxed to their workspace no longer need `HOME` to be accessible. Override with `OPENCLAW_SAGE_CACHE_DIR`.
- **All scripts now source `scripts/lib.sh`** — `is_cache_fresh` and `fetch_text` were previously duplicated in every script.
- **`fetch-doc.sh` doc TTL** raised from 1hr to 24hr (via `DOC_TTL` default). Sitemap TTL stays at 1hr.
- **`fetch-doc.sh` fetch strategy** — now always fetches raw HTML first, then derives plain text from the cached file (single HTTP request instead of potentially two).
- **`build-index.sh search`** now uses BM25 ranking via `bm25_search.py` instead of grep. Falls back to grep when `python3` is unavailable.
- **`search.sh`** unified output format: `[score] path -> url / excerpt` regardless of which search path is taken. BM25 path shows float scores; grep/sitemap paths show `[---]`.
- **`recent.sh`** output split into two clearly labelled sections: `=== Docs updated at source ===` and `=== Recently accessed locally ===`.
- **`cache.sh status`** now shows active TTL values and the env var names that override them.
- **`cache.sh clear-docs`** now also removes `doc_*.html` files and `index_meta.json`.
- **`track-changes.sh`** now uses `trap "rm -f $AFTER_TMP" EXIT` to guarantee temp file cleanup.
- **`SKILL.md`** fully rewritten with formal Tool definitions (purpose, input, output, errors), explicit Decision Rules, inline config snippets for all providers, and an Error Handling table.
- **`README.md`** — `python3` marked as optional/recommended; env var table added; cache file table updated.
- **`.gitignore`** — added `.cache/` to prevent cached docs from being committed.

---

## [0.1.0] - 2026-03-06

Initial release.

- `sitemap.sh` — fetch and display docs by category (cached 1hr)
- `fetch-doc.sh` — fetch a specific doc as plain text (cached 1hr)
- `search.sh` — search cached docs by keyword, with sitemap path fallback
- `build-index.sh` — download all docs, build grep-based full-text index, search index
- `recent.sh` — show docs updated in the last N days via sitemap `lastmod`
- `cache.sh` — cache management (status, refresh, clear-docs, dir)
- `track-changes.sh` — sitemap snapshot diffing (snapshot, list, since, diff)
- `SKILL.md` — agent-facing skill description
- `snippets/common-configs.md` — ready-to-use config snippets for all providers
