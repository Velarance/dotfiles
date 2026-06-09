#!/bin/bash
ROFI_CFG="$HOME/.config/rofi/config-wifi.rasi"

state=$(nmcli -g WIFI radio wifi)

if [ "$state" = "enabled" ]; then
    toggle="󰖪  Disable Wi-Fi"
    list=$(nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list | awk -F: '
        $4=="" { next }
        !seen[$4]++ {
            sig=$2+0
            icon=(sig>=75)?"󰤨":(sig>=50)?"󰤥":(sig>=25)?"󰤢":"󰤟"
            if ($1=="*") icon="󰸞"
            print icon " " $4
        }')
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

ssid="${chosen#* }"
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
