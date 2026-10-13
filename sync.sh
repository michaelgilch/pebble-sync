#!/usr/bin/env bash
# Pull notes added since the last run from the Worker and append them to a local file.
#   PEBBLE_URL    Worker URL, e.g. https://pebble-notes.you.workers.dev (required)
#   PEBBLE_TOKEN  same secret given to `wrangler secret put AUTH_TOKEN` (required)
#   NOTES_FILE    local output (default ~/notes.txt)
set -euo pipefail

url=${PEBBLE_URL:?set PEBBLE_URL to your Worker URL}
token=${PEBBLE_TOKEN:?set PEBBLE_TOKEN to your auth token}
notes_file=${NOTES_FILE:-$HOME/notes.txt}
state=${XDG_STATE_HOME:-$HOME/.local/state}/pebble-sync-last-id

mkdir -p "$(dirname "$state")"
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
