# openclaw-sage

An [OpenClaw](https://openclaw.ai) skill that makes Claude an expert on [openClaw](https://docs.openclaw.ai) documentation — with live doc fetching, keyword search, full-text indexing, and change tracking.

## Requirements

- `bash`
- `curl`
- `python3` *(optional, recommended — enables BM25 ranked search and `recent.sh` date parsing)*
- `lynx` or `w3m` *(optional, recommended — improves HTML-to-text extraction)*

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_SAGE_SITEMAP_TTL` | `3600` | Sitemap cache TTL in seconds (1hr) |
| `OPENCLAW_SAGE_DOC_TTL` | `86400` | Doc page cache TTL in seconds (24hr) |
| `OPENCLAW_SAGE_CACHE_DIR` | `<skill_root>/.cache/openclaw-sage` | Cache directory |
| `OPENCLAW_SAGE_LANGS` | `en` | Languages to fetch — comma-separated codes (`en,zh`) or `all` |

Example:
```bash
OPENCLAW_SAGE_DOC_TTL=60 ./scripts/fetch-doc.sh gateway/configuration
```

## Scripts

All scripts live in `./scripts/` and cache results in `~/.cache/openclaw-sage/`.

### Core

```bash
./scripts/sitemap.sh              # List all docs grouped by category (cached 1hr)
./scripts/cache.sh status         # Check cache location, age, and doc count
./scripts/cache.sh refresh        # Clear sitemap cache to force re-fetch
./scripts/cache.sh clear-docs     # Clear all cached doc files and index
```

### Search & Fetch

```bash
./scripts/search.sh discord                  # Search cached docs by keyword
./scripts/fetch-doc.sh gateway/configuration # Fetch and display a specific doc
./scripts/recent.sh 7                        # Docs updated in the last N days (default: 7)
```

### Full-Text Index

For comprehensive search across all docs, build a local index:

```bash
./scripts/build-index.sh fetch               # Download all docs to cache
./scripts/build-index.sh build               # Build grep-able text index
./scripts/build-index.sh search "webhook retry" # Search the index
./scripts/build-index.sh status              # Show doc/index counts
```

### Version Tracking

Track what changes in the docs over time:

```bash
./scripts/track-changes.sh snapshot          # Save a snapshot of current doc list
./scripts/track-changes.sh list              # Show all saved snapshots
./scripts/track-changes.sh since 2026-01-01  # Show added/removed docs since a date
./scripts/track-changes.sh diff <snap1> <snap2> # Compare two specific snapshots
```

## Cache

Cached files are stored in `.cache/openclaw-sage/` inside the skill root by default (overridable via `OPENCLAW_SAGE_CACHE_DIR`):

| File | Description |
|---|---|
| `sitemap.xml` | Raw sitemap from docs.openclaw.ai |
| `sitemap.txt` | Parsed sitemap (1hr TTL) |
| `doc_<path>.txt` | Individually cached doc pages (1hr TTL) |
| `index.txt` | Full-text search index |
| `index_meta.json` | BM25 pre-computed doc lengths and term frequencies |
| `snapshots/` | Timestamped doc-list snapshots for change tracking |

## Docs

All documentation is at [docs.openclaw.ai](https://docs.openclaw.ai).

## License

MIT
