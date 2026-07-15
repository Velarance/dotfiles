#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/install.sh"
WLOGOUT_LAYOUT="${ROOT}/config/wlogout/layout"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "${TEST_TMP}"' EXIT

source "${INSTALLER}"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

new_fixture() {
    local name="$1"
    CASE_DIR="${TEST_TMP}/${name}"
    DOTFILES_EFI_PATH="${CASE_DIR}/efi"
    DOTFILES_MKINITCPIO_CONFIG="${CASE_DIR}/mkinitcpio.conf"
    EVENT_LOG="${CASE_DIR}/events"
    BUSCTL_OUTPUT='s "yes"'
    BUSCTL_STATUS=0

    mkdir -p "${DOTFILES_EFI_PATH}"
    printf 'HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)\n' \
        > "${DOTFILES_MKINITCPIO_CONFIG}"
    : > "${EVENT_LOG}"
}

print_success() {
    printf 'success:%s\n' "$1" >> "${EVENT_LOG}"
}

print_warning() {
    printf 'warning:%s\n' "$1" >> "${EVENT_LOG}"
}

busctl() {
    printf 'busctl %s\n' "$*" >> "${EVENT_LOG}"
    if [[ "${BUSCTL_STATUS}" -ne 0 ]]; then
        return "${BUSCTL_STATUS}"
    fi
    printf '%s\n' "${BUSCTL_OUTPUT}"
}

run_check_nonfatally() {
    check_manual_hibernation \
        || fail "check_manual_hibernation returned nonzero"
}

assert_log_contains() {
    local expected="$1"
    grep -Fq "${expected}" "${EVENT_LOG}" \
        || fail "event log is missing: ${expected}"
}

assert_busctl_call_once() {
    local expected='busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate'
    local count
    count=$(grep -Fxc "${expected}" "${EVENT_LOG}" || true)
    [[ "${count}" -eq 1 ]] \
        || fail "expected one exact login1 CanHibernate call; got ${count}"
}

assert_busctl_not_called() {
    ! grep -Fq 'busctl call ' "${EVENT_LOG}" \
        || fail "busctl was called for an unsupported preflight"
}

test_yes_is_supported() (
    new_fixture yes
    BUSCTL_OUTPUT='s "yes"'

    run_check_nonfatally

    assert_busctl_call_once
    assert_log_contains 'success:Manual hibernation is available via Wlogout'
    ! grep -Fq 'warning:' "${EVENT_LOG}" \
        || fail "yes result produced a warning"
)

test_challenge_is_supported() (
    new_fixture challenge
    BUSCTL_OUTPUT='s "challenge"'

    run_check_nonfatally

    assert_busctl_call_once
    assert_log_contains 'success:Manual hibernation is available via Wlogout'
    ! grep -Fq 'warning:' "${EVENT_LOG}" \
        || fail "challenge result produced a warning"
)

test_missing_efi_warns_without_busctl() (
    new_fixture missing-efi
    rmdir "${DOTFILES_EFI_PATH}"

    run_check_nonfatally

    assert_log_contains 'warning:'
    assert_log_contains 'UEFI'
    assert_busctl_not_called
)

test_missing_mkinitcpio_config_warns_without_busctl() (
    new_fixture missing-config
    rm -- "${DOTFILES_MKINITCPIO_CONFIG}"

    run_check_nonfatally

    assert_log_contains 'warning:'
    assert_log_contains 'mkinitcpio.conf'
    assert_busctl_not_called
)

test_missing_exact_systemd_hook_warns_without_busctl() (
    new_fixture missing-systemd-hook
    cat > "${DOTFILES_MKINITCPIO_CONFIG}" <<'EOF'
# HOOKS=(base systemd autodetect)
HOOKS=(base systemd-udevd autodetect modconf block filesystems fsck)
EOF

    run_check_nonfatally

    assert_log_contains 'warning:'
    assert_log_contains 'systemd hook'
    assert_busctl_not_called
)

test_last_hooks_assignment_wins() (
    new_fixture last-hooks-assignment
    cat > "${DOTFILES_MKINITCPIO_CONFIG}" <<'EOF'
HOOKS=(base systemd autodetect block filesystems)
HOOKS=(base udev autodetect block filesystems)
EOF

    run_check_nonfatally

    assert_log_contains 'warning:'
    assert_log_contains 'systemd hook'
    assert_busctl_not_called
)

test_missing_busctl_warns() (
    new_fixture missing-busctl
    command_exists() {
        [[ "$1" != busctl ]]
    }

    run_check_nonfatally

    assert_log_contains 'warning:'
    assert_log_contains 'busctl'
    assert_busctl_not_called
)

test_login1_no_warns() (
    new_fixture login1-no
    BUSCTL_OUTPUT='s "no"'

    run_check_nonfatally

    assert_busctl_call_once
    assert_log_contains 'warning:'
    assert_log_contains 'CanHibernate'
    ! grep -Fq 'success:' "${EVENT_LOG}" \
        || fail "login1 no result produced success"
)

test_login1_failure_warns() (
    new_fixture login1-failure
    BUSCTL_STATUS=1

    run_check_nonfatally

    assert_busctl_call_once
    assert_log_contains 'warning:'
    assert_log_contains 'CanHibernate'
    ! grep -Fq 'success:' "${EVENT_LOG}" \
        || fail "failed login1 query produced success"
)

test_yes_is_supported || fail "login1 yes classification failed"
test_challenge_is_supported || fail "login1 challenge classification failed"
test_missing_efi_warns_without_busctl || fail "missing EFI classification failed"
test_missing_mkinitcpio_config_warns_without_busctl \
    || fail "missing mkinitcpio config classification failed"
test_missing_exact_systemd_hook_warns_without_busctl \
    || fail "missing systemd hook classification failed"
test_last_hooks_assignment_wins || fail "last HOOKS assignment was not authoritative"
test_missing_busctl_warns || fail "missing busctl classification failed"
test_login1_no_warns || fail "login1 no classification failed"
test_login1_failure_warns || fail "login1 failure classification failed"

grep -Fq '"action" : "sleep 1; systemctl hibernate"' "${WLOGOUT_LAYOUT}" \
    || fail "Wlogout hibernate action must remain systemctl hibernate"

swap_call_line=$(grep -nE '^[[:space:]]+setup_btrfs_swap[[:space:]]*$' "${INSTALLER}" \
    | cut -d: -f1)
hibernate_call_line=$(grep -nE '^[[:space:]]+check_manual_hibernation[[:space:]]*$' "${INSTALLER}" \
    | cut -d: -f1)
[[ -n "${swap_call_line}" && -n "${hibernate_call_line}" ]] \
    || fail "main must call swap setup and manual hibernation verification"
(( hibernate_call_line == swap_call_line + 1 )) \
    || fail "main must check manual hibernation immediately after swap setup"

hibernation_function=$(awk '
    /^check_manual_hibernation\(\)[[:space:]]*\{/ { capture = 1 }
    capture { print }
    capture && /^}/ { exit }
' "${INSTALLER}")
[[ -n "${hibernation_function}" ]] \
    || fail "check_manual_hibernation function is missing"

if grep -Eiq '(grub-(install|mkconfig)|update-grub|resume(_offset)?=|mkinitcpio[[:space:]]+-P|bootctl[[:space:]]+(install|update)|systemctl[[:space:]]+hibernate)' \
    <<< "${hibernation_function}"; then
    fail "manual hibernation check must not mutate boot/resume state or trigger hibernation"
fi

printf 'hibernation contract: ok\n'
