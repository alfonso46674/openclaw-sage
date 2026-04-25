# Design: GitHub/Local Source Mode + Doc Versioning

**Date:** 2026-04-23
**Status:** Implemented — v0.3.1
**Target release:** v0.3.0 or new minor (TBD after design approval)

---

## Problem

openclaw-sage currently fetches docs from `https://docs.openclaw.ai` (HTML). This requires:
- An HTML cleaning pipeline (`clean_html_file` in `lib.sh`) to strip nav/footer/JS/CSS
- A sitemap.xml for discovery
- HTML-to-text conversion (lynx/w3m/sed fallback)

The OpenClaw docs are maintained as Markdown in the public GitHub repo (`openclaw/openclaw`, `docs/`). Fetching from source:
- Eliminates the HTML cleaning pipeline entirely
- Produces cleaner search index content
- Enables fetching docs at specific git tags (release-based versioning)
- Allows local-repo mode for offline/development use

---

## Approach: Thin adapter layer (Option A)

Replace fetch internals in `lib.sh`. Leave all consumers (`search.sh`, `fetch-doc.sh`, `bm25_search.py`, `info.sh`, `track-changes.sh`) untouched — they read `.txt` files from `$CACHE_DIR` regardless of source. The cache layout changes to support versioned subdirectories.

---

## Section 1 — Source modes & environment variables

One new env var joins the existing `OPENCLAW_SAGE_*` family. Version is a CLI flag, not an env var.

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_SAGE_SOURCE` | `github` | `github` or `local:/path/to/openclaw/docs` |

Scripts that operate on a specific version accept `--version <tag>` as a CLI flag. Omitting it defaults to `latest` (fetched from `main`).

```bash
./scripts/build-index.sh fetch                    # fetch latest (main)
./scripts/build-index.sh fetch --version v2026.4.9  # fetch a specific tag
./scripts/search.sh webhook                         # search latest
./scripts/search.sh --version v2026.4.9 webhook     # search a specific version
./scripts/fetch-doc.sh gateway/configuration        # read latest
./scripts/fetch-doc.sh --version v2026.4.9 gateway/configuration
```

`OPENCLAW_SAGE_SOURCE` remains an env var because it describes the source backend (github vs local), which is a session-level setting rather than a per-command choice. Version is per-command.

**`github` mode:** fetches `docs.json` and each `.md` file from
`raw.githubusercontent.com/openclaw/openclaw/<ref>/docs/`.
`<ref>` = tag value when `--version` is given, `main` otherwise.

**`local` mode:** reads files directly from the given path. No network needed.
`--version` is ignored in local mode — the on-disk repo is whatever it is.
Useful for development and offline work against a cloned repo.

`OPENCLAW_SAGE_DOCS_BASE_URL` is unchanged — still used to construct
canonical reference URLs (`https://docs.openclaw.ai/<path>`) in output.
Source and citation URL are decoupled.

---

## Section 2 — Cache layout

Each version gets its own subdirectory. All existing scripts that read `$CACHE_DIR/doc_*.txt` are updated to read from `$VERSION_CACHE_DIR` instead — a variable set in `lib.sh` based on the active version.

```text
$CACHE_DIR/
  latest/               # fetched from main branch (OPENCLAW_SAGE_VERSION unset)
    docs.json
    doc_gateway_configuration.txt
    doc_gateway_configuration.md   # raw markdown (new, replaces .html)
    index.txt
    index_meta.json
    snapshots/
  v2026.4.22/           # fetched at that tag
    docs.json
    doc_gateway_configuration.txt
    doc_gateway_configuration.md
    index.txt
    index_meta.json
    snapshots/
  v2026.4.9/
    ...
```

**Key points:**

- `.md` replaces `.html` as the intermediate cache file. The `.txt` file is still derived from it and used by all downstream consumers unchanged.
- `docs.json` is cached per version (replaces `sitemap.xml`).
- `$VERSION_CACHE_DIR` is a derived variable in `lib.sh`: `${CACHE_DIR}/${active_version}`. Scripts use this instead of `$CACHE_DIR` directly when reading/writing doc files.
- The old flat cache (`$CACHE_DIR/doc_*.txt`, `sitemap.xml`) is abandoned — clean break. Users re-fetch.

---

## Section 3 — Discovery: docs.json replaces sitemap.xml

`sitemap.sh` currently fetches and parses `sitemap.xml`. It is replaced by fetching and parsing `docs.json`.

**Fetch location:**

- `github` mode: `raw.githubusercontent.com/openclaw/openclaw/<ref>/docs/docs.json`
- `local` mode: `<local_path>/docs.json`

**Parsing:** `docs.json` has a `navigation.languages[0].tabs[].groups[].pages[]` tree. A Python one-liner walks this tree and extracts all page paths (537 paths from current docs). Paths that are nested objects (groups-within-groups) are recursed. This replaces the `grep '<loc>'` sitemap parsing.

