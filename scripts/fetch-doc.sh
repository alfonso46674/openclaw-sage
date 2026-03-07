#!/bin/bash
# Fetch a specific doc and display as readable text
if [ -z "$1" ]; then
  echo "Usage: fetch-doc.sh <path>"
  echo "Example: fetch-doc.sh gateway/configuration"
  exit 1
fi

CACHE_DIR="${HOME}/.cache/openclaw-sage"
DOC_PATH="${1#/}"  # strip leading slash if present
CACHE_FILE="${CACHE_DIR}/doc_$(echo "$DOC_PATH" | tr '/' '_').txt"
CACHE_TTL=3600

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

if is_cache_fresh "$CACHE_FILE"; then
  cat "$CACHE_FILE"
  exit 0
fi

URL="https://docs.openclaw.ai/${DOC_PATH}"
echo "Fetching: $URL" >&2

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

fetch_text "$URL" | tee "$CACHE_FILE"

if [ ! -s "$CACHE_FILE" ]; then
  rm -f "$CACHE_FILE"
  echo "Error: Failed to fetch or empty response for: $URL" >&2
  echo "Check that the path is valid. Run ./scripts/sitemap.sh to see available docs." >&2
  exit 1
fi
