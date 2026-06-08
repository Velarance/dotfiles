#!/bin/bash
cover="$HOME/.cache/eww-cover"
D=$'\x1f'

wallblur=""
cw=$(cat "$HOME/.cache/current_wallpaper" 2>/dev/null)
if [ -n "$cw" ] && [ -f "$cw" ]; then
    wh=$(md5sum "$cw" | cut -d' ' -f1)
    wallblur="$HOME/.cache/eww-wallblur-$wh.png"
    if [ ! -f "$wallblur" ]; then
        magick "$cw" -resize 560x560^ -gravity center -extent 560x560 \
            -blur 0x22 -brightness-contrast -25x-10 "$wallblur" 2>/dev/null
        find "$HOME/.cache" -maxdepth 1 -name 'eww-wallblur-*.png' ! -name "eww-wallblur-$wh.png" -delete 2>/dev/null
    fi
    [ -f "$wallblur" ] || wallblur=""
fi

data=$(playerctl metadata --format "{{status}}${D}{{title}}${D}{{artist}}${D}{{playerName}}${D}{{mpris:artUrl}}${D}{{mpris:length}}" 2>/dev/null)
if [ -z "$data" ]; then
    jq -nc --arg blur "$wallblur" '{status:"Stopped",title:"Nothing playing",artist:"",source:"",art:"",blur:$blur,posstr:"00:00",lenstr:"00:00",pos:0,len:1,playicon:"▶"}'
    exit 0
fi

IFS="$D" read -r status title artist source arturl len_us <<< "$data"
pos=$(playerctl position 2>/dev/null | cut -d. -f1)
len_us=${len_us:-0}; pos=${pos:-0}
[[ "$len_us" =~ ^[0-9]+$ ]] || len_us=0

lc="$HOME/.cache/eww-len-$(printf '%s' "$title" | md5sum | cut -d' ' -f1)"
if [ "$len_us" -gt 0 ]; then echo "$len_us" > "$lc"; elif [ -f "$lc" ]; then len_us=$(cat "$lc"); fi

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

blur=""
if [ -n "$cover" ]; then
    bh=$(printf '%s' "$arturl" | md5sum | cut -d' ' -f1)
    blur="$HOME/.cache/eww-blur-$bh.png"
    [ -f "$blur" ] || magick "$cover" -resize 540x540^ -gravity center -extent 540x540 \
        -blur 0x18 -brightness-contrast -28x-10 "$blur" 2>/dev/null
    [ -f "$blur" ] || blur=""
fi
[ -n "$blur" ] || blur="$wallblur"

if [ "$status" = "Playing" ]; then playicon=$(printf '⏸'); else playicon=$(printf '▶'); fi

jq -nc --arg s "$status" --arg t "${title:-Unknown}" --arg a "${artist:-}" \
    --arg src "${source:-}" --arg art "$cover" --arg blur "$blur" --arg ps "$(fmt "$pos")" \
    --arg ls "$(fmt "$len")" --argjson pos "$pos" --argjson len "$len" \
    --arg pi "$playicon" \
    '{status:$s,title:$t,artist:$a,source:$src,art:$art,blur:$blur,posstr:$ps,lenstr:$ls,pos:$pos,len:$len,playicon:$pi}'
