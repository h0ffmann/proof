#!/usr/bin/env bash
# aixiv: publish a paper of papers/ to aiXiv (https://aixiv.online) through its REST API, as
# https://aixiv.online/skill.md describes it (read 2026-11-11). The workflow
# .github/workflows/aixiv.yml runs it by hand only; docs/aixiv.md is the guide.
#
#   scripts/aixiv.sh check                      # every papers/*/aixiv.json is valid (no network)
#   scripts/aixiv.sh check --self-test          # the check must refuse bad manifests
#   scripts/aixiv.sh build <slug>               # PDF, LaTeX and metadata into build/aixiv/<slug>/
#   scripts/aixiv.sh submit <slug>              # dry run: aiXiv validates, nothing is published
#   scripts/aixiv.sh submit <slug> --publish [--changelog TEXT]
#
# papers/<slug>/aixiv.json holds the fields of the submission under the names of the API (the same
# names the aixiv command line reads from an aixiv.json, so `npx aixiv publish` works on it too),
# long ones as "file:NAME.md", plus "id" once the paper is on aiXiv. With an id, --publish sends a
# new version, and --changelog is required. The token is AIXIV_TOKEN; it is never printed.
#
# `build` runs in the paper shell (`nix develop`), `check` and `submit` in `nix develop .#aixiv`
# (nix/aixiv.nix: curl, jq); the script enters the shell it needs by itself.
set -euo pipefail
cd "$(dirname "$0")/.."

site="${AIXIV_SITE:-https://aixiv.online}"
# The manifest fields of the aixiv command line 0.4.1 (MANIFEST_FIELDS in
# https://aixiv.online/cli/aixiv.js), and "id". "source" and "pdf" are left out: build/ makes them.
fields='["id","title","authors","abstract","primary_category","categories","repo_url","ai_models","ai_contribution","process_summary","prompts_harness","verification_notes","negative_results","trace_url","comments","msc_class","license","anonymous"]'
# The six AI-use levels of skill.md, lightest first.
levels='["ai-proofread","ai-consulted","ai-assisted","ai-derived","ai-discovered","ai-authored"]'
# Long fields that may be "file:NAME" (relative to the paper's folder).
long_fields=(abstract process_summary prompts_harness verification_notes negative_results comments)

die() { echo "aixiv: $*" >&2; exit 1; }

enter() {
  local shell="$1"; shift
  [ -n "${AIXIV_IN_SHELL:-}" ] && return 0
  command -v nix > /dev/null || die "needs nix"
  exec env AIXIV_IN_SHELL=1 nix develop --extra-experimental-features 'nix-command flakes' \
    --no-update-lock-file "$shell" --command bash "$0" "$@"
}

# check_manifest <file>: print every fault of one aixiv.json; exit 1 if there is one.
check_manifest() {
  local m="$1" dir bad=0 f
  dir="$(dirname "$m")"
  jq -e 'type == "object"' "$m" > /dev/null 2>&1 || { echo "$m: not a JSON object"; return 1; }
  while read -r k; do echo "$m: unknown field \"$k\""; bad=1; done \
    < <(jq -r --argjson f "$fields" 'keys[] | select(. as $k | $f | index($k) | not)' "$m")
  jq -e '.primary_category | type == "string" and test("^[a-z-]+(\\.[A-Za-z-]+)?$")' "$m" > /dev/null \
    || { echo "$m: primary_category is required (a code such as math.ST)"; bad=1; }
  jq -e --argjson l "$levels" '.ai_contribution as $c | $l | index($c)' "$m" > /dev/null \
    || { echo "$m: ai_contribution must be one of $(jq -r 'join(" | ")' <<< "$levels")"; bad=1; }
  jq -e '.ai_models | type == "string" and length > 0' "$m" > /dev/null \
    || { echo "$m: ai_models is required (a short list of names)"; bad=1; }
  jq -e '(.id // "2601.00001") | type == "string" and test("^[0-9]{4}\\.[0-9]{4,5}$")' "$m" > /dev/null \
    || { echo "$m: id must be an aiXiv id such as 2611.01105"; bad=1; }
  jq -e '(.categories // []) | type == "array" and all(type == "string")' "$m" > /dev/null \
    || { echo "$m: categories must be a list of codes"; bad=1; }
  while read -r f; do
    [ -f "$dir/$f" ] || { echo "$m: file:$f does not exist"; bad=1; }
  done < <(jq -r '.[] | strings | select(startswith("file:")) | .[5:]' "$m")
  return "$bad"
}

