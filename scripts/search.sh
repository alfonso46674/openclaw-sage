#!/bin/bash
# Search docs by keyword - searches cached docs and sitemap paths
if [ -z "$1" ]; then
  echo "Usage: search.sh <keyword>"
  exit 1
fi

KEYWORD="$1"
CACHE_DIR="${HOME}/.cache/openclaw-sage"
SITEMAP_CACHE="${CACHE_DIR}/sitemap.txt"
INDEX_FILE="${CACHE_DIR}/index.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Searching docs for: $KEYWORD"
echo ""

found=0

# 1. Search full-text index if available
if [ -f "$INDEX_FILE" ]; then
  echo "=== Full-text index matches ==="
  grep -i "$KEYWORD" "$INDEX_FILE" \
    | awk -F'|' '
        {
          if ($1 != prev) {
            print ""
            print "  📄 " $1
            prev = $1
            count = 0
          }
          if (count < 3) {
            gsub(/^[[:space:]]+/, "", $2)
            print "     " $2
            count++
          }
        }
      ' \
    | head -60
  echo ""
  found=1
fi

# 2. Search individually cached docs (if no index)
if [ "$found" -eq 0 ] && ls "$CACHE_DIR"/doc_*.txt &>/dev/null 2>&1; then
  echo "=== Cached doc matches ==="
  grep -ril "$KEYWORD" "$CACHE_DIR"/doc_*.txt 2>/dev/null | while IFS= read -r f; do
    path=$(basename "$f" .txt | sed 's/^doc_//; s/_/\//g')
    echo ""
    echo "  📄 $path"
    grep -i "$KEYWORD" "$f" | head -3 | sed 's/^[[:space:]]*/     /'
  done
  echo ""
  found=1
fi

# 3. Search sitemap paths (always useful)
if [ -f "$SITEMAP_CACHE" ]; then
  matches=$(grep -i "$KEYWORD" "$SITEMAP_CACHE" | grep '^\s*-')
  if [ -n "$matches" ]; then
    echo "=== Matching doc paths ==="
    echo "$matches" | head -15
    echo ""
  fi
fi

# 4. Suggest expanding search
if [ "$found" -eq 0 ]; then
  echo "No cached content to search. Options:"
  echo "  1. Fetch a specific doc:  ./scripts/fetch-doc.sh <path>"
  echo "  2. Download all docs:     ./scripts/build-index.sh fetch"
  echo "  3. Build search index:    ./scripts/build-index.sh build"
fi

echo "Tip: For comprehensive results, run:"
echo "  ./scripts/build-index.sh fetch && ./scripts/build-index.sh build"
echo "  ./scripts/build-index.sh search \"$KEYWORD\""
