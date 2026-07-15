#!/bin/bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROFI_CFG="$HOME/.config/rofi/config-workspaces.rasi"

source "${SCRIPT_DIR}/lib/modal-menu.sh"
modal_menu_enter
trap modal_menu_release EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

read -r mid mname < <(hyprctl monitors -j | jq -r '.[] | select(.focused==true) | "\(.id) \(.name)"')

all=$(hyprctl workspaces -j | jq -r --argjson m "$mid" '.[] | select(.monitorID==$m and .id > 0) | .id' | sort -un)
[ -z "$all" ] && all=$(seq 1 10)

sel=$(printf '%s\n' "$all" | rofi -dmenu -replace -p "$mname" -monitor "$mname" -config "$ROFI_CFG")
[ -n "$sel" ] && hyprctl dispatch workspace "$sel"
