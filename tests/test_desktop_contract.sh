#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

source "${ROOT}/lib/packages.conf"

required_session_packages=(
    starship
    polkit-gnome
    swayosd
    qt6ct
    python
    easyeffects
    lsp-plugins
    eww
    network-manager-applet
    bibata-cursor-theme
    zoxide
    nautilus
    file-roller
    sushi
    gvfs-mtp
    gvfs-smb
    ffmpegthumbnailer
    gst-libav
    gst-plugins-ugly
    xdg-utils
    firefox
)

for package in "${required_session_packages[@]}"; do
    contains "${package}" "${CORE_PACKAGES[@]}" \
        || fail "${package} must be a core session package"
    ! contains "${package}" "${OPTIONAL_PACKAGES[@]}" \
        || fail "${package} is duplicated in optional packages"
done

contains lazygit "${OPTIONAL_PACKAGES[@]}" \
    || fail "lazygit must be offered for the configured Neovim integration"

required_nautilus_optional_packages=(
    nautilus-python
    nautilus-open-any-terminal
    nautilus-admin-gtk4
)

for package in "${required_nautilus_optional_packages[@]}"; do
    contains "${package}" "${OPTIONAL_PACKAGES[@]}" \
        || fail "${package} must be offered as an optional Nautilus integration"
done

retired_file_manager_packages=(
    thunar
    thunar-volman
    thunar-archive-plugin
    tumbler
)

for package in "${retired_file_manager_packages[@]}"; do
    ! contains "${package}" "${CORE_PACKAGES[@]}" \
        || fail "${package} must not be a core package"
    ! contains "${package}" "${OPTIONAL_PACKAGES[@]}" \
        || fail "${package} must not be installed alongside Nautilus"
done

for package in "${CORE_PACKAGES[@]}"; do
    ! contains "${package}" "${OPTIONAL_PACKAGES[@]}" \
        || fail "${package} appears in both core and optional packages"
done

autostart="${ROOT}/config/hypr/conf/autostart.conf"
hyprland="${ROOT}/config/hypr/hyprland.conf"

! grep -Eq '^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*swaync([[:space:]]|$)' "${autostart}" \
    || fail "swaync must not be started as an unmanaged process"
grep -Fq 'systemctl --user start swaync.service' "${autostart}" \
    || fail "swaync must be started by the user systemd manager"

dbus_updates=$(grep -hF 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP' \
    "${autostart}" "${hyprland}" | wc -l)
[[ "${dbus_updates}" -eq 1 ]] \
    || fail "the systemd D-Bus environment must be imported exactly once"

settings_script="${ROOT}/config/hypr/scripts/settings.sh"
[[ -x "${settings_script}" ]] || fail "settings menu script is missing or not executable"
grep -Fq 'exec, ~/.config/hypr/scripts/settings.sh' "${ROOT}/config/hypr/conf/keybinding.conf" \
    || fail "XF86Tools must launch the settings menu"

aliases="${ROOT}/home/shell/aliases.zsh"
grep -Fq "alias hyprconf='cd \${HOME}/dotfiles/config/hypr/conf'" "${aliases}" \
    || fail "hyprconf alias points at the wrong directory"
grep -Fq "alias nvimconf='cd \${HOME}/dotfiles/config/nvim'" "${aliases}" \
    || fail "nvimconf alias points at the wrong directory"
grep -Fq "alias hypr-restart='\${HOME}/dotfiles/config/waybar/launch.sh &'" "${aliases}" \
    || fail "hypr-restart alias points at the wrong script"

grep -Fq 'command -v starship' "${ROOT}/home/.zshrc" \
    || fail "starship initialization must tolerate a partial install"
grep -Fq 'command -v zoxide' "${ROOT}/home/.zshrc" \
    || fail "zoxide initialization must tolerate a partial install"

bash -n "${settings_script}"

minimal_menu=$(DOTFILES_DIR="${ROOT}" PATH=/nonexistent /usr/bin/bash "${settings_script}" --list) \
    || fail "settings menu must tolerate unavailable optional tools"
[[ "${minimal_menu}" == "Wallpaper" ]] \
    || fail "settings menu must retain available entries during a partial install"

network_block=$(sed -n '/^[[:space:]]*"network": {/,/^[[:space:]]*},/p' \
    "${ROOT}/config/waybar/config")
[[ "${network_block}" == *'"tooltip-format-ethernet":'* ]] \
    || fail "ethernet network tooltip is missing"
[[ "${network_block}" == *'"tooltip-format-wifi":'* ]] \
    || fail "wifi network tooltip is missing"
for field in ifname ipaddr cidr gwaddr bandwidthDownBytes bandwidthUpBytes; do
    [[ "${network_block}" == *"{${field}}"* ]] \
        || fail "network tooltip is missing {${field}}"
done
for field in essid bssid signalStrength signaldBm frequency; do
    [[ "${network_block}" == *"{${field}}"* ]] \
        || fail "wifi tooltip is missing {${field}}"
done
[[ "${network_block}" == *'"interval": 5'* ]] \
    || fail "network statistics must refresh every five seconds"

grep -Fq 'env = FILEMANAGER,nautilus --new-window' \
    "${ROOT}/config/hypr/conf/defaults.conf" \
    || fail "FILEMANAGER must request a new Nautilus window"
grep -Fq 'bind = $mainMod, E, exec, $FILEMANAGER' \
    "${ROOT}/config/hypr/conf/keybinding.conf" \
    || fail "Super+E must use the FILEMANAGER command"

printf 'desktop contract: ok\n'
