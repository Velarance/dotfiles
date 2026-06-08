#!/bin/bash
ROFI_CFG="$HOME/.config/rofi/config-workspaces.rasi"

entries() {
    local focused ws_json
    focused=$(hyprctl activeworkspace -j | jq -r '.id')
    ws_json=$(hyprctl workspaces -j)
    while IFS=$'\t' read -r mid mname; do
        printf '%s\x00nonselectable\x1ftrue\x1furgent\x1ftrue\n' "󰍹  $mname"
        printf '%s\n' "$ws_json" | jq -r --argjson mid "$mid" \
            'map(select(.monitorID==$mid and .id>0)) | sort_by(.id)[] | "\(.id)\t\(.windows)"' \
        | while IFS=$'\t' read -r wid wins; do
            local mk=" "; [ "$wid" = "$focused" ] && mk="●"
            local wc=""; [ "${wins:-0}" -gt 0 ] && wc="·$wins"
            printf '   %s  %-3s  %s\n' "$mk" "$wid" "$wc"
        done
    done < <(hyprctl monitors -j | jq -r 'sort_by(.id)[] | "\(.id)\t\(.name)"')
}

[ "$1" = "print" ] && { entries | tr '\000' '@'; exit 0; }

sel=$(entries | rofi -dmenu -config "$ROFI_CFG" -no-custom -p "Workspaces")
[ -z "$sel" ] && exit 0
wid=$(printf '%s' "$sel" | grep -oE '[0-9]+' | head -1)
[ -n "$wid" ] && hyprctl dispatch workspace "$wid"
