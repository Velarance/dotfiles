#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/lib/modal-menu.sh"
LAUNCHER="${ROOT}/config/hypr/scripts/modal-menu-launch.sh"
WORKSPACES="${ROOT}/config/hypr/scripts/rofi-workspaces.sh"
WIFI="${ROOT}/config/hypr/scripts/rofi-wifi.sh"
SETTINGS="${ROOT}/config/hypr/scripts/settings.sh"
CLIPHIST="${ROOT}/scripts/cliphist.sh"
EWW_OVERLAY="${ROOT}/config/eww/scripts/lib/music-overlay.sh"
GDK_MONITOR_HELPER="${ROOT}/config/eww/scripts/gdk-monitor-index.py"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

wait_for_file() {
    local path="$1"
    local attempt

    for attempt in $(seq 1 100); do
        [[ -e "${path}" ]] && return 0
        sleep 0.02
    done
    return 1
}

[[ -r "${HELPER}" ]] || fail "shared modal-menu lock helper is missing"
[[ -x "${LAUNCHER}" ]] || fail "guarded modal-menu launcher is missing or not executable"
[[ -x "${GDK_MONITOR_HELPER}" ]] || fail "GDK monitor-index helper is missing or not executable"
grep -Fq '"python-gobject"' "${ROOT}/lib/packages.conf" \
    || fail "GDK monitor-index helper dependency must be mandatory"

test_tmp=$(mktemp -d)
PYTHONPYCACHEPREFIX="${test_tmp}/pycache" python -m py_compile "${GDK_MONITOR_HELPER}" \
    || fail "GDK monitor-index helper is not Python syntax-valid"
holder_pid=""
descendant_pid=""
wifi_pid=""
stale_eww_pid=""
unrelated_pid=""
daemon_probe_pid=""
music_holder_pid=""
music_close_pid=""
bind_owner_pid=""
screen_owner_pid=""
cleanup() {
    if [[ -n "${holder_pid}" ]] && kill -0 "${holder_pid}" 2>/dev/null; then
        kill "${holder_pid}" 2>/dev/null || true
        wait "${holder_pid}" 2>/dev/null || true
    fi
    if [[ -n "${descendant_pid}" ]] && kill -0 "${descendant_pid}" 2>/dev/null; then
        kill "${descendant_pid}" 2>/dev/null || true
        wait "${descendant_pid}" 2>/dev/null || true
    fi
    if [[ -n "${wifi_pid}" ]] && kill -0 "${wifi_pid}" 2>/dev/null; then
        kill "${wifi_pid}" 2>/dev/null || true
        wait "${wifi_pid}" 2>/dev/null || true
    fi
    if [[ -n "${stale_eww_pid}" ]] && kill -0 "${stale_eww_pid}" 2>/dev/null; then
        kill -KILL "${stale_eww_pid}" 2>/dev/null || true
        wait "${stale_eww_pid}" 2>/dev/null || true
    fi
    if [[ -n "${unrelated_pid}" ]] && kill -0 "${unrelated_pid}" 2>/dev/null; then
        kill "${unrelated_pid}" 2>/dev/null || true
        wait "${unrelated_pid}" 2>/dev/null || true
    fi
    if [[ -n "${daemon_probe_pid}" ]] && kill -0 "${daemon_probe_pid}" 2>/dev/null; then
        kill -KILL "${daemon_probe_pid}" 2>/dev/null || true
        wait "${daemon_probe_pid}" 2>/dev/null || true
    fi
    if [[ -n "${music_holder_pid}" ]] && kill -0 "${music_holder_pid}" 2>/dev/null; then
        kill "${music_holder_pid}" 2>/dev/null || true
        wait "${music_holder_pid}" 2>/dev/null || true
    fi
    if [[ -n "${music_close_pid}" ]] && kill -0 "${music_close_pid}" 2>/dev/null; then
        kill "${music_close_pid}" 2>/dev/null || true
        wait "${music_close_pid}" 2>/dev/null || true
    fi
    if [[ -n "${bind_owner_pid}" ]] && kill -0 "${bind_owner_pid}" 2>/dev/null; then
        kill "${bind_owner_pid}" 2>/dev/null || true
        wait "${bind_owner_pid}" 2>/dev/null || true
    fi
    if [[ -n "${screen_owner_pid}" ]] && kill -0 "${screen_owner_pid}" 2>/dev/null; then
        kill "${screen_owner_pid}" 2>/dev/null || true
        wait "${screen_owner_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${test_tmp}"
}
trap cleanup EXIT

