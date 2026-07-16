#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/steinsgrub.conf
source "${REPO_ROOT}/lib/steinsgrub.conf"
# shellcheck source=../lib/steinsgrub.sh
source "${REPO_ROOT}/lib/steinsgrub.sh"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

maybe_fail() {
    case "${DOTFILES_STEINSGRUB_FAILPOINT:-}" in
        "$1")
            return 1
            ;;
        "term-$1")
            kill -TERM "$$"
            return 1
            ;;
        "int-$1")
            kill -INT "$$"
            return 1
            ;;
    esac
}

path_is_within_root() {
    local path="$1"
    local resolved

    [[ -n "${root_prefix}" ]] || return 0
    resolved="$(realpath -e -- "${path}")" || return 1
    [[ "${resolved}" == "${root_prefix}" || "${resolved}" == "${root_prefix}/"* ]]
}

require_contained_path() {
    path_is_within_root "$1" \
        || die "path escapes DOTFILES_STEINSGRUB_ROOT: $1"
}

install_owned_file() {
    local mode="$1"
    local source="$2"
    local target="$3"

    if [[ -z "${root_prefix}" ]]; then
        install -o root -g root -m "${mode}" "${source}" "${target}"
    else
        install -m "${mode}" "${source}" "${target}"
    fi
}

install_owned_directory() {
    local mode="$1"
    local target="$2"

    if [[ -z "${root_prefix}" ]]; then
        install -d -o root -g root -m "${mode}" "${target}"
    else
        install -d -m "${mode}" "${target}"
    fi
}

