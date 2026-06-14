#!/bin/bash
ROFI_CFG="$HOME/.config/rofi/config-workspaces.rasi"

read -r mid mname < <(hyprctl monitors -j | jq -r '.[] | select(.focused==true) | "\(.id) \(.name)"')

eww open wsdim --screen "$mid" 2>/dev/null &

all=$(hyprctl workspaces -j | jq -r --argjson m "$mid" '.[] | select(.monitorID==$m) | .id' | sort -un)
[ -z "$all" ] && all=$(seq 1 10)

sel=$(printf '%s\n' "$all" | rofi -dmenu -p "$mname" -monitor "$mname" -config "$ROFI_CFG")
eww close wsdim 2>/dev/null
[ -n "$sel" ] && hyprctl dispatch workspace "$sel"
