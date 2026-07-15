#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "${SCRIPT_DIR}" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR=.
source "${SCRIPT_DIR}/lib/music-overlay.sh"

exec 9>"$HOME/.cache/eww-music.lock"
flock 9

eww_close_music_overlay
