#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
pgrep -x eww >/dev/null || { eww daemon; sleep 0.4; }
eww open --toggle music