**Category structure is preserved:** the tabs/groups hierarchy maps naturally to the category grouping that `sitemap.sh` currently outputs. `sitemap.sh --json` output format is unchanged.

**`sitemap.xml` and `SITEMAP_TTL`** are removed. `docs.json` uses `DOC_TTL` for its own freshness check (or a new `OPENCLAW_SAGE_DOCS_JSON_TTL` if finer control is wanted — defer to implementation).

---

## Section 4 — Fetch pipeline changes

### lib.sh

`fetch_and_cache <url> <safe_path>` is replaced by `fetch_and_cache <source_path> <safe_path>` where `source_path` is a URL (github mode) or filesystem path (local mode).

New function `resolve_source <doc_path>` returns the fetch URL or local path for a given doc path:

- `github`: `https://raw.githubusercontent.com/openclaw/openclaw/<ref>/docs/<doc_path>.md`
- `local`: `<local_path>/<doc_path>.md`

New function `fetch_markdown <source> <safe_path>`:

1. Fetch or copy the `.md` file to `$VERSION_CACHE_DIR/doc_<safe_path>.md`
2. Strip MDX components (see Section 5) and YAML frontmatter
3. Write clean plain text to `$VERSION_CACHE_DIR/doc_<safe_path>.txt`

The entire `clean_html_file` + `html_to_text` chain is **removed**. `check_online` is updated: in `github` mode it pings `raw.githubusercontent.com`; in `local` mode it checks the directory exists.

### build-index.sh fetch

The URL list comes from `docs.json` (via `resolve_source docs`) instead of `sitemap.xml`. Each path becomes a `resolve_source <path>` call. The `xargs -P` parallel fetch loop is preserved — it now calls `fetch_markdown` instead of `fetch_and_cache`.

---

## Section 5 — MDX cleaning

The markdown files contain Mintlify MDX components (`<Tooltip>`, `<Tip>`, `<CardGroup>`, `<Tabs>`, `<Tab>`, etc.). Decision: **strip tags, keep inner text.**

A Python function `clean_markdown <input> <output>` in `lib.sh`:

1. Strip YAML frontmatter block (`---` ... `---` at top of file)
2. Strip self-closing MDX tags: `<TagName ... />` → nothing
3. Strip paired MDX tags: `<TagName ...>content</TagName>` → `content`
4. Preserve standard markdown and fenced code blocks untouched

