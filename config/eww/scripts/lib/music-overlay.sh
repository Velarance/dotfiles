#!/usr/bin/env bash

EWW_CONFIG="${EWW_CONFIG:-${HOME}/.config/eww}"
EWW_IPC_TIMEOUT="${EWW_IPC_TIMEOUT:-2}"
EWW_IPC_KILL_AFTER="${EWW_IPC_KILL_AFTER:-0.5}"
EWW_LAYER_SETTLE_ATTEMPTS="${EWW_LAYER_SETTLE_ATTEMPTS:-20}"
EWW_LAYER_SETTLE_DELAY="${EWW_LAYER_SETTLE_DELAY:-0.05}"

eww_ipc() {
    timeout --foreground --kill-after="${EWW_IPC_KILL_AFTER}" \
        "${EWW_IPC_TIMEOUT}" eww -c "${EWW_CONFIG}" "$@"
}

hypr_ipc() {
    timeout --foreground --kill-after="${EWW_IPC_KILL_AFTER}" \
        "${EWW_IPC_TIMEOUT}" hyprctl "$@"
}

hypr_music_target_monitor() {
    local cursor_json monitors_json target_monitor
    cursor_json=""
    cursor_json=$(hypr_ipc cursorpos -j 2>/dev/null) || cursor_json=""

    monitors_json=$(hypr_ipc monitors -j 2>/dev/null) || return 1
    jq -e 'type == "array"' <<< "${monitors_json}" >/dev/null 2>&1 || return 1

    target_monitor=""
    if [[ -n "${cursor_json}" ]]; then
        target_monitor=$(
            jq -r --argjson cursor "${cursor_json}" '
                select(type == "array")
                | $cursor as $cursor_position
                | select(
                    ($cursor_position | type) == "object"
                    and ($cursor_position.x | type) == "number"
                    and ($cursor_position.y | type) == "number"
                  )
                | [
                    .[]
                    | . as $monitor
                    | select(
                        ($monitor.name | type) == "string"
                        and $monitor.name != ""
                        and ($monitor.x | type) == "number"
                        and ($monitor.y | type) == "number"
                        and ($monitor.width | type) == "number"
                        and ($monitor.height | type) == "number"
                      )
                    | (($monitor.scale // 1) | if type == "number" then . else 0 end) as $scale
                    | (($monitor.transform // 0) | if type == "number" then . else 0 end) as $transform
                    | select($scale > 0 and $monitor.width > 0 and $monitor.height > 0)
                    | (if ($transform == 1 or $transform == 3 or $transform == 5 or $transform == 7)
                        then $monitor.height else $monitor.width end) as $pixel_width
                    | (if ($transform == 1 or $transform == 3 or $transform == 5 or $transform == 7)
                        then $monitor.width else $monitor.height end) as $pixel_height
                    | select(
                        $cursor_position.x >= $monitor.x
                        and $cursor_position.x < ($monitor.x + ($pixel_width / $scale))
                        and $cursor_position.y >= $monitor.y
                        and $cursor_position.y < ($monitor.y + ($pixel_height / $scale))
                      )
                    | $monitor.name
                  ][0] // empty
            ' <<< "${monitors_json}" 2>/dev/null
        ) || target_monitor=""
    fi

    if [[ -z "${target_monitor}" ]]; then
        target_monitor=$(
            jq -r '
                [
                    .[]
                    | select(
                        .focused == true
                        and (.name | type) == "string"
                        and .name != ""
                      )
                    | .name
                  ][0] // empty
            ' <<< "${monitors_json}" 2>/dev/null
        ) || return 1
    fi

    [[ -n "${target_monitor}" ]] || return 1
    printf '%s\n' "${target_monitor}"
}

eww_music_layer_pids() {
    local layers pids

    layers=$(hypr_ipc layers -j 2>/dev/null) || return 2
    pids=$(jq -r '
            .. | objects
            | select(
                .namespace? == "eww-music"
            )
            | .pid? // empty
        ' <<< "${layers}" 2>/dev/null) || return 2

    [[ -n "${pids}" ]] || return 0
    sort -un <<< "${pids}" || return 2
}

eww_music_overlay_visible() {
    local pids status

    pids=$(eww_music_layer_pids)
    status=$?
    ((status == 0)) || return 2
    [[ -n "${pids}" ]]
}

eww_wait_for_music_layers_to_close() {
    local attempt pids status

    for ((attempt = 0; attempt < EWW_LAYER_SETTLE_ATTEMPTS; attempt++)); do
        pids=$(eww_music_layer_pids)
        status=$?
        ((status == 0)) || return 2
        [[ -z "${pids}" ]] && return 0
        sleep "${EWW_LAYER_SETTLE_DELAY}"
    done

    printf '%s\n' "${pids}"
    return 1
}

eww_signal_music_layer_owners() {
    local pids="$1"
    local signal="$2"
    local comm pid

    while IFS= read -r pid; do
        [[ "${pid}" =~ ^[0-9]+$ ]] || continue
        [[ -r "/proc/${pid}/comm" ]] || continue
        IFS= read -r comm < "/proc/${pid}/comm" || continue
        [[ "${comm}" == "eww" ]] || continue
        kill "-${signal}" "${pid}" 2>/dev/null || true
    done <<< "${pids}"
}

eww_close_music_overlay() {
    local pids result=0 status

    eww_ipc update winopen=false >/dev/null 2>&1 || true
    eww_ipc close music >/dev/null 2>&1 || true

    pids=$(eww_wait_for_music_layers_to_close)
    status=$?
    if ((status == 1)); then
        eww_signal_music_layer_owners "${pids}" TERM
        pids=$(eww_wait_for_music_layers_to_close)
        status=$?
        if ((status == 1)); then
            eww_signal_music_layer_owners "${pids}" KILL
            eww_wait_for_music_layers_to_close >/dev/null 2>&1 || result=1
        elif ((status != 0)); then
            result=1
        fi
    elif ((status != 0)); then
        result=1
    fi

    if ((result == 0)); then
        hypr_ipc keyword unbind ,ESCAPE >/dev/null 2>&1 || true
    fi
    return "${result}"
}

eww_wait_for_music_layer_to_open() {
    local attempt status

    for ((attempt = 0; attempt < EWW_LAYER_SETTLE_ATTEMPTS; attempt++)); do
        eww_music_overlay_visible
        status=$?
        case "${status}" in
            0) return 0 ;;
            1) sleep "${EWW_LAYER_SETTLE_DELAY}" ;;
            *) return 2 ;;
        esac
    done

    return 1
}

eww_ensure_daemon() {
    local attempt

    eww_ipc ping >/dev/null 2>&1 && return 0
    eww -c "${EWW_CONFIG}" daemon 9>&- >/dev/null 2>&1 &

    for ((attempt = 0; attempt < EWW_LAYER_SETTLE_ATTEMPTS; attempt++)); do
        eww_ipc ping >/dev/null 2>&1 && return 0
        sleep "${EWW_LAYER_SETTLE_DELAY}"
    done

    return 1
}

eww_daemon_argv_matches() {
    local arg configured_path="" actual_config expected_config index=1
    local -a argv=("$@")

    ((${#argv[@]} >= 2)) || return 1
    [[ "${argv[0]##*/}" == "eww" ]] || return 1

    while ((index < ${#argv[@]})); do
        arg="${argv[index]}"
        case "${arg}" in
            -c|--config)
                [[ -z "${configured_path}" && $((index + 1)) -lt ${#argv[@]} ]] || return 1
                configured_path="${argv[index + 1]}"
                ((index += 2))
                ;;
            --config=*)
                [[ -z "${configured_path}" ]] || return 1
                configured_path="${arg#*=}"
                [[ -n "${configured_path}" ]] || return 1
                ((index++))
                ;;
            --debug|--force-wayland|--logs|--no-daemonize|--restart)
                ((index++))
                ;;
            --)
                ((index++))
                break
                ;;
            -*)
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    [[ "${argv[index]:-}" == "daemon" ]] || return 1
    ((index++))
    ((index == ${#argv[@]})) || return 1

    if [[ -n "${configured_path}" ]]; then
        expected_config=$(readlink -f -- "${EWW_CONFIG}") || return 1
        actual_config=$(readlink -f -- "${configured_path}") || return 1
        [[ "${actual_config}" == "${expected_config}" ]] || return 1
    fi
}

eww_pid_is_config_daemon() {
    local pid="$1"
    local config_path cwd
    local -a argv=()

    [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
    [[ -r "/proc/${pid}/cmdline" ]] || return 1
    mapfile -d '' -t argv < "/proc/${pid}/cmdline" || true
    eww_daemon_argv_matches "${argv[@]}" || return 1

    config_path=$(readlink -f -- "${EWW_CONFIG}") || return 1
    cwd=$(readlink -- "/proc/${pid}/cwd") || return 1
    [[ "${cwd}" == "${config_path}" || "${cwd}" == "${config_path} (deleted)" ]]
}

eww_config_daemon_pids() {
    local pid

    while IFS= read -r pid; do
        eww_pid_is_config_daemon "${pid}" && printf '%s\n' "${pid}"
    done < <(pgrep -x eww 2>/dev/null || true)
}

eww_wait_for_daemon_pids_to_exit() {
    local pids="$1"
    local alive attempt pid

    for ((attempt = 0; attempt < EWW_LAYER_SETTLE_ATTEMPTS; attempt++)); do
        alive=""
        while IFS= read -r pid; do
            [[ -n "${pid}" ]] || continue
            kill -0 "${pid}" 2>/dev/null && alive+="${pid}"$'\n'
        done <<< "${pids}"
        [[ -z "${alive}" ]] && return 0
        pids="${alive}"
        sleep "${EWW_LAYER_SETTLE_DELAY}"
    done

    printf '%s' "${alive}"
    return 1
}

eww_stop_config_daemons() {
    local pids remaining pid

    pids=$(eww_config_daemon_pids)
    [[ -n "${pids}" ]] || return 0

    while IFS= read -r pid; do
        eww_pid_is_config_daemon "${pid}" && kill -TERM "${pid}" 2>/dev/null || true
    done <<< "${pids}"

    if ! remaining=$(eww_wait_for_daemon_pids_to_exit "${pids}"); then
        while IFS= read -r pid; do
            eww_pid_is_config_daemon "${pid}" && kill -KILL "${pid}" 2>/dev/null || true
        done <<< "${remaining}"
        eww_wait_for_daemon_pids_to_exit "${remaining}" >/dev/null 2>&1 || return 1
    fi
}

eww_restart_daemon() {
    eww_ipc kill >/dev/null 2>&1 || true
    eww_stop_config_daemons || return 1
    eww -c "${EWW_CONFIG}" daemon 9>&- >/dev/null 2>&1 &

    local attempt
    for ((attempt = 0; attempt < EWW_LAYER_SETTLE_ATTEMPTS; attempt++)); do
        eww_ipc ping >/dev/null 2>&1 && return 0
        sleep "${EWW_LAYER_SETTLE_DELAY}"
    done

    return 1
}

eww_open_music_overlay_once() {
    local target_monitor="${1:-}"
    local -a open_args=(open music)

    if [[ -n "${target_monitor}" ]]; then
        open_args+=(--screen "${target_monitor}")
    fi

    eww_ensure_daemon || return 1
    eww_ipc update winopen=true >/dev/null 2>&1 || return 1
    if ! eww_ipc "${open_args[@]}" >/dev/null 2>&1; then
        eww_wait_for_music_layer_to_open && return 0
        return 1
    fi
    eww_wait_for_music_layer_to_open
}

eww_open_music_overlay() {
    local target_monitor="${1:-}"

    if eww_open_music_overlay_once "${target_monitor}"; then
        return 0
    fi

    eww_close_music_overlay || return 1
    eww_restart_daemon || return 1

    if ! eww_open_music_overlay_once "${target_monitor}"; then
        eww_close_music_overlay || true
        return 1
    fi

    return 0
}
