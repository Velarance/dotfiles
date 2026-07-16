#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT="${ROOT}/config/hypr/scripts/screenshot.sh"
HELPER="${ROOT}/config/hypr/scripts/lib/modal-menu.sh"

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

line_count() {
    wc -l < "$1" | tr -d '[:space:]'
}

[[ -r "${SCREENSHOT}" ]] || fail "screenshot script is missing"
[[ -r "${HELPER}" ]] || fail "shared modal-menu helper is missing"

test_tmp=$(mktemp -d)
first_pid=""
holder_pid=""
slurp_release="${test_tmp}/slurp-release"
grim_release="${test_tmp}/grim-release"
cleanup() {
    : > "${slurp_release}" 2>/dev/null || true
    : > "${grim_release}" 2>/dev/null || true
    if [[ -n "${first_pid}" ]] && kill -0 "${first_pid}" 2>/dev/null; then
        kill -TERM "${first_pid}" 2>/dev/null || true
        wait "${first_pid}" 2>/dev/null || true
    fi
    if [[ -n "${holder_pid}" ]] && kill -0 "${holder_pid}" 2>/dev/null; then
        kill -TERM "${holder_pid}" 2>/dev/null || true
        wait "${holder_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${test_tmp}"
}
trap cleanup EXIT

fake_bin="${test_tmp}/fake-bin"
fake_home="${test_tmp}/home"
runtime_dir="${test_tmp}/runtime"
mkdir -p "${fake_bin}" "${fake_home}" "${runtime_dir}"

cat > "${fake_bin}/slurp" <<'FAKE_SLURP'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$$" >> "${FAKE_SLURP_LOG}"
call_count=$(wc -l < "${FAKE_SLURP_LOG}")

if [[ "${FAKE_SLURP_CANCEL:-0}" == "1" ]]; then
    exit 1
fi
if [[ "${FAKE_SLURP_EMPTY:-0}" == "1" ]]; then
    exit 0
fi
if [[ "${FAKE_SLURP_BLOCK_FIRST:-0}" == "1" && "${call_count}" -eq 1 ]]; then
    : > "${FAKE_SLURP_READY}"
    while [[ ! -e "${FAKE_SLURP_RELEASE}" ]]; do
        sleep 0.02
    done
fi

printf '%s\n' '1,2 30x40'
FAKE_SLURP

cat > "${fake_bin}/grim" <<'FAKE_GRIM'
#!/usr/bin/env bash
set -euo pipefail

printf '<%s>' "$@" >> "${FAKE_GRIM_LOG}"
printf '\n' >> "${FAKE_GRIM_LOG}"

[[ "${1:-}" == "-g" || "${1:-}" == "-o" ]] || exit 64
[[ -n "${2:-}" ]] || exit 65

if [[ -e "${FAKE_GRIM_BLOCK_ENABLED}" ]]; then
    : > "${FAKE_GRIM_READY}"
    while [[ ! -e "${FAKE_GRIM_RELEASE}" ]]; do
        sleep 0.02
    done
fi

: > "${!#}"
FAKE_GRIM

cat > "${fake_bin}/hyprctl" <<'FAKE_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-} ${2:-}" == '-j activeworkspace' ]] || exit 64
printf '{"monitor":"TEST-1"}\n'
FAKE_HYPRCTL

cat > "${fake_bin}/wl-copy" <<'FAKE_WL_COPY'
#!/usr/bin/env bash
cat >/dev/null
FAKE_WL_COPY

cat > "${fake_bin}/notify-send" <<'FAKE_NOTIFY_SEND'
#!/usr/bin/env bash
exit 0
FAKE_NOTIFY_SEND

cat > "${fake_bin}/fake-editor" <<'FAKE_EDITOR'
#!/usr/bin/env bash
exit 0
FAKE_EDITOR