runtime_dir="${test_tmp}/runtime"
mkdir -p "${runtime_dir}"
export XDG_RUNTIME_DIR="${runtime_dir}"
export DOTFILES_MODAL_MENU_LOCK="${runtime_dir}/modal-menu.lock"

holder_started="${test_tmp}/holder-started"
holder_release="${test_tmp}/holder-release"
blocked_marker="${test_tmp}/blocked-marker"

"${LAUNCHER}" bash -c '
    : > "$1"
    while [[ ! -e "$2" ]]; do sleep 0.02; done
' bash "${holder_started}" "${holder_release}" &
holder_pid=$!

wait_for_file "${holder_started}" \
    || fail "first guarded process did not acquire the modal lock"

"${LAUNCHER}" bash -c ': > "$1"' bash "${blocked_marker}" \
    || fail "a blocked duplicate invocation must exit successfully"
[[ ! -e "${blocked_marker}" ]] \
    || fail "a second modal command executed while the first held the lock"

: > "${holder_release}"
wait "${holder_pid}"
holder_pid=""

"${LAUNCHER}" bash -c ': > "$1"' bash "${blocked_marker}" \
    || fail "modal command did not execute after the first command exited"
[[ -e "${blocked_marker}" ]] \
    || fail "modal lock was not released after the guarded process exited"

setup_failure_marker="${test_tmp}/setup-failure-marker"
if DOTFILES_MODAL_MENU_LOCK=/proc/dotfiles-modal-menu/lock \
    "${LAUNCHER}" bash -c ': > "$1"' bash "${setup_failure_marker}" 2>/dev/null; then
    fail "modal launcher hides a lock setup failure as ordinary contention"
fi
[[ ! -e "${setup_failure_marker}" ]] \
    || fail "modal command executed after its lock setup failed"

descendant_pid_file="${test_tmp}/descendant-pid"
descendant_marker="${test_tmp}/descendant-marker"
"${LAUNCHER}" bash -c '
    nohup sh -c "sleep 30" >/dev/null 2>&1 &
    printf "%s\n" "$!" > "$1"
' bash "${descendant_pid_file}"
wait_for_file "${descendant_pid_file}" \
    || fail "guarded process did not report its background descendant"
read -r descendant_pid < "${descendant_pid_file}"

"${LAUNCHER}" bash -c ': > "$1"' bash "${descendant_marker}" \
    || fail "launcher failed after a guarded command spawned a descendant"
[[ -e "${descendant_marker}" ]] \
    || fail "modal lock leaked into a guarded command's descendant"
kill "${descendant_pid}" 2>/dev/null || true
wait "${descendant_pid}" 2>/dev/null || true
descendant_pid=""

fake_bin="${test_tmp}/fake-bin"
fake_home="${test_tmp}/home"
mkdir -p "${fake_bin}" "${fake_home}/.cache" "${fake_home}/.config/rofi"

