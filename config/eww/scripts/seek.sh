#!/bin/bash
st=$(date +%s%N)
echo "$st" > "$HOME/.cache/eww-seek-stamp"
echo "$1" > "$HOME/.cache/eww-seek-val"
(
    sleep 0.25
    [ "$(cat "$HOME/.cache/eww-seek-stamp" 2>/dev/null)" = "$st" ] || exit 0
    playerctl position "$(cat "$HOME/.cache/eww-seek-val" 2>/dev/null)" 2>/dev/null
) &
