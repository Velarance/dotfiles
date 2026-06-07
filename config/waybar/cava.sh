#!/bin/bash
export LC_ALL=C.UTF-8
bars=12
blocks="▁▂▃▄▅▆▇█"
grace=90

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

silent=0
cava -p "$cfg" | while IFS= read -r line; do
    out=$(printf '%s' "$line" | sed "$dict")
    case "$line" in
        *[!0\;]*)
            silent=0
            printf '%s\n' "$out"
            ;;
        *)
            silent=$((silent + 1))
            if [ "$silent" -lt "$grace" ]; then
                printf '%s\n' "$out"
            else
                printf '\n'
            fi
            ;;
    esac
done