cat > "${fake_bin}/hyprctl" <<'FAKE_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-} ${2:-}" in
    "monitors -j")
        [[ "${FAKE_HYPRCTL_MONITORS_FAIL:-0}" != "1" ]] || exit 4
        if [[ -n "${FAKE_HYPRCTL_MONITORS_JSON:-}" ]]; then
            printf '%s\n' "${FAKE_HYPRCTL_MONITORS_JSON}"
        else
            printf '[{"id":0,"name":"TEST-1","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}]\n'
        fi
        ;;
    "cursorpos -j")
        [[ "${FAKE_HYPRCTL_CURSORPOS_FAIL:-0}" != "1" ]] || exit 4
        if [[ -n "${FAKE_HYPRCTL_CURSORPOS_JSON:-}" ]]; then
            printf '%s\n' "${FAKE_HYPRCTL_CURSORPOS_JSON}"
        else
            printf '{"x":0,"y":0}\n'
        fi
        ;;
    "workspaces -j")
        printf '[{"id":1,"monitorID":0},{"id":3,"monitorID":0}]\n'
        ;;
    "dispatch workspace")
        printf '%s\n' "$*" >> "${FAKE_HYPRCTL_LOG}"
        ;;
    "layers -j")
        [[ "${FAKE_HYPRCTL_LAYERS_FAIL:-0}" != "1" ]] || exit 5
        if [[ "${FAKE_HYPRCTL_LAYERS_INVALID:-0}" == "1" ]]; then
            printf '{invalid-json\n'
        elif [[ -n "${FAKE_EWW_LAYER_PID:-}" ]] \
            && { [[ -z "${FAKE_EWW_LAYER_FLAG:-}" ]] || [[ -e "${FAKE_EWW_LAYER_FLAG}" ]]; } \
            && kill -0 "${FAKE_EWW_LAYER_PID}" 2>/dev/null; then
            printf '{"TEST":{"levels":{"3":[{"namespace":"eww-music","pid":%s}]}}}\n' \
                "${FAKE_EWW_LAYER_PID}"
        else
            printf '{}\n'
        fi
        ;;
    "keyword unbind")
        printf '%s\n' "$*" >> "${FAKE_HYPRCTL_LOG}"
        ;;
    "keyword bind")
        printf '%s\n' "$*" >> "${FAKE_HYPRCTL_LOG}"
        [[ "${FAKE_HYPRCTL_BIND_FAIL:-0}" != "1" ]] || exit 6
        ;;
    *)
        exit 2
        ;;
esac
FAKE_HYPRCTL

cat > "${fake_bin}/rofi" <<'FAKE_ROFI'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_ROFI_LOG}"
cat >/dev/null
if [[ -n "${FAKE_ROFI_BLOCK_FILE:-}" ]]; then
    : > "${FAKE_ROFI_BLOCK_FILE}.ready"
    while [[ ! -e "${FAKE_ROFI_BLOCK_FILE}" ]]; do
        sleep 0.02
    done
    exit 0
fi
if [[ -n "${FAKE_ROFI_OUTPUT:-}" ]]; then
    printf '%s\n' "${FAKE_ROFI_OUTPUT}"
fi
FAKE_ROFI

cat > "${fake_bin}/eww" <<'FAKE_EWW'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_EWW_LOG}"
if [[ -n "${FAKE_EWW_LAYER_FLAG:-}" ]]; then
    case " $* " in
        *" open music "*)
            open_count=0
            if [[ -n "${FAKE_EWW_OPEN_COUNT_FILE:-}" && -r "${FAKE_EWW_OPEN_COUNT_FILE}" ]]; then
                read -r open_count < "${FAKE_EWW_OPEN_COUNT_FILE}"
            fi
            open_count=$((open_count + 1))
            if [[ -n "${FAKE_EWW_OPEN_COUNT_FILE:-}" ]]; then
                printf '%s\n' "${open_count}" > "${FAKE_EWW_OPEN_COUNT_FILE}"
            fi
            if ((open_count >= ${FAKE_EWW_OPEN_SUCCEEDS_AFTER:-1})); then
                : > "${FAKE_EWW_LAYER_FLAG}"
            fi
            ;;
        *" close music "*) rm -f -- "${FAKE_EWW_LAYER_FLAG}" ;;
    esac
fi
FAKE_EWW

cat > "${fake_bin}/gdk-monitor-index" <<'FAKE_GDK_MONITOR_INDEX'
#!/usr/bin/env bash
set -euo pipefail
target=$(cat)
jq -er 'if .name == "DP-1" then 7 elif .name == "HDMI-A-1" then 4 elif .name == "DVI-D-1" then 9 else error("unknown monitor") end' <<< "${target}"
FAKE_GDK_MONITOR_INDEX

cat > "${fake_bin}/nmcli" <<'FAKE_NMCLI'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "-g WIFI radio wifi" ]]; then
    printf 'disabled\n'
    exit 0
fi
exit 2
FAKE_NMCLI

chmod +x "${fake_bin}/hyprctl" "${fake_bin}/rofi" "${fake_bin}/eww" "${fake_bin}/nmcli" "${fake_bin}/gdk-monitor-index"

