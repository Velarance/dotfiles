#!/bin/bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "${SCRIPT_DIR}" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR=.
source "${SCRIPT_DIR}/lib/music-overlay.sh"

exec 9>"$HOME/.cache/eww-music.lock"
flock -n 9 || exit 0
target_monitor=""
target_monitor=$(hypr_music_target_monitor 2>/dev/null) || target_monitor=""

eww_music_overlay_visible
visible_status=$?
case "${visible_status}" in
    0)
        eww_close_music_overlay || exit 1
        exit 0
        ;;
    1) ;;
    *) exit 1 ;;
esac


eww_close_music_overlay || exit 1
eww_open_music_overlay "${target_monitor}" || exit 1
if ! hypr_ipc keyword bind ,ESCAPE,exec,~/.config/eww/scripts/close.sh; then
    eww_close_music_overlay || true
    exit 1
fi
