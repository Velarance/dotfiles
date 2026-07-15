#!/usr/bin/env bash

set -euo pipefail

readonly DOTFILES_DIR="${DOTFILES_DIR:-${HOME}/dotfiles}"
readonly WALLPAPER_SCRIPT="${DOTFILES_DIR}/config/hypr/scripts/wallpaper.sh"
readonly DOCTOR_SCRIPT="${DOTFILES_DIR}/scripts/doctor.sh"
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "${SCRIPT_DIR}" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR=.
readonly SCRIPT_DIR

source "${SCRIPT_DIR}/lib/modal-menu.sh"

entries=()

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

add_command() {
    local label="$1"
    local command="$2"
    if command_exists "${command}"; then
        entries+=("${label}")
    fi
}

terminal_available() {
    command_exists alacritty || command_exists kitty
}

run_in_terminal() {
    local hold="$1"
    shift

    if command_exists alacritty; then
        [[ "${hold}" == "hold" ]] \
            && exec alacritty --hold --class dotfiles-floating -e "$@"
        exec alacritty --class dotfiles-floating -e "$@"
    fi

    [[ "${hold}" == "hold" ]] \
        && exec kitty --hold --class dotfiles-floating -e "$@"
    exec kitty --class dotfiles-floating -e "$@"
}

add_command "Network" nm-connection-editor
add_command "Audio" pavucontrol
add_command "Audio effects" easyeffects
add_command "Displays" nwg-displays
[[ -x "${WALLPAPER_SCRIPT}" ]] && entries+=("Wallpaper")
if command_exists pacseek && terminal_available; then
    entries+=("Packages")
fi
if [[ -x "${DOCTOR_SCRIPT}" ]] && terminal_available; then
    entries+=("Dotfiles health")
fi

if [[ "${1:-}" == "--list" ]]; then
    printf '%s\n' "${entries[@]}"
    exit 0
fi

if ! command_exists rofi || [[ ${#entries[@]} -eq 0 ]]; then
    command_exists notify-send && notify-send "Settings" "No settings tools are available"
    exit 1
fi

modal_menu_enter
trap modal_menu_release EXIT
selection=$(printf '%s\n' "${entries[@]}" | rofi -dmenu -replace -i -p "Settings") || exit 0
modal_menu_release
trap - EXIT

case "${selection}" in
    "Network") exec nm-connection-editor ;;
    "Audio") exec pavucontrol ;;
    "Audio effects") exec easyeffects ;;
    "Displays") exec nwg-displays ;;
    "Wallpaper") exec "${WALLPAPER_SCRIPT}" select ;;
    "Packages") run_in_terminal close pacseek ;;
    "Dotfiles health") run_in_terminal hold "${DOCTOR_SCRIPT}" ;;
esac