export FAKE_HYPRCTL_LOG="${test_tmp}/hyprctl.log"
export FAKE_ROFI_LOG="${test_tmp}/rofi.log"
export FAKE_EWW_LOG="${test_tmp}/eww.log"
export EWW_GDK_MONITOR_HELPER="${fake_bin}/gdk-monitor-index"
: > "${FAKE_HYPRCTL_LOG}"
: > "${FAKE_ROFI_LOG}"
: > "${FAKE_EWW_LOG}"

HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" FAKE_ROFI_OUTPUT=3 \
    bash "${WORKSPACES}" \
    || fail "workspace selector failed in the command harness"

grep -Fqx 'dispatch workspace 3' "${FAKE_HYPRCTL_LOG}" \
    || fail "workspace selector did not dispatch the selected workspace"
grep -Eq '(^| )-replace( |$)' "${FAKE_ROFI_LOG}" \
    || fail "workspace selector must invoke Rofi in replacement mode"
[[ ! -s "${FAKE_EWW_LOG}" ]] \
    || fail "workspace selector must not create an Eww overlay"

: > "${FAKE_ROFI_LOG}"
: > "${FAKE_EWW_LOG}"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" FAKE_ROFI_OUTPUT= \
    bash "${WIFI}" \
    || fail "cancelled Wi-Fi menu must exit successfully"

grep -Eq '(^| )-replace( |$)' "${FAKE_ROFI_LOG}" \
    || fail "Wi-Fi menu must invoke Rofi in replacement mode"
grep -Eq '(^| )-click-to-exit( |$)' "${FAKE_ROFI_LOG}" \
    || fail "Wi-Fi menu must make Rofi own click-outside cancellation"
[[ ! -s "${FAKE_EWW_LOG}" ]] \
    || fail "Wi-Fi menu must not create a daemon-owned Eww backdrop"

: > "${FAKE_EWW_LOG}"
signal_release="${test_tmp}/signal-release"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_ROFI_OUTPUT= FAKE_ROFI_BLOCK_FILE="${signal_release}" \
    bash "${WIFI}" &
wifi_pid=$!
wait_for_file "${signal_release}.ready" \
    || fail "signal test did not reach the blocking Rofi process"
kill -TERM "${wifi_pid}"
: > "${signal_release}"
if wait "${wifi_pid}"; then
    fail "signal-driven Wi-Fi menu exit unexpectedly returned success"
fi
wifi_pid=""
post_signal_marker="${test_tmp}/post-signal-marker"
"${LAUNCHER}" bash -c ': > "$1"' bash "${post_signal_marker}"
[[ -e "${post_signal_marker}" ]] \
    || fail "Wi-Fi menu did not release the modal lock after a signal"

nested_root="${test_tmp}/nested-dotfiles"
nested_wallpaper="${nested_root}/config/hypr/scripts/wallpaper.sh"
nested_marker="${test_tmp}/nested-marker"
mkdir -p "$(dirname "${nested_wallpaper}")"
cat > "${nested_wallpaper}" <<FAKE_WALLPAPER
#!/usr/bin/env bash
set -euo pipefail
source "${HELPER}"
modal_menu_acquire || exit 90
: > "${nested_marker}"
FAKE_WALLPAPER
chmod +x "${nested_wallpaper}"

HOME="${fake_home}" DOTFILES_DIR="${nested_root}" \
    PATH="${fake_bin}:/usr/bin:/bin" FAKE_ROFI_OUTPUT=Wallpaper \
    bash "${SETTINGS}" \
    || fail "Settings did not release the modal lock before its nested action"
[[ -e "${nested_marker}" ]] \
    || fail "nested Settings action could not acquire the released modal lock"

keybindings="${ROOT}/config/hypr/conf/keybinding.conf"
waybar="${ROOT}/config/waybar/config"
decoration="${ROOT}/config/hypr/conf/decoration.conf"
windowrules="${ROOT}/config/hypr/conf/windowrule.conf"

grep -Fq 'modal-menu-launch.sh rofi -show drun -replace -i' "${keybindings}" \
    || fail "app launcher keybind bypasses the shared modal guard"
grep -Fq 'modal-menu-launch.sh wlogout ' "${keybindings}" \
    || fail "Wlogout keybind bypasses the shared modal guard"
