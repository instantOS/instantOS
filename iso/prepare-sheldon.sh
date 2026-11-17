#!/usr/bin/env bash
# Fetch the pinned live-shell plugins outside mkarchiso's network-free chroot.
set -euo pipefail

dotfiles="$(realpath "$1")"
plugin_data="$(realpath -m "$2")"
config_dir="$dotfiles/dots/.config/sheldon"
[[ -s "$config_dir/plugins.toml" ]] || {
    echo "dotfiles are missing the live Sheldon configuration" >&2
    exit 1
}
mkdir -p "$plugin_data"
sheldon --non-interactive --config-dir "$config_dir" --data-dir "$plugin_data" lock

# Sheldon locks contain absolute paths. Relocate those to the live user's
# home so `sheldon source` can use them without re-resolving or downloading.
python3 - "$plugin_data/plugins.lock" "$config_dir" "$plugin_data" <<'PY'
import json
from pathlib import Path
import sys

lock, config, data = sys.argv[1:]
p = Path(lock)
s = p.read_text()
for old, new in [(config, '/home/instantos/.config/sheldon'),
                 (data, '/home/instantos/.local/share/sheldon')]:
    s = s.replace(old, new)
s = s.replace('home = ' + json.dumps(str(Path.home())),
              'home = "/home/instantos"', 1)
p.write_text(s)
PY
