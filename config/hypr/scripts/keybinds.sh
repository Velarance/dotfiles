#!/usr/bin/env bash
# Keybind cheatsheet — 2-column themed panel in a floating kitty window

conf="${HOME}/.config/hypr/conf/keybinding.conf"

clear
printf '\n   \033[1;35m  Keybinds\033[0m\n\n'

awk -v W=42 '
function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
function lbl(a,   num){
    if(a=="movefocus, l")return"Focus ←"; if(a=="movefocus, r")return"Focus →"
    if(a=="movefocus, u")return"Focus ↑"; if(a=="movefocus, d")return"Focus ↓"
    if(a=="movewindow, l")return"Move window ←"; if(a=="movewindow, r")return"Move window →"
    if(a=="movewindow, u")return"Move window ↑"; if(a=="movewindow, d")return"Move window ↓"
    if(a=="movewindow")return"Move (drag)"; if(a=="resizewindow")return"Resize (drag)"
    if(a=="resizeactive, 100 0")return"Resize →"; if(a=="resizeactive, -100 0")return"Resize ←"
    if(a=="resizeactive, 0 -100")return"Resize ↑"; if(a=="resizeactive, 0 100")return"Resize ↓"
    if(a=="focusmonitor, l")return"Focus monitor ←"; if(a=="focusmonitor, r")return"Focus monitor →"
    if(a=="movewindow, mon:-1")return"→ monitor ←"; if(a=="movewindow, mon:+1")return"→ monitor →"
    if(a=="killactive")return"Close window"; if(a=="togglefloating")return"Toggle floating"
    if(a=="layoutmsg, togglesplit")return"Toggle split"; if(a=="fullscreen, 0")return"Fullscreen"
    if(a=="togglespecialworkspace, dropdown")return"Dropdown terminal"
    if(a=="movetoworkspace, special:dropdown")return"→ dropdown"
    if(a=="togglespecialworkspace, magic")return"Scratchpad"
    if(a=="movetoworkspace, special:magic")return"→ scratchpad"
    if(a~/^workspace, [0-9]/){num=a; sub(/^workspace, /,"",num); return"Workspace "num}
    if(a~/^movetoworkspace, [0-9]/){num=a; sub(/^movetoworkspace, /,"",num); return"→ workspace "num}
    if(a=="workspace, e+1")return"Next workspace"; if(a=="workspace, e-1")return"Prev workspace"
    if(a=="workspace, empty")return"Empty workspace"
    if(a=="submap, passthru")return"VM passthrough"; if(a=="submap, reset")return"Exit passthrough"
    if(a~/brightnessctl.*\+/)return"Brightness +"; if(a~/brightnessctl/)return"Brightness −"
    if(a~/set-volume.*5%\+|sink-volume.*\+/)return"Volume +"
    if(a~/set-volume.*5%-|sink-volume.*-/)return"Volume −"
    if(a~/set-source-mute|source-mute/)return"Mic mute"; if(a~/set-mute/)return"Mute"
    if(a~/play-pause/)return"Play / Pause"; if(a=="playerctl pause")return"Pause"
    if(a~/playerctl next/)return"Next track"; if(a~/playerctl previous/)return"Prev track"
    if(a=="qalculate-gtk")return"Calculator"; if(a=="hyprlock")return"Lock"
    if(a=="loginctl lock-session")return"Lock"; if(a=="cliphist wipe")return"Wipe clipboard"
    if(a=="exit")return"Exit Hyprland"
    if(a~/screenshot_claude/)return"Screenshot → Claude"
    if(a~/screenshot\.sh area/)return"Screenshot (area)"; if(a~/screenshot\.sh/)return"Screenshot"
    if(a~/wallpaper\.sh scheme/)return"Recolor theme"; if(a~/wallpaper\.sh select/)return"Pick wallpaper"
    if(a~/launch\.sh/)return"Restart waybar"; if(a~/cliphist\.sh/)return"Clipboard history"
    if(a~/keybinds\.sh/)return"This cheatsheet"; if(a~/settings\.sh/)return"Settings"
    if(a~/\$TERMINAL/)return"Terminal"; if(a~/\$BROWSER/)return"Browser"; if(a~/\$FILEMANAGER/)return"File manager"
    if(a~/^wlogout/)return"Power menu"; if(a~/listen-on.*claude/)return"Claude in kitty"
    if(a~/^rofi -show drun/)return"App launcher"; if(a~/^rofi -show window/)return"Window switcher"
    return a
}
function hdrcell(t,   pad){ pad=W-length(t)-2; if(pad<0)pad=0; return "\033[1;36m▌ " t "\033[0m" sprintf("%*s",pad,"") }
function bindcell(k,a,   max,pl,pad){ max=W-4-length(k); if(length(a)>max && max>1) a=substr(a,1,max-1)"…"; pl=4+length(k)+length(a); pad=W-pl; if(pad<0)pad=0; return "  \033[1;33m" k "\033[0m  \033[0;37m" a "\033[0m" sprintf("%*s",pad,"") }
function blank(){ return sprintf("%*s",W,"") }
/^[[:space:]]*#/ { h=$0; sub(/^[^#]*#[[:space:]]*/,"",h); h=trim(h); if(h=="" || h ~ /KEY$/) next; if(h~/^Personal/)h="Personal"; if(h~/^Passthrough/)h="VM passthrough"; ns++; title[ns]=h; cnt[ns]=0; next }
/^[[:space:]]*bind/ {
    if(ns==0){ns=1; title[1]="Keybinds"; cnt[1]=0}
    line=$0; sub(/^[^=]*=[[:space:]]*/,"",line); n=split(line,a,","); mods=trim(a[1]); key=trim(a[2]); gsub(/\$mainMod/,"SUPER",mods)
    act=""; for(i=3;i<=n;i++) act=act (i>3?",":"") a[i]; act=trim(act); sub(/^exec,[[:space:]]*/,"",act)
    if(act ~ /^workspace, [0-9]+$/){ if(!ws[ns]){ws[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER + 1…0"; A[ns,cnt[ns]]="Workspace 1–10"} next }
    if(act ~ /^movetoworkspace, [0-9]+$/){ if(!mw[ns]){mw[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER SHIFT + 1…0"; A[ns,cnt[ns]]="Move → workspace"} next }
    if(act ~ /^movefocus,/){ if(!mf[ns]){mf[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER + arrows"; A[ns,cnt[ns]]="Move focus"} next }
    if(act ~ /^resizeactive,/){ if(!rz[ns]){rz[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER SHIFT + arrows"; A[ns,cnt[ns]]="Resize window"} next }
    if(act ~ /^movewindow, [lrud]$/){ if(!mv[ns]){mv[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER CTRL + arrows"; A[ns,cnt[ns]]="Move window"} next }
    if(act ~ /^focusmonitor,/){ if(!fm[ns]){fm[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER ALT + ←→"; A[ns,cnt[ns]]="Focus monitor"} next }
    if(act ~ /^movewindow, mon:/){ if(!mm[ns]){mm[ns]=1; cnt[ns]++; K[ns,cnt[ns]]="SUPER ALT SHIFT + ←→"; A[ns,cnt[ns]]="Window to monitor"} next }
    cnt[ns]++; K[ns,cnt[ns]]=(mods!=""?mods" + "key:key); A[ns,cnt[ns]]=lbl(act)
}
END {
    total=0; for(s=1;s<=ns;s++) total+=cnt[s]+1; half=int((total+1)/2); col=1; c1=0; c2=0
    for(s=1;s<=ns;s++){ if(col==1 && c1>=half) col=2
        if(col==1){ c1++; L1[c1]=hdrcell(title[s]); for(i=1;i<=cnt[s];i++){c1++; L1[c1]=bindcell(K[s,i],A[s,i])} }
        else      { c2++; L2[c2]=hdrcell(title[s]); for(i=1;i<=cnt[s];i++){c2++; L2[c2]=bindcell(K[s,i],A[s,i])} } }
    mr=(c1>c2?c1:c2); for(r=1;r<=mr;r++){ l=(r<=c1?L1[r]:blank()); rr=(r<=c2?L2[r]:""); print "  " l "   " rr }
}
' "$conf"

printf '\n   \033[2mPress any key to close\033[0m\n'
read -rsn1
