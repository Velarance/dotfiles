#!/bin/bash
status=$(playerctl status 2>/dev/null)
case "$status" in
    Playing) icon=$(printf '') ;;
    Paused)  icon=$(printf '') ;;
    *) exit 0 ;;
esac

title=$(playerctl metadata --format '{{title}}' 2>/dev/null)
[ -z "$title" ] && exit 0
artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null)

line="$title"
[ -n "$artist" ] && line="$artist - $title"
if [ "${#line}" -gt 45 ]; then line="${line:0:44}$(printf '…')"; fi

echo "$icon  $line"
