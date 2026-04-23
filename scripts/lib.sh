#!/bin/bash
# Shared utilities for openclaw-sage scripts

SITEMAP_TTL="${OPENCLAW_SAGE_SITEMAP_TTL:-3600}"    # 1hr default
DOC_TTL="${OPENCLAW_SAGE_DOC_TTL:-86400}"           # 24hr default
LANGS="${OPENCLAW_SAGE_LANGS:-en}"                  # comma-separated lang codes, or "all"
FETCH_JOBS="${OPENCLAW_SAGE_FETCH_JOBS:-8}"         # parallel fetch workers for build-index.sh fetch
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${OPENCLAW_SAGE_CACHE_DIR:-${_LIB_DIR}/../.cache/openclaw-sage}"
DOCS_BASE_URL="${OPENCLAW_SAGE_DOCS_BASE_URL:-https://docs.openclaw.ai}"

mkdir -p "$CACHE_DIR"

# check_online — returns 0 if DOCS_BASE_URL is reachable, 1 if not
check_online() {
  curl -sf --max-time 2 -o /dev/null -I "$DOCS_BASE_URL" 2>/dev/null
}

# clean_html_file <input_html> <output_html> — remove non-content chrome while preserving structure
clean_html_file() {
  local input_html="$1" output_html="$2"

  if ! command -v python3 &>/dev/null; then
    cat "$input_html" > "$output_html"
    return 0
  fi

  python3 - "$input_html" "$output_html" <<'PYEOF' || {
import sys
from html import escape
from html.parser import HTMLParser

input_path, output_path = sys.argv[1], sys.argv[2]
drop_tags = {"script", "style", "noscript", "nav", "header", "footer", "aside"}
keep_attrs = {"id", "href", "src", "alt", "title"}
content_id_targets = {"content", "content-area", "main-content", "docs-content"}


class Node:
    def __init__(self, tag=None, attrs=None, self_closing=False):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.self_closing = self_closing
        self.children = []


class Cleaner(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.skip_depth = 0
        self.root = Node()
        self.stack = [self.root]

    def _keep(self):
        return self.skip_depth == 0

    def _push_node(self, tag, attrs, self_closing=False):
        node = Node(tag, attrs, self_closing=self_closing)
        self.stack[-1].children.append(node)
        if not self_closing:
            self.stack.append(node)

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in drop_tags:
            self.skip_depth += 1
            return
        if self._keep():
            self._push_node(tag, attrs)

    def handle_startendtag(self, tag, attrs):
        tag = tag.lower()
        if tag in drop_tags or not self._keep():
            return
        self._push_node(tag, attrs, self_closing=True)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in drop_tags:
            if self.skip_depth:
                self.skip_depth -= 1
            return
        if self._keep() and len(self.stack) > 1:
            for idx in range(len(self.stack) - 1, 0, -1):
                if self.stack[idx].tag == tag:
                    del self.stack[idx:]
                    break

    def handle_data(self, data):
        if self._keep():
            self.stack[-1].children.append(data)

    def handle_entityref(self, name):
        if self._keep():
            self.stack[-1].children.append(f"&{name};")

    def handle_charref(self, name):
        if self._keep():
            self.stack[-1].children.append(f"&#{name};")

    def handle_comment(self, data):
        pass

    def handle_decl(self, decl):
        pass

    def handle_pi(self, data):
        pass


def walk(node):
    if isinstance(node, str):
        return
    yield node
    for child in node.children:
        yield from walk(child)


def text_content(node):
    parts = []
    for child in node.children:
        if isinstance(child, str):
            parts.append(child)
        else:
            parts.append(text_content(child))
    return "".join(parts)


def find_first(node, predicate):
    for child in node.children:
        if isinstance(child, str):
            continue
        if predicate(child):
            return child
        found = find_first(child, predicate)
        if found is not None:
            return found
    return None


def render(node):
    if isinstance(node, str):
        return node

    attrs = []
    for key, value in node.attrs.items():
        if key in keep_attrs and value is not None:
            attrs.append(f' {key}="{escape(value, quote=True)}"')
    start = f"<{node.tag}{''.join(attrs)}>"
    if node.self_closing:
        return start[:-1] + "/>"

    inner = "".join(render(child) for child in node.children)
    return f"{start}{inner}</{node.tag}>"


with open(input_path, encoding="utf-8", errors="replace") as fh:
    raw_html = fh.read()

parser = Cleaner()
parser.feed(raw_html)
parser.close()

title_node = find_first(parser.root, lambda n: n.tag == "title")
title_html = ""
if title_node is not None:
    title_html = f"<title>{escape(text_content(title_node))}</title>"

content_node = find_first(
    parser.root,
    lambda n: (
        n.attrs.get("id") in content_id_targets
        or "data-page-title" in n.attrs
        or "data-page-href" in n.attrs
        or n.tag in {"main", "article"}
        or n.attrs.get("role") == "main"
    ),
)

if content_node is None:
    body_node = find_first(parser.root, lambda n: n.tag == "body")
    content_html = "".join(render(child) for child in (body_node.children if body_node else parser.root.children))
else:
    content_html = render(content_node)

with open(output_path, "w", encoding="utf-8") as fh:
    fh.write(f"<html><head>{title_html}</head><body>{content_html}</body></html>")
PYEOF
    cat "$input_html" > "$output_html"
  }
}

# html_to_text <html_file> — convert cached HTML to plain text
html_to_text() {
  local html_file="$1"
  if command -v lynx &>/dev/null; then
    lynx -dump -nolist "file://${html_file}" 2>/dev/null
  elif command -v w3m &>/dev/null; then
    w3m -dump "$html_file" 2>/dev/null
  else
    sed 's/<[^>]*>//g' "$html_file" \
      | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&nbsp;/ /g' \
      | sed '/^[[:space:]]*$/d'
  fi
}

# get_mtime <file> — print file mtime as epoch seconds
get_mtime() {
  local file="$1"
  [ -f "$file" ] || return 1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file"
  else
    stat -c %Y "$file"
  fi
}

# is_cache_fresh <file> <ttl_seconds>
is_cache_fresh() {
  local file="$1" ttl="$2"
  [ -f "$file" ] || return 1
  local now mtime
  now=$(date +%s)
  mtime=$(get_mtime "$file") || return 1
  [ $((now - mtime)) -lt "$ttl" ]
}

# fetch_and_cache <url> <safe_path> — fetch HTML, clean it, and derive plain text
# Writes: $CACHE_DIR/doc_<safe_path>.html  (cleaned HTML)
#         $CACHE_DIR/doc_<safe_path>.txt   (plain text)
# Returns 0 on success, 1 on failure (nothing written).
fetch_and_cache() {
  local url="$1" safe="$2"
  local html_file="${CACHE_DIR}/doc_${safe}.html"
  local txt_file="${CACHE_DIR}/doc_${safe}.txt"
  local tmp_raw tmp_html
  tmp_raw=$(mktemp)
  tmp_html=$(mktemp)
  trap 'rm -f "$tmp_raw" "$tmp_html"' RETURN

  if ! curl -sf --max-time 15 "$url" -o "$tmp_raw" 2>/dev/null || [ ! -s "$tmp_raw" ]; then
    rm -f "$tmp_raw" "$tmp_html"
    return 1
  fi

  clean_html_file "$tmp_raw" "$tmp_html"
  mv "$tmp_html" "$html_file"
  html_to_text "$html_file" > "$txt_file"

  if [ ! -s "$txt_file" ]; then
    rm -f "$txt_file"
    return 1
  fi
}

# fetch_text <url> — lynx → w3m → curl+sed fallback chain
fetch_text() {
  local url="$1"
  local tmp_raw tmp_html
  tmp_raw=$(mktemp)
  tmp_html=$(mktemp)
  trap 'rm -f "$tmp_raw" "$tmp_html"' RETURN

  if ! curl -sf --max-time 15 "$url" -o "$tmp_raw" 2>/dev/null || [ ! -s "$tmp_raw" ]; then
    rm -f "$tmp_raw" "$tmp_html"
    return 1
  fi

  clean_html_file "$tmp_raw" "$tmp_html"
  html_to_text "$tmp_html"
}
