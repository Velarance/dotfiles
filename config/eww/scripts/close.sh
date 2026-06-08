#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
echo "$(date +%T) close.sh fired" >> "$HOME/.cache/eww-toggle.log"
eww update winopen=false
eww close music backdrop