grep -Fq 'modal-menu-launch.sh wlogout ' "${waybar}" \
    || fail "Waybar power menu bypasses the shared modal guard"

grep -Eq '^[[:space:]]*dim_around[[:space:]]*=[[:space:]]*0\.35([[:space:]]|$)' "${decoration}" \
    || fail "Hyprland Rofi dim strength is not configured"
grep -Fq 'layerrule = dim_around on, match:namespace (rofi)' "${windowrules}" \
    || fail "Rofi layer does not use lifecycle-bound Hyprland dimming"

! grep -RqE 'wsdim|eww-wsdim' \
    "${ROOT}/config/eww" "${WORKSPACES}" \
    || fail "orphanable Eww workspace dim overlay still exists"
! grep -RqE 'rofibd|eww-rofibd' \
    "${ROOT}/config/eww" "${WIFI}" \
    || fail "daemon-owned Wi-Fi click backdrop still exists"

wallpaper="${ROOT}/config/hypr/scripts/wallpaper.sh"
rofi_calls=$(grep -cE '[|[:space:]]rofi[[:space:]]' "${wallpaper}")
replace_calls=$(grep -cE '[|[:space:]]rofi[[:space:]].*-replace([[:space:]]|\))' "${wallpaper}")
[[ "${rofi_calls}" -eq "${replace_calls}" ]] \
    || fail "every wallpaper Rofi selector must use replacement mode"

grep -Fq 'modal_menu_enter' "${CLIPHIST}" \
    || fail "clipboard selector bypasses the shared modal guard"
cliphist_rofi_calls=$(grep -cE '[|[:space:]]rofi[[:space:]]' "${CLIPHIST}")
cliphist_replace_calls=$(grep -cE '[|[:space:]]rofi[[:space:]].*-replace([[:space:]]|\))' "${CLIPHIST}")
[[ "${cliphist_rofi_calls}" -eq "${cliphist_replace_calls}" ]] \
    || fail "every clipboard Rofi selector must use replacement mode"

[[ -r "${EWW_OVERLAY}" ]] \
    || fail "resilient Eww music overlay helper is missing"
grep -Fq -- '--kill-after=' "${EWW_OVERLAY}" \
    || fail "bounded Eww IPC does not kill a TERM-resistant client"

daemon_probe_config="${test_tmp}/daemon-config"
daemon_probe_bin="${test_tmp}/daemon-bin"
mkdir -p "${daemon_probe_config}" "${daemon_probe_bin}"
cp /usr/bin/yes "${daemon_probe_bin}/eww"
(
    cd "${daemon_probe_config}"
    exec "${daemon_probe_bin}/eww" -- daemon >/dev/null
) &
daemon_probe_pid=$!

daemon_probe_comm=""
for attempt in $(seq 1 100); do
    if [[ -r "/proc/${daemon_probe_pid}/comm" ]]; then
        IFS= read -r daemon_probe_comm < "/proc/${daemon_probe_pid}/comm" || true
    fi
    [[ "${daemon_probe_comm}" == "eww" ]] && break
    sleep 0.01
done
[[ "${daemon_probe_comm}" == "eww" ]] \
    || fail "daemon filter probe did not set comm=eww"

EWW_CONFIG="${daemon_probe_config}" bash -c '
    source "$1"
    eww_pid_is_config_daemon "$2"
' bash "${EWW_OVERLAY}" "${daemon_probe_pid}" \
    || fail "exact daemon filter rejects the configured Eww daemon argv"

EWW_CONFIG="${daemon_probe_config}" bash -c '
    source "$1"
    eww_daemon_argv_matches eww -c "$2" daemon
    ! eww_daemon_argv_matches eww -c /wrong/config daemon
    ! eww_daemon_argv_matches eww open daemon
    ! eww_daemon_argv_matches eww -- -c "$2" daemon
' bash "${EWW_OVERLAY}" "${daemon_probe_config}" \
    || fail "daemon argv matching does not enforce the configured path and command"

kill -KILL "${daemon_probe_pid}" 2>/dev/null || true
wait "${daemon_probe_pid}" 2>/dev/null || true
daemon_probe_pid=""