Implementation: simple regex pass using `re` (stdlib). No HTML parser needed — these are XML-like tags in an otherwise-markdown file. Fenced code blocks (```` ``` ``` ```) are excluded from tag stripping to avoid mangling code examples that contain angle brackets.

YAML frontmatter `summary` and `title` fields are extracted and prepended to the `.txt` output as a header — they are useful for BM25 and for `info.sh` title extraction.

---

## Section 6 — Versioning UX

### Fetching a specific version

```bash
./scripts/build-index.sh fetch                      # fetch latest (main)
./scripts/build-index.sh fetch --version v2026.4.9  # fetch at a specific tag
./scripts/build-index.sh build                      # build index for latest
./scripts/build-index.sh build --version v2026.4.9  # build index for that version
```

Each version is fetched into its own cache subdirectory (`$CACHE_DIR/v2026.4.9/`). Multiple versions can coexist in cache.

### Querying a specific version

```bash
./scripts/search.sh webhook                            # search latest
./scripts/search.sh --version v2026.4.9 webhook        # search a specific version
./scripts/fetch-doc.sh gateway/configuration           # read from latest
./scripts/fetch-doc.sh --version v2026.4.9 gateway/configuration
```

All scripts resolve `$VERSION_CACHE_DIR` from the `--version` flag. Omitted = `latest`.

### Comparing two versions

No new command needed — fetch two tags, then diff the `fetch-doc.sh` output directly:

```bash
./scripts/build-index.sh fetch --version v2026.4.9
./scripts/build-index.sh fetch --version v2026.4.22
diff <(./scripts/fetch-doc.sh --version v2026.4.9 gateway/configuration) \
     <(./scripts/fetch-doc.sh --version v2026.4.22 gateway/configuration)
```

A dedicated `diff-versions` command can come in a future release if needed.

### Listing cached versions

`cache.sh status` is extended to list all version subdirectories present in `$CACHE_DIR`, their doc counts, and whether an index is built.

```text
Cached versions:
  latest       87 docs   index: built
  v2026.4.22   87 docs   index: built
  v2026.4.9    81 docs   index: not built
```

### Listing available tags from GitHub

A new `cache.sh tags` subcommand hits the GitHub API to list available release tags for the OpenClaw repo. No auth required for public repos (60 req/hr unauthenticated is sufficient for occasional tag listing).

```bash
./scripts/cache.sh tags
```

```text
Available OpenClaw releases (most recent first):
  v2026.4.22
  v2026.4.21
  v2026.4.20-beta.2
  v2026.4.9
  ...

Fetch a version: OPENCLAW_SAGE_VERSION=v2026.4.9 ./scripts/build-index.sh fetch
```

This is `github` mode only. In `local` mode, `cache.sh tags` prints a message that tag listing is not available for local sources.

### Local mode

```bash
OPENCLAW_SAGE_SOURCE=local:/home/alfonso/WebProjects/openclaw/docs ./scripts/build-index.sh fetch
```

`--version` is ignored in local mode. The version label used for the cache directory is `local`.

---

## Section 7 — recent.sh impact

`recent.sh` currently uses sitemap `<lastmod>` dates to show docs updated at source. With `docs.json` there are no `lastmod` dates.

**Replacement behaviour:**

- The "updated at source" section is removed (no equivalent data in `docs.json`).
- The "recently accessed locally" section (file mtime) is unchanged.
- A new informational line is added: `Run cache.sh status to see available versions and fetch dates.`

This is a minor regression in functionality. A future enhancement (post-v0.3.0) could query the GitHub API for commit dates per file, but that requires authentication for reasonable rate limits and is out of scope here.

---

## Section 8 — Scripts untouched

These scripts read `$VERSION_CACHE_DIR/doc_*.txt` and need **no logic changes** — only the `$VERSION_CACHE_DIR` variable substitution in `lib.sh` makes them version-aware automatically:

- `search.sh` — reads `index.txt` and `doc_*.txt` from cache dir
- `bm25_search.py` — receives index path as argument, no path assumptions
- `fetch-doc.sh` — reads `.txt` (and `.md` replaces `.html` for `--toc`/`--section`)
- `info.sh` — reads `.txt` and title from cache
- `track-changes.sh` — reads snapshots from cache dir



**`fetch-doc.sh --toc` / `--section`:** currently parses `.html` for headings. With markdown, heading extraction is simpler: grep for `^#` lines in the `.md` cache file. This is a net improvement and replaces the HTML heading parser without changing the external interface.

---

## Section 9 — Release placement & backlog impact

### Release placement

This is a **new minor release: v0.3.1** (or absorbed into v0.3.0 if v0.3.0 hasn't shipped yet).

It does **not** fit inside the current v0.3.0 scope (BUG-10, ENH-20, ENH-09, ENH-15) without displacing its theme. However:

- BUG-10 (HTML cleaning) is **superseded** — there is no HTML to clean anymore. It can be marked done-by-replacement.
- ENH-20 (parallel fetch with `xargs -P`) is **preserved** — the parallel fetch loop is reused as-is.
- ENH-09 and ENH-15 are **unaffected**.

**Recommended:** ship v0.3.0 as planned (the items are already done per backlog), then this work becomes v0.3.1 or v0.4.0-pre depending on timing.

### Backlog impact

| Item | Impact |
| --- | --- |
| BUG-10 | Superseded — HTML cleaning pipeline removed entirely. Mark `done-by-design`. |
| ENH-19 (content checksums) | Simplified — checksum `.txt` files as before; no change needed. |
| ENH-25 (archive snapshots) | Improved — storing `.md` files in archives is cleaner than `.txt`. |
| ENH-22 (auto-refresh) | Compatible — `build-index.sh fetch` semantics unchanged. |
| ENH-07 (ask.sh) | Unaffected — sits above the fetch layer. |
| `recent.sh` lastmod | Regressed — documented in Section 7. Future work. |

### Files changed

| File | Change |
| --- | --- |
| `scripts/lib.sh` | Replace `fetch_and_cache`, `fetch_text`, `clean_html_file`, `html_to_text`, `check_online` with `fetch_markdown`, `resolve_source`, `clean_markdown`, updated `check_online`. Add `VERSION_CACHE_DIR` derived var (resolved from `--version` flag passed by callers). Add `OPENCLAW_SAGE_SOURCE` env var. |
| `scripts/build-index.sh` | `fetch` subcommand: use `docs.json` for discovery, call `fetch_markdown`. `build`/`search`/`status`: use `VERSION_CACHE_DIR`. |
| `scripts/sitemap.sh` | Parse `docs.json` instead of `sitemap.xml`. |
| `scripts/cache.sh` | `status` lists version subdirectories. `clear-docs` scopes to active version or all. Add `tags` subcommand. |
| `scripts/fetch-doc.sh` | `--toc`/`--section`: parse `.md` headings instead of `.html`. Use `VERSION_CACHE_DIR`. |
| `scripts/info.sh` | Read title from frontmatter in `.md` instead of HTML `<title>`. Use `VERSION_CACHE_DIR`. |
| `scripts/recent.sh` | Remove "updated at source" section; keep local mtime section. |
| `scripts/search.sh` | Use `VERSION_CACHE_DIR`. |
| `scripts/track-changes.sh` | Use `VERSION_CACHE_DIR`. |
| `README.md` | Document new env vars, remove `lynx`/`w3m` as optional deps, update cache table. |
| `SKILL.md` | Update tool descriptions to reflect version support. |
