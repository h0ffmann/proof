#!/usr/bin/env bash
# md-quality: three analysers over the Markdown files, each for one kind of fault.
#   - markdownlint-cli2: the structure (.markdownlint-cli2.jsonc)
#   - Vale: the prose rules of AGENTS.md (.vale.ini, .vale/styles/fabric/)
#   - lychee: links to files and headings that do not exist; with --online, dead web links too
# The tools come from the flake's `md` shell (`just md-quality` enters it), pinned by flake.lock.
# From Paper Fabric (h0ffmann/closed-source, scripts/md-quality.sh); docs/paper-fabric.md says
# what each rule is and what the three do not check.
#
#   scripts/md-quality.sh              # what CI runs: structure, prose, local links
#   scripts/md-quality.sh --online     # the same, and lychee fetches every web link
#   scripts/md-quality.sh --self-test  # each analyser must refuse a bad file
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Not checked by any of the three: other people's text (vendored tools).
skip='^(vendor/|LICENSES/)'
# The paper's sources are pandoc's Markdown, and `tools/fabric ste-check` is their check.
# The video script is such a paper, in the bandit's folder (contextual-bandits/script/).
paper='^(papers/[^/]+/([^/]+/)?|contextual-bandits/script/)(prose[^/]*/|metadata\.md$)'
# Vale's rules are for English that this repository writes, not for Portuguese.
not_prose='(pt-BR)'

files() { git ls-files '*.md' | grep -Ev "$skip" | grep -Ev "$paper"; }

self_test() {
  local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  fail() { echo "md-quality: self-test: $1" >&2; exit 1; }
  printf '# A page\n## No blank line above\n\n\n\nTwo blank lines above.\n' > "$d/structure.md"
  ! markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/structure.md" >/dev/null 2>&1 \
    || fail "markdownlint passed a heading with no blank line"
  printf '# A page\n\nWe utilize a very robust tool.\n' > "$d/prose.md"
  ! vale --config .vale.ini --no-wrap "$d/prose.md" >/dev/null 2>&1 \
    || fail "Vale passed 'utilize' and 'very'"
  printf '# A page\n\nA plain sentence with a number: 3 tools.\n' > "$d/good.md"
  vale --config .vale.ini --no-wrap "$d/good.md" >/dev/null 2>&1 || fail "Vale refused a plain sentence"
  printf '# A page\n\n[a file that is not there](not-there.md)\n' > "$d/link.md"
  ! lychee --offline --no-progress "$d/link.md" >/dev/null 2>&1 \
    || fail "lychee passed a link to a file that does not exist"
  echo "md-quality: self-test ok: each of the three refused a bad file" >&2
}


online=0
case "${1:-}" in
  --self-test) self_test; exit 0 ;;
  --online) online=1 ;;
  "") ;;
  *) echo "md-quality: usage: scripts/md-quality.sh [--online | --self-test]" >&2; exit 1 ;;
esac

mapfile -t all < <(files)
mapfile -t prose < <(files | grep -Ev "$not_prose")
bad=0

echo "md-quality: structure: markdownlint-cli2 on ${#all[@]} files" >&2
markdownlint-cli2 "${all[@]}" >/dev/null 2>"${TMPDIR:-/tmp}/md-quality.$$" \
  || { grep -E ' (error|warning) ' "${TMPDIR:-/tmp}/md-quality.$$" >&2 || cat "${TMPDIR:-/tmp}/md-quality.$$" >&2; bad=1; }
rm -f "${TMPDIR:-/tmp}/md-quality.$$"

echo "md-quality: prose: Vale on ${#prose[@]} files (an error fails; a warning is advice)" >&2
vale --no-wrap --output=line "${prose[@]}" >&2 || bad=1

# 403, 405 and 429 count as an answer: the site is there and refuses a robot (a publisher's page
# behind a DOI does this), or asks it to slow down. A person with a browser gets the page.
if [ "$online" = 1 ]; then
  echo "md-quality: links: lychee on ${#all[@]} files, web links too" >&2
  # A site that is busy for a moment (a 503 from GitHub) must not fail a pull request, and a dead
  # link must. So: each link is tried five times; the answers are kept (`--cache`); and if a link
  # still fails, lychee runs once more after a minute, which fetches only the links that failed.
  web() {
    # Two requests at a time to one host, half a second apart: github.com answers 500 and 503 to
    # a checker that asks too fast (Paper Fabric's md-quality.md, 14 October 2026).
    lychee --no-progress --include-fragments --max-concurrency 6 --max-retries 4 --retry-wait-time 5 \
      --host-concurrency 2 --host-request-interval 500ms \
      --timeout 30 --cache --max-cache-age 1h --accept 200,403,405,429 "${all[@]}" >&2
  }
  rm -f .lycheecache
  web || { echo "md-quality: links: a link did not answer; the second and last try in 60 s" >&2; sleep 60; web || bad=1; }
  rm -f .lycheecache
else
  echo "md-quality: links: lychee on ${#all[@]} files, local links (run --online for the web)" >&2
  lychee --offline --no-progress --include-fragments "${all[@]}" >&2 || bad=1
fi

[ "$bad" = 0 ] || { echo "md-quality: failed" >&2; exit 1; }
echo "md-quality: ok" >&2
