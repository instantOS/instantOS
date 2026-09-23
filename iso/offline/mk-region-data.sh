#!/usr/bin/env bash
# Snapshot archlinux.org mirror-region data into an offline ISO bundle.
#
# Output layout (consumed verbatim by instantCLI's src/arch/mirrors.rs):
#   <dir>/regions.html            raw https://archlinux.org/mirrorlist/ page
#                                 (parsed into name -> country-code)
#   <dir>/mirrorlists/<CODE>.txt  per-country mirrorlists: active HTTPS IPv4
#                                 mirrors, best status-API score first
#
# Two requests total: the per-country endpoint rate-limits (HTTP 429), the
# mirror status API does not. regions.html stays a verbatim response — the
# runtime parses it with the same parser as the live page — while the
# per-country files are composed from the status API in the endpoint's
# output format; the runtime only uncomments and checks them either way.
#
# Requires: curl, jq (pacman -S jq).
set -euo pipefail

out="${1:?usage: mk-region-data.sh <output-dir>}"

command -v jq >/dev/null || {
    echo "error: jq is required (pacman -S jq)" >&2
    exit 1
}

rm -rf "$out/mirrorlists"
mkdir -p "$out/mirrorlists"

curl -fsSL --retry 3 --max-time 60 \
    "https://archlinux.org/mirrorlist/" \
    -o "$out/regions.html"
curl -fsSL --retry 3 --max-time 120 \
    "https://archlinux.org/mirrors/status/json/" \
    -o "$out/mirror-status.json"

# Codes the runtime can look up, using the runtime parser's exact rules:
# <option value="CODE">NAME</option> (extra attributes allowed), skipping
# empty values and the "All" pseudo-entry.
mapfile -t codes < <(
    sed -n 's/^[[:space:]]*<option value="\([^"]*\)"[^>]*>\([^<]*\)<\/option>[[:space:]]*$/\1\t\2/p' \
        "$out/regions.html" |
        awk -F'\t' '$1 != "" && $2 != "All" { print $1 }' |
        sort -u
)
((${#codes[@]} > 0)) || {
    echo "error: no region codes parsed from $out/regions.html" >&2
    exit 1
}

# Records of: a CODE line, its Server lines, a blank separator line. Offline
# installs skip latency probing, so status-score order is all the target gets.
header='## Arch Linux repository mirrorlist
## Generated for the instantOS offline bundle

'
file=""
jq -r '
    [.urls[]
        | select(.protocol == "https" and .active and .ipv4 and .country_code != "")
        | {code: .country_code,
           score: (if .score == null then 1e9 else .score end),
           url: (.url + (if (.url | endswith("/")) then "" else "/" end))}]
    | group_by(.code)
    | .[]
    | sort_by(.score)
    | "\(.[0].code)\n\(map("Server = \(.url)$repo/os/$arch") | join("\n"))\n"
' "$out/mirror-status.json" |
    while IFS= read -r line; do
        if [[ "$line" == "Server = "* ]]; then
            printf '%s\n' "$line" >>"$file"
        elif [[ -n "$line" ]]; then
            file="$out/mirrorlists/$line.txt"
            printf '%s' "$header" >"$file"
        fi
    done

missing=0
for code in "${codes[@]}"; do
    f="$out/mirrorlists/$code.txt"
    if [[ ! -f "$f" ]] || ! grep -q "Server =" "$f"; then
        echo "warning: region $code has no active HTTPS IPv4 mirrors; the installer falls back for it" >&2
        missing=$((missing + 1))
    fi
done

rm -f "$out/mirror-status.json"
echo "Snapshotted ${#codes[@]} regions into $out ($missing without active mirrors)"
