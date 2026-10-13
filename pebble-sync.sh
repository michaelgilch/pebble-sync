#!/usr/bin/env bash
# Pull notes added since the last run from the Worker and append them to a local file.
# Settings come from ~/.config/pebble-sync/config (created by install.sh).
# PEBBLE_TOKEN comes from the environment so the config holds no secrets.
set -euo pipefail

config=${XDG_CONFIG_HOME:-$HOME/.config}/pebble-sync/config
if [[ ! -r $config ]]; then
  echo "missing config: $config (run install.sh)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$config"

url=${PEBBLE_URL:?set PEBBLE_URL in $config}
token=${PEBBLE_TOKEN:?export PEBBLE_TOKEN in your environment}
notes_file=${NOTES_FILE:?set NOTES_FILE in $config}
state=${XDG_STATE_HOME:-$HOME/.local/state}/pebble-sync-last-id

mkdir -p "$(dirname "$state")" "$(dirname "$notes_file")"
last=$(cat "$state" 2>/dev/null || echo 0)

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

curl -fsS -H "Authorization: Bearer $token" "${url%/}/notes?after=$last" > "$tmp"

count=0
while IFS=$'\t' read -r id ms text; do
  printf '[%s] %s\n' "$(date -d "@$((ms / 1000))" '+%Y-%m-%d %H:%M')" "$text" >> "$notes_file"
  # Saved per note so an interrupted run never duplicates or skips.
  echo "$id" > "$state"
  count=$((count + 1))
done < "$tmp"

echo "pulled $count new notes"
