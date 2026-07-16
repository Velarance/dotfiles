#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/div-meter-plymouth.sh
source "${REPO_ROOT}/lib/div-meter-plymouth.sh"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

maybe_fail() {
    case "${DOTFILES_PLYMOUTH_FAILPOINT:-}" in
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
        || die "path escapes DOTFILES_PLYMOUTH_ROOT: $1"
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

write_plymouth_theme_config() {
    local source_config="$1"
    local destination="$2"

    awk -v selected_theme="${DIV_METER_THEME_NAME}" '
        BEGIN {
            in_daemon = 0
            daemon_sections = 0
            theme_assignments = 0
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            in_daemon = ($0 ~ /^[[:space:]]*\[Daemon\][[:space:]]*$/)
            if (in_daemon) {
                daemon_sections++
            }
        }
        in_daemon && /^[[:space:]]*Theme[[:space:]]*=/ {
            theme_assignments++
            print "Theme=" selected_theme
            next
        }
        { print }
        END {
            if (daemon_sections != 1 || theme_assignments != 1) {
                exit 42
            }
        }
    ' "${source_config}" > "${destination}" || return 1

    [[ "$(grep -Ec '^[[:space:]]*Theme[[:space:]]*=[[:space:]]*div-meter[[:space:]]*$' "${destination}")" -eq 1 ]]
}

grub_config_has_splash() {
    local config="$1"

    [[ -f "${config}" && ! -L "${config}" ]] || return 1
    grep -Eq \
        '^[[:space:]]*(linux|linuxefi)[[:space:]].*[[:space:]]splash([[:space:]]|$)' \
        "${config}"
}

validate_initramfs_image() {
    local image="$1"
    local manifest="$2"
    local expected_config="$3"
    local extraction_dir
    local validation_rc=0

    extraction_dir="$(mktemp -d)" || return 1
    (
        cd "${extraction_dir}" || exit 1
        lsinitcpio -x "${image}" >/dev/null 2>&1 || exit 1
        [[ -f etc/plymouth/plymouthd.conf \
            && ! -L etc/plymouth/plymouthd.conf ]] || exit 1
        cmp -s "${expected_config}" etc/plymouth/plymouthd.conf \
            || exit 1
        [[ "$(grep -Ec \
            '^[[:space:]]*Theme[[:space:]]*=[[:space:]]*div-meter[[:space:]]*$' \
            etc/plymouth/plymouthd.conf)" -eq 1 ]] || exit 1
        [[ -f usr/lib/plymouth/script.so \
            && ! -L usr/lib/plymouth/script.so ]] || exit 1
        [[ -f usr/share/plymouth/themes/div-meter/SHA256SUMS \
            && ! -L usr/share/plymouth/themes/div-meter/SHA256SUMS ]] || exit 1
        cmp -s \
            "${manifest}" \
            usr/share/plymouth/themes/div-meter/SHA256SUMS \
            || exit 1
        validate_div_meter_theme_tree \
            usr/share/plymouth/themes/div-meter \
            usr/share/plymouth/themes/div-meter/SHA256SUMS
    ) || validation_rc=$?
    rm -rf -- "${extraction_dir}" || return 1
    return "${validation_rc}"
}

all_initramfs_images_valid() {
    local logical_image target

    for logical_image in "${logical_images[@]}"; do
        target="${root_prefix}${logical_image}"
        validate_initramfs_image \
            "${target}" "${manifest}" "${plymouth_config}" || return 1
    done
}

root_prefix="${DOTFILES_PLYMOUTH_ROOT:-}"
root_prefix="${root_prefix%/}"
if [[ -n "${root_prefix}" ]]; then
    [[ "${root_prefix}" == /* && -d "${root_prefix}" && ! -L "${root_prefix}" ]] \
        || die "DOTFILES_PLYMOUTH_ROOT must be a real absolute directory"
    resolved_root="$(realpath -e -- "${root_prefix}")" \
        || die "could not resolve DOTFILES_PLYMOUTH_ROOT"
    [[ "${resolved_root}" == "${root_prefix}" ]] \
        || die "DOTFILES_PLYMOUTH_ROOT must be canonical and contain no symlink components"
    root_prefix="${resolved_root}"
elif [[ "${EUID}" -ne 0 ]]; then
    die "this transaction must run as root"
fi

[[ "$#" -eq 1 ]] || die "usage: $0 VALIDATED_THEME_DIR"
source_dir="$1"
manifest="${DOTFILES_PLYMOUTH_MANIFEST:-${source_dir}/SHA256SUMS}"

plymouth_config="${root_prefix}/etc/plymouth/plymouthd.conf"
mkinitcpio_config="${root_prefix}/etc/mkinitcpio.conf"
preset_dir="${root_prefix}/etc/mkinitcpio.d"
script_plugin="${root_prefix}/usr/lib/plymouth/script.so"
theme_parent="${root_prefix}/usr/share/plymouth/themes"
theme_target="${theme_parent}/div-meter"
grub_default="${root_prefix}/etc/default/grub"
grub_dir="${root_prefix}/boot/grub"
grub_cfg="${grub_dir}/grub.cfg"
grub_btrfs_cfg="${grub_dir}/grub-btrfs.cfg"
grub_btrfs_config="${root_prefix}/etc/default/grub-btrfs/config"
backup_parent="${root_prefix}/var/backups"
lock_path="${root_prefix}/run/lock/dotfiles-div-meter-plymouth.lock"

for required_tool in \
    awk bash chmod chown cmp cp date diff find flock grep install lsinitcpio \
    mkdir mkinitcpio mktemp mv realpath rm sha256sum sort stat uniq; do
    command -v "${required_tool}" >/dev/null 2>&1 \
        || die "required command is missing: ${required_tool}"
done

validate_div_meter_theme_tree "${source_dir}" "${manifest}" \
    || die "vendored div-meter source tree failed validation"
[[ -f "${plymouth_config}" && ! -L "${plymouth_config}" ]] \
    || die "${plymouth_config} must be a regular non-symlink file"
[[ -f "${mkinitcpio_config}" && ! -L "${mkinitcpio_config}" ]] \
    || die "${mkinitcpio_config} must be a regular non-symlink file"
[[ -d "${preset_dir}" && ! -L "${preset_dir}" ]] \
    || die "${preset_dir} must be a real directory"
[[ -f "${script_plugin}" && ! -L "${script_plugin}" ]] \
    || die "Plymouth script plugin is unavailable"
[[ -d "${theme_parent}" && ! -L "${theme_parent}" ]] \
    || die "${theme_parent} must be a real directory"
if [[ -e "${theme_target}" || -L "${theme_target}" ]]; then
    [[ -d "${theme_target}" && ! -L "${theme_target}" ]] \
        || die "${theme_target} must be a real directory"
fi
[[ -f "${grub_default}" && ! -L "${grub_default}" ]] \
    || die "${grub_default} must be a regular non-symlink file"
if [[ -z "${root_prefix}" ]]; then
    source_path_is_trusted "${grub_default}" 0 \
        || die "${grub_default} must be root-owned and not group/world-writable"
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

backup_parent_parent="${backup_parent%/*}"
[[ -d "${backup_parent_parent}" && ! -L "${backup_parent_parent}" ]] \
    || die "${backup_parent_parent} must be a real directory"
require_contained_path "${backup_parent_parent}"
if [[ -e "${backup_parent}" || -L "${backup_parent}" ]]; then
    [[ -d "${backup_parent}" && ! -L "${backup_parent}" ]] \
        || die "${backup_parent} must be a real directory"
else
    install_owned_directory 0700 "${backup_parent}" \
        || die "could not create ${backup_parent}"
fi
[[ -d "${backup_parent}" && ! -L "${backup_parent}" ]] \
    || die "${backup_parent} must be a real directory"
lock_parent="${lock_path%/*}"
[[ -d "${lock_parent}" && ! -L "${lock_parent}" ]] \
    || die "${lock_parent} must be an existing directory"

for contained_path in \
    "${plymouth_config}" \
    "${mkinitcpio_config}" \
    "${preset_dir}" \
    "${script_plugin}" \
    "${theme_parent}" \
    "${grub_default}" \
    "${grub_dir}" \
    "${grub_cfg}" \
    "${backup_parent}" \
    "${lock_parent}"; do
    require_contained_path "${contained_path}"
done
if [[ -e "${theme_target}" || -L "${theme_target}" ]]; then
    require_contained_path "${theme_target}"
fi
if [[ -e "${grub_btrfs_cfg}" || -L "${grub_btrfs_cfg}" ]]; then
    require_contained_path "${grub_btrfs_cfg}"
fi
if [[ -e "${grub_btrfs_config}" || -L "${grub_btrfs_config}" ]]; then
    require_contained_path "${grub_btrfs_config}"
fi

if [[ -z "${root_prefix}" ]]; then
    logical_images_output="$(list_mkinitcpio_images "${preset_dir}" 0)" \
        || die "could not enumerate trusted mkinitcpio presets"
else
    logical_images_output="$(list_mkinitcpio_images "${preset_dir}")" \
        || die "could not enumerate conventional mkinitcpio images"
fi
mapfile -t logical_images <<< "${logical_images_output}"
[[ "${#logical_images[@]}" -gt 0 ]] || die "no mkinitcpio images were found"
for logical_image in "${logical_images[@]}"; do
    [[ "${logical_image}" == /* && "${logical_image}" != *'..'* ]] \
        || die "unsafe mkinitcpio image path: ${logical_image}"
    image_target="${root_prefix}${logical_image}"
    [[ -f "${image_target}" && ! -L "${image_target}" ]] \
        || die "${image_target} must be an existing regular initramfs image"
    require_contained_path "${image_target}"
done

if [[ ! -e "${lock_path}" && ! -L "${lock_path}" ]]; then
    (
        umask 077
        set -o noclobber
        : > "${lock_path}"
    ) || die "could not create the Plymouth transaction lock"
fi
[[ -f "${lock_path}" && ! -L "${lock_path}" ]] \
    || die "${lock_path} must be a regular non-symlink file"
require_contained_path "${lock_path}"
exec 9<> "${lock_path}"
flock -n 9 || die "another div-meter Plymouth transaction is already running"

theme_transaction="$(mktemp -d "${theme_parent}/.div-meter-transaction.XXXXXX")"
theme_stage="${theme_transaction}/theme"
theme_displaced="${theme_transaction}/previous-theme"
plymouth_candidate="${theme_transaction}/plymouthd.conf"
mkinitcpio_candidate="${theme_transaction}/mkinitcpio.conf"
grub_candidate="${theme_transaction}/grub-default"
grub_stage=""
backup_dir=""
had_theme=0
had_btrfs=0
mutation_started=0
commit_done=0

cleanup_stages() {
    if [[ -n "${theme_transaction:-}" \
        && "${theme_transaction}" == "${theme_parent}/.div-meter-transaction."* ]]; then
        rm -rf -- "${theme_transaction}"
    fi
    if [[ -n "${grub_stage:-}" \
        && "${grub_stage}" == "${grub_dir}/.div-meter-transaction."* ]]; then
        rm -rf -- "${grub_stage}"
    fi
}
trap cleanup_stages EXIT

mkdir -p -- "${theme_stage}"
cp -a -- "${source_dir}/." "${theme_stage}/"
validate_div_meter_theme_tree "${theme_stage}" "${theme_stage}/SHA256SUMS" \
    || die "root-owned theme stage failed validation"
find "${theme_stage}" -type d -exec chmod 0755 {} +
find "${theme_stage}" -type f -exec chmod 0644 {} +
if [[ -z "${root_prefix}" ]]; then
    chown -R root:root "${theme_stage}"
fi

write_plymouth_theme_config "${plymouth_config}" "${plymouth_candidate}" \
    || die "could not create a safe Plymouth config candidate"
write_mkinitcpio_plymouth_config "${mkinitcpio_config}" "${mkinitcpio_candidate}" \
    || die "could not create a safe mkinitcpio config candidate"
write_grub_splash_config "${grub_default}" "${grub_candidate}" \
    || die "could not create a safe GRUB splash candidate"

grub_regeneration_required=0
if ! cmp -s "${grub_candidate}" "${grub_default}" \
    || ! grub_config_has_splash "${grub_cfg}"; then
    grub_regeneration_required=1
fi
theme_matches=0
if [[ -d "${theme_target}" ]] \
    && validate_div_meter_theme_tree "${theme_target}" "${theme_target}/SHA256SUMS" \
    && diff -qr -- "${source_dir}" "${theme_target}" >/dev/null; then
    theme_matches=1
fi
if [[ "${theme_matches}" -eq 1 ]] \
    && cmp -s "${plymouth_candidate}" "${plymouth_config}" \
    && cmp -s "${mkinitcpio_candidate}" "${mkinitcpio_config}" \
    && cmp -s "${grub_candidate}" "${grub_default}" \
    && [[ "${grub_regeneration_required}" -eq 0 ]] \
    && all_initramfs_images_valid; then
    printf 'Divergence Meter Plymouth is already configured; initramfs images are valid\n'
    exit 0
fi

if [[ "${grub_regeneration_required}" -eq 1 ]]; then
    for required_tool in grub-mkconfig grub-script-check; do
        command -v "${required_tool}" >/dev/null 2>&1 \
            || die "required command is missing for splash activation: ${required_tool}"
    done
    grub_stage="$(mktemp -d "${grub_dir}/.div-meter-transaction.XXXXXX")"
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
backup_dir="${backup_parent}/dotfiles-div-meter-plymouth-${stamp}"
install_owned_directory 0700 "${backup_dir}"
cp -a -- "${plymouth_config}" "${backup_dir}/plymouthd.conf"
cp -a -- "${mkinitcpio_config}" "${backup_dir}/mkinitcpio.conf"
cp -a -- "${grub_default}" "${backup_dir}/grub-default"
cp -a -- "${grub_cfg}" "${backup_dir}/grub.cfg"
if [[ -f "${grub_btrfs_cfg}" ]]; then
    had_btrfs=1
    cp -a -- "${grub_btrfs_cfg}" "${backup_dir}/grub-btrfs.cfg"
fi
if [[ -d "${theme_target}" ]]; then
    had_theme=1
    cp -a -- "${theme_target}" "${backup_dir}/theme"
fi
for logical_image in "${logical_images[@]}"; do
    backup_image="${backup_dir}/initramfs${logical_image}"
    mkdir -p -- "${backup_image%/*}"
    cp -a --reflink=auto -- "${root_prefix}${logical_image}" "${backup_image}"
done
printf '%s\n' "${logical_images[@]}" > "${backup_dir}/initramfs-images"

restore_file() {
    local backup="$1"
    local target="$2"
    local temporary="${target}.dotfiles-rollback.$$"

    cp -a --reflink=auto -- "${backup}" "${temporary}" \
        && mv -f -- "${temporary}" "${target}"
}

rollback_transaction() {
    local rc="${1:-$?}"
    local rollback_failed=0
    local logical_image
    trap - ERR
    trap '' INT TERM
    set +e

    if [[ "${mutation_started}" -eq 1 && "${commit_done}" -eq 0 ]]; then
        restore_file "${backup_dir}/plymouthd.conf" "${plymouth_config}" \
            || rollback_failed=1
        restore_file "${backup_dir}/mkinitcpio.conf" "${mkinitcpio_config}" \
            || rollback_failed=1
        restore_file "${backup_dir}/grub-default" "${grub_default}" \
            || rollback_failed=1
        restore_file "${backup_dir}/grub.cfg" "${grub_cfg}" \
            || rollback_failed=1
        if [[ "${had_btrfs}" -eq 1 ]]; then
            restore_file "${backup_dir}/grub-btrfs.cfg" "${grub_btrfs_cfg}" \
                || rollback_failed=1
        else
            rm -f -- "${grub_btrfs_cfg}" || rollback_failed=1
        fi

        rm -rf -- "${theme_target}" || rollback_failed=1
        if [[ "${had_theme}" -eq 1 ]]; then
            cp -a -- "${backup_dir}/theme" "${theme_target}" || rollback_failed=1
        fi
        for logical_image in "${logical_images[@]}"; do
            restore_file \
                "${backup_dir}/initramfs${logical_image}" \
                "${root_prefix}${logical_image}" \
                || rollback_failed=1
        done
        rm -f -- \
            "${plymouth_config}.new" \
            "${mkinitcpio_config}.new" \
            "${grub_default}.new" \
            "${grub_cfg}.new" \
            "${grub_btrfs_cfg}.new" \
            || rollback_failed=1
    fi

    cleanup_stages
    if [[ "${rollback_failed}" -eq 1 ]]; then
        warn "rollback was incomplete; recovery files remain in ${backup_dir}"
    else
        warn "transaction failed; restored the previous Plymouth and initramfs state from ${backup_dir}"
    fi
    exit "${rc}"
}
trap 'rollback_transaction $?' ERR
trap 'rollback_transaction 130' INT
trap 'rollback_transaction 143' TERM

mutation_started=1
if [[ "${had_theme}" -eq 1 ]]; then
    mv -- "${theme_target}" "${theme_displaced}"
fi
mv -- "${theme_stage}" "${theme_target}"
maybe_fail after-theme

plymouth_mode="$(stat -c '%a' "${plymouth_config}")"
install_owned_file "${plymouth_mode}" "${plymouth_candidate}" "${plymouth_config}.new"
mv -f -- "${plymouth_config}.new" "${plymouth_config}"
maybe_fail after-config

if ! cmp -s "${mkinitcpio_candidate}" "${mkinitcpio_config}"; then
    mkinitcpio_mode="$(stat -c '%a' "${mkinitcpio_config}")"
    install_owned_file "${mkinitcpio_mode}" "${mkinitcpio_candidate}" "${mkinitcpio_config}.new"
    mv -f -- "${mkinitcpio_config}.new" "${mkinitcpio_config}"
fi

if [[ "${grub_regeneration_required}" -eq 1 ]]; then
    if ! cmp -s "${grub_candidate}" "${grub_default}"; then
        grub_default_mode="$(stat -c '%a' "${grub_default}")"
        install_owned_file "${grub_default_mode}" "${grub_candidate}" "${grub_default}.new"
        mv -f -- "${grub_default}.new" "${grub_default}"
    fi

    env \
        GRUB_BTRFS_GRUB_DIRNAME="${grub_stage}" \
        GRUB_BTRFS_GBTRFS_DIRNAME="${grub_stage}" \
        grub-mkconfig -o "${grub_stage}/grub.cfg"
    [[ -s "${grub_stage}/grub.cfg" ]] || die "grub-mkconfig produced no configuration"
    grub-script-check "${grub_stage}/grub.cfg"
    grep -Eq '^[[:space:]]*(linux|linuxefi)[[:space:]].*[[:space:]]splash([[:space:]]|$)' \
        "${grub_stage}/grub.cfg" \
        || die "staged GRUB configuration does not contain splash"
    validate_grub_kernel_arguments \
        "${grub_candidate}" "${grub_stage}/grub.cfg" \
        || die "staged GRUB configuration lost an expected kernel argument"
    if grep -Fq 'Windows Boot Manager' "${backup_dir}/grub.cfg"; then
        grep -Fq 'Windows Boot Manager' "${grub_stage}/grub.cfg" \
            || die "staged GRUB configuration lost Windows Boot Manager"
    fi
    if [[ -e "${grub_stage}/grub-btrfs.cfg" \
        || -L "${grub_stage}/grub-btrfs.cfg" ]]; then
        [[ -s "${grub_stage}/grub-btrfs.cfg" ]] \
            && [[ -f "${grub_stage}/grub-btrfs.cfg" \
                && ! -L "${grub_stage}/grub-btrfs.cfg" ]] \
            || die "staged grub-btrfs.cfg is not a regular non-empty file"
        grub-script-check "${grub_stage}/grub-btrfs.cfg"
        validate_grub_kernel_arguments \
            "${grub_candidate}" "${grub_stage}/grub-btrfs.cfg" \
            || die "staged grub-btrfs.cfg lost an expected kernel argument"
        install_owned_file 0644 "${grub_stage}/grub-btrfs.cfg" "${grub_btrfs_cfg}.new"
        mv -f -- "${grub_btrfs_cfg}.new" "${grub_btrfs_cfg}"
    elif [[ "${had_btrfs}" -eq 1 ]]; then
        die "staged GRUB configuration lost grub-btrfs.cfg"
    fi
    install_owned_file 0600 "${grub_stage}/grub.cfg" "${grub_cfg}.new"
    mv -f -- "${grub_cfg}.new" "${grub_cfg}"
fi

mkinitcpio -P
maybe_fail after-rebuild
all_initramfs_images_valid \
    || die "one or more generated initramfs images do not contain the complete div-meter theme"

trap '' INT TERM
commit_done=1
trap - ERR
cleanup_stages
trap - EXIT
printf 'Divergence Meter Plymouth installed successfully\nBackup: %s\n' "${backup_dir}"
