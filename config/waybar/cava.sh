#!/bin/bash
bars=12
blocks="▁▂▃▄▅▆▇█"

dict="s/;//g"
i=0
while [ "$i" -lt 8 ]; do
    dict="$dict;s/$i/${blocks:$i:1}/g"
    i=$((i + 1))
done

silence=$(printf '▁%.0s' $(seq 1 "$bars"))

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
    out=$(printf '%s' "$line" | sed "$dict")
    if [ "$out" = "$silence" ]; then
        printf '\n'
    else
        printf '%s\n' "$out"
    fi
done
