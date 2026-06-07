#!/bin/bash
bars=12
blocks="▁▂▃▄▅▆▇█"

dict="s/;//g"
i=0
while [ "$i" -lt 8 ]; do
    dict="$dict;s/$i/${blocks:$i:1}/g"
    i=$((i + 1))
done

cfg=$(mktemp)
trap 'rm -f "$cfg"' EXIT
cat > "$cfg" <<EOF
[general]
bars = $bars
framerate = 30
sensitivity = 100
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

cava -p "$cfg" | while IFS= read -r line; do
    case "$line" in
        *[!0\;]*) printf '%s\n' "$(printf '%s' "$line" | sed "$dict")" ;;
        *) printf '\n' ;;
    esac
done