root_prefix="${DOTFILES_STEINSGRUB_ROOT:-}"
root_prefix="${root_prefix%/}"
if [[ -n "${root_prefix}" ]]; then
    [[ "${root_prefix}" == /* && -d "${root_prefix}" && ! -L "${root_prefix}" ]] \
        || die "DOTFILES_STEINSGRUB_ROOT must be a real absolute directory"
    resolved_root="$(realpath -e -- "${root_prefix}")" \
        || die "could not resolve DOTFILES_STEINSGRUB_ROOT"
    [[ "${resolved_root}" == "${root_prefix}" ]] \
        || die "DOTFILES_STEINSGRUB_ROOT must be canonical and contain no symlink components"
    root_prefix="${resolved_root}"
elif [[ "${EUID}" -ne 0 ]]; then
    die "this transaction must run as root"
fi

[[ "$#" -eq 1 ]] || die "usage: $0 VALIDATED_THEME_DIR"
source_dir="$1"
manifest="${DOTFILES_STEINSGRUB_MANIFEST:-${REPO_ROOT}/lib/steinsgrub.sha256}"
theme_patch="${DOTFILES_STEINSGRUB_PATCH:-${REPO_ROOT}/lib/steinsgrub-theme.patch}"
upstream_metadata="${DOTFILES_STEINSGRUB_UPSTREAM:-${REPO_ROOT}/lib/steinsgrub-UPSTREAM}"
patched_theme_sha256="${DOTFILES_STEINSGRUB_PATCHED_THEME_SHA256:-${STEINSGRUB_PATCHED_THEME_SHA256}}"

default_grub="${root_prefix}/etc/default/grub"
grub_dir="${root_prefix}/boot/grub"
grub_cfg="${grub_dir}/grub.cfg"
grub_btrfs_cfg="${grub_dir}/grub-btrfs.cfg"
grub_btrfs_config="${root_prefix}/etc/default/grub-btrfs/config"
theme_parent="${root_prefix}/usr/share/grub/themes"
theme_target="${theme_parent}/steinsgrub"
theme_config_path="/usr/share/grub/themes/steinsgrub/theme.txt"
backup_parent="${root_prefix}/var/backups"
lock_path="${root_prefix}/var/lock/dotfiles-steinsgrub.lock"

for required_tool in \
    awk bash chmod chown cmp cp date find flock grep grub-mkconfig \
    grub-script-check install mkdir mktemp mv patch realpath rm sha256sum stat; do
    command -v "${required_tool}" >/dev/null 2>&1 \
        || die "required command is missing: ${required_tool}"
done

[[ -d "${source_dir}" && ! -L "${source_dir}" ]] || die "validated source tree is unavailable"
[[ -f "${manifest}" && ! -L "${manifest}" ]] || die "source manifest is unavailable"
[[ -f "${theme_patch}" && ! -L "${theme_patch}" ]] || die "theme patch is unavailable"
[[ -f "${upstream_metadata}" && ! -L "${upstream_metadata}" ]] || die "upstream metadata is unavailable"
[[ -f "${default_grub}" && ! -L "${default_grub}" ]] \
    || die "${default_grub} must be a regular non-symlink file"
if [[ -z "${root_prefix}" ]]; then
    steinsgrub_source_path_is_trusted "${default_grub}" 0 \
        || die "${default_grub} must be root-owned and not group/world-writable"
fi
[[ -d "${grub_dir}" && ! -L "${grub_dir}" ]] \
    || die "${grub_dir} must be a real directory"
[[ -f "${grub_cfg}" && ! -L "${grub_cfg}" ]] \
    || die "${grub_cfg} must be a regular non-symlink file"
if [[ -e "${grub_btrfs_cfg}" || -L "${grub_btrfs_cfg}" ]]; then
    [[ -f "${grub_btrfs_cfg}" && ! -L "${grub_btrfs_cfg}" ]] \
        || die "${grub_btrfs_cfg} must be a regular non-symlink file"
fi
if [[ -e "${grub_btrfs_config}" || -L "${grub_btrfs_config}" ]]; then
    [[ -f "${grub_btrfs_config}" && ! -L "${grub_btrfs_config}" ]] \
        || die "${grub_btrfs_config} must be a regular non-symlink file"
    if grep -Eq \
        '^[[:space:]]*(export[[:space:]]+)?GRUB_BTRFS_(GRUB|GBTRFS)_DIRNAME[[:space:]]*=' \
        "${grub_btrfs_config}"; then
        die "grub-btrfs config overrides transaction staging directories"
    fi
fi
[[ -d "${theme_parent}" && ! -L "${theme_parent}" ]] \
    || die "${theme_parent} must be a real directory"
if [[ -e "${theme_target}" || -L "${theme_target}" ]]; then
    [[ -d "${theme_target}" && ! -L "${theme_target}" ]] \
        || die "${theme_target} must be a real directory"
fi
[[ -d "${backup_parent}" && ! -L "${backup_parent}" ]] \
    || die "${backup_parent} must be a real directory"
lock_parent="${lock_path%/*}"
[[ -d "${lock_parent}" && ! -L "${lock_parent}" ]] \
    || die "${lock_parent} must be a real directory"

for contained_path in \
    "${default_grub}" \
    "${grub_dir}" \
    "${grub_cfg}" \
    "${theme_parent}" \
    "${backup_parent}" \
    "${lock_parent}"; do
    require_contained_path "${contained_path}"
done
if [[ -e "${grub_btrfs_cfg}" || -L "${grub_btrfs_cfg}" ]]; then
    require_contained_path "${grub_btrfs_cfg}"
fi
if [[ -e "${grub_btrfs_config}" || -L "${grub_btrfs_config}" ]]; then
    require_contained_path "${grub_btrfs_config}"
fi
if [[ -e "${theme_target}" || -L "${theme_target}" ]]; then
    require_contained_path "${theme_target}"
fi

if [[ ! -e "${lock_path}" && ! -L "${lock_path}" ]]; then
    (
        umask 077
        set -o noclobber
        : > "${lock_path}"
    ) || die "could not create the Steins;GRUB transaction lock"
fi
[[ -f "${lock_path}" && ! -L "${lock_path}" ]] \
    || die "${lock_path} must be a regular non-symlink file"
require_contained_path "${lock_path}"
exec 9<> "${lock_path}"
flock -n 9 || die "another Steins;GRUB transaction is already running"

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
backup_dir="${backup_parent}/dotfiles-steinsgrub-${stamp}"
theme_transaction="$(mktemp -d "${theme_parent}/.steinsgrub-transaction.XXXXXX")"
grub_stage="$(mktemp -d "${grub_dir}/.steinsgrub-transaction.XXXXXX")"
theme_stage="${theme_transaction}/theme"
theme_displaced="${theme_transaction}/previous-theme"
default_candidate="${theme_transaction}/default-grub"
patched_manifest="${theme_transaction}/patched.sha256"
had_theme=0
had_btrfs=0
mutation_started=0
commit_done=0

cleanup_stages() {
    [[ -n "${theme_transaction:-}" && "${theme_transaction}" == "${theme_parent}/.steinsgrub-transaction."* ]] \
        && rm -rf -- "${theme_transaction}"
    [[ -n "${grub_stage:-}" && "${grub_stage}" == "${grub_dir}/.steinsgrub-transaction."* ]] \
        && rm -rf -- "${grub_stage}"
}

rollback_transaction() {
    local rc="${1:-$?}"
    local rollback_failed=0
    trap - ERR
    trap '' INT TERM
    set +e

    if [[ "${mutation_started}" -eq 1 && "${commit_done}" -eq 0 ]]; then
        install_owned_file 0600 "${backup_dir}/grub.cfg" "${grub_cfg}.rollback" \
            && mv -f -- "${grub_cfg}.rollback" "${grub_cfg}" \
            || rollback_failed=1

        if [[ "${had_btrfs}" -eq 1 ]]; then
            install_owned_file 0644 "${backup_dir}/grub-btrfs.cfg" "${grub_btrfs_cfg}.rollback" \
                && mv -f -- "${grub_btrfs_cfg}.rollback" "${grub_btrfs_cfg}" \
                || rollback_failed=1
        else
            rm -f -- "${grub_btrfs_cfg}" "${grub_btrfs_cfg}.rollback" || rollback_failed=1
        fi

        install_owned_file 0644 "${backup_dir}/default-grub" "${default_grub}.rollback" \
            && mv -f -- "${default_grub}.rollback" "${default_grub}" \
            || rollback_failed=1

        rm -rf -- "${theme_target}" || rollback_failed=1
        if [[ "${had_theme}" -eq 1 ]]; then
            cp -a -- "${backup_dir}/theme" "${theme_target}" || rollback_failed=1
        fi

        rm -f -- \
            "${default_grub}.new" \
            "${default_grub}.rollback" \
            "${grub_btrfs_cfg}.new" \
            "${grub_btrfs_cfg}.rollback" \
            "${grub_cfg}.new" \
            "${grub_cfg}.rollback" \
            || rollback_failed=1
    fi

    cleanup_stages
    if [[ "${rollback_failed}" -eq 1 ]]; then
        warn "rollback was incomplete; recovery files remain in ${backup_dir}"
    else
        warn "transaction failed; restored the previous GRUB state from ${backup_dir}"
    fi
    exit "${rc}"
}
trap 'rollback_transaction $?' ERR
trap 'rollback_transaction 130' INT
trap 'rollback_transaction 143' TERM

mkdir -p -- "${theme_stage}"
cp -a -- "${source_dir}/." "${theme_stage}/"
validate_steinsgrub_theme_tree "${theme_stage}" "${manifest}" \
    || die "root-owned source stage failed manifest validation"

patch \
    --batch \
    --forward \
    --fuzz=0 \
    --no-backup-if-mismatch \
    -d "${theme_stage}" \
    -p1 < "${theme_patch}"

awk -v patched_sha="${patched_theme_sha256}" '
    $2 == "theme.txt" { print patched_sha "  theme.txt"; next }
    { print }
' "${manifest}" > "${patched_manifest}"
validate_steinsgrub_theme_tree "${theme_stage}" "${patched_manifest}" \
    || die "patched theme stage failed manifest validation"
install -m 0644 -- "${upstream_metadata}" "${theme_stage}/UPSTREAM"
find "${theme_stage}" -type d -exec chmod 0755 {} +
find "${theme_stage}" -type f -exec chmod 0644 {} +
if [[ -z "${root_prefix}" ]]; then
    chown -R root:root "${theme_stage}"
fi

install_owned_directory 0700 "${backup_dir}"
cp -a -- "${default_grub}" "${backup_dir}/default-grub"
cp -a -- "${grub_cfg}" "${backup_dir}/grub.cfg"
if [[ -f "${grub_btrfs_cfg}" ]]; then
    had_btrfs=1
    cp -a -- "${grub_btrfs_cfg}" "${backup_dir}/grub-btrfs.cfg"
fi
if [[ -d "${theme_target}" ]]; then
    had_theme=1
    cp -a -- "${theme_target}" "${backup_dir}/theme"
fi

write_grub_theme_config "${default_grub}" "${default_candidate}" "${theme_config_path}" \
    || die "failed to produce a GRUB defaults candidate"

mutation_started=1
if [[ "${had_theme}" -eq 1 ]]; then
    mv -- "${theme_target}" "${theme_displaced}"
fi
mv -- "${theme_stage}" "${theme_target}"
maybe_fail after-theme

install_owned_file 0644 "${default_candidate}" "${default_grub}.new"
bash -n "${default_grub}.new"
mv -f -- "${default_grub}.new" "${default_grub}"
maybe_fail after-default

env \
    GRUB_BTRFS_GRUB_DIRNAME="${grub_stage}" \
    GRUB_BTRFS_GBTRFS_DIRNAME="${grub_stage}" \
    grub-mkconfig -o "${grub_stage}/grub.cfg"
maybe_fail after-generation

staged_main="${grub_stage}/grub.cfg"
[[ -s "${staged_main}" && -f "${staged_main}" && ! -L "${staged_main}" ]] \
    || die "grub-mkconfig produced no regular main configuration"
grub-script-check "${staged_main}"
grep -Fq 'steinsgrub/theme.txt' "${staged_main}" \
    || die "generated GRUB configuration does not select Steins;GRUB"
validate_steinsgrub_kernel_arguments "${default_candidate}" "${staged_main}" \
    || die "generated GRUB configuration lost an expected kernel argument"

if grep -Fq 'Windows Boot Manager' "${backup_dir}/grub.cfg"; then
    grep -Fq 'Windows Boot Manager' "${staged_main}" \
        || die "generated GRUB configuration lost Windows Boot Manager"
fi

if [[ "${had_btrfs}" -eq 1 ]]; then
    cmp -s "${grub_btrfs_cfg}" "${backup_dir}/grub-btrfs.cfg" \
        || die "grub-mkconfig modified the active snapshot configuration"
elif [[ -e "${grub_btrfs_cfg}" || -L "${grub_btrfs_cfg}" ]]; then
    die "grub-mkconfig created the active snapshot configuration outside staging"
fi

staged_sidecar="${grub_stage}/grub-btrfs.cfg"
if [[ -e "${staged_sidecar}" || -L "${staged_sidecar}" ]]; then
    [[ -s "${staged_sidecar}" && -f "${staged_sidecar}" && ! -L "${staged_sidecar}" ]] \
        || die "staged grub-btrfs.cfg is not a regular non-empty file"
    grub-script-check "${staged_sidecar}"
    validate_steinsgrub_kernel_arguments "${default_candidate}" "${staged_sidecar}" \
        || die "generated snapshot configuration lost an expected kernel argument"
    install_owned_file 0644 "${staged_sidecar}" "${grub_btrfs_cfg}.new"
    grub-script-check "${grub_btrfs_cfg}.new"
    mv -f -- "${grub_btrfs_cfg}.new" "${grub_btrfs_cfg}"
elif [[ "${had_btrfs}" -eq 1 ]]; then
    die "grub-mkconfig did not stage the snapshot configuration"
fi
maybe_fail after-sidecar

install_owned_file 0600 "${grub_stage}/grub.cfg" "${grub_cfg}.new"
grub-script-check "${grub_cfg}.new"
maybe_fail before-main
mv -f -- "${grub_cfg}.new" "${grub_cfg}"

trap '' INT TERM
commit_done=1
trap - ERR
cleanup_stages || warn "could not remove all transaction staging paths"
printf 'Steins;GRUB installed successfully\nBackup: %s\n' "${backup_dir}"
