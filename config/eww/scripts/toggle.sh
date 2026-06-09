#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
exec 9>"$HOME/.cache/eww-music.lock"
flock -n 9 || exit 0

pgrep -x eww >/dev/null || { eww daemon >/dev/null 2>&1 & sleep 0.6; }

if [ "$(eww get winopen 2>/dev/null)" = "true" ]; then
    eww update winopen=false
    eww close music backdrop 2>/dev/null
    hyprctl keyword unbind ,ESCAPE
else
    eww close music backdrop 2>/dev/null
    eww update winopen=true
    eww open-many music backdrop
    hyprctl keyword bind ,ESCAPE,exec,~/.config/eww/scripts/close.sh
fi
