#!/usr/bin/env bash
#
# Registers statusline.sh as the Claude Code status line in
# ~/.claude/settings.json. Backs up the settings file first.
#
# Runs on macOS and Linux; needs jq.

set -o errexit -o nounset -o pipefail

readonly SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
readonly REFRESH_INTERVAL_SECONDS=60

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly RENDER_COMMAND="$script_dir/statusline.sh"

assume_yes=false
case "${1:-}" in
  --yes) assume_yes=true ;;
  --help)
    printf 'Usage: %s [--yes]\n\nWrites the statusLine block to %s.\n' "$(basename "$0")" "$SETTINGS_FILE"
    exit 0
    ;;
  '') ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
esac

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

existing=""
if [[ -f "$SETTINGS_FILE" ]]; then
  if ! existing=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE"); then
    printf '%s is not valid JSON, fix it before installing.\n' "$SETTINGS_FILE" >&2
    exit 1
  fi
fi

printf 'Setting statusLine in %s to:\n  %s\n' "$SETTINGS_FILE" "$RENDER_COMMAND"
if [[ -n "$existing" ]]; then
  printf 'Replacing existing command:\n  %s\n' "$existing"
fi

if [[ "$assume_yes" != true ]]; then
  printf 'Continue? [y/N] '
  read -r reply
  case "$reply" in
    y | Y | yes) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

mkdir -p "$(dirname "$SETTINGS_FILE")"
if [[ -f "$SETTINGS_FILE" ]]; then
  backup="$SETTINGS_FILE.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS_FILE" "$backup"
  printf 'Backup written to %s\n' "$backup"
else
  printf '{}\n' > "$SETTINGS_FILE"
fi

tmp=$(mktemp)
jq --arg cmd "$RENDER_COMMAND" --argjson interval "$REFRESH_INTERVAL_SECONDS" \
  '.statusLine = {type: "command", command: $cmd, refreshInterval: $interval}' \
  "$SETTINGS_FILE" > "$tmp"
mv "$tmp" "$SETTINGS_FILE"
printf 'Installed. The status line appears in the next Claude Code session.\n'
