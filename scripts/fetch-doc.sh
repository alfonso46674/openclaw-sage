#!/bin/bash
# Fetch a specific doc and display as readable text
if [ -z "$1" ]; then
  echo "Usage: fetch-doc.sh <path>"
  echo "Example: fetch-doc.sh gateway/configuration"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

DOC_PATH="${1#/}"  # strip leading slash if present
CACHE_FILE="${CACHE_DIR}/doc_$(echo "$DOC_PATH" | tr '/' '_').txt"

if is_cache_fresh "$CACHE_FILE" "$DOC_TTL"; then
  cat "$CACHE_FILE"
  exit 0
fi

URL="${DOCS_BASE_URL}/${DOC_PATH}"
echo "Fetching: $URL" >&2

fetch_text "$URL" | tee "$CACHE_FILE"

if [ ! -s "$CACHE_FILE" ]; then
  rm -f "$CACHE_FILE"
  echo "Error: Failed to fetch or empty response for: $URL" >&2
  echo "Check that the path is valid. Run ./scripts/sitemap.sh to see available docs." >&2
  exit 1
fi
