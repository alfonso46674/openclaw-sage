#!/bin/bash
# Full-text index management for offline search
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

INDEX_FILE="${CACHE_DIR}/index.txt"
SITEMAP_XML="${CACHE_DIR}/sitemap.xml"

case "$1" in
  fetch)
    echo "Downloading all docs..."

    if ! check_online; then
      echo "Offline: cannot reach ${DOCS_BASE_URL}" >&2
      echo "fetch requires network access. Run build-index.sh status to see cached docs." >&2
      exit 1
    fi

    # Ensure sitemap XML is available
    if [ ! -f "$SITEMAP_XML" ]; then
      echo "Fetching sitemap first..." >&2
      if ! curl -sf --max-time 10 "${DOCS_BASE_URL}/sitemap.xml" -o "$SITEMAP_XML" 2>/dev/null; then
        echo "Error: failed to fetch sitemap (network unreachable?)" >&2
        exit 1
      fi
    fi

    ALL_URLS=$(grep -o '<loc>[^<]*</loc>' "$SITEMAP_XML" 2>/dev/null | sed 's/<[^>]*>//g' | grep "${DOCS_BASE_URL}/" | grep -v "^${DOCS_BASE_URL}/$")

    # Show available languages in the sitemap
    # Language prefix format: "ll/" or "ll-RR/" (e.g. zh-CN/, pt-BR/)
    available_langs=$(echo "$ALL_URLS" | awk -v base_url="$DOCS_BASE_URL" '
      {
        path = $0
        sub(base_url "/", "", path)
        if (match(path, /^[a-z][a-z](-[A-Za-z]+)?\//))
          lang = substr(path, 1, RLENGTH - 1)
        else
          lang = "en"
        langs[lang]++
      }
      END { for (l in langs) printf "%s (%d docs)  ", l, langs[l]; print "" }
    ')
    echo "Languages in sitemap: $available_langs" >&2
    echo "Fetching language(s): $LANGS  (override with OPENCLAW_SAGE_LANGS=en,zh or =all)" >&2

    # Filter URLs by language.
    # LANGS is matched against the base 2-letter code so "zh" catches "zh-CN", "zh-TW", etc.
    if [ "$LANGS" = "all" ]; then
      URLS="$ALL_URLS"
    else
      URLS=$(echo "$ALL_URLS" | awk -v langs=",$LANGS," -v base_url="$DOCS_BASE_URL" '
        {
          url = $0
          sub(base_url "/", "", url)
          if (match(url, /^[a-z][a-z](-[A-Za-z]+)?\//))
            lang = substr(url, 1, 2)   # base code only: "zh-CN" → "zh"
          else
            lang = "en"
          if (index(langs, "," lang ",") > 0) print $0
        }
      ')
    fi

    if [ -z "$URLS" ]; then
      echo "Error: Could not get URL list from sitemap. Run ./scripts/sitemap.sh first." >&2
      exit 1
    fi

    total=$(printf '%s\n' "$URLS" | wc -l)
    fetch_jobs="$FETCH_JOBS"
    if ! [[ "$fetch_jobs" =~ ^[0-9]+$ ]] || [ "$fetch_jobs" -le 0 ]; then
      fetch_jobs=8
    fi
    new=0
    fetch_sequential() {
      while IFS= read -r url; do
        path=$(echo "$url" | sed "s|${DOCS_BASE_URL}/||")
        [ -z "$path" ] && continue
        cache_file="${CACHE_DIR}/doc_$(echo "$path" | tr '/' '_').txt"
        if [ ! -f "$cache_file" ] || ! is_cache_fresh "$cache_file" "$DOC_TTL"; then
          safe="$(echo "$path" | tr '/' '_')"
          if fetch_and_cache "$url" "$safe"; then
            new=$((new + 1))
            echo "  [done] $path" >&2
          fi
          sleep 0.3
        fi
      done <<< "$URLS"
    }

    if command -v xargs &>/dev/null; then
      MARKER_DIR=$(mktemp -d)
      trap 'rm -rf "$MARKER_DIR"' EXIT
      export OPENCLAW_SAGE_CACHE_DIR OPENCLAW_SAGE_DOCS_BASE_URL OPENCLAW_SAGE_DOC_TTL OPENCLAW_SAGE_LANGS
      export LIB_SH="$SCRIPT_DIR/lib.sh" MARKER_DIR

      if printf '%s\n' "$URLS" \
        | tr '\n' '\0' \
        | xargs -0 -n 1 -P "$fetch_jobs" bash -c '
            source "$LIB_SH"
            url="$1"
            [ -z "$url" ] && exit 0
            path=$(echo "$url" | sed "s|${DOCS_BASE_URL}/||")
            [ -z "$path" ] && exit 0
            safe=$(echo "$path" | tr "/" "_")
            cache_file="${CACHE_DIR}/doc_${safe}.txt"
            if [ ! -f "$cache_file" ] || ! is_cache_fresh "$cache_file" "$DOC_TTL"; then
              if fetch_and_cache "$url" "$safe"; then
                touch "${MARKER_DIR}/${safe}"
                echo "  [done] $path" >&2
              fi
              sleep 0.3
            fi
          ' --; then
        set -- "$MARKER_DIR"/*
        if [ -e "$1" ]; then
          new=$#
        fi
      else
        echo "xargs unavailable or failed; falling back to sequential fetch." >&2
        new=0
        fetch_sequential
      fi
      trap - EXIT
      rm -rf "$MARKER_DIR"
    else
      echo "xargs not available; falling back to sequential fetch." >&2
      fetch_sequential
    fi

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

    META_FILE="${CACHE_DIR}/index_meta.json"
    TMP_INDEX=$(mktemp)
    CURRENT_PATHS=$(mktemp)
    CHANGED_PATHS=$(mktemp)
    UNCHANGED_PATHS=$(mktemp)
    INDEXED_PATHS=$(mktemp)
    trap 'rm -f "$TMP_INDEX" "$CURRENT_PATHS" "$CHANGED_PATHS" "$UNCHANGED_PATHS" "$INDEXED_PATHS"' RETURN

    append_doc_lines() {
      local doc_file="$1" out_file="$2" path
      path=$(basename "$doc_file" .txt | sed 's/^doc_//; s/_/\//g')
      grep -v '^[[:space:]]*$' "$doc_file" | while IFS= read -r line; do
        echo "${path}|${line}"
      done >> "$out_file"
    }

    doc_count=0
    changed_count=0
    index_exists=false
    [ -f "$INDEX_FILE" ] && index_exists=true
    if $index_exists; then
      index_mtime=$(get_mtime "$INDEX_FILE")
    fi

    for f in "$CACHE_DIR"/doc_*.txt; do
      path=$(basename "$f" .txt | sed 's/^doc_//; s/_/\//g')
      echo "$path" >> "$CURRENT_PATHS"
      doc_count=$((doc_count + 1))
      if ! $index_exists || [ "$(get_mtime "$f")" -gt "$index_mtime" ]; then
        echo "$path" >> "$CHANGED_PATHS"
        changed_count=$((changed_count + 1))
      else
        echo "$path" >> "$UNCHANGED_PATHS"
      fi
    done

    removed_count=0
    if $index_exists; then
      awk -F'|' '!seen[$1]++ { print $1 }' "$INDEX_FILE" > "$INDEXED_PATHS"
      removed_count=$(awk '
        NR==FNR { current[$0]=1; next }
        !($0 in current) { removed++ }
        END { print removed + 0 }
      ' "$CURRENT_PATHS" "$INDEXED_PATHS")
    fi

    if $index_exists && [ "$changed_count" -eq 0 ] && [ "$removed_count" -eq 0 ]; then
      line_count=$(wc -l < "$INDEX_FILE")
      echo "Index already up to date: $doc_count docs, $line_count lines."
    else
      : > "$TMP_INDEX"
      if $index_exists && [ -s "$INDEX_FILE" ] && [ -s "$UNCHANGED_PATHS" ]; then
        awk -F'|' '
          NR==FNR { keep[$0]=1; next }
          ($1 in keep) { print }
        ' "$UNCHANGED_PATHS" "$INDEX_FILE" >> "$TMP_INDEX"
      fi

      for f in "$CACHE_DIR"/doc_*.txt; do
        path=$(basename "$f" .txt | sed 's/^doc_//; s/_/\//g')
        if ! $index_exists || grep -Fxq "$path" "$CHANGED_PATHS"; then
          append_doc_lines "$f" "$TMP_INDEX"
        fi
      done

      mv "$TMP_INDEX" "$INDEX_FILE"
      line_count=$(wc -l < "$INDEX_FILE")
      echo "Index built: $doc_count docs, $line_count lines."
    fi

    if command -v python3 &>/dev/null; then
      echo "Building BM25 meta..." >&2
      python3 "$SCRIPT_DIR/bm25_search.py" build-meta "$INDEX_FILE" || {
        echo "Error: build-meta failed" >&2
        exit 1
      }
    fi

    echo "Location: $INDEX_FILE"
    echo "Search with: ./scripts/build-index.sh search <query>"
    ;;

  search)
    shift
    MAX_RESULTS=10
    QUERY_ARGS=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --max-results)
          shift
          if [ -z "$1" ] || ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -le 0 ]; then
            echo "Usage: build-index.sh search [--max-results N] <query>"
            exit 1
          fi
          MAX_RESULTS="$1"
          ;;
        *)
          QUERY_ARGS+=("$1")
          ;;
      esac
      shift
    done
    QUERY="${QUERY_ARGS[*]}"
    if [ -z "$QUERY" ]; then
      echo "Usage: build-index.sh search [--max-results N] <query>"
      exit 1
    fi

    if [ ! -f "$INDEX_FILE" ]; then
      echo "No index found. Run:"
      echo "  ./scripts/build-index.sh fetch"
      echo "  ./scripts/build-index.sh build"
      exit 1
    fi

    echo "Search results for: $QUERY"
    echo ""

    if command -v python3 &>/dev/null; then
      python3 "$SCRIPT_DIR/bm25_search.py" search "$INDEX_FILE" "$QUERY" "$MAX_RESULTS" \
        | while IFS='|' read -r score path excerpt; do
            score=$(echo "$score" | tr -d ' ')
            path=$(echo "$path" | tr -d ' ')
            excerpt=$(echo "$excerpt" | sed 's/^[[:space:]]*//')
            echo "  [$score] $path  ->  ${DOCS_BASE_URL}/$path"
            echo "          $excerpt"
            echo ""
          done
    else
      # grep fallback when python3 unavailable
      grep -i "$QUERY" "$INDEX_FILE" \
        | awk -F'|' -v base_url="$DOCS_BASE_URL" '
            {
              if ($1 != prev) {
                if (prev != "") print ""
                print "  [---] " $1 "  ->  " base_url "/" $1
                prev = $1
                count = 0
              }
              if (count < 4) {
                gsub(/^[[:space:]]+/, "", $2)
                print "        " $2
                count++
              }
            }
          ' \
        | head -"$((MAX_RESULTS * 4))"
      echo ""
      echo "Note: Install python3 for ranked BM25 results."
    fi

    match_count=$(grep -ic "$QUERY" "$INDEX_FILE" 2>/dev/null || echo 0)
    echo "($match_count matching lines across all docs)"
    ;;

  status)
    doc_count=$(ls "$CACHE_DIR"/doc_*.txt 2>/dev/null | wc -l)
    echo "Cached docs: $doc_count"
    if [ -f "$INDEX_FILE" ]; then
      line_count=$(wc -l < "$INDEX_FILE")
      echo "Index:       $line_count lines  ($INDEX_FILE)"
      META_FILE="${CACHE_DIR}/index_meta.json"
      if [ -f "$META_FILE" ]; then
        echo "BM25 meta:   present"
      else
        echo "BM25 meta:   not built (run 'build' to generate)"
      fi
    else
      echo "Index:       not built"
    fi
    ;;

  *)
    echo "Usage: build-index.sh {fetch|build|search [--max-results N] <query>|status}"
    ;;
esac
