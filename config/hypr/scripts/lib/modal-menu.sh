#!/usr/bin/env bash

modal_menu_lock_path() {
    if [[ -n "${DOTFILES_MODAL_MENU_LOCK:-}" ]]; then
        printf '%s\n' "${DOTFILES_MODAL_MENU_LOCK}"
        return 0
    fi

    local runtime_dir="${XDG_RUNTIME_DIR:-}"
    if [[ -z "${runtime_dir}" || ! -d "${runtime_dir}" || ! -w "${runtime_dir}" ]]; then
        runtime_dir="${XDG_CACHE_HOME:-${HOME}/.cache}"
    fi

    mkdir -p -- "${runtime_dir}" || return 1
    printf '%s/dotfiles-modal-menu.lock\n' "${runtime_dir}"
}

modal_menu_acquire() {
    [[ -z "${MODAL_MENU_LOCK_FD:-}" ]] || return 0

    local lock_path
    lock_path=$(modal_menu_lock_path) || return 1
    mkdir -p -- "$(dirname -- "${lock_path}")" || return 1

    exec {MODAL_MENU_LOCK_FD}>"${lock_path}" || return 1
    local status
    if flock -E 75 -n "${MODAL_MENU_LOCK_FD}"; then
        return 0
    else
        status=$?
        exec {MODAL_MENU_LOCK_FD}>&-
        unset MODAL_MENU_LOCK_FD
        return "${status}"
    fi
}

modal_menu_enter() {
    local status

    if modal_menu_acquire; then
        return 0
    else
        status=$?
    fi

    [[ "${status}" -eq 75 ]] && exit 0
    exit "${status}"
}

modal_menu_release() {
    [[ -n "${MODAL_MENU_LOCK_FD:-}" ]] || return 0

    flock -u "${MODAL_MENU_LOCK_FD}" 2>/dev/null || true
    exec {MODAL_MENU_LOCK_FD}>&-
    unset MODAL_MENU_LOCK_FD
}
