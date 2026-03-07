#!/bin/bash
# Sitemap generator - fetches and displays all docs by category
CACHE_DIR="${HOME}/.cache/openclaw-sage"
SITEMAP_CACHE="${CACHE_DIR}/sitemap.txt"
SITEMAP_XML="${CACHE_DIR}/sitemap.xml"
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

if is_cache_fresh "$SITEMAP_CACHE"; then
  cat "$SITEMAP_CACHE"
  exit 0
fi

echo "Fetching Clawdbot documentation sitemap..." >&2

if curl -sf --max-time 10 "https://docs.openclaw.ai/sitemap.xml" -o "$SITEMAP_XML" 2>/dev/null; then
  # Parse URLs from sitemap XML, group by top-level category
  grep -oP '(?<=<loc>)[^<]+' "$SITEMAP_XML" \
    | grep "docs\.openclaw\.ai/" \
    | sed 's|https://docs\.openclaw\.ai/||' \
    | grep -v '^$' \
    | sort \
    | awk -F'/' '
        {
          cat = $1
          if (cat == "") next
          if (cat != prev_cat) {
            if (prev_cat != "") print ""
            print "📁 /" cat "/"
            prev_cat = cat
          }
          if (NF > 1) print "  - " $0
        }
      ' \
    | tee "$SITEMAP_CACHE"
else
  echo "Warning: Could not fetch live sitemap. Showing known categories." >&2
  {
    printf "📁 /start/\n  - start/getting-started\n  - start/setup\n  - start/faq\n\n"
    printf "📁 /gateway/\n  - gateway/configuration\n  - gateway/configuration-examples\n  - gateway/security\n  - gateway/health\n  - gateway/logging\n  - gateway/tailscale\n  - gateway/troubleshooting\n\n"
    printf "📁 /providers/\n  - providers/discord\n  - providers/telegram\n  - providers/whatsapp\n  - providers/slack\n  - providers/signal\n  - providers/imessage\n  - providers/msteams\n  - providers/troubleshooting\n\n"
    printf "📁 /concepts/\n  - concepts/agent\n  - concepts/sessions\n  - concepts/messages\n  - concepts/models\n  - concepts/queues\n  - concepts/streaming\n  - concepts/system-prompt\n\n"
    printf "📁 /tools/\n  - tools/bash\n  - tools/browser\n  - tools/skills\n  - tools/reactions\n  - tools/subagents\n  - tools/thinking\n  - tools/browser-linux-troubleshooting\n\n"
    printf "📁 /automation/\n  - automation/cron-jobs\n  - automation/webhook\n  - automation/polling\n  - automation/gmail-pubsub\n\n"
    printf "📁 /cli/\n  - cli/gateway\n  - cli/message\n  - cli/sandbox\n  - cli/update\n\n"
    printf "📁 /platforms/\n  - platforms/linux\n  - platforms/macos\n  - platforms/windows\n  - platforms/ios\n  - platforms/android\n  - platforms/hetzner\n\n"
    printf "📁 /nodes/\n  - nodes/camera\n  - nodes/audio\n  - nodes/images\n  - nodes/location\n  - nodes/voice\n\n"
    printf "📁 /web/\n  - web/webchat\n  - web/dashboard\n\n"
    printf "📁 /install/\n  - install/docker\n  - install/ansible\n  - install/bun\n  - install/nix\n  - install/updating\n\n"
    printf "📁 /reference/\n  - reference/templates\n  - reference/rpc\n  - reference/device-models\n"
  } | tee "$SITEMAP_CACHE"
fi
