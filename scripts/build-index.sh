#!/bin/bash
# Full-text index management for offline search
CACHE_DIR="${HOME}/.cache/openclaw-sage"
INDEX_FILE="${CACHE_DIR}/index.txt"
SITEMAP_XML="${CACHE_DIR}/sitemap.xml"

mkdir -p "$CACHE_DIR"

fetch_text() {
  local url="$1"
  if command -v lynx &>/dev/null; then
    lynx -dump -nolist "$url" 2>/dev/null
  elif command -v w3m &>/dev/null; then
    w3m -dump "$url" 2>/dev/null
  else
    curl -sf --max-time 15 "$url" 2>/dev/null \
      | sed 's/<script[^>]*>.*<\/script>//gI' \
      | sed 's/<style[^>]*>.*<\/style>//gI' \
      | sed 's/<[^>]*>//g' \
      | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&nbsp;/ /g' \
      | sed '/^[[:space:]]*$/d'
  fi
}

case "$1" in
  fetch)
    echo "Downloading all docs..."

    # Ensure sitemap XML is available
    if [ ! -f "$SITEMAP_XML" ]; then
      echo "Fetching sitemap first..." >&2
      curl -sf --max-time 10 "https://docs.openclaw.ai/sitemap.xml" -o "$SITEMAP_XML" 2>/dev/null
    fi

    URLS=$(grep -oP '(?<=<loc>)[^<]+' "$SITEMAP_XML" 2>/dev/null | grep "docs\.openclaw\.ai/" | grep -v '^https://docs\.openclaw\.ai/$')

    if [ -z "$URLS" ]; then
      echo "Error: Could not get URL list from sitemap. Run ./scripts/sitemap.sh first."
      exit 1
    fi

    total=$(echo "$URLS" | wc -l)
    count=0
    new=0

    while IFS= read -r url; do
      path=$(echo "$url" | sed 's|https://docs\.clawd\.bot/||')
      [ -z "$path" ] && continue
      cache_file="${CACHE_DIR}/doc_$(echo "$path" | tr '/' '_').txt"
      count=$((count + 1))
      printf "\r  [%d/%d] %s          " "$count" "$total" "$path" >&2

      if [ ! -f "$cache_file" ]; then
        fetch_text "$url" > "$cache_file"
        if [ ! -s "$cache_file" ]; then
          rm -f "$cache_file"
        else
          new=$((new + 1))
        fi
        sleep 0.3  # be polite to the server
      fi
    done <<< "$URLS"

    printf "\n" >&2
    cached=$(ls "$CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
    echo "Done. $new new docs fetched, $cached total cached."
    echo "Next: run './scripts/build-index.sh build' to index them."
    ;;

  build)
    echo "Building search index..."
    if ! ls "$CACHE_DIR"/doc_*.txt &>/dev/null 2>&1; then
      echo "No docs cached. Run: ./scripts/build-index.sh fetch first."
      exit 1
    fi

    > "$INDEX_FILE"
    doc_count=0
    for f in "$CACHE_DIR"/doc_*.txt; do
      path=$(basename "$f" .txt | sed 's/^doc_//; s/_/\//g')
      grep -v '^[[:space:]]*$' "$f" | while IFS= read -r line; do
        echo "${path}|${line}"
      done >> "$INDEX_FILE"
      doc_count=$((doc_count + 1))
    done

    line_count=$(wc -l < "$INDEX_FILE")
    echo "Index built: $doc_count docs, $line_count lines."
    echo "Location: $INDEX_FILE"
    echo "Search with: ./scripts/build-index.sh search <query>"
    ;;

  search)
    shift
    if [ -z "$*" ]; then
      echo "Usage: build-index.sh search <query>"
      exit 1
    fi
    QUERY="$*"

    if [ ! -f "$INDEX_FILE" ]; then
      echo "No index found. Run:"
      echo "  ./scripts/build-index.sh fetch"
      echo "  ./scripts/build-index.sh build"
      exit 1
    fi

    echo "Search results for: $QUERY"
    echo ""

    grep -i "$QUERY" "$INDEX_FILE" \
      | awk -F'|' '
          {
            if ($1 != prev) {
              if (prev != "") print ""
              print "📄 " $1 "  →  https://docs.openclaw.ai/" $1
              prev = $1
              count = 0
            }
            if (count < 4) {
              gsub(/^[[:space:]]+/, "", $2)
              print "   " $2
              count++
            }
          }
        ' \
      | head -80

    match_count=$(grep -ic "$QUERY" "$INDEX_FILE" 2>/dev/null || echo 0)
    echo ""
    echo "($match_count matching lines across all docs)"
    ;;

  status)
    doc_count=$(ls "$CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
    echo "Cached docs: $doc_count"
    if [ -f "$INDEX_FILE" ]; then
      line_count=$(wc -l < "$INDEX_FILE")
      echo "Index:       $line_count lines  ($INDEX_FILE)"
    else
      echo "Index:       not built"
    fi
    ;;

  *)
    echo "Usage: build-index.sh {fetch|build|search <query>|status}"
    ;;
esac