bash -c 'printf "eww\n" > /proc/self/comm; trap "" TERM; while :; do :; done' &
stale_eww_pid=$!
stale_comm=""
for attempt in $(seq 1 100); do
    IFS= read -r stale_comm < "/proc/${stale_eww_pid}/comm" || true
    [[ "${stale_comm}" == "eww" ]] && break
    sleep 0.01
done
[[ "${stale_comm}" == "eww" ]] \
    || fail "TERM-resistant test owner did not set comm=eww"
disown "${stale_eww_pid}" 2>/dev/null || true

HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${stale_eww_pid}" \
    EWW_LAYER_SETTLE_ATTEMPTS=2 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash -c 'source "$1"; eww_close_music_overlay' bash "${EWW_OVERLAY}"

if kill -0 "${stale_eww_pid}" 2>/dev/null; then
    fail "stale Eww namespace owner survived overlay recovery"
fi
wait "${stale_eww_pid}" 2>/dev/null || true
stale_eww_pid=""

/usr/bin/sleep 30 &
unrelated_pid=$!
if HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${unrelated_pid}" \
    EWW_LAYER_SETTLE_ATTEMPTS=1 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash -c 'source "$1"; eww_close_music_overlay' bash "${EWW_OVERLAY}"; then
    fail "overlay recovery reported success while an unowned layer survived"
fi

kill -0 "${unrelated_pid}" 2>/dev/null \
    || fail "overlay recovery killed a non-Eww namespace owner"
kill "${unrelated_pid}" 2>/dev/null || true
wait "${unrelated_pid}" 2>/dev/null || true
unrelated_pid=""

grep -Fq 'music-overlay.sh' "${ROOT}/config/eww/scripts/toggle.sh" \
    || fail "music toggle bypasses stale-overlay recovery"
[[ $(grep -Fc 'eww_close_music_overlay || exit 1' \
    "${ROOT}/config/eww/scripts/toggle.sh") -eq 2 ]] \
    || fail "music toggle hides a failed overlay cleanup"
grep -Fq 'music-overlay.sh' "${ROOT}/config/eww/scripts/close.sh" \
    || fail "music close action bypasses stale-overlay recovery"
grep -Fq 'eww-music.lock' "${ROOT}/config/eww/scripts/close.sh" \
    || fail "music close action is not serialized with the toggle"
grep -Eq '^flock[[:space:]]+9([[:space:]]|$)' "${ROOT}/config/eww/scripts/close.sh" \
    || fail "music close action can time out and silently lose a toggle race"

toggle_script="${ROOT}/config/eww/scripts/toggle.sh"
target_capture_line="$(grep -nF 'target_monitor=$(hypr_music_target_monitor' "${toggle_script}" | cut -d: -f1 | head -1 || true)"
visible_probe_line="$(grep -nF 'eww_music_overlay_visible' "${toggle_script}" | cut -d: -f1 | head -1 || true)"
[[ -n "${target_capture_line}" && -n "${visible_probe_line}" ]] \
    || fail "music toggle must capture a target monitor and probe overlay visibility"
if (( target_capture_line >= visible_probe_line )); then
    fail "music toggle samples the cursor after potentially blocking overlay IPC"
fi

cursor_query_line="$(grep -nF 'cursor_json=$(hypr_ipc cursorpos -j' "${EWW_OVERLAY}" | cut -d: -f1 | head -1 || true)"
monitors_query_line="$(grep -nF 'monitors_json=$(hypr_ipc monitors -j' "${EWW_OVERLAY}" | cut -d: -f1 | head -1 || true)"
[[ -n "${cursor_query_line}" && -n "${monitors_query_line}" ]] \
    || fail "music target helper must query both cursor position and monitors"
if (( cursor_query_line >= monitors_query_line )); then
    fail "music target helper does not snapshot the cursor before monitor discovery IPC"
fi

