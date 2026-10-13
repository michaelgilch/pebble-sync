#!/usr/bin/env bash
# Symlink pebble-sync.sh into ~/.local/bin and create the config file if it doesn't exist.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
bin_dir=$HOME/.local/bin
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/pebble-sync

mkdir -p "$bin_dir" "$config_dir"

ln -sf "$repo/pebble-sync.sh" "$bin_dir/pebble-sync.sh"
echo "linked $bin_dir/pebble-sync.sh"

if [[ -e $config_dir/config ]]; then
  echo "kept existing $config_dir/config"
else
  cp "$repo/config.example" "$config_dir/config"
  echo "created $config_dir/config: fill in PEBBLE_URL"
fi

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "note: $bin_dir is not on your PATH" ;;
esac