chmod +x "${fake_bin}/slurp" "${fake_bin}/grim" "${fake_bin}/hyprctl" \
    "${fake_bin}/wl-copy" "${fake_bin}/notify-send" "${fake_bin}/fake-editor"

export HOME="${fake_home}"
export PATH="${fake_bin}:/usr/bin:/bin"
export XDG_RUNTIME_DIR="${runtime_dir}"
export DOTFILES_MODAL_MENU_LOCK="${runtime_dir}/modal-menu.lock"
export SCREENSHOT_EDITOR="fake-editor"
export FAKE_SLURP_LOG="${test_tmp}/slurp.log"
export FAKE_SLURP_READY="${test_tmp}/slurp-ready"
export FAKE_SLURP_RELEASE="${slurp_release}"
export FAKE_GRIM_LOG="${test_tmp}/grim.log"
export FAKE_GRIM_BLOCK_ENABLED="${test_tmp}/grim-block-enabled"
export FAKE_GRIM_READY="${test_tmp}/grim-ready"
export FAKE_GRIM_RELEASE="${grim_release}"
: > "${FAKE_SLURP_LOG}"
: > "${FAKE_GRIM_LOG}"

FAKE_SLURP_BLOCK_FIRST=1 bash "${SCREENSHOT}" area &
first_pid=$!
wait_for_file "${FAKE_SLURP_READY}" \
    || fail "first area screenshot did not reach the blocking selector"

bash "${SCREENSHOT}" area \
    || fail "a blocked duplicate area screenshot must exit successfully"
[[ "$(line_count "${FAKE_SLURP_LOG}")" -eq 1 ]] \
    || fail "a duplicate area screenshot invoked slurp while a selector was already open"

: > "${FAKE_GRIM_BLOCK_ENABLED}"
: > "${slurp_release}"
wait_for_file "${FAKE_GRIM_READY}" \
    || fail "first area screenshot did not reach its blocking image capture"
rm -f -- "${FAKE_GRIM_BLOCK_ENABLED}"

bash "${SCREENSHOT}" area \
    || fail "area screenshot did not run after the selector resolved"
[[ "$(line_count "${FAKE_SLURP_LOG}")" -eq 2 ]] \
    || fail "modal lock was not released before the first screenshot finished processing"

: > "${grim_release}"
wait "${first_pid}" \
    || fail "first area screenshot did not complete successfully"
first_pid=""

grim_calls_before_cancel=$(line_count "${FAKE_GRIM_LOG}")
FAKE_SLURP_CANCEL=1 bash "${SCREENSHOT}" area \
    || fail "cancelled area selection must exit successfully"
[[ "$(line_count "${FAKE_GRIM_LOG}")" -eq "${grim_calls_before_cancel}" ]] \
    || fail "cancelled area selection invoked grim with an empty geometry"

grim_calls_before_empty=$(line_count "${FAKE_GRIM_LOG}")
FAKE_SLURP_EMPTY=1 bash "${SCREENSHOT}" area \
    || fail "empty area selection must exit successfully"
[[ "$(line_count "${FAKE_GRIM_LOG}")" -eq "${grim_calls_before_empty}" ]] \
    || fail "empty area selection invoked grim"

holder_started="${test_tmp}/holder-started"
holder_release="${test_tmp}/holder-release"
bash -c '
    source "$1"
    modal_menu_enter
    : > "$2"
    while [[ ! -e "$3" ]]; do sleep 0.02; done
' bash "${HELPER}" "${holder_started}" "${holder_release}" &
holder_pid=$!
wait_for_file "${holder_started}" \
    || fail "test lock holder did not acquire the shared modal lock"

bash "${SCREENSHOT}" \
    || fail "full-monitor screenshot must not be blocked by the modal selector lock"
grep -Fq '<-o><TEST-1>' "${FAKE_GRIM_LOG}" \
    || fail "full-monitor screenshot did not capture the active monitor"

: > "${holder_release}"
wait "${holder_pid}"
holder_pid=""

printf 'screenshot contract: ok\n'
