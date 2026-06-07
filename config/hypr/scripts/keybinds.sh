#!/usr/bin/env bash
# Themed keybind cheatsheet (rofi, matugen colors)

conf="${HOME}/.config/hypr/conf/keybinding.conf"
rofi_conf="${HOME}/.config/rofi/config-keybinds.rasi"

awk '
function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
/^[[:space:]]*#/ {
    h=$0; sub(/^[[:space:]]*#[[:space:]]*/,"",h); h=trim(h)
    if (h!="" && h !~ /KEY$/) printf "<b>  %s</b>\n", h
    next
}
/^[[:space:]]*bind/ {
    line=$0; sub(/^[^=]*=[[:space:]]*/,"",line)
    n=split(line,a,",")
    mods=trim(a[1]); key=trim(a[2]); gsub(/\$mainMod/,"SUPER",mods)
    act=""; for(i=3;i<=n;i++) act=act (i>3?",":"") a[i]; act=trim(act)
    sub(/^exec,[[:space:]]*/,"",act)
    gsub(/.*scripts\//,"",act); gsub(/.*waybar\//,"",act)
    if      (act ~ /screenshot_claude/)   act="Screenshot → Claude"
    else if (act ~ /screenshot\.sh area/) act="Screenshot (area)"
    else if (act ~ /screenshot\.sh/)      act="Screenshot"
    else if (act ~ /wallpaper\.sh scheme/) act="Recolor theme from wallpaper"
    else if (act ~ /wallpaper\.sh select/) act="Pick wallpaper"
    else if (act ~ /launch\.sh/)          act="Restart waybar"
    else if (act ~ /cliphist\.sh/)        act="Clipboard history"
    else if (act ~ /keybinds\.sh/)        act="Show this cheatsheet"
    else if (act ~ /settings\.sh/)        act="Settings"
    else if (act ~ /\$TERMINAL/)          act="Terminal"
    else if (act ~ /\$BROWSER/)           act="Browser"
    else if (act ~ /\$FILEMANAGER/)       act="File manager"
    else if (act ~ /^wlogout/)            act="Logout menu"
    else if (act ~ /listen-on.*claude/)   act="Claude in kitty"
    else if (act ~ /^rofi -show drun/)    act="App launcher"
    else if (act ~ /^rofi -show window/)  act="Window switcher"
    keys=(mods!=""? mods" + "key : key)
    printf "<b>%-26s</b>  %s\n", keys, act
}' "$conf" | rofi -dmenu -i -markup-rows -p "  Keybinds" -config "$rofi_conf" >/dev/null
