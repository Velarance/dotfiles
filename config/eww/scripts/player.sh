#!/bin/bash
cover="$HOME/.cache/eww-cover"

status=$(playerctl status 2>/dev/null)
if [ -z "$status" ]; then
    jq -nc '{status:"Stopped",title:"Nothing playing",artist:"",source:"",art:"",posstr:"00:00",lenstr:"00:00",pos:0,len:1,playicon:"▶"}'
    exit 0
fi

title=$(playerctl metadata title 2>/dev/null)
artist=$(playerctl metadata artist 2>/dev/null)
source=$(playerctl metadata --format '{{playerName}}' 2>/dev/null)
arturl=$(playerctl metadata mpris:artUrl 2>/dev/null)
len_us=$(playerctl metadata mpris:length 2>/dev/null)
pos=$(playerctl position 2>/dev/null | cut -d. -f1)
len_us=${len_us:-0}; pos=${pos:-0}
len=$(( len_us / 1000000 ))
[ "$len" -lt 1 ] && len=1

fmt() { printf '%02d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }

case "$arturl" in
    file://*) cp -f "${arturl#file://}" "$cover" 2>/dev/null ;;
    http*)
        h=$(printf '%s' "$arturl" | md5sum | cut -d' ' -f1)
        cached="$HOME/.cache/eww-cover-$h"
        [ -f "$cached" ] || curl -sL --max-time 5 "$arturl" -o "$cached" 2>/dev/null
        cp -f "$cached" "$cover" 2>/dev/null
        ;;
esac
[ -f "$cover" ] || cover=""

if [ "$status" = "Playing" ]; then playicon=$(printf '⏸'); else playicon=$(printf '▶'); fi

jq -nc --arg s "$status" --arg t "${title:-Unknown}" --arg a "${artist:-}" \
    --arg src "${source:-}" --arg art "$cover" --arg ps "$(fmt "$pos")" \
    --arg ls "$(fmt "$len")" --argjson pos "$pos" --argjson len "$len" \
    --arg pi "$playicon" \
    '{status:$s,title:$t,artist:$a,source:$src,art:$art,posstr:$ps,lenstr:$ls,pos:$pos,len:$len,playicon:$pi}'
