#!/usr/bin/env bash
#
# Renders every fixture in testdata/ and compares the ANSI-stripped output
# with the matching .expected file. Color thresholds are checked separately.

set -o errexit -o nounset -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

readonly ESC=$'\033'
readonly RED_CODE='38;5;196m'
readonly AMBER_CODE='38;5;220m'

failures=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

expect_color() {
  local fixture=$1 code=$2 raw=$3
  if [[ "$raw" != *"${ESC}[${code}"* ]]; then
    fail "$fixture" "expected color code ${code} in second line"
  fi
}

expect_no_alert_colors() {
  local fixture=$1 raw=$2
  if [[ "$raw" == *"${ESC}[${RED_CODE}"* || "$raw" == *"${ESC}[${AMBER_CODE}"* ]]; then
    fail "$fixture" "expected neutral color"
  fi
}

for fixture in testdata/*.json; do
  name=$(basename "$fixture" .json)
  raw=$(./statusline.sh < "$fixture")
  plain=$(printf '%s' "$raw" | sed "s/${ESC}\[[0-9;]*m//g")
  expected=$(cat "testdata/${name}.expected")

  if [[ "$plain" != "$expected" ]]; then
    fail "$name" "output differs"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$plain") || true
  fi

  case "$name" in
    alert-*) expect_color "$name" "$RED_CODE" "$raw" ;;
    warn) expect_color "$name" "$AMBER_CODE" "$raw" ;;
    *) expect_no_alert_colors "$name" "$raw" ;;
  esac
done

if ((failures > 0)); then
  printf '%d test(s) failed\n' "$failures"
  exit 1
fi
printf 'all fixtures passed\n'