cmd_check() {
  if [ "${1:-}" = "--self-test" ]; then
    local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
    mkdir -p "$d/ok" "$d/a" "$d/b" "$d/c" "$d/e"
    printf 'notes\n' > "$d/ok/notes.md"
    printf '{"primary_category":"math.ST","ai_contribution":"ai-assisted","ai_models":"Agda","process_summary":"file:notes.md"}' > "$d/ok/aixiv.json"
    printf '{"primary_category":"math.ST","ai_contribution":"human-led-ish","ai_models":"Agda"}' > "$d/a/aixiv.json"
    printf '{"primary_category":"math.ST","ai_contribution":"ai-assisted","ai_models":"Agda","source":"x.tex"}' > "$d/b/aixiv.json"
    printf '{"primary_category":"math.ST","ai_contribution":"ai-assisted","ai_models":"Agda","negative_results":"file:gone.md"}' > "$d/c/aixiv.json"
    printf '{"ai_contribution":"ai-assisted","ai_models":"Agda","id":"abs/1"}' > "$d/e/aixiv.json"
    check_manifest "$d/ok/aixiv.json" > /dev/null || die "self-test: a good manifest was refused"
    for x in a b c e; do
      ! check_manifest "$d/$x/aixiv.json" > /dev/null || die "self-test: bad manifest $x passed"
    done
    echo "aixiv: self-test ok: 1 good manifest passed, 4 bad ones refused"
    return 0
  fi
  local n=0 bad=0 m
  shopt -s nullglob
  for m in papers/*/aixiv.json; do
    n=$((n + 1))
    if check_manifest "$m"; then echo "aixiv: OK $m"; else bad=1; fi
  done
  [ "$bad" -eq 0 ] || die "a manifest is not valid"
  echo "aixiv: $n manifests OK"
}

cmd_build() {
  local slug="$1" out="build/aixiv/$1" t
  [ -f "papers/$slug/metadata.md" ] || die "no paper papers/$slug"
  just paper "$slug"
  mkdir -p "$out"
  cp "build/tex/$slug.tex" "$out/source.tex"
  cp "pdf/$slug.pdf" "$out/paper.pdf"
  # The metadata from metadata.md, so the record matches the PDF. The abstract stays Markdown with
  # TeX math ($...$), which the aiXiv page renders.
  t="$(mktemp -d)"
  # shellcheck disable=SC2016  # pandoc template variables, not shell ones
  {
    printf '%s\n' '$title$' > "$t/title"
    printf '%s\n' '$for(author)$$author.name$$sep$, $endfor$' > "$t/authors"
    printf '%s\n' '$abstract$' > "$t/abstract"
  }
  pandoc "papers/$slug/metadata.md" -t plain --wrap=none --template "$t/title" -o "$out/title.txt"
  pandoc "papers/$slug/metadata.md" -t plain --wrap=none --template "$t/authors" -o "$out/authors.txt"
  pandoc "papers/$slug/metadata.md" -t markdown --wrap=none --template "$t/abstract" -o "$out/abstract.md"
  rm -rf "$t"
  [ -s "$out/title.txt" ] && [ -s "$out/authors.txt" ] && [ -s "$out/abstract.md" ] \
    || die "papers/$slug/metadata.md needs a title, an author and an abstract"
  echo "aixiv: $out: $(cat "$out/title.txt") ($(cat "$out/authors.txt"))"
}

# value <field>: the manifest's value, with "file:" read from the paper's folder.
value() {
  local v
  v="$(jq -r --arg k "$1" '.[$k] // empty | if type == "array" then join(",") else tostring end' "$manifest")"
  if [[ "$v" == file:* ]]; then cat "$(dirname "$manifest")/${v#file:}"; else printf '%s' "$v"; fi
}

cmd_submit() {
  local slug="$1"; shift
  local publish=0 changelog=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --publish) publish=1 ;;
      --changelog) changelog="${2:-}"; shift ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  manifest="papers/$slug/aixiv.json"
  local out="build/aixiv/$slug"
  [ -f "$manifest" ] || die "no $manifest: write one (docs/aixiv.md)"
  check_manifest "$manifest" || die "$manifest is not valid"
  [ -f "$out/source.tex" ] && [ -f "$out/paper.pdf" ] || die "run scripts/aixiv.sh build $slug first"
  [ -n "${AIXIV_TOKEN:-}" ] || die "AIXIV_TOKEN is not set (a token from $site/settings)"

  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  # The token goes to curl through a file, so it is in no command line and no log.
  ( umask 077; printf 'Authorization: Bearer %s\n' "$AIXIV_TOKEN" > "$tmp/auth" )
  api() { curl -sS --retry 2 -H "@$tmp/auth" -o "$tmp/body" -w '%{http_code}' "$@"; }
  fail_on() {
    local code="$1" what="$2"
    if [ "${code:0:1}" != 2 ] || ! jq -e '.ok != false' "$tmp/body" > /dev/null 2>&1; then
      jq -r '.error.compile_log // empty' "$tmp/body" 2> /dev/null | tail -n 25 >&2 || true
      die "$what: HTTP $code: $(jq -r '(.error.code // "") + ": " + (.error.message // "")' "$tmp/body" 2> /dev/null || head -c 300 "$tmp/body")"
    fi
  }

  local code
  code="$(api "$site/api/v1/me")"; fail_on "$code" "preflight"
  jq -e '.can_submit == true' "$tmp/body" > /dev/null \
    || die "this account cannot submit yet: verify its email or GitHub at $site/settings"

  local repo_url id
  repo_url="$(value repo_url)"
  if [ -z "$repo_url" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
    repo_url="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY"
  fi
  id="$(value id)"

  # The fields of a submission. Short values with --form-string (no curl syntax inside them),
  # long ones from a file with "<".
  local form=(--form-string "title=$(cat "$out/title.txt")"
              --form-string "authors=$(cat "$out/authors.txt")"
              --form-string "primary_category=$(value primary_category)"
              -F "source=@$out/source.tex;filename=$slug.tex"
              -F "pdf=@$out/paper.pdf;filename=$slug.pdf;type=application/pdf")
  if [ -n "$(value abstract)" ]; then value abstract > "$tmp/abstract"; else cp "$out/abstract.md" "$tmp/abstract"; fi
  form+=(-F "abstract=<$tmp/abstract")
  local c
  while read -r c; do form+=(--form-string "categories=$c"); done \
    < <(jq -r '.categories // [] | .[]' "$manifest")
  for k in license msc_class; do
    [ -z "$(value "$k")" ] || form+=(--form-string "$k=$(value "$k")")
  done
  local notes=(--form-string "ai_models=$(value ai_models)"
               --form-string "ai_contribution=$(value ai_contribution)")
  [ -z "$repo_url" ] || notes+=(--form-string "repo_url=$repo_url")
  for k in trace_url anonymous; do
    [ -z "$(value "$k")" ] || notes+=(--form-string "$k=$(value "$k")")
  done
  for k in "${long_fields[@]}"; do
    [ "$k" = abstract ] && continue
    [ -n "$(value "$k")" ] || continue
    value "$k" > "$tmp/$k"
    notes+=(-F "$k=<$tmp/$k")
  done

  # Always a dry run first: aiXiv validates every field and nothing is stored.
  code="$(api -X POST "${form[@]}" "${notes[@]}" "$site/api/v1/submit?dry_run=1")"
  fail_on "$code" "dry run"
  echo "aixiv: dry run OK for papers/$slug"
  jq '{resolved, warnings, would_publish: (.would_publish // null)} | with_entries(select(.value != null))' \
    "$tmp/body" 2> /dev/null || true
  cp "$tmp/body" "$out/dry-run.json"

  if [ "$publish" -eq 0 ]; then
    echo "aixiv: nothing published (dry run). Publish with --publish."
    return 0
  fi

  if [ -n "$id" ]; then
    [ "${#changelog}" -ge 5 ] || die "papers/$slug is aiXiv:$id: a new version needs --changelog \"what changed\""
    code="$(api -X POST --form-string "changelog=$changelog" "${form[@]}" \
      "$site/api/v1/papers/$id/versions")"
    fail_on "$code" "new version of $id"
    cp "$tmp/body" "$out/published.json"
    echo "aixiv: published version $(jq -r '.version // "?"' "$tmp/body") of aiXiv:$id: $(jq -r '.abs_url // empty' "$tmp/body")"
    # The AI process notes are not part of the versioned record: they change in place.
    jq -n --rawfile ps <(value process_summary) --rawfile vn <(value verification_notes) \
      --rawfile nr <(value negative_results) --arg m "$(value ai_models)" \
      --arg c "$(value ai_contribution)" --arg r "$repo_url" \
      '{ai_models: $m, ai_contribution: $c, repo_url: $r, process_summary: $ps,
        verification_notes: $vn, negative_results: $nr} | with_entries(select(.value != ""))' \
      > "$tmp/patch.json"
    code="$(api -X PATCH -H 'Content-Type: application/json' --data-binary "@$tmp/patch.json" \
      "$site/api/v1/papers/$id")"
    fail_on "$code" "notes of $id"
    echo "aixiv: notes of aiXiv:$id: $(jq -c '.changed // .updated // "updated"' "$tmp/body")"
  else
    code="$(api -X POST "${form[@]}" "${notes[@]}" "$site/api/v1/submit")"
    fail_on "$code" "submit"
    cp "$tmp/body" "$out/published.json"
    id="$(jq -r '.aixiv_id' "$tmp/body")"
    echo "aixiv: published aiXiv:$id: $(jq -r '.abs_url // empty' "$tmp/body")"
    echo "aixiv: add \"id\": \"$id\" to $manifest in a pull request, so the next run makes a new version"
  fi
  jq '.priority_record // .record.priority_record // empty' "$tmp/body" 2> /dev/null || true
}

case "${1:-}" in
  check) enter .#aixiv "$@"; shift; cmd_check "$@" ;;
  build) [ -n "${2:-}" ] || die "usage: scripts/aixiv.sh build <slug>"; enter . "$@"; cmd_build "$2" ;;
  submit) [ -n "${2:-}" ] || die "usage: scripts/aixiv.sh submit <slug> [--publish [--changelog TEXT]]"
    enter .#aixiv "$@"; shift; cmd_submit "$@" ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
