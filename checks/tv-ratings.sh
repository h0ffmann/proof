#!/usr/bin/env bash
# The TV ratings pipeline's parsers (tools/tv-ratings/) on pages written for the test: numbers,
# dates, rowspans, footnotes, the Nielsen lists and a Wikipedia table, and broken pages that must
# fail. It does not fetch: the public pages change, and a check must give the same verdict
# offline. `tools/tv-ratings/run.sh` fetches and parses the real pages.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/tv-ratings/run.sh --self-test
