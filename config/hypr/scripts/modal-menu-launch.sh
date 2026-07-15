#!/usr/bin/env bash

set -u

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "${SCRIPT_DIR}" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR=.
readonly SCRIPT_DIR
source "${SCRIPT_DIR}/lib/modal-menu.sh"

[[ $# -gt 0 ]] || exit 64
modal_menu_enter
trap modal_menu_release EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

status=0
"$@" {MODAL_MENU_LOCK_FD}>&- || status=$?
exit "${status}"
