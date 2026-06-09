#!/bin/bash
ROFI_CFG="$HOME/.config/rofi/config-wifi.rasi"

mid=$(hyprctl monitors -j | jq -r '.[] | select(.focused==true) | .id')
eww open rofibd --screen "${mid:-0}" 2>/dev/null
trap 'eww close rofibd 2>/dev/null' EXIT

state=$(nmcli -g WIFI radio wifi)

if [ "$state" = "enabled" ]; then
    toggle="󰖪  Disable Wi-Fi"
    list=$(nmcli -t -f SIGNAL,SSID device wifi list | sort -t: -k1 -rn | awk -F: '
        $2 && !seen[$2]++ { print "󰖩  " $2 }')
    menu=$(printf '%s\n%s' "$toggle" "$list")
else
    menu="󰖩  Enable Wi-Fi"
fi

chosen=$(printf '%s\n' "$menu" | rofi -dmenu -i -p "Wi-Fi" -config "$ROFI_CFG")
[ -z "$chosen" ] && exit 0

case "$chosen" in
    "󰖪  Disable Wi-Fi") nmcli radio wifi off; notify-send -a Wi-Fi "Wi-Fi disabled"; exit 0 ;;
    "󰖩  Enable Wi-Fi")  nmcli radio wifi on;  notify-send -a Wi-Fi "Wi-Fi enabled";  exit 0 ;;
esac

ssid=$(printf '%s' "$chosen" | sed 's/^[^ ]*  *//')
[ -z "$ssid" ] && exit 0

if nmcli -t -g NAME connection show | grep -qxF "$ssid"; then
    nmcli connection up id "$ssid" >/dev/null 2>&1 \
        && notify-send -a Wi-Fi "Connected" "$ssid" \
        || notify-send -a Wi-Fi "Failed to connect" "$ssid"
    exit 0
fi

secured=$(nmcli -t -f SSID,SECURITY device wifi list | awk -F: -v s="$ssid" '$1==s {print $2; exit}')

if [ -n "$secured" ]; then
    pass=$(printf '' | rofi -dmenu -password -p "Password: $ssid" -config "$ROFI_CFG")
    [ -z "$pass" ] && exit 0
    nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1
else
    nmcli device wifi connect "$ssid" >/dev/null 2>&1
fi

if nmcli -t -f IN-USE,SSID device wifi list | grep -q "^\*:$ssid$"; then
    notify-send -a Wi-Fi "Connected" "$ssid"
else
    notify-send -a Wi-Fi "Failed to connect" "$ssid"
fi
