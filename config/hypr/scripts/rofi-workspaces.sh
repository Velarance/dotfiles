#!/bin/bash
ROFI_CFG="$HOME/.config/rofi/config-workspaces.rasi"

mons=$(hyprctl monitors -j)
mid=$(printf '%s' "$mons" | jq -r '.[] | select(.focused==true) | .id')
mname=$(printf '%s' "$mons" | jq -r '.[] | select(.focused==true) | .name')

ws=$(hyprctl workspaces -j | jq -r --argjson m "$mid" '.[] | select(.monitorID==$m) | .id')
wsw=$(hyprctl clients -j | jq -r --argjson m "$mid" '.[] | select(.monitor==$m) | .workspace.id')

all=$(printf '%s\n%s\n' "$ws" "$wsw" | grep -E '^[0-9]+$' | sort -un)
[ -z "$all" ] && all=$(seq 1 10)

eww open wsdim --screen "$mid" 2>/dev/null
sel=$(printf '%s\n' "$all" | rofi -dmenu -p "$mname" -monitor "$mname" -config "$ROFI_CFG")
eww close wsdim 2>/dev/null
[ -n "$sel" ] && hyprctl dispatch workspace "$sel"
