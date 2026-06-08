#!/bin/bash

if [ "$1" = "toggle" ]; then
    kb=$(hyprctl devices -j | jq -r 'first(.keyboards[] | select(.main == true) | .name)')
    [ -n "$kb" ] && hyprctl switchxkblayout "$kb" next
    exit 0
fi

km=$(hyprctl devices -j | jq -r 'first(.keyboards[] | select(.main == true) | .active_keymap) // empty')
case "$km" in
    "English (US)") echo "us" ;;
    "English (UK)") echo "uk" ;;
    "Russian")      echo "ru" ;;
    "Ukrainian")    echo "ua" ;;
    "German")       echo "de" ;;
    "French")       echo "fr" ;;
    "Spanish")      echo "es" ;;
    "")             echo "??" ;;
    *)              echo "${km:0:2}" | tr '[:upper:]' '[:lower:]' ;;
esac
