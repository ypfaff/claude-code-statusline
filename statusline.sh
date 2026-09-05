#!/usr/bin/env bash
#
# Claude Code status line renderer. Reads the session JSON from stdin and
# prints two lines: model, thinking effort, project directory; then a context
# window bar with token usage and session duration.
#
# Runs on macOS and Linux; needs bash, jq and awk.

set -o errexit -o nounset -o pipefail

readonly BAR_WIDTH=20
readonly MAX_DIR_LENGTH=50
readonly WARN_PERCENT=60
readonly WARN_TOKENS=150000
readonly ALERT_PERCENT=80
readonly ALERT_TOKENS=200000

readonly DIM=$'\033[38;5;245m'
readonly BOLD=$'\033[1m'
readonly AMBER=$'\033[38;5;220m'
readonly RED=$'\033[38;5;196m'
readonly RESET=$'\033[0m'
readonly SEP=" ${DIM}·${RESET} "

# 8200 -> 8.2k, 48000 -> 48k, 1000000 -> 1M
format_tokens() {
  LC_NUMERIC=C awk -v t="$1" 'BEGIN {
    if (t >= 1000000) { v = t / 1000000; unit = "M" }
    else if (t >= 1000) { v = t / 1000; unit = "k" }
    else { printf "%d", t; exit }
    if (v == int(v) || v >= 10) printf "%d%s", v, unit
    else printf "%.1f%s", v, unit
  }'
}

# Minutes are the finest unit so the line does not flicker every second.
format_duration() {
  local minutes=$(($1 / 60000))
  if ((minutes < 60)); then
    printf '%dm' "$minutes"
  elif ((minutes < 1440)); then
    printf '%dh %dm' $((minutes / 60)) $((minutes % 60))
  else
    printf '%dd %dh' $((minutes / 1440)) $((minutes % 1440 / 60))
  fi
}

shorten_dir() {
  local dir="${1/#"$HOME"/\~}"
  if ((${#dir} > MAX_DIR_LENGTH)); then
    local parent
    parent=$(basename "$(dirname "$dir")")
    dir="$parent/$(basename "$dir")"
  fi
  printf '%s' "$dir"
}

render_bar() {
  local filled=$(($1 * BAR_WIDTH / 100))
  ((filled > BAR_WIDTH)) && filled=$BAR_WIDTH
  local bar=""
  local i
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if ((i < filled)); then bar+="▓"; else bar+="░"; fi
  done
  printf '%s' "$bar"
}

main() {
  local model thinking effort project_dir tokens window_size duration_ms
  # Unit separator instead of tab: read collapses consecutive whitespace,
  # which would shift fields when effort is absent.
  IFS=$'\x1f' read -r model thinking effort project_dir tokens window_size duration_ms < <(
    jq -r '[
      (.model.display_name // "Claude"),
      (.thinking.enabled // false),
      (.effort.level // ""),
      (.workspace.project_dir // .cwd // ""),
      (.context_window.current_usage
        | if . == null then -1
          else (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
          end),
      (.context_window.context_window_size // 200000),
      (.cost.total_duration_ms // 0)
    ] | map(tostring) | join("\u001f")'
  )

  local line1="${BOLD}${model}${RESET}"
  if [[ "$thinking" == "true" ]]; then
    line1+="${SEP}◆ ${effort:-think}"
  fi
  line1+="${SEP}${DIM}$(shorten_dir "$project_dir")${RESET}"

  local percent=0 color="" usage="–"
  if ((tokens >= 0)); then
    percent=$((tokens * 100 / window_size))
    usage=$(format_tokens "$tokens")
    if ((percent >= ALERT_PERCENT || tokens >= ALERT_TOKENS)); then
      color=$RED
    elif ((percent >= WARN_PERCENT || tokens >= WARN_TOKENS)); then
      color=$AMBER
    fi
  fi

  local bar line2
  bar=$(render_bar "$percent")
  line2="${color}${bar} ${usage}/$(format_tokens "$window_size")${RESET}"
  line2+="${SEP}${DIM}$(format_duration "$duration_ms")${RESET}"

  printf '%s\n%s\n' "$line1" "$line2"
}

main
