#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/install.sh"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "${TEST_TMP}"' EXIT

source "${INSTALLER}"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

run_fixture() (
    local scenario="$1"
    local case_dir="${TEST_TMP}/${scenario}"

    mkdir -p "${case_dir}"

    DOTFILES_FSTAB_PATH="${case_dir}/fstab"
    DOTFILES_SWAP_DIR="${case_dir}/swap"
    DOTFILES_MEMINFO_PATH="${case_dir}/meminfo"
    EVENT_LOG="${case_dir}/events"

    printf '# fixture fstab\n' > "${DOTFILES_FSTAB_PATH}"
    printf 'MemTotal:       8388608 kB\n' > "${DOTFILES_MEMINFO_PATH}"
    : > "${EVENT_LOG}"

    ROOT_FSTYPE=btrfs
    ROOT_SOURCE=/dev/test-root
    ROOT_UUID=1111-2222
    SWAP_MOUNT_UUID="${ROOT_UUID}"
    BTRFS_MKSWAP_AVAILABLE=1
    TOP_SWAP_STATE=missing
    TOP_MOUNT_DIR=
    SWAP_MOUNTED=0
    SWAP_MOUNT_FSTYPE=btrfs
    SWAP_MOUNT_OPTIONS=rw,noatime,subvol=/@swap
    ACTIVE_SWAP=
    MKSWAPFILE_FAIL=0
    SWAPON_FAIL=0
    MAP_SWAPFILE_FAIL=0
    FSTAB_VERIFY_FAIL=0
    FSTAB_ROOT_ONLY=0
    FSTAB_EDIT_BEFORE_SNAPSHOT=0
    FSTAB_SNAPSHOT_EDIT_DONE=0
    CONCURRENT_FSTAB_EDIT_BEFORE_COMMIT=0
    INSTALL_FAIL=0
    MV_FAIL=0
    MV_FAIL_ON_OPERATION=0
    MV_SEND_TERM=0
    MV_OPERATION_COUNT=0
    SWAPON_SEND_TERM=0

    record() {
        printf '%s\n' "$*" >> "${EVENT_LOG}"
    }

    _touches_fstab() {
        local arg
        for arg in "$@"; do
            if [[ "${arg}" == "${DOTFILES_FSTAB_PATH}" ||
                "${arg}" == "${DOTFILES_FSTAB_PATH}."* ]]; then
                return 0
            fi
        done
        return 1
    }

    _require_fstab_privilege() {
        if [[ "${FSTAB_ROOT_ONLY}" -eq 1 && "${DOTFILES_FAKE_SUDO:-0}" -ne 1 ]] &&
            _touches_fstab "$@"; then
            return 13
        fi
        return 0
    }

    awk() {
        _require_fstab_privilege "$@" || return $?
        command awk "$@"
    }

    cat() {
        _require_fstab_privilege "$@" || return $?
        if [[ "${FSTAB_EDIT_BEFORE_SNAPSHOT}" -eq 1 &&
            "${FSTAB_SNAPSHOT_EDIT_DONE}" -eq 0 &&
            "${DOTFILES_FAKE_SUDO:-0}" -eq 1 ]] &&
            _touches_fstab "$@"; then
            printf '%s\n' "$(canonical_mount_entry)" >> "${DOTFILES_FSTAB_PATH}"
            FSTAB_SNAPSHOT_EDIT_DONE=1
        fi
        command cat "$@"
    }

    cp() {
        _require_fstab_privilege "$@" || return $?
        command cp "$@"
    }

    cmp() {
        _require_fstab_privilege "$@" || return $?
        command cmp "$@"
    }

    tee() {
        _require_fstab_privilege "$@" || return $?
        command tee "$@"
    }

    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    print_error() { :; }
    ask_confirmation() { return 0; }
    command_exists() { [[ "$1" == btrfs ]]; }

    sudo() {
        local arg
        record "sudo $*"
        for arg in "$@"; do
            case "${arg}" in
                /etc/fstab|/etc/fstab.*|/swap|/swap/*)
                    record "blocked live path: ${arg}"
                    return 97
                    ;;
            esac
        done
        DOTFILES_FAKE_SUDO=1 "$@"
    }

    findmnt() {
        if [[ "$*" == "-no FSTYPE /" ]]; then
            printf '%s\n' "${ROOT_FSTYPE}"
            return 0
        fi
        if [[ "$*" == "-no SOURCE /" ]]; then
            printf '%s\n' "${ROOT_SOURCE}"
            return 0
        fi
        if [[ "$*" == "-no UUID /" ]]; then
            printf '%s\n' "${ROOT_UUID}"
            return 0
        fi
        if [[ "$#" -eq 4 && "$1" == "-no" && "$2" == "FSTYPE" && "$3" == "--target" && "$4" == "${DOTFILES_SWAP_DIR}" ]]; then
            printf '%s\n' "${SWAP_MOUNT_FSTYPE}"
            return 0
        fi
        if [[ "$#" -eq 4 && "$1" == "-no" && "$2" == "OPTIONS" && "$3" == "--target" && "$4" == "${DOTFILES_SWAP_DIR}" ]]; then
            printf '%s\n' "${SWAP_MOUNT_OPTIONS}"
            return 0
        fi
        if [[ "$#" -eq 4 && "$1" == "-no" && "$2" == "UUID" && "$3" == "--target" && "$4" == "${DOTFILES_SWAP_DIR}" ]]; then
            printf '%s\n' "${SWAP_MOUNT_UUID}"
            return 0
        fi
        if [[ "$#" -eq 3 && "$1" == "--verify" && "$2" == "--tab-file" ]]; then
            record "findmnt --verify --tab-file $3"
            [[ "${FSTAB_VERIFY_FAIL}" -eq 0 ]] || return 1
            return 0
        fi
        record "unexpected findmnt: $*"
        return 2
    }

    mountpoint() {
        [[ "$1" == "-q" ]] || return 1
        if [[ "$2" == "${DOTFILES_SWAP_DIR}" ]]; then
            [[ "${SWAP_MOUNTED}" -eq 1 ]]
            return
        fi
        [[ -n "${TOP_MOUNT_DIR}" && "$2" == "${TOP_MOUNT_DIR}" ]]
    }

    mount() {
        local options="$2"
        local target="${@: -1}"

        if [[ "$1" == "-o" && "${options}" == *subvolid=5* ]]; then
            TOP_MOUNT_DIR="${target}"
            case "${TOP_SWAP_STATE}" in
                valid)
                    mkdir -p "${target}/@swap"
                    : > "${target}/@swap/.fake-subvolume"
                    ;;
                regular)
                    mkdir -p "${target}/@swap"
                    ;;
            esac
            return 0
        fi

        if [[ "$1" == "-o" && "${target}" == "${DOTFILES_SWAP_DIR}" && "${options}" == *subvol=@swap* ]]; then
            mkdir -p "${target}"
            SWAP_MOUNTED=1
            SWAP_MOUNT_FSTYPE=btrfs
            SWAP_MOUNT_OPTIONS=rw,noatime,subvol=/@swap
            return 0
        fi

        return 2
    }

    umount() {
        local target="$1"

        if [[ "${target}" == "${DOTFILES_SWAP_DIR}" ]]; then
            SWAP_MOUNTED=0
            return 0
        fi
        if [[ -n "${TOP_MOUNT_DIR}" && "${target}" == "${TOP_MOUNT_DIR}" ]]; then
            command rm -rf -- "${target}/@swap"
            TOP_MOUNT_DIR=
            return 0
        fi
        return 2
    }

    btrfs() {
        if [[ "$*" == "filesystem mkswapfile --help" ]]; then
            [[ "${BTRFS_MKSWAP_AVAILABLE}" -eq 1 ]]
            return
        fi

        if [[ "$1 $2" == "subvolume show" ]]; then
            [[ -f "$3/.fake-subvolume" ]]
            return
        fi

        if [[ "$1 $2" == "subvolume create" ]]; then
            mkdir -p "$3"
            : > "$3/.fake-subvolume"
            TOP_SWAP_STATE=valid
            return 0
        fi

        if [[ "$1 $2" == "subvolume delete" ]]; then
            command rm -rf -- "$3"
            TOP_SWAP_STATE=missing
            return 0
        fi

        if [[ "$1 $2" == "filesystem mkswapfile" ]]; then
            [[ "${MKSWAPFILE_FAIL}" -eq 0 ]] || return 1
            : > "${@: -1}"
            return 0
        fi

        if [[ "$1 $2" == "inspect-internal map-swapfile" ]]; then
            [[ "${MAP_SWAPFILE_FAIL}" -eq 0 && -f "${@: -1}" ]]
            return
        fi

        return 2
    }

    swapon() {
        if [[ "$1" == "--show=NAME" ]]; then
            [[ -n "${ACTIVE_SWAP}" ]] && printf '%s\n' "${ACTIVE_SWAP}"
            return 0
        fi

        [[ "${SWAPON_FAIL}" -eq 0 ]] || return 1
        ACTIVE_SWAP="$1"
        if [[ "${SWAPON_SEND_TERM}" -eq 1 ]]; then
            kill -TERM "${BASHPID}"
        fi
    }

    swapoff() {
        [[ "$1" == "${ACTIVE_SWAP}" ]] || return 1
        ACTIVE_SWAP=
    }

    install() {
        [[ "${INSTALL_FAIL}" -eq 0 ]] || return 1
        command install "$@"
    }

    mv() {
        local source target exchange_tmp status

        _require_fstab_privilege "$@" || return $?
        [[ "${MV_FAIL}" -eq 0 ]] || return 1
        if [[ "$1" == "--exchange" ]]; then
            (( MV_OPERATION_COUNT += 1 ))
            if [[ "${MV_FAIL_ON_OPERATION}" -eq "${MV_OPERATION_COUNT}" ]]; then
                return 1
            fi
            source="${@: -2:1}"
            target="${@: -1}"
            if [[ "${CONCURRENT_FSTAB_EDIT_BEFORE_COMMIT}" -eq 1 &&
                "${MV_OPERATION_COUNT}" -eq 1 ]]; then
                printf '# external concurrent marker\n' >> "${target}"
            fi

            exchange_tmp="${case_dir}/exchange.${MV_OPERATION_COUNT}"
            command mv -- "${source}" "${exchange_tmp}" || return 1
            command mv -- "${target}" "${source}" || return 1
            command mv -- "${exchange_tmp}" "${target}" || return 1

            if [[ "${MV_SEND_TERM}" -eq 1 && "${MV_OPERATION_COUNT}" -eq 1 ]]; then
                kill -TERM "${BASHPID}"
            fi
            return 0
        fi

        (( MV_OPERATION_COUNT += 1 ))
        if [[ "${MV_FAIL_ON_OPERATION}" -eq "${MV_OPERATION_COUNT}" ]]; then
            return 1
        fi
        source="${@: -2:1}"
        target="${@: -1}"
        if [[ "${CONCURRENT_FSTAB_EDIT_BEFORE_COMMIT}" -eq 1 &&
            "${MV_OPERATION_COUNT}" -eq 1 ]]; then
            printf '# external concurrent marker\n' >> "${target}"
        fi
        command mv "$@"
        status=$?
        if [[ "${status}" -eq 0 && "${MV_SEND_TERM}" -eq 1 &&
            "${MV_OPERATION_COUNT}" -eq 1 ]]; then
            kill -TERM "${BASHPID}"
        fi
        return "${status}"
    }

    canonical_mount_entry() {
        printf 'UUID=%s %s btrfs noatime,subvol=@swap 0 0' \
            "${ROOT_UUID}" "${DOTFILES_SWAP_DIR}"
    }

    canonical_swap_entry() {
        printf '%s none swap defaults 0 0' "${DOTFILES_SWAP_DIR}/swapfile"
    }

    assert_fstab_entry_once() {
        local entry="$1"
        local count
        count=$(grep -Fxc "${entry}" "${DOTFILES_FSTAB_PATH}" || true)
        [[ "${count}" -eq 1 ]] || fail "expected one fstab entry: ${entry}; got ${count}"
    }

    assert_fstab_targets_once() {
        local mount_count swap_count
        mount_count=$(awk -v dir="${DOTFILES_SWAP_DIR}" '$2 == dir { count++ } END { print count + 0 }' \
            "${DOTFILES_FSTAB_PATH}")
        swap_count=$(awk -v file="${DOTFILES_SWAP_DIR}/swapfile" '$1 == file { count++ } END { print count + 0 }' \
            "${DOTFILES_FSTAB_PATH}")
        [[ "${mount_count}" -eq 1 ]] || fail "expected one fstab mount target; got ${mount_count}"
        [[ "${swap_count}" -eq 1 ]] || fail "expected one fstab swap target; got ${swap_count}"
    }

    assert_log_contains() {
        grep -Fq "$1" "${EVENT_LOG}" || fail "event log is missing: $1"
    }

    assert_log_absent() {
        ! grep -Fq "$1" "${EVENT_LOG}" || fail "event log unexpectedly contains: $1"
    }

    log_count() {
        grep -Fc "$1" "${EVENT_LOG}" || true
    }

    assert_ordered() {
        local previous=0 needle line
        for needle in "$@"; do
            line=$(grep -nF "${needle}" "${EVENT_LOG}" | head -1 | cut -d: -f1)
            [[ -n "${line}" ]] || fail "ordered event is missing: ${needle}"
            (( line > previous )) || fail "event is out of order: ${needle}"
            previous="${line}"
        done
    }

    seed_existing_swap() {
        mkdir -p "${DOTFILES_SWAP_DIR}"
        : > "${DOTFILES_SWAP_DIR}/swapfile"
        TOP_SWAP_STATE=valid
        SWAP_MOUNTED=1
        SWAP_MOUNT_FSTYPE=btrfs
        SWAP_MOUNT_OPTIONS=rw,noatime,subvol=/@swap
        ACTIVE_SWAP="${DOTFILES_SWAP_DIR}/swapfile"
    }

    invoke_setup() {
        setup_btrfs_swap <<< ""
    }

    test_success_ordering() {
        local original_int_trap original_term_trap
        trap 'record "original INT trap"' INT
        trap 'record "original TERM trap"' TERM
        original_int_trap=$(trap -p INT)
        original_term_trap=$(trap -p TERM)

        invoke_setup || fail "fresh setup failed"

        assert_ordered \
            "sudo mount -o noatime,subvol=@swap ${ROOT_SOURCE} ${DOTFILES_SWAP_DIR}" \
            "sudo btrfs filesystem mkswapfile --size" \
            "sudo swapon ${DOTFILES_SWAP_DIR}/swapfile" \
            "findmnt --verify --tab-file" \
            "sudo cp --preserve=all -- ${DOTFILES_FSTAB_PATH} ${DOTFILES_FSTAB_PATH}.dotfiles." \
            "sudo tee ${DOTFILES_FSTAB_PATH}.dotfiles." \
            "sudo mv --exchange --no-copy -- "
        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        [[ "${ACTIVE_SWAP}" == "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "fresh swapfile is not active"
        [[ "$(trap -p INT)" == "${original_int_trap}" ]] \
            || fail "setup did not restore the original INT trap"
        [[ "$(trap -p TERM)" == "${original_term_trap}" ]] \
            || fail "setup did not restore the original TERM trap"
        assert_log_absent "sudo swapoff "
    }

    test_mkswapfile_failure_rolls_back() {
        local before="${case_dir}/fstab.before"
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"
        MKSWAPFILE_FAIL=1

        if invoke_setup; then
            fail "mkswapfile failure unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after mkswapfile failure"
        assert_log_contains "sudo btrfs subvolume delete "
        assert_log_contains "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_contains "sudo rmdir ${DOTFILES_SWAP_DIR}"
        assert_log_absent "sudo swapon "
    }

    test_swapon_failure_rolls_back() {
        local before="${case_dir}/fstab.before"
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"
        SWAPON_FAIL=1

        if invoke_setup; then
            fail "swapon failure unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after swapon failure"
        assert_log_contains "sudo swapon ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_contains "sudo btrfs subvolume delete "
    }

    test_fstab_commit_failure_rolls_back() {
        local before="${case_dir}/fstab.before"
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"
        MV_FAIL=1

        if invoke_setup; then
            fail "fstab commit failure unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after commit failure"
        assert_log_contains "sudo swapon ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_contains "sudo btrfs subvolume delete "
        assert_log_contains "sudo cp --preserve=all -- "
        assert_log_contains "sudo tee "
        assert_log_contains "sudo mv "
    }

    test_fstab_validation_failure_rolls_back() {
        local before="${case_dir}/fstab.before"
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"
        FSTAB_VERIFY_FAIL=1

        if invoke_setup; then
            fail "fstab validation failure unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after validation failure"
        assert_log_contains "findmnt --verify --tab-file"
        assert_log_contains "sudo swapon ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_contains "sudo btrfs subvolume delete "
        assert_log_absent "sudo cp --preserve=all -- "
    }

    test_idempotent_rerun_has_no_duplicates() {
        local first_swapon_count first_commit_count
        invoke_setup || fail "first idempotency setup failed"
        first_swapon_count=$(log_count "sudo swapon ")
        first_commit_count=$(log_count "sudo cp --preserve=all -- ")

        invoke_setup || fail "second idempotency setup failed"

        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        [[ "$(log_count "sudo swapon ")" -eq "${first_swapon_count}" ]] \
            || fail "idempotent rerun called swapon again"
        [[ "$(log_count "sudo cp --preserve=all -- ")" -eq "${first_commit_count}" ]] \
            || fail "idempotent rerun committed fstab again"
    }

    test_active_swap_repairs_missing_fstab() {
        seed_existing_swap

        invoke_setup || fail "active swap fstab repair failed"

        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        [[ -f "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "existing swapfile was removed during repair"
        [[ "${ACTIVE_SWAP}" == "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "existing active swap was disabled during repair"
        assert_log_absent "sudo swapon "
        assert_log_absent "sudo swapoff "
        assert_log_contains "sudo cp --preserve=all -- "
        assert_log_contains "sudo tee "
        assert_log_contains "sudo mv "
    }

    test_mounted_swap_with_wrong_uuid_is_rejected() {
        local before="${case_dir}/fstab.before"
        seed_existing_swap
        SWAP_MOUNT_UUID=9999-aaaa
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"

        if invoke_setup; then
            fail "mounted swap from the wrong UUID unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after mounted UUID preflight failure"
        assert_log_contains "sudo awk "
        assert_log_absent "sudo mount "
        assert_log_absent "sudo swapon "
        assert_log_absent "sudo cp "
        assert_log_absent "sudo tee "
        assert_log_absent "sudo mv "
    }

    test_existing_active_swap_survives_commit_failure() {
        local before="${case_dir}/fstab.before"
        seed_existing_swap
        MV_FAIL=1
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"

        if invoke_setup; then
            fail "existing active swap repair commit failure unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after existing swap repair commit failure"
        [[ "${ACTIVE_SWAP}" == "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "existing active swap was disabled after commit failure"
        [[ -f "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "existing swapfile was removed after commit failure"
        [[ "${SWAP_MOUNTED}" -eq 1 ]] \
            || fail "existing swap mount was removed after commit failure"
        assert_log_absent "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_absent "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_absent "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_absent "sudo btrfs subvolume delete "
    }

    test_term_after_swapon_rolls_back() {
        local before="${case_dir}/fstab.before"
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"
        SWAPON_SEND_TERM=1

        if ( invoke_setup ); then
            fail "TERM after swapon unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed after TERM"
        assert_log_contains "sudo swapon ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_contains "sudo btrfs subvolume delete "
    }

    test_fstab_mode_is_preserved() {
        chmod 0600 "${DOTFILES_FSTAB_PATH}"

        invoke_setup || fail "metadata-preserving setup failed"

        [[ "$(stat -c '%a' "${DOTFILES_FSTAB_PATH}")" == "600" ]] \
            || fail "fstab mode was not preserved"
        assert_log_contains "sudo cp --preserve=all -- "
        assert_log_contains "sudo tee "
    }

    test_root_only_fstab_is_supported() {
        FSTAB_ROOT_ONLY=1

        if ! invoke_setup; then
            FSTAB_ROOT_ONLY=0
            fail "root-only fstab setup failed"
        fi
        FSTAB_ROOT_ONLY=0

        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        assert_log_contains "sudo awk "
        assert_log_contains "sudo cat -- ${DOTFILES_FSTAB_PATH}"
        assert_log_contains "sudo cmp -s "
        assert_log_contains "sudo mv --exchange --no-copy -- "
        assert_log_absent "sudo swapoff "
    }

    test_snapshot_state_avoids_duplicate_entries() {
        FSTAB_EDIT_BEFORE_SNAPSHOT=1

        invoke_setup || fail "setup failed after fstab changed before its snapshot"

        assert_fstab_targets_once
        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        assert_log_absent "sudo swapoff "
    }

    test_concurrent_fstab_edit_is_preserved() {
        CONCURRENT_FSTAB_EDIT_BEFORE_COMMIT=1

        if invoke_setup; then
            fail "concurrent fstab edit unexpectedly committed"
        fi

        grep -Fq '# external concurrent marker' "${DOTFILES_FSTAB_PATH}" \
            || fail "concurrent fstab marker was overwritten"
        assert_log_contains "findmnt --verify --tab-file"
        assert_log_contains "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_contains "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_contains "sudo btrfs subvolume delete "
        [[ "$(log_count "sudo mv --exchange --no-copy -- ")" -eq 2 ]] \
            || fail "concurrent edit was not restored with a second atomic exchange"
    }

    test_term_after_fstab_exchange_keeps_committed_state() {
        MV_SEND_TERM=1

        invoke_setup || fail "TERM during fstab exchange broke the committed setup"

        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        [[ "${ACTIVE_SWAP}" == "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "swap was disabled after the fstab exchange"
        assert_log_contains "sudo mv --exchange --no-copy -- "
        assert_log_absent "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_absent "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
    }

    test_exchange_back_failure_preserves_recovery_state() {
        local recovery_stage
        CONCURRENT_FSTAB_EDIT_BEFORE_COMMIT=1
        MV_FAIL_ON_OPERATION=2

        if invoke_setup; then
            fail "failed exchange-back unexpectedly reported success"
        fi

        assert_fstab_entry_once "$(canonical_mount_entry)"
        assert_fstab_entry_once "$(canonical_swap_entry)"
        recovery_stage=$(find "${case_dir}" -maxdepth 1 -type f \
            -name 'fstab.dotfiles.*' -print -quit)
        [[ -n "${recovery_stage}" ]] || fail "displaced fstab recovery file was removed"
        grep -Fq '# external concurrent marker' "${recovery_stage}" \
            || fail "recovery file does not contain the displaced external edit"
        [[ "${ACTIVE_SWAP}" == "${DOTFILES_SWAP_DIR}/swapfile" ]] \
            || fail "swap was disabled while its fstab candidate remained live"
        [[ "$(log_count "sudo mv --exchange --no-copy -- ")" -eq 2 ]] \
            || fail "exchange-back failure was not exercised"
        assert_log_absent "sudo swapoff ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_absent "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
        assert_log_absent "sudo umount ${DOTFILES_SWAP_DIR}"
    }

    test_invalid_existing_swapfile_is_preserved() {
        local before="${case_dir}/fstab.before"
        seed_existing_swap
        MAP_SWAPFILE_FAIL=1
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"

        if invoke_setup; then
            fail "invalid existing swapfile unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "fstab changed for invalid existing swapfile"
        [[ -f "${DOTFILES_SWAP_DIR}/swapfile" && "${SWAP_MOUNTED}" -eq 1 ]] \
            || fail "invalid existing swap resources were removed"
        assert_log_absent "sudo swapoff "
        assert_log_absent "sudo umount ${DOTFILES_SWAP_DIR}"
        assert_log_absent "sudo rm -f -- ${DOTFILES_SWAP_DIR}/swapfile"
    }

    test_conflicting_fstab_is_rejected() {
        local before="${case_dir}/fstab.before"
        printf 'UUID=other %s btrfs defaults 0 0\n' "${DOTFILES_SWAP_DIR}" \
            >> "${DOTFILES_FSTAB_PATH}"
        cp -- "${DOTFILES_FSTAB_PATH}" "${before}"

        if invoke_setup; then
            fail "conflicting fstab unexpectedly succeeded"
        fi

        cmp -s "${before}" "${DOTFILES_FSTAB_PATH}" \
            || fail "conflicting fstab was overwritten"
        assert_log_contains "sudo awk "
        assert_log_absent "sudo mount "
        assert_log_absent "sudo swapon "
        assert_log_absent "sudo cp "
        assert_log_absent "sudo tee "
        assert_log_absent "sudo mv "
    }

    "${scenario}"
)

tests=(
    test_success_ordering
    test_mkswapfile_failure_rolls_back
    test_swapon_failure_rolls_back
    test_fstab_commit_failure_rolls_back
    test_fstab_validation_failure_rolls_back
    test_idempotent_rerun_has_no_duplicates
    test_active_swap_repairs_missing_fstab
    test_mounted_swap_with_wrong_uuid_is_rejected
    test_existing_active_swap_survives_commit_failure
    test_term_after_swapon_rolls_back
    test_fstab_mode_is_preserved
    test_root_only_fstab_is_supported
    test_snapshot_state_avoids_duplicate_entries
    test_concurrent_fstab_edit_is_preserved
    test_term_after_fstab_exchange_keeps_committed_state
    test_exchange_back_failure_preserves_recovery_state
    test_invalid_existing_swapfile_is_preserved
    test_conflicting_fstab_is_rejected
)

for test_name in "${tests[@]}"; do
    if [[ -n "${TEST_FILTER:-}" && "${test_name}" != "${TEST_FILTER}" ]]; then
        continue
    fi
    if output=$(run_fixture "${test_name}" 2>&1); then
        printf 'ok - %s\n' "${test_name}"
    else
        printf '%s\n' "${output}" >&2
        fail "${test_name}"
    fi
done

printf 'btrfs swap transaction: ok\n'
