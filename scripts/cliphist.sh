#!/bin/bash

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "${SCRIPT_DIR}" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR=.
source "${SCRIPT_DIR}/../config/hypr/scripts/lib/modal-menu.sh"

modal_menu_enter
trap modal_menu_release EXIT

case $1 in
    d) selected=$(cliphist list | rofi -dmenu -replace -config ~/dotfiles/config/rofi/config-cliphist.rasi)
       modal_menu_release
       trap - EXIT
       [ -n "$selected" ] && printf '%s\n' "$selected" | cliphist delete
       ;;

    w) selected=$(printf 'Clear\nCancel\n' | rofi -dmenu -replace -config ~/dotfiles/config/rofi/config-short.rasi)
       modal_menu_release
       trap - EXIT
       if [ "$selected" == "Clear" ] ; then
            cliphist wipe
       fi
       ;;

    *) selected=$(cliphist list | rofi -dmenu -replace -config ~/dotfiles/config/rofi/config-cliphist.rasi)
       modal_menu_release
       trap - EXIT
       [ -n "$selected" ] && printf '%s\n' "$selected" | cliphist decode | wl-copy
       ;;
esac
