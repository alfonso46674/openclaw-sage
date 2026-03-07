#!/bin/bash
# Search docs by keyword - searches cached docs and sitemap paths
if [ -z "$1" ]; then
  echo "Usage: search.sh <keyword>"
  exit 1
fi

KEYWORD="$*"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

SITEMAP_CACHE="${CACHE_DIR}/sitemap.txt"
INDEX_FILE="${CACHE_DIR}/index.txt"

echo "Searching docs for: $KEYWORD"
echo ""

found=0

# 1. Search full-text index with BM25 if available
if [ -f "$INDEX_FILE" ] && command -v python3 &>/dev/null; then
  echo "=== Full-text index matches (BM25 ranked) ==="
  python3 "$SCRIPT_DIR/bm25_search.py" search "$INDEX_FILE" "$KEYWORD" \
    | while IFS='|' read -r score path excerpt; do
        score=$(echo "$score" | tr -d ' ')
        path=$(echo "$path" | tr -d ' ')
        excerpt=$(echo "$excerpt" | sed 's/^[[:space:]]*//')
        echo "  [$score] $path  ->  ${DOCS_BASE_URL}/$path"
        echo "          $excerpt"
        echo ""
      done
  echo ""
  found=1

# 2. grep fallback when index exists but python3 unavailable
elif [ -f "$INDEX_FILE" ]; then
  echo "=== Full-text index matches ==="
  echo "Note: Install python3 for ranked BM25 results."
  echo ""
  grep -i "$KEYWORD" "$INDEX_FILE" \
    | awk -F'|' '
        {
          if ($1 != prev) {
            print ""
            print "  [---] " $1 "  ->  https://docs.openclaw.ai/" $1
            prev = $1
            count = 0
          }
          if (count < 3) {
            gsub(/^[[:space:]]+/, "", $2)
            print "        " $2
            count++
          }
        }
      ' \
    | head -60
  echo ""
  found=1

# 3. Search individually cached docs (no index built yet)
elif ls "$CACHE_DIR"/doc_*.txt &>/dev/null 2>&1; then
  echo "=== Cached doc matches ==="
  echo "Note: Run './scripts/build-index.sh build' for ranked BM25 results."
  echo ""
  grep -ril "$KEYWORD" "$CACHE_DIR"/doc_*.txt 2>/dev/null | while IFS= read -r f; do
    path=$(basename "$f" .txt | sed 's/^doc_//; s/_/\//g')
    echo "  [---] $path  ->  ${DOCS_BASE_URL}/$path"
    grep -i "$KEYWORD" "$f" | head -3 | sed 's/^[[:space:]]*/        /'
    echo ""
  done
  found=1
fi

# 4. Search sitemap paths (always shown when available)
if [ -f "$SITEMAP_CACHE" ]; then
  matches=$(grep -i "$KEYWORD" "$SITEMAP_CACHE" | grep '^\s*-')
  if [ -n "$matches" ]; then
    echo "=== Matching doc paths ==="
    echo "$matches" | head -15 | sed 's/^[[:space:]]*/  /'
    echo ""
  fi
fi

# 5. No content at all
if [ "$found" -eq 0 ]; then
  echo "No cached content to search. Options:"
  echo "  1. Fetch a specific doc:  ./scripts/fetch-doc.sh <path>"
  echo "  2. Download all docs:     ./scripts/build-index.sh fetch"
  echo "  3. Build search index:    ./scripts/build-index.sh build"
fi

echo "Tip: For comprehensive ranked results:"
echo "  ./scripts/build-index.sh fetch && ./scripts/build-index.sh build"
echo "  ./scripts/build-index.sh search \"$KEYWORD\""
