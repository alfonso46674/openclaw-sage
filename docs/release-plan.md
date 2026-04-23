# Release Plan

Last updated: 2026-03-11

---

## Versioning

openclaw-sage follows [Semantic Versioning](https://semver.org/) within the `0.x.y` pre-1.0 range:

- **Patch** (`0.2.x`) — bug fixes only. No new scripts, no changed interfaces. Safe to merge anytime.
- **Minor** (`0.x.0`) — new features, new scripts, or interface/behavior changes.
- **Major** (`1.0.0`) — stable API. See [Criteria for 1.0](#criteria-for-10) below.

---

## Principles

1. **Patch releases are bugs-only** — no new features, no interface changes.
2. **Minor releases have a theme** — each delivers a coherent improvement area.
3. **Dependencies flow forward** — prerequisite items ship in earlier releases.
4. **Every fix/feature ships with tests** — no item lands without regression coverage.
5. **CHANGELOG updated per release** — backlog items marked `done` with commit SHA.

---

## Planned Releases

### v0.2.4 — Bug sweep

Bug-only patch. Resolves all remaining critical and important bugs.

| Item | Summary | Severity |
|------|---------|----------|
| BUG-15 | Outdated model name in `snippets/common-configs.md` | Important |
| BUG-17 | Hardcoded `docs.openclaw.ai` URLs missed by BUG-01 fix | Critical |
| BUG-18 | `fetch-doc.sh` local `fetch_and_cache` shadows `lib.sh` version | Important |
| BUG-19 | `search.sh` sends diagnostic text to stdout | Important |
| BUG-20 | `build-index.sh` error message goes to stdout | Important |
| I-1 | Bare redirection `> "$INDEX_FILE"` (SC2188) | Code quality |

---

### v0.2.5 — Tech debt cleanup

Bug-only patch. Clears medium-priority tech debt and code quality issues.

| Item | Summary | Severity |
|------|---------|----------|
| BUG-11 | `curl` exit code not checked after sitemap fetch | Medium |
| BUG-12 | `build-index.sh build` does not check `build-meta` exit code | Medium |
| BUG-13 | `for f in $(ls … \| sort)` anti-pattern in `track-changes.sh` | Medium |
| BUG-14 + ENH-16 | Mtime OS detection duplicated → add `get_mtime` helper | Medium |
| BUG-16 | Progress display garbles when a shorter path follows a longer one | Medium |

---

### v0.3.0 — Performance & quality

Minor bump — introduces new env vars and changes fetch behavior.

| Item | Summary | Type |
|------|---------|------|
| BUG-10 | Clean fetched HTML of CSS/JS/chrome noise before caching | Bug fix |
| ENH-20 | Parallel doc fetching with `xargs -P` (`OPENCLAW_SAGE_FETCH_JOBS`) | Enhancement |
| ENH-09 | `search.sh --max-results N` | Enhancement |
| ENH-15 | Incremental index builds (only reprocess changed docs) | Enhancement |

---

### v0.4.0 — The "ask" release

Minor bump — adds the flagship `ask.sh` tool and supporting features.

| Item | Summary | Type |
|------|---------|------|
| ENH-07 | `ask.sh <question>` — one-shot answer tool | Enhancement |
| ENH-08 | Passage-level BM25 (chunked index) | Enhancement |
| ENH-10 | `fetch-doc.sh --grep <pattern>` | Enhancement |
| ENH-13 | `fetch-doc.sh --format json` | Enhancement |

**Dependencies:** ENH-08 (passage-level BM25) should land before ENH-07 (`ask.sh`) for good answer quality.

---

### v0.5.0 — Intelligence layer

Minor bump — adds content-change awareness, config validation, and smarter search.

| Item | Summary | Type |
|------|---------|------|
| ENH-19 | Content-change tracking (page-level checksums) | Enhancement |
| ENH-25 | Doc archive snapshots with full-content diff | Enhancement |
| ENH-21 | `validate-config.sh <config.json>` | Enhancement |
| ENH-22 | Offline-first background auto-refresh | Enhancement |
| ENH-24 | Synonym/expansion search | Enhancement |

**Dependencies:** ENH-25 shares checksum infrastructure with ENH-19 and benefits from ENH-20's parallel fetch (ship ENH-19 and ENH-20 first).

---

### v0.6.0 — Polish & advanced

Minor bump — advanced features and remaining Tier 4/5 items.

| Item | Summary | Type |
|------|---------|------|
| ENH-23 | Doc version awareness (builds on ENH-19) | Enhancement |
| ENH-11 | `info.sh --batch <path1> <path2> …` | Enhancement |
| ENH-14 | Language-aware search (`--lang <code>`) | Enhancement |
| ENH-18 | `prefetch.sh <topic>` | Enhancement |
| ENH-12 | `cache pin` / `cache unpin` | Enhancement |
| ENH-17 | Query history log | Enhancement |

**Dependencies:** ENH-23 requires ENH-19 (shipped in v0.5.0).

---

## Criteria for 1.0

Consider tagging `1.0.0` when all of the following are met:

- [ ] `ask.sh` is stable (the flagship feature)
- [ ] HTML cleaning is done (clean search results)
- [ ] Parallel fetch works (usable cold-cache experience)
- [ ] All critical and important bugs are resolved
- [ ] Test coverage gaps marked "High" and "Medium" in the backlog are closed
- [ ] `SKILL.md` and `AGENTS.md` fully reflect all available tools

Target: after v0.4.0 or v0.5.0, depending on stability.

---

## How to cut a release

1. Ensure all items for the release are `done` in `docs/backlog.md` with commit SHAs.
2. Run the full test suite: `bats tests/` and `pytest tests/test_bm25.py`.
3. Run `shellcheck --severity=error scripts/*.sh` — must be clean.
4. Update `CHANGELOG.md`: move items from `[Unreleased]` to `[x.y.z] - YYYY-MM-DD`.
5. Update this file: check off the completed release.
6. Commit, tag (`git tag vx.y.z`), push.
