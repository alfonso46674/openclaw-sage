#!/bin/bash
# Shared utilities for openclaw-sage scripts

SITEMAP_TTL="${OPENCLAW_SAGE_SITEMAP_TTL:-3600}"    # 1hr default
DOC_TTL="${OPENCLAW_SAGE_DOC_TTL:-86400}"           # 24hr default
CACHE_DIR="${OPENCLAW_SAGE_CACHE_DIR:-${HOME}/.cache/openclaw-sage}"
DOCS_BASE_URL="https://docs.openclaw.ai"

mkdir -p "$CACHE_DIR"

# is_cache_fresh <file> <ttl_seconds>
is_cache_fresh() {
  local file="$1" ttl="$2"
  [ -f "$file" ] || return 1
  local now mtime
  now=$(date +%s)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    mtime=$(stat -f %m "$file")
  else
    mtime=$(stat -c %Y "$file")
  fi
  [ $((now - mtime)) -lt "$ttl" ]
}

# fetch_text <url> — lynx → w3m → curl+sed fallback chain
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
