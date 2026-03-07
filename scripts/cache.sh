#!/bin/bash
# Cache management for Clawdbot docs
CACHE_DIR="${HOME}/.cache/openclaw-sage"
SITEMAP_CACHE="${CACHE_DIR}/sitemap.txt"
CACHE_TTL=3600  # 1 hour in seconds

mkdir -p "$CACHE_DIR"

is_cache_fresh() {
  [ -f "$1" ] || return 1
  local now mtime
  now=$(date +%s)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    mtime=$(stat -f %m "$1")
  else
    mtime=$(stat -c %Y "$1")
  fi
  [ $((now - mtime)) -lt $CACHE_TTL ]
}

case "$1" in
  status)
    if [ -f "$SITEMAP_CACHE" ]; then
      if is_cache_fresh "$SITEMAP_CACHE"; then
        local_mtime=""
        if [[ "$OSTYPE" == "darwin"* ]]; then
          local_mtime=$(stat -f %m "$SITEMAP_CACHE")
        else
          local_mtime=$(stat -c %Y "$SITEMAP_CACHE")
        fi
        cached_at=$(date -d "@${local_mtime}" 2>/dev/null || date -r "$local_mtime" 2>/dev/null)
        echo "Cache status: FRESH"
        echo "Location:     $CACHE_DIR"
        echo "Cached at:    ${cached_at}"
        echo "TTL:          1 hour"
        doc_count=$(ls "$CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
        echo "Cached docs:  $doc_count"
      else
        echo "Cache status: STALE"
        echo "Run: ./scripts/cache.sh refresh"
      fi
    else
      echo "Cache status: EMPTY"
      echo "Run: ./scripts/sitemap.sh to populate"
    fi
    ;;
  refresh)
    echo "Forcing cache refresh..."
    rm -f "${CACHE_DIR}/sitemap.txt" "${CACHE_DIR}/sitemap.xml"
    echo "Sitemap cache cleared. Next sitemap.sh call will re-fetch."
    echo "(Cached docs preserved. Delete ${CACHE_DIR}/doc_*.txt to clear them.)"
    ;;
  clear-docs)
    count=$(ls "$CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
    rm -f "${CACHE_DIR}"/doc_*.txt "${CACHE_DIR}/index.txt"
    echo "Cleared $count cached docs and index."
    ;;
  dir)
    echo "$CACHE_DIR"
    ;;
  *)
    echo "Usage: cache.sh {status|refresh|clear-docs|dir}"
    ;;
esac
