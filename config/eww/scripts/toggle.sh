#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
pgrep -x eww >/dev/null || { eww daemon; sleep 0.4; }
if eww active-windows 2>/dev/null | grep -q '^music'; then
    eww update winopen=false
    eww close music backdrop
    hyprctl keyword unbind ,ESCAPE
else
    eww update winopen=true
    eww open backdrop
    eww open music
    hyprctl keyword bind ,ESCAPE,exec,~/.config/eww/scripts/close.sh
fi
