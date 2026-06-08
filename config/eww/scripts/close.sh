#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
eww update winopen=false
eww close music backdrop
hyprctl keyword unbind ,ESCAPE