screen_layer_flag="${test_tmp}/screen-layer-open"
screen_open_count="${test_tmp}/screen-open-count"
screen_monitors='[{"id":0,"name":"DVI-D-1","model":"SMC27A550U","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},{"id":1,"name":"DP-1","model":"P27FBB-RGGL","focused":false,"x":1920,"y":0,"width":2560,"height":1440,"scale":2,"transform":1}]'
duplicate_models='[{"id":0,"name":"DVI-D-1","model":"SAME","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},{"id":1,"name":"DP-1","model":"SAME","focused":false,"x":1920,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}]'
if ! duplicate_screen=$(HOME="${fake_home}" \
    PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_HYPRCTL_MONITORS_JSON="${duplicate_models}" \
    FAKE_HYPRCTL_CURSORPOS_JSON='{"x":2500,"y":500}' \
    bash -c 'source "$1"; hypr_music_target_monitor' bash "${EWW_OVERLAY}"); then
    fail "music target helper failed for duplicate GDK monitor models"
elif [[ "${duplicate_screen}" != "7" ]]; then
    fail "music target helper did not use the resolved GDK monitor index"
fi

/usr/bin/sleep 30 &
screen_owner_pid=$!
: > "${FAKE_EWW_LOG}"
rm -f -- "${screen_layer_flag}" "${screen_open_count}"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${screen_owner_pid}" \
    FAKE_EWW_LAYER_FLAG="${screen_layer_flag}" \
    FAKE_HYPRCTL_MONITORS_JSON="${screen_monitors}" \
    FAKE_HYPRCTL_CURSORPOS_JSON='{"x":2500,"y":1200}' \
    EWW_LAYER_SETTLE_ATTEMPTS=2 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash "${ROOT}/config/eww/scripts/toggle.sh" \
    || fail "music toggle failed while selecting the monitor under the cursor"
grep -Fqx -- "-c ${fake_home}/.config/eww open music --screen 7" "${FAKE_EWW_LOG}" \
    || fail "music popup did not prefer the transformed monitor under the cursor over the focused monitor"
rm -f -- "${screen_layer_flag}"

