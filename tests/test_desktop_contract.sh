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
    nwg-displays
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
polkit_service="${ROOT}/config/systemd/user/polkit-gnome-authentication-agent.service"

! grep -Eq '^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*swaync([[:space:]]|$)' "${autostart}" \
    || fail "swaync must not be started as an unmanaged process"
grep -Fxq 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP && systemctl --user start swaync.service polkit-gnome-authentication-agent.service' "${autostart}" \
    || fail "session services must start together only after the D-Bus environment import"
! grep -Eq '^[[:space:]]*exec-once.*polkit-gnome-authentication-agent-1' "${autostart}" \
    || fail "the polkit agent must not be started as an unmanaged Hyprland process"

[[ -f "${polkit_service}" ]] \
    || fail "the supervised polkit user service is missing"
grep -Fxq 'ExecStart=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1' "${polkit_service}" \
    || fail "the polkit user service has the wrong executable"
grep -Fxq 'ConditionFileIsExecutable=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1' "${polkit_service}" \
    || fail "the polkit user service must use a valid executable condition"
grep -Fxq 'Restart=on-failure' "${polkit_service}" \
    || fail "the polkit user service must restart after failures"
grep -Fxq 'RestartSec=1' "${polkit_service}" \
    || fail "the polkit user service restart delay is not bounded"

dbus_updates=$(grep -hF 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP' \
    "${autostart}" "${hyprland}" | wc -l)
[[ "${dbus_updates}" -eq 1 ]] \
    || fail "the systemd D-Bus environment must be imported exactly once"

fallback_monitor_line=$(grep -nFx 'source = ~/dotfiles/config/hypr/conf/monitor.conf' "${hyprland}" \
    | cut -d: -f1 || true)
generated_monitor_line=$(grep -nFx 'source = ~/.config/hypr/monitors.conf' "${hyprland}" \
    | cut -d: -f1 || true)
generated_workspace_line=$(grep -nFx 'source = ~/.config/hypr/workspaces.conf' "${hyprland}" \
    | cut -d: -f1 || true)
[[ -n "${fallback_monitor_line}" && -n "${generated_monitor_line}" && -n "${generated_workspace_line}" ]] \
    || fail "Hyprland must load nwg-displays monitor and workspace configurations"
[[ "${generated_monitor_line}" -eq $((fallback_monitor_line + 1)) ]] \
    || fail "generated monitor rules must load immediately after the generic fallback"
[[ "${generated_workspace_line}" -eq $((generated_monitor_line + 1)) ]] \
    || fail "generated workspace assignments must load after monitor rules"

generated_hypr_files=(
    config/hypr/monitors.conf
    config/hypr/monitors.lua
    config/hypr/workspaces.conf
    config/hypr/workspaces.lua
)
for generated_file in "${generated_hypr_files[@]}"; do
    git -C "${ROOT}" check-ignore -q "${generated_file}" \
        || fail "${generated_file} must remain machine-specific and ignored"
done

settings_script="${ROOT}/config/hypr/scripts/settings.sh"
keybindings="${ROOT}/config/hypr/conf/keybinding.conf"
keybinds_script="${ROOT}/config/hypr/scripts/keybinds.sh"
[[ -x "${settings_script}" ]] || fail "settings menu script is missing or not executable"
[[ -x "${keybinds_script}" ]] || fail "keybind cheatsheet script is missing or not executable"
grep -Fxq 'bind = $mainMod SHIFT, D, exec, ~/.config/hypr/scripts/settings.sh' "${keybindings}" \
    || fail "Super+Shift+D must launch the settings menu"
! grep -Fq 'XF86Tools, exec, ~/.config/hypr/scripts/settings.sh' "${keybindings}" \
    || fail "the inaccessible XF86Tools Settings binding must be removed"
grep -Eq '^bind = \$mainMod, slash, exec, .*keybinds\.sh$' "${keybindings}" \
    || fail "Super+/ must keep launching keybinds.sh"
grep -Fxq 'bind = , PRINT, exec, ~/dotfiles/config/hypr/scripts/screenshot.sh area' "${keybindings}" \
    || fail "Print must start area screenshot selection"
grep -Fxq 'bind = $mainMod, PRINT, exec, ~/dotfiles/config/hypr/scripts/screenshot.sh' "${keybindings}" \
    || fail "Super+Print must screenshot the active monitor immediately"

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

settings_tmp=$(mktemp -d)
keybinds_tmp=""
trap 'rm -rf -- "${settings_tmp}" "${keybinds_tmp}"' EXIT
touch "${settings_tmp}/nwg-displays"
chmod +x "${settings_tmp}/nwg-displays"
display_menu=$(DOTFILES_DIR="${ROOT}" PATH="${settings_tmp}" /usr/bin/bash "${settings_script}" --list) \
    || fail "settings menu must detect nwg-displays"
[[ "${display_menu}" == $'Displays\nWallpaper' ]] \
    || fail "settings menu must expose Displays when nwg-displays is installed"
grep -Fq '"Displays") exec nwg-displays ;;' "${settings_script}" \
    || fail "settings menu must launch nwg-displays"

cat > "${settings_tmp}/rofi" <<'FAKE_ROFI'
#!/usr/bin/env bash
set -euo pipefail
printf 'Displays\n'
FAKE_ROFI
cat > "${settings_tmp}/nwg-displays" <<'FAKE_NWG_DISPLAYS'
#!/usr/bin/env bash
set -euo pipefail
printf 'launched\n' > "${NWG_DISPLAYS_LOG:?}"
FAKE_NWG_DISPLAYS
chmod +x "${settings_tmp}/rofi" "${settings_tmp}/nwg-displays"
settings_launch_log="${settings_tmp}/nwg-displays.log"
if ! HOME="${settings_tmp}/home" \
    DOTFILES_DIR="${ROOT}" \
    DOTFILES_MODAL_MENU_LOCK="${settings_tmp}/settings.lock" \
    NWG_DISPLAYS_LOG="${settings_launch_log}" \
    PATH="${settings_tmp}:/usr/bin:/bin" \
    /usr/bin/bash "${settings_script}"; then
    fail "settings menu failed while launching Displays"
fi
grep -Fxq 'launched' "${settings_launch_log}" \
    || fail "settings menu did not execute nwg-displays after selecting Displays"

keybinds_tmp=$(mktemp -d)
mkdir -p "${keybinds_tmp}/.config/hypr/conf"
cp "${keybindings}" "${keybinds_tmp}/.config/hypr/conf/keybinding.conf"
cheatsheet_output=$(printf '\n' \
    | HOME="${keybinds_tmp}" TERM=dumb bash "${keybinds_script}" \
    | sed -r 's/\x1B\[[0-9;]*[[:alpha:]]//g')
for expected_row in \
    'SUPER SHIFT + D  Settings' \
    'SUPER + /  This cheatsheet' \
    'SUPER + M  App launcher' \
    'SUPER SHIFT + X  Power menu' \
    'XF86MonBrightnessUp  Brightness +' \
    'XF86AudioRaiseVolume  Volume +' \
    'PRINT  Screenshot (area)' \
    'SUPER + PRINT  Screenshot' \
    'SUPER + A  Toggle music overlay'; do
    grep -Fq "${expected_row}" <<< "${cheatsheet_output}" \
        || fail "cheatsheet is missing '${expected_row}'"
done
! grep -Fq 'swayosd-client' <<< "${cheatsheet_output}" \
    || fail "cheatsheet must not expose raw swayosd commands"

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