: > "${FAKE_EWW_LOG}"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${screen_owner_pid}" \
    FAKE_EWW_LAYER_FLAG="${screen_layer_flag}" \
    FAKE_HYPRCTL_MONITORS_JSON='[{"id":0,"name":"HDMI-A-1","model":"SAMSUNG","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},{"id":1,"name":"DP-1","model":"P27FBB-RGGL","focused":false,"x":1920,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}]' \
    FAKE_HYPRCTL_CURSORPOS_JSON='{invalid-json' \
    EWW_LAYER_SETTLE_ATTEMPTS=2 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash "${ROOT}/config/eww/scripts/toggle.sh" \
    || fail "music toggle failed while falling back to the focused monitor"
grep -Fqx -- "-c ${fake_home}/.config/eww open music --screen 4" "${FAKE_EWW_LOG}" \
    || fail "music popup did not fall back to the focused monitor after invalid cursor data"
rm -f -- "${screen_layer_flag}"

: > "${FAKE_EWW_LOG}"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${screen_owner_pid}" \
    FAKE_EWW_LAYER_FLAG="${screen_layer_flag}" \
    FAKE_HYPRCTL_MONITORS_FAIL=1 \
    EWW_LAYER_SETTLE_ATTEMPTS=2 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash "${ROOT}/config/eww/scripts/toggle.sh" \
    || fail "music toggle failed when monitor discovery was unavailable"
grep -Fqx -- "-c ${fake_home}/.config/eww open music" "${FAKE_EWW_LOG}" \
    || fail "music popup did not gracefully open without a screen after monitor discovery failed"
rm -f -- "${screen_layer_flag}"

: > "${FAKE_EWW_LOG}"
rm -f -- "${screen_open_count}"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${screen_owner_pid}" \
    FAKE_EWW_LAYER_FLAG="${screen_layer_flag}" \
    FAKE_EWW_OPEN_COUNT_FILE="${screen_open_count}" \
    FAKE_EWW_OPEN_SUCCEEDS_AFTER=2 \
    FAKE_HYPRCTL_MONITORS_JSON="${screen_monitors}" \
    FAKE_HYPRCTL_CURSORPOS_JSON='{"x":2500,"y":1200}' \
    EWW_LAYER_SETTLE_ATTEMPTS=1 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash "${ROOT}/config/eww/scripts/toggle.sh" \
    || fail "music toggle did not recover after its first open attempt failed"
[[ $(grep -Fxc -- "-c ${fake_home}/.config/eww open music --screen 7" "${FAKE_EWW_LOG}") -eq 2 ]] \
    || fail "music popup lost its target screen while retrying after an Eww restart"
rm -f -- "${screen_layer_flag}"
kill "${screen_owner_pid}" 2>/dev/null || true
wait "${screen_owner_pid}" 2>/dev/null || true
screen_owner_pid=""

: > "${FAKE_HYPRCTL_LOG}"
if HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_HYPRCTL_LAYERS_FAIL=1 \
    EWW_LAYER_SETTLE_ATTEMPTS=1 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash -c 'source "$1"; eww_close_music_overlay' bash "${EWW_OVERLAY}"; then
    fail "music cleanup reports success when layer validation is unavailable"
fi
! grep -Fq 'keyword unbind ,ESCAPE' "${FAKE_HYPRCTL_LOG}" \
    || fail "music cleanup unbinds recovery Escape after failed layer validation"

: > "${FAKE_HYPRCTL_LOG}"
if HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_HYPRCTL_LAYERS_INVALID=1 \
    EWW_LAYER_SETTLE_ATTEMPTS=1 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash -c 'source "$1"; eww_close_music_overlay' bash "${EWW_OVERLAY}"; then
    fail "music cleanup reports success for malformed layer JSON"
fi
! grep -Fq 'keyword unbind ,ESCAPE' "${FAKE_HYPRCTL_LOG}" \
    || fail "music cleanup unbinds recovery Escape after malformed layer JSON"

bind_layer_flag="${test_tmp}/bind-layer-open"
/usr/bin/sleep 30 &
bind_owner_pid=$!
: > "${FAKE_EWW_LOG}"
: > "${FAKE_HYPRCTL_LOG}"
if HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    FAKE_EWW_LAYER_PID="${bind_owner_pid}" \
    FAKE_EWW_LAYER_FLAG="${bind_layer_flag}" \
    FAKE_HYPRCTL_BIND_FAIL=1 \
    EWW_LAYER_SETTLE_ATTEMPTS=2 EWW_LAYER_SETTLE_DELAY=0.01 \
    bash "${ROOT}/config/eww/scripts/toggle.sh"; then
    fail "music toggle reports success after Escape binding failed"
fi
[[ ! -e "${bind_layer_flag}" ]] \
    || fail "music popup remained open after Escape binding failed"
[[ $(grep -cE '(^| )close music( |$)' "${FAKE_EWW_LOG}") -ge 2 ]] \
    || fail "Escape bind failure did not execute rollback cleanup"
kill "${bind_owner_pid}" 2>/dev/null || true
wait "${bind_owner_pid}" 2>/dev/null || true
bind_owner_pid=""

music_lock="${fake_home}/.cache/eww-music.lock"
music_lock_held="${test_tmp}/music-lock-held"
bash -c '
    exec 9>"$1"
    flock 9
    : > "$2"
    sleep 3.2
' bash "${music_lock}" "${music_lock_held}" &
music_holder_pid=$!
wait_for_file "${music_lock_held}" \
    || fail "music lock holder did not start"

: > "${FAKE_HYPRCTL_LOG}"
HOME="${fake_home}" PATH="${fake_bin}:/usr/bin:/bin" \
    bash "${ROOT}/config/eww/scripts/close.sh" &
music_close_pid=$!
wait "${music_holder_pid}"
music_holder_pid=""
if ! wait "${music_close_pid}"; then
    fail "music close gave up while waiting for an in-progress toggle"
fi
music_close_pid=""
grep -Fq 'keyword unbind ,ESCAPE' "${FAKE_HYPRCTL_LOG}" \
    || fail "pending music close did not execute after the toggle released its lock"
! grep -Fq '(defwindow backdrop' "${ROOT}/config/eww/eww.yuck" \
    || fail "fullscreen daemon-owned music backdrop still exists"
! grep -Eq 'open-many[[:space:]]+music[[:space:]]+backdrop|close[[:space:]]+music[[:space:]]+backdrop' \
    "${ROOT}/config/eww/scripts/toggle.sh" \
    "${ROOT}/config/eww/scripts/close.sh" \
    "${EWW_OVERLAY}" \
    || fail "music lifecycle still manages the removed fullscreen backdrop"

printf 'modal menu contract: ok\n'
