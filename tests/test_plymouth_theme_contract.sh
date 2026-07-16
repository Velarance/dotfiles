#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_DIR="${ROOT}/config/plymouth/themes/div-meter"
MANIFEST="${THEME_DIR}/SHA256SUMS"
UPSTREAM="${THEME_DIR}/UPSTREAM"
LIBRARY="${ROOT}/lib/div-meter-plymouth.sh"
ROOT_INSTALLER="${ROOT}/scripts/install-div-meter-plymouth-root.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -d "${THEME_DIR}" && ! -L "${THEME_DIR}" ]] \
    || fail "vendored div-meter theme directory is missing"
[[ -f "${MANIFEST}" && ! -L "${MANIFEST}" ]] \
    || fail "div-meter checksum manifest is missing"
[[ -f "${UPSTREAM}" && ! -L "${UPSTREAM}" ]] \
    || fail "div-meter upstream provenance is missing"

expected_files=(
    LICENSE
    SHA256SUMS
    UPSTREAM
    div-meter.plymouth
    div-meter.script
)
for frame in {0..32}; do
    expected_files+=("end${frame}.png")
done
for frame in {0..8}; do
    expected_files+=("loop${frame}.png")
done

mapfile -t expected_sorted < <(printf '%s\n' "${expected_files[@]}" | LC_ALL=C sort)
mapfile -t actual_files < <(
    find "${THEME_DIR}" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' \
        | LC_ALL=C sort
)
[[ "${#actual_files[@]}" -eq 47 ]] \
    || fail "div-meter theme must contain exactly 47 regular files"
[[ "$(printf '%s\n' "${actual_files[@]}")" == "$(printf '%s\n' "${expected_sorted[@]}")" ]] \
    || fail "div-meter theme tree differs from the audited file list"

for executable_source in div-meter.plymouth div-meter.script; do
    [[ "$(stat -c '%a' "${THEME_DIR}/${executable_source}")" == 755 ]] \
        || fail "vendored upstream mode drifted for ${executable_source}"
done

if find "${THEME_DIR}" -mindepth 1 \( -type l -o -type d -o ! -type f \) -print -quit \
    | grep -q .; then
    fail "div-meter theme must be a flat tree of regular non-symlink files"
fi

grep -Fxq 'Source: https://github.com/jericjan/divergence-meter-plymouth' "${UPSTREAM}" \
    || fail "div-meter provenance has the wrong source"
grep -Fxq 'Commit: 7fe92523659811b0339ea60af4a92aff5fd4a256' "${UPSTREAM}" \
    || fail "div-meter provenance has the wrong commit"
grep -Fxq 'Tree: ea39e39bc7810538e22d99bd5cc3049baab4a445' "${UPSTREAM}" \
    || fail "div-meter provenance has the wrong tree"
grep -Fxq 'Archive-SHA256: 0c5f48106e679ef95383b5f1e1e600437cd8079fd027225255146f19a995bdba' "${UPSTREAM}" \
    || fail "div-meter provenance has the wrong archive digest"
grep -Fxq 'License: GPL-3.0' "${UPSTREAM}" \
    || fail "div-meter provenance must record GPL-3.0"
grep -Fxq 'Local-Change: div-meter.script fixes end_imags to end_imgs for the terminal frame' "${UPSTREAM}" \
    || fail "div-meter provenance must disclose the local script correction"

manifest_paths=()
while read -r digest relative_path extra; do
    [[ -z "${extra:-}" && "${digest}" =~ ^[0-9a-f]{64}$ && -n "${relative_path:-}" ]] \
        || fail "div-meter manifest contains an invalid row"
    [[ "${relative_path}" != /* && "${relative_path}" != *'..'* ]] \
        || fail "div-meter manifest contains an unsafe path: ${relative_path}"
    manifest_paths+=("${relative_path}")
done < "${MANIFEST}"
[[ "${#manifest_paths[@]}" -eq 45 ]] \
    || fail "div-meter manifest must pin exactly 45 runtime files"
mapfile -t manifest_sorted < <(printf '%s\n' "${manifest_paths[@]}" | LC_ALL=C sort)
mapfile -t runtime_sorted < <(
    printf '%s\n' "${expected_files[@]}" \
        | grep -Ev '^(SHA256SUMS|UPSTREAM)$' \
        | LC_ALL=C sort
)
[[ "$(printf '%s\n' "${manifest_sorted[@]}")" == "$(printf '%s\n' "${runtime_sorted[@]}")" ]] \
    || fail "div-meter manifest paths differ from the runtime tree"
(cd "${THEME_DIR}" && sha256sum --strict -c SHA256SUMS >/dev/null) \
    || fail "div-meter runtime checksum validation failed"

grep -Fxq 'Name=div-meter' "${THEME_DIR}/div-meter.plymouth" \
    || fail "div-meter descriptor has the wrong name"
grep -Fxq 'ModuleName=script' "${THEME_DIR}/div-meter.plymouth" \
    || fail "div-meter descriptor must use the script plugin"
grep -Fxq 'ImageDir=/usr/share/plymouth/themes/div-meter' "${THEME_DIR}/div-meter.plymouth" \
    || fail "div-meter descriptor has the wrong image path"
grep -Fxq 'ScriptFile=/usr/share/plymouth/themes/div-meter/div-meter.script' "${THEME_DIR}/div-meter.plymouth" \
    || fail "div-meter descriptor has the wrong script path"

grep -Fq 'end_imgs[NUM_END_FRAMES - 1]' "${THEME_DIR}/div-meter.script" \
    || fail "div-meter terminal frame must use the loaded end_imgs array"
if grep -Fq 'end_imags' "${THEME_DIR}/div-meter.script"; then
    fail "div-meter script retains the upstream end_imags typo"
fi

for image in "${THEME_DIR}"/{end{0..32},loop{0..8}}.png; do
    file -b "${image}" | grep -Fq 'PNG image data, 800 x 600' \
        || fail "unexpected div-meter frame format: ${image##*/}"
done

grep -Fxq 'config/plymouth/themes/div-meter/** -whitespace' "${ROOT}/.gitattributes" \
    || fail "vendored div-meter files must be excluded from whitespace checks"

[[ -f "${LIBRARY}" && ! -L "${LIBRARY}" ]] \
    || fail "div-meter helper library is missing"
# shellcheck source=../lib/div-meter-plymouth.sh
source "${LIBRARY}"

[[ "${DIV_METER_MANIFEST_SHA256}" == "b7b455d7cd82cacf649fa9ff5072334bf767202fc159b56d2abb0a9f9d43d964" ]] \
    || fail "div-meter helper pins the wrong manifest digest"
for helper in \
    validate_div_meter_theme_tree \
    write_mkinitcpio_plymouth_config \
    write_grub_splash_config \
    validate_grub_kernel_arguments \
    grub_defaults_file_is_trusted \
    list_mkinitcpio_images; do
    declare -F "${helper}" >/dev/null \
        || fail "div-meter helper is missing: ${helper}"
done

package_counts="$(
    bash --noprofile --norc -c '
        source "$1"
        core_count=0
        optional_count=0
        for package in "${CORE_PACKAGES[@]}"; do
            [[ "${package}" == plymouth ]] && ((core_count += 1))
        done
        for package in "${OPTIONAL_PACKAGES[@]}"; do
            [[ "${package}" == plymouth ]] && ((optional_count += 1))
        done
        printf "%s %s\n" "${core_count}" "${optional_count}"
    ' bash "${ROOT}/lib/packages.conf"
)"
[[ "${package_counts}" == "1 0" ]] \
    || fail "plymouth must appear exactly once in CORE_PACKAGES and never optional"

validate_div_meter_theme_tree "${THEME_DIR}" "${MANIFEST}" \
    || fail "valid div-meter repository tree was rejected"

test_tmp="$(mktemp -d)"
trap 'rm -rf -- "${test_tmp}"' EXIT
theme_fixture="${test_tmp}/theme"
cp -a -- "${THEME_DIR}" "${theme_fixture}"
printf '\n# tampered\n' >> "${theme_fixture}/div-meter.script"
if validate_div_meter_theme_tree "${theme_fixture}" "${theme_fixture}/SHA256SUMS"; then
    fail "div-meter validator accepted a checksum mismatch"
fi
cp -- "${THEME_DIR}/div-meter.script" "${theme_fixture}/div-meter.script"
printf 'unexpected\n' > "${theme_fixture}/unexpected"
if validate_div_meter_theme_tree "${theme_fixture}" "${theme_fixture}/SHA256SUMS"; then
    fail "div-meter validator accepted an extra file"
fi
rm -- "${theme_fixture}/unexpected"
ln -s -- loop0.png "${theme_fixture}/linked.png"
if validate_div_meter_theme_tree "${theme_fixture}" "${theme_fixture}/SHA256SUMS"; then
    fail "div-meter validator accepted a symlink"
fi

mkinit_existing="${test_tmp}/mkinit-existing.conf"
mkinit_existing_out="${test_tmp}/mkinit-existing.out"
cat > "${mkinit_existing}" <<'MKINIT_EXISTING'
# keep this comment
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)
COMPRESSION="zstd"
MKINIT_EXISTING
write_mkinitcpio_plymouth_config "${mkinit_existing}" "${mkinit_existing_out}" \
    || fail "existing Plymouth hook was rejected"
cmp -s "${mkinit_existing}" "${mkinit_existing_out}" \
    || fail "existing Plymouth hook order must remain byte-for-byte unchanged"

mkinit_systemd="${test_tmp}/mkinit-systemd.conf"
mkinit_systemd_out="${test_tmp}/mkinit-systemd.out"
cat > "${mkinit_systemd}" <<'MKINIT_SYSTEMD'
MODULES=(i915)
HOOKS=(base systemd autodetect microcode kms modconf block filesystems)
FILES=()
MKINIT_SYSTEMD
write_mkinitcpio_plymouth_config "${mkinit_systemd}" "${mkinit_systemd_out}" \
    || fail "systemd mkinitcpio config could not gain Plymouth"
grep -Fxq 'HOOKS=(base systemd plymouth autodetect microcode kms modconf block filesystems)' "${mkinit_systemd_out}" \
    || fail "Plymouth hook must be inserted immediately after systemd"
grep -Fxq 'MODULES=(i915)' "${mkinit_systemd_out}" \
    || fail "mkinitcpio helper lost unrelated settings"

mkinit_udev="${test_tmp}/mkinit-udev.conf"
mkinit_udev_out="${test_tmp}/mkinit-udev.out"
printf 'HOOKS=(base udev autodetect kms block filesystems)\n' > "${mkinit_udev}"
write_mkinitcpio_plymouth_config "${mkinit_udev}" "${mkinit_udev_out}" \
    || fail "udev mkinitcpio config could not gain Plymouth"
grep -Fxq 'HOOKS=(base udev plymouth autodetect kms block filesystems)' "${mkinit_udev_out}" \
    || fail "Plymouth hook must be inserted immediately after udev"

mkinit_duplicate="${test_tmp}/mkinit-duplicate.conf"
printf 'HOOKS=(base systemd plymouth autodetect plymouth filesystems)\n' > "${mkinit_duplicate}"
if write_mkinitcpio_plymouth_config "${mkinit_duplicate}" "${test_tmp}/duplicate.out"; then
    fail "mkinitcpio helper accepted duplicate Plymouth hooks"
fi

mkinit_ambiguous="${test_tmp}/mkinit-ambiguous.conf"
cat > "${mkinit_ambiguous}" <<'MKINIT_AMBIGUOUS'
HOOKS=(base systemd filesystems)
HOOKS=(base systemd kms filesystems)
MKINIT_AMBIGUOUS
if write_mkinitcpio_plymouth_config "${mkinit_ambiguous}" "${test_tmp}/ambiguous.out"; then
    fail "mkinitcpio helper accepted multiple active HOOKS assignments"
fi

mkinit_multiline="${test_tmp}/mkinit-multiline.conf"
cat > "${mkinit_multiline}" <<'MKINIT_MULTILINE'
HOOKS=(
    base systemd filesystems
)
MKINIT_MULTILINE
if write_mkinitcpio_plymouth_config "${mkinit_multiline}" "${test_tmp}/multiline.out"; then
    fail "mkinitcpio helper must reject unsupported multiline HOOKS safely"
fi

grub_existing="${test_tmp}/grub-existing"
grub_existing_out="${test_tmp}/grub-existing.out"
cat > "${grub_existing}" <<'GRUB_EXISTING'
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog splash loglevel=3'
GRUB_CMDLINE_LINUX=""
GRUB_EXISTING
write_grub_splash_config "${grub_existing}" "${grub_existing_out}" \
    || fail "existing splash argument was rejected"
cmp -s "${grub_existing}" "${grub_existing_out}" \
    || fail "existing splash config must remain byte-for-byte unchanged"

grub_missing="${test_tmp}/grub-missing"
grub_missing_out="${test_tmp}/grub-missing.out"
cat > "${grub_missing}" <<'GRUB_MISSING'
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog nvme_load=YES loglevel=3'
GRUB_CMDLINE_LINUX=""
GRUB_MISSING
write_grub_splash_config "${grub_missing}" "${grub_missing_out}" \
    || fail "GRUB config could not gain splash"
bash --noprofile --norc -c '
    source "$1"
    [[ "${GRUB_CMDLINE_LINUX_DEFAULT}" == "nowatchdog nvme_load=YES loglevel=3 splash" ]]
    [[ "${GRUB_CMDLINE_LINUX}" == "" ]]
' bash "${grub_missing_out}" \
    || fail "GRUB helper lost arguments or added splash incorrectly"

grub_ambiguous="${test_tmp}/grub-ambiguous"
cat > "${grub_ambiguous}" <<'GRUB_AMBIGUOUS'
GRUB_CMDLINE_LINUX_DEFAULT='one'
GRUB_CMDLINE_LINUX_DEFAULT='two'
GRUB_AMBIGUOUS
if write_grub_splash_config "${grub_ambiguous}" "${test_tmp}/grub-ambiguous.out"; then
    fail "GRUB helper accepted multiple active default command lines"
fi

validator_defaults="${test_tmp}/grub-validator-defaults"
cat > "${validator_defaults}" <<'VALIDATOR_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'
GRUB_CMDLINE_LINUX='audit=0 lockdown=integrity'
VALIDATOR_DEFAULTS
validator_recovery="${test_tmp}/grub-validator-recovery.cfg"
cat > "${validator_recovery}" <<'VALIDATOR_RECOVERY'
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash
}
menuentry 'recovery' {
    linuxefi /boot/vmlinuz root=fixture audit=0 lockdown=integrity single
}
VALIDATOR_RECOVERY
validate_grub_kernel_arguments "${validator_defaults}" "${validator_recovery}" \
    || fail "GRUB validator rejected a recovery entry that retained global arguments"

validator_outside_entry="${test_tmp}/grub-validator-outside-entry.cfg"
cat > "${validator_outside_entry}" <<'VALIDATOR_OUTSIDE_ENTRY'
linux /boot/vmlinuz root=fixture quiet splash audit=0 lockdown=integrity
VALIDATOR_OUTSIDE_ENTRY
if validate_grub_kernel_arguments "${validator_defaults}" "${validator_outside_entry}"; then
    fail "GRUB validator accepted a kernel line outside an explicit menuentry"
fi

validator_nested_entry="${test_tmp}/grub-validator-nested-entry.cfg"
cat > "${validator_nested_entry}" <<'VALIDATOR_NESTED_ENTRY'
menuentry 'nested' {
    conditional {
        linux /boot/vmlinuz root=fixture quiet splash audit=0 lockdown=integrity
    }
}
VALIDATOR_NESTED_ENTRY
if validate_grub_kernel_arguments \
    "${validator_defaults}" "${validator_nested_entry}"; then
    fail "GRUB validator accepted nested structural braces inside a menuentry"
fi

validator_no_linux="${test_tmp}/grub-validator-no-linux.cfg"
cat > "${validator_no_linux}" <<'VALIDATOR_NO_LINUX'
submenu 'snapshots' {
}
VALIDATOR_NO_LINUX
if validate_grub_kernel_arguments "${validator_defaults}" "${validator_no_linux}"; then
    fail "GRUB validator accepted a nonempty config without Linux entries"
fi

validator_duplicate_defaults="${test_tmp}/grub-validator-duplicate-defaults"
cat > "${validator_duplicate_defaults}" <<'VALIDATOR_DUPLICATE_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet'
GRUB_CMDLINE_LINUX='audit=0 audit=0'
VALIDATOR_DUPLICATE_DEFAULTS
validator_duplicate_cfg="${test_tmp}/grub-validator-duplicate.cfg"
cat > "${validator_duplicate_cfg}" <<'VALIDATOR_DUPLICATE_CFG'
menuentry 'duplicate lost' {
    linux /boot/vmlinuz root=fixture audit=0 quiet
}
VALIDATOR_DUPLICATE_CFG
if validate_grub_kernel_arguments \
    "${validator_duplicate_defaults}" "${validator_duplicate_cfg}"; then
    fail "GRUB validator ignored duplicate global argument multiplicity"
fi

validator_cross_duplicate_defaults="${test_tmp}/grub-validator-cross-duplicate-defaults"
cat > "${validator_cross_duplicate_defaults}" <<'VALIDATOR_CROSS_DUPLICATE_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet'
GRUB_CMDLINE_LINUX='quiet'
VALIDATOR_CROSS_DUPLICATE_DEFAULTS
validator_cross_duplicate_cfg="${test_tmp}/grub-validator-cross-duplicate.cfg"
cat > "${validator_cross_duplicate_cfg}" <<'VALIDATOR_CROSS_DUPLICATE_CFG'
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture quiet
}
VALIDATOR_CROSS_DUPLICATE_CFG
if validate_grub_kernel_arguments \
    "${validator_cross_duplicate_defaults}" "${validator_cross_duplicate_cfg}"; then
    fail "GRUB validator let one token satisfy default and global duplicates"
fi

validator_partial_normal_defaults="${test_tmp}/grub-validator-partial-normal-defaults"
cat > "${validator_partial_normal_defaults}" <<'VALIDATOR_PARTIAL_NORMAL_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet'
GRUB_CMDLINE_LINUX='quiet'
VALIDATOR_PARTIAL_NORMAL_DEFAULTS
validator_partial_normal_cfg="${test_tmp}/grub-validator-partial-normal.cfg"
cat > "${validator_partial_normal_cfg}" <<'VALIDATOR_PARTIAL_NORMAL_CFG'
menuentry 'complete normal' {
    linux /boot/vmlinuz root=fixture quiet quiet
}
menuentry 'incomplete normal' {
    linuxefi /boot/vmlinuz root=fixture quiet
}
VALIDATOR_PARTIAL_NORMAL_CFG
if validate_grub_kernel_arguments \
    "${validator_partial_normal_defaults}" "${validator_partial_normal_cfg}"; then
    fail "GRUB validator let one complete normal entry mask another without defaults"
fi

validator_recovery_only_defaults="${test_tmp}/grub-validator-recovery-only-defaults"
cat > "${validator_recovery_only_defaults}" <<'VALIDATOR_RECOVERY_ONLY_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'
GRUB_CMDLINE_LINUX='audit=0'
VALIDATOR_RECOVERY_ONLY_DEFAULTS
validator_recovery_only_cfg="${test_tmp}/grub-validator-recovery-only.cfg"
cat > "${validator_recovery_only_cfg}" <<'VALIDATOR_RECOVERY_ONLY_CFG'
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0
}
menuentry 'fallback' --class recovery {
    linuxefi /boot/vmlinuz root=fixture quiet splash audit=0 single
}
VALIDATOR_RECOVERY_ONLY_CFG
if validate_grub_kernel_arguments \
    "${validator_recovery_only_defaults}" "${validator_recovery_only_cfg}"; then
    fail "GRUB validator accepted default arguments found only in a recovery entry"
fi

validator_global_order_defaults="${test_tmp}/grub-validator-global-order-defaults"
cat > "${validator_global_order_defaults}" <<'VALIDATOR_GLOBAL_ORDER_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet'
GRUB_CMDLINE_LINUX='audit=0 lockdown=integrity'
VALIDATOR_GLOBAL_ORDER_DEFAULTS
validator_global_order_cfg="${test_tmp}/grub-validator-global-order.cfg"
cat > "${validator_global_order_cfg}" <<'VALIDATOR_GLOBAL_ORDER_CFG'
menuentry 'global reordered' {
    linux /boot/vmlinuz root=fixture lockdown=integrity audit=0 quiet
}
VALIDATOR_GLOBAL_ORDER_CFG
if validate_grub_kernel_arguments \
    "${validator_global_order_defaults}" "${validator_global_order_cfg}"; then
    fail "GRUB validator ignored global argument order"
fi

validator_default_order_defaults="${test_tmp}/grub-validator-default-order-defaults"
cat > "${validator_default_order_defaults}" <<'VALIDATOR_DEFAULT_ORDER_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'
GRUB_CMDLINE_LINUX='audit=0'
VALIDATOR_DEFAULT_ORDER_DEFAULTS
validator_default_order_cfg="${test_tmp}/grub-validator-default-order.cfg"
cat > "${validator_default_order_cfg}" <<'VALIDATOR_DEFAULT_ORDER_CFG'
menuentry 'defaults reordered' {
    linux /boot/vmlinuz root=fixture audit=0 splash quiet
}
VALIDATOR_DEFAULT_ORDER_CFG
if validate_grub_kernel_arguments \
    "${validator_default_order_defaults}" "${validator_default_order_cfg}"; then
    fail "GRUB validator ignored default argument order"
fi

for ambiguous_kind in quoted escaped; do
    ambiguous_defaults="${test_tmp}/grub-validator-${ambiguous_kind}-defaults"
    ambiguous_cfg="${test_tmp}/grub-validator-${ambiguous_kind}.cfg"
    if [[ "${ambiguous_kind}" == quoted ]]; then
        printf '%s\n' \
            "GRUB_CMDLINE_LINUX_DEFAULT=''" \
            "GRUB_CMDLINE_LINUX='console=\"tty S0\"'" \
            > "${ambiguous_defaults}"
        printf '%s\n' \
            "menuentry 'quoted' {" \
            '    linux /boot/vmlinuz root=fixture console="tty S0"' \
            '}' \
            > "${ambiguous_cfg}"
    else
        printf '%s\n' \
            "GRUB_CMDLINE_LINUX_DEFAULT=''" \
            "GRUB_CMDLINE_LINUX='rd.luks.name=foo\\ bar'" \
            > "${ambiguous_defaults}"
        printf '%s\n' \
            "menuentry 'escaped' {" \
            '    linux /boot/vmlinuz root=fixture rd.luks.name=foo\ bar' \
            '}' \
            > "${ambiguous_cfg}"
    fi
    if validate_grub_kernel_arguments "${ambiguous_defaults}" "${ambiguous_cfg}"; then
        fail "GRUB validator unsafely accepted ${ambiguous_kind} kernel arguments"
    fi
done

trusted_defaults="${test_tmp}/grub-validator-trusted-defaults"
cp -- "${validator_defaults}" "${trusted_defaults}"
chmod 0644 "${trusted_defaults}"
current_uid="$(id -u)"
grub_defaults_file_is_trusted "${trusted_defaults}" "${current_uid}" \
    || fail "GRUB defaults trust check rejected a protected owner-controlled file"
if grub_defaults_file_is_trusted "${trusted_defaults}" "$((current_uid + 1))"; then
    fail "GRUB defaults trust check accepted the wrong owner"
fi
chmod 0664 "${trusted_defaults}"
if grub_defaults_file_is_trusted "${trusted_defaults}" "${current_uid}"; then
    fail "GRUB defaults trust check accepted group-writable input"
fi

preset_dir="${test_tmp}/presets"
mkdir -p "${preset_dir}"
cat > "${preset_dir}/linux-a.preset" <<'PRESET_A'
PRESETS=('default')
default_image="/boot/initramfs-linux-a.img"
PRESET_A
cat > "${preset_dir}/linux-b.preset" <<'PRESET_B'
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-linux-b.img"
fallback_image="/boot/initramfs-linux-b-fallback.img"
PRESET_B
images="$(list_mkinitcpio_images "${preset_dir}")" \
    || fail "valid mkinitcpio presets were rejected"
[[ "${images}" == $'/boot/initramfs-linux-a.img\n/boot/initramfs-linux-b-fallback.img\n/boot/initramfs-linux-b.img' ]] \
    || fail "mkinitcpio image enumeration is incomplete or nondeterministic"

chmod 0755 "${preset_dir}"
chmod 0644 "${preset_dir}/linux-a.preset" "${preset_dir}/linux-b.preset"
trusted_images="$(list_mkinitcpio_images "${preset_dir}" "${current_uid}")" \
    || fail "trusted current-user mkinitcpio presets were rejected"
[[ "${trusted_images}" == "${images}" ]] \
    || fail "trusted preset enumeration changed the image list"
if list_mkinitcpio_images "${preset_dir}" "$((current_uid + 1))" >/dev/null; then
    fail "trusted preset enumeration accepted the wrong owner"
fi
chmod 0664 "${preset_dir}/linux-a.preset"
if list_mkinitcpio_images "${preset_dir}" "${current_uid}" >/dev/null; then
    fail "trusted preset enumeration accepted a group-writable preset"
fi
chmod 0644 "${preset_dir}/linux-a.preset"
chmod 0775 "${preset_dir}"
if list_mkinitcpio_images "${preset_dir}" "${current_uid}" >/dev/null; then
    fail "trusted preset enumeration accepted a group-writable preset directory"
fi
chmod 0755 "${preset_dir}"

ln -s -- linux-a.preset "${preset_dir}/linked.preset"
if list_mkinitcpio_images "${preset_dir}" >/dev/null; then
    fail "mkinitcpio image enumeration accepted a symlinked preset"
fi
rm -- "${preset_dir}/linked.preset"

cat > "${preset_dir}/linux-uki.preset" <<'PRESET_UKI'
PRESETS=('default')
default_uki="/efi/EFI/Linux/linux-uki.efi"
PRESET_UKI
if list_mkinitcpio_images "${preset_dir}" >/dev/null; then
    fail "mkinitcpio image enumeration accepted an unsupported UKI-only preset"
fi

[[ -x "${ROOT_INSTALLER}" && ! -L "${ROOT_INSTALLER}" ]] \
    || fail "div-meter root transaction is missing or not executable"

fake_bin="${test_tmp}/fake-bin"
mkdir -p "${fake_bin}"
cat > "${fake_bin}/mkinitcpio" <<'FAKE_MKINITCPIO'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 1 && "$1" == "-P" ]]
root="${DOTFILES_PLYMOUTH_TEST_ROOT:?}"
printf 'mkinitcpio -P\n' >> "${root}/mkinitcpio.calls"
index=0
while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    index=$((index + 1))
    printf 'generated image %s\n' "${index}" > "${root}${image}.new"
    mv -f -- "${root}${image}.new" "${root}${image}"
    if [[ "${FAKE_MKINITCPIO_FAIL_AFTER_FIRST:-0}" == 1 && "${index}" -eq 1 ]]; then
        exit 70
    fi
done < "${root}/image-list"
FAKE_MKINITCPIO

cat > "${fake_bin}/lsinitcpio" <<'FAKE_LSINITCPIO'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-x" ]]; then
    image="${2:?}"
    grep -Fq 'generated image' "${image}"
    mkdir -p \
        etc/plymouth \
        usr/lib/plymouth \
        usr/share/plymouth/themes/div-meter
    cp -- "${DOTFILES_PLYMOUTH_TEST_ROOT:?}/etc/plymouth/plymouthd.conf" \
        etc/plymouth/plymouthd.conf
    if [[ "${FAKE_LSINITCPIO_WRONG_CONFIG:-0}" == 1 ]]; then
        sed -i 's/Theme=div-meter/Theme=cachyos/' etc/plymouth/plymouthd.conf
    fi
    [[ "${FAKE_LSINITCPIO_CONFIG_DRIFT:-0}" != 1 ]] \
        || printf '# unexpected initramfs drift\n' >> etc/plymouth/plymouthd.conf
    : > usr/lib/plymouth/script.so
    cp -a -- "${DOTFILES_PLYMOUTH_TEST_THEME:?}/." \
        usr/share/plymouth/themes/div-meter/
    [[ "${FAKE_LSINITCPIO_BAD:-0}" != 1 ]] \
        || rm -- usr/share/plymouth/themes/div-meter/end32.png
    exit 0
fi
image="${1:?}"
grep -Fq 'generated image' "${image}"
printf '%s\n' \
    etc/plymouth/plymouthd.conf \
    usr/lib/plymouth/script.so \
    usr/share/plymouth/themes/div-meter/SHA256SUMS \
    usr/share/plymouth/themes/div-meter/UPSTREAM
while read -r digest relative_path extra; do
    [[ -z "${extra:-}" ]]
    if [[ "${FAKE_LSINITCPIO_BAD:-0}" == 1 && "${relative_path}" == end32.png ]]; then
        continue
    fi
    printf 'usr/share/plymouth/themes/div-meter/%s\n' "${relative_path}"
done < "${DOTFILES_PLYMOUTH_TEST_MANIFEST:?}"
FAKE_LSINITCPIO

cat > "${fake_bin}/grub-mkconfig" <<'FAKE_GRUB_MKCONFIG'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAKE_GRUB_MKCONFIG_FAIL:-0}" != 1 ]] || exit 71
[[ "$#" -eq 2 && "$1" == "-o" ]]
mkdir -p -- "${2%/*}"
# The real generator sources this file; keep the fake output tied to the same inputs.
source "${DOTFILES_PLYMOUTH_TEST_ROOT:?}/etc/default/grub"
fixture_arguments="${GRUB_CMDLINE_LINUX:-} ${GRUB_CMDLINE_LINUX_DEFAULT:-}"
main_linux_arguments="root=fixture rw ${fixture_arguments}"
main_linuxefi_arguments="${main_linux_arguments}"
if [[ "${FAKE_GRUB_DROP_MAIN_GLOBAL_ARGUMENT:-0}" == 1 ]]; then
    main_linuxefi_arguments="${main_linuxefi_arguments/audit=0/}"
fi
if [[ "${FAKE_GRUB_DROP_ALL_DEFAULT_ARGUMENT:-0}" == 1 ]]; then
    main_linux_arguments="${main_linux_arguments/loglevel=3/}"
    main_linuxefi_arguments="${main_linuxefi_arguments/loglevel=3/}"
fi
cat > "$2" <<GRUB_CFG
menuentry 'CachyOS fixture Linux' {
    linux /boot/vmlinuz-linux-cachyos ${main_linux_arguments}
}
menuentry 'CachyOS fixture Linux EFI' {
    linuxefi /boot/vmlinuz-linux-cachyos ${main_linuxefi_arguments}
}
GRUB_CFG
if [[ "${FAKE_GRUB_CREATE_BTRFS:-0}" == 1 ]]; then
    if [[ "${FAKE_GRUB_EMPTY_BTRFS:-0}" == 1 ]]; then
        printf "submenu 'CachyOS snapshots' {\n}\n" > "${2%/*}/grub-btrfs.cfg"
        exit 0
    fi
    snapshot_linux_arguments="root=fixture rw ${fixture_arguments}"
    snapshot_linuxefi_arguments="${snapshot_linux_arguments}"
    if [[ "${FAKE_GRUB_DROP_BTRFS_GLOBAL_ARGUMENT:-0}" == 1 ]]; then
        snapshot_linuxefi_arguments="${snapshot_linuxefi_arguments/audit=0/}"
    fi
    cat > "${2%/*}/grub-btrfs.cfg" <<GRUB_BTRFS_CFG
submenu 'CachyOS snapshots' {
    menuentry 'snapshot Linux' {
        linux /boot/vmlinuz-linux-cachyos ${snapshot_linux_arguments}
    }
    menuentry 'snapshot Linux EFI' {
        linuxefi /boot/vmlinuz-linux-cachyos ${snapshot_linuxefi_arguments}
    }
}
GRUB_BTRFS_CFG
fi
FAKE_GRUB_MKCONFIG

cat > "${fake_bin}/grub-script-check" <<'FAKE_GRUB_SCRIPT_CHECK'
#!/usr/bin/env bash
set -euo pipefail
[[ -s "${1:?}" ]]
FAKE_GRUB_SCRIPT_CHECK
chmod +x "${fake_bin}/mkinitcpio" "${fake_bin}/lsinitcpio" \
    "${fake_bin}/grub-mkconfig" "${fake_bin}/grub-script-check"

make_fake_root() {
    local fake_root="$1"

    rm -rf -- "${fake_root}"
    mkdir -p \
        "${fake_root}/boot/grub" \
        "${fake_root}/etc/default" \
        "${fake_root}/etc/mkinitcpio.d" \
        "${fake_root}/etc/plymouth" \
        "${fake_root}/usr/lib/plymouth" \
        "${fake_root}/usr/share/plymouth/themes/div-meter" \
        "${fake_root}/run/lock" \
        "${fake_root}/var"
    ln -s -- ../run/lock "${fake_root}/var/lock"
    : > "${fake_root}/usr/lib/plymouth/script.so"
    printf 'old theme\n' > "${fake_root}/usr/share/plymouth/themes/div-meter/old.marker"
    cat > "${fake_root}/etc/plymouth/plymouthd.conf" <<'PLYMOUTH_CONF'
[Daemon]
Theme=cachyos
# keep this comment
PLYMOUTH_CONF
    cat > "${fake_root}/etc/mkinitcpio.conf" <<'MKINIT_CONF'
MODULES=(i915)
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)
FILES=()
MKINIT_CONF
    cat > "${fake_root}/etc/default/grub" <<'GRUB_DEFAULT'
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog splash loglevel=3'
GRUB_CMDLINE_LINUX='audit=0'
GRUB_DEFAULT
    cat > "${fake_root}/boot/grub/grub.cfg" <<'GRUB_CFG'
menuentry 'CachyOS fixture' {
    linux /boot/vmlinuz-linux-cachyos root=fixture rw splash
}
GRUB_CFG
    cat > "${fake_root}/etc/mkinitcpio.d/linux-a.preset" <<'PRESET_A'
PRESETS=('default')
default_image="/boot/initramfs-linux-a.img"
PRESET_A
    cat > "${fake_root}/etc/mkinitcpio.d/linux-b.preset" <<'PRESET_B'
PRESETS=('default')
default_image="/boot/initramfs-linux-b.img"
PRESET_B
    printf 'old image a\n' > "${fake_root}/boot/initramfs-linux-a.img"
    printf 'old image b\n' > "${fake_root}/boot/initramfs-linux-b.img"
    printf '/boot/initramfs-linux-a.img\n/boot/initramfs-linux-b.img\n' \
        > "${fake_root}/image-list"
}

run_fake_transaction() {
    local fake_root="$1"
    shift
    env \
        PATH="${fake_bin}:/usr/bin:/bin" \
        DOTFILES_PLYMOUTH_ROOT="${fake_root}" \
        DOTFILES_PLYMOUTH_TEST_ROOT="${fake_root}" \
        DOTFILES_PLYMOUTH_TEST_MANIFEST="${MANIFEST}" \
        DOTFILES_PLYMOUTH_TEST_THEME="${THEME_DIR}" \
        "$@" \
        "${ROOT_INSTALLER}" "${THEME_DIR}"
}

snapshot_fake_root() {
    local fake_root="$1"
    local snapshot="$2"

    mkdir -p "${snapshot}"
    cp -a -- "${fake_root}/etc/plymouth/plymouthd.conf" "${snapshot}/plymouthd.conf"
    cp -a -- "${fake_root}/etc/mkinitcpio.conf" "${snapshot}/mkinitcpio.conf"
    cp -a -- "${fake_root}/etc/default/grub" "${snapshot}/grub-default"
    cp -a -- "${fake_root}/boot/grub/grub.cfg" "${snapshot}/grub.cfg"
    if [[ -f "${fake_root}/boot/grub/grub-btrfs.cfg" ]]; then
        : > "${snapshot}/had-grub-btrfs"
        cp -a -- "${fake_root}/boot/grub/grub-btrfs.cfg" "${snapshot}/grub-btrfs.cfg"
    fi
    cp -a -- "${fake_root}/boot/initramfs-linux-a.img" "${snapshot}/initramfs-a"
    cp -a -- "${fake_root}/boot/initramfs-linux-b.img" "${snapshot}/initramfs-b"
    if [[ -d "${fake_root}/usr/share/plymouth/themes/div-meter" ]]; then
        : > "${snapshot}/had-theme"
        cp -a -- "${fake_root}/usr/share/plymouth/themes/div-meter" "${snapshot}/theme"
    fi
}

assert_restored_fake_root() {
    local fake_root="$1"
    local snapshot="$2"

    cmp -s "${snapshot}/plymouthd.conf" "${fake_root}/etc/plymouth/plymouthd.conf" \
        || fail "rollback did not restore the Plymouth config"
    cmp -s "${snapshot}/mkinitcpio.conf" "${fake_root}/etc/mkinitcpio.conf" \
        || fail "rollback did not restore mkinitcpio.conf"
    cmp -s "${snapshot}/grub-default" "${fake_root}/etc/default/grub" \
        || fail "rollback did not restore GRUB defaults"
    cmp -s "${snapshot}/grub.cfg" "${fake_root}/boot/grub/grub.cfg" \
        || fail "rollback did not restore grub.cfg"
    if [[ -f "${snapshot}/had-grub-btrfs" ]]; then
        cmp -s "${snapshot}/grub-btrfs.cfg" "${fake_root}/boot/grub/grub-btrfs.cfg" \
            || fail "rollback did not restore grub-btrfs.cfg"
    elif [[ -e "${fake_root}/boot/grub/grub-btrfs.cfg" \
        || -L "${fake_root}/boot/grub/grub-btrfs.cfg" ]]; then
        fail "rollback retained grub-btrfs.cfg that did not exist before the transaction"
    fi
    cmp -s "${snapshot}/initramfs-a" "${fake_root}/boot/initramfs-linux-a.img" \
        || fail "rollback did not restore the first initramfs"
    cmp -s "${snapshot}/initramfs-b" "${fake_root}/boot/initramfs-linux-b.img" \
        || fail "rollback did not restore the second initramfs"
    if [[ -f "${snapshot}/had-theme" ]]; then
        diff -qr -- "${snapshot}/theme" "${fake_root}/usr/share/plymouth/themes/div-meter" >/dev/null \
            || fail "rollback did not restore the previous destination theme"
    elif [[ -e "${fake_root}/usr/share/plymouth/themes/div-meter" \
        || -L "${fake_root}/usr/share/plymouth/themes/div-meter" ]]; then
        fail "rollback retained a theme that did not exist before the transaction"
    fi
}

assert_preflight_rejected_without_mutation() {
    local fake_root="$1"
    local snapshot="$2"
    local description="$3"

    if run_fake_transaction "${fake_root}" >/dev/null 2>&1; then
        fail "root transaction accepted ${description}"
    fi
    assert_restored_fake_root "${fake_root}" "${snapshot}"
    [[ ! -e "${fake_root}/mkinitcpio.calls" ]] \
        || fail "${description} preflight invoked mkinitcpio"
    [[ ! -e "${fake_root}/run/lock/dotfiles-div-meter-plymouth.lock" \
        && ! -L "${fake_root}/run/lock/dotfiles-div-meter-plymouth.lock" ]] \
        || fail "${description} preflight created a transaction lock"
}

success_root="${test_tmp}/root-success"
make_fake_root "${success_root}"
mkinit_before="$(sha256sum "${success_root}/etc/mkinitcpio.conf" | awk '{print $1}')"
grub_default_before="$(sha256sum "${success_root}/etc/default/grub" | awk '{print $1}')"
grub_cfg_before="$(sha256sum "${success_root}/boot/grub/grub.cfg" | awk '{print $1}')"
success_output="$(run_fake_transaction "${success_root}")" \
    || fail "valid fake-root Plymouth transaction failed"
[[ -d "${success_root}/var/backups" && ! -L "${success_root}/var/backups" ]] \
    || fail "fresh fake-root transaction did not create a real backup directory"
[[ "$(stat -c '%a' "${success_root}/var/backups")" == 700 ]] \
    || fail "fresh fake-root backup directory must use mode 0700"
[[ "$(stat -c '%u' "${success_root}/var/backups")" == "${current_uid}" ]] \
    || fail "fresh fake-root backup directory must remain owned by the current user"
[[ -f "${success_root}/run/lock/dotfiles-div-meter-plymouth.lock" \
    && ! -L "${success_root}/run/lock/dotfiles-div-meter-plymouth.lock" ]] \
    || fail "fake-root transaction did not use the real /run/lock directory"
[[ -L "${success_root}/var/lock" ]] \
    || fail "fake-root transaction replaced the standard /var/lock symlink"
validate_div_meter_theme_tree \
    "${success_root}/usr/share/plymouth/themes/div-meter" \
    "${success_root}/usr/share/plymouth/themes/div-meter/SHA256SUMS" \
    || fail "installed fake-root theme failed validation"
grep -Fxq 'Theme=div-meter' "${success_root}/etc/plymouth/plymouthd.conf" \
    || fail "fake-root transaction did not select div-meter"
[[ "$(sha256sum "${success_root}/etc/mkinitcpio.conf" | awk '{print $1}')" == "${mkinit_before}" ]] \
    || fail "existing mkinitcpio hook order changed"
[[ "$(sha256sum "${success_root}/etc/default/grub" | awk '{print $1}')" == "${grub_default_before}" ]] \
    || fail "GRUB defaults changed even though splash already existed"
[[ "$(sha256sum "${success_root}/boot/grub/grub.cfg" | awk '{print $1}')" == "${grub_cfg_before}" ]] \
    || fail "grub.cfg changed even though splash already existed"
grep -Fq 'generated image' "${success_root}/boot/initramfs-linux-a.img" \
    || fail "first fake initramfs was not regenerated"
grep -Fq 'generated image' "${success_root}/boot/initramfs-linux-b.img" \
    || fail "second fake initramfs was not regenerated"
backup_dir="$(find "${success_root}/var/backups" -mindepth 1 -maxdepth 1 -type d -name 'dotfiles-div-meter-plymouth-*' -print -quit)"
[[ -n "${backup_dir}" && -f "${backup_dir}/initramfs/boot/initramfs-linux-a.img" ]] \
    || fail "fake-root transaction did not retain initramfs recovery data"
grep -Fq 'Backup:' <<< "${success_output}" \
    || fail "successful transaction must report its backup path"
[[ "$(wc -l < "${success_root}/mkinitcpio.calls")" -eq 1 ]] \
    || fail "successful fake-root transaction must rebuild exactly once"

rerun_output="$(run_fake_transaction "${success_root}")" \
    || fail "idempotent fake-root rerun failed"
grep -Fq 'already configured' <<< "${rerun_output}" \
    || fail "idempotent rerun did not report the stable state"
[[ "$(wc -l < "${success_root}/mkinitcpio.calls")" -eq 1 ]] \
    || fail "idempotent rerun rebuilt unchanged initramfs images"

run_lock_only_root="${test_tmp}/root-run-lock-only"
make_fake_root "${run_lock_only_root}"
rm -- "${run_lock_only_root}/var/lock"
run_fake_transaction "${run_lock_only_root}" >/dev/null \
    || fail "transaction depended on a /var/lock entry instead of real /run/lock"
[[ -f "${run_lock_only_root}/run/lock/dotfiles-div-meter-plymouth.lock" \
    && ! -L "${run_lock_only_root}/run/lock/dotfiles-div-meter-plymouth.lock" ]] \
    || fail "transaction without /var/lock did not create the /run/lock file"
[[ ! -e "${run_lock_only_root}/var/lock" && ! -L "${run_lock_only_root}/var/lock" ]] \
    || fail "transaction recreated or followed a /var/lock entry"

fresh_root="${test_tmp}/root-fresh"
make_fake_root "${fresh_root}"
rm -rf -- "${fresh_root}/usr/share/plymouth/themes/div-meter"
run_fake_transaction "${fresh_root}" >/dev/null \
    || fail "fresh fake-root Plymouth transaction failed"
validate_div_meter_theme_tree \
    "${fresh_root}/usr/share/plymouth/themes/div-meter" \
    "${fresh_root}/usr/share/plymouth/themes/div-meter/SHA256SUMS" \
    || fail "fresh fake-root transaction did not install a valid theme"

missing_hook_root="${test_tmp}/root-missing-hook"
make_fake_root "${missing_hook_root}"
sed -i 's/ sd-vconsole plymouth filesystems/ sd-vconsole filesystems/' \
    "${missing_hook_root}/etc/mkinitcpio.conf"
run_fake_transaction "${missing_hook_root}" >/dev/null \
    || fail "transaction could not add a missing Plymouth hook"
grep -Fxq 'HOOKS=(base systemd plymouth autodetect microcode kms modconf block keyboard sd-vconsole filesystems)' \
    "${missing_hook_root}/etc/mkinitcpio.conf" \
    || fail "transaction added the missing Plymouth hook incorrectly"

missing_splash_root="${test_tmp}/root-missing-splash"
make_fake_root "${missing_splash_root}"
sed -i 's/ splash//' "${missing_splash_root}/etc/default/grub"
run_fake_transaction "${missing_splash_root}" FAKE_GRUB_CREATE_BTRFS=1 >/dev/null \
    || fail "transaction could not add a missing GRUB splash argument"
grep -Fq "loglevel=3 splash" "${missing_splash_root}/etc/default/grub" \
    || fail "transaction did not persist the GRUB splash argument"
grep -Fq ' splash' "${missing_splash_root}/boot/grub/grub.cfg" \
    || fail "transaction did not activate a staged splash-enabled grub.cfg"
grep -Fq "CachyOS snapshots" "${missing_splash_root}/boot/grub/grub-btrfs.cfg" \
    || fail "transaction discarded a newly generated grub-btrfs.cfg"

stale_grub_root="${test_tmp}/root-stale-grub"
make_fake_root "${stale_grub_root}"
stale_grub_default_before="$(
    sha256sum "${stale_grub_root}/etc/default/grub" | awk '{print $1}'
)"
sed -i 's/ splash//' "${stale_grub_root}/boot/grub/grub.cfg"
run_fake_transaction "${stale_grub_root}" >/dev/null \
    || fail "transaction could not repair a stale splash-less grub.cfg"
[[ "$(sha256sum "${stale_grub_root}/etc/default/grub" | awk '{print $1}')" == "${stale_grub_default_before}" ]] \
    || fail "stale grub.cfg repair changed already-correct GRUB defaults"
grep -Fq ' splash' "${stale_grub_root}/boot/grub/grub.cfg" \
    || fail "transaction did not repair the stale splash-less grub.cfg"

for failure_case in after-theme fresh-after-theme term-after-theme after-config mkinitcpio validation embedded-config embedded-config-drift grub-generation grub-main-kernel-argument grub-btrfs-kernel-argument grub-all-default-argument grub-btrfs-no-linux-entries; do
    failure_root="${test_tmp}/root-failure-${failure_case}"
    make_fake_root "${failure_root}"
    failure_env=()
    case "${failure_case}" in
        after-theme|after-config)
            failure_env+=("DOTFILES_PLYMOUTH_FAILPOINT=${failure_case}")
            ;;
        fresh-after-theme)
            rm -rf -- "${failure_root}/usr/share/plymouth/themes/div-meter"
            failure_env+=(DOTFILES_PLYMOUTH_FAILPOINT=after-theme)
            ;;
        term-after-theme)
            failure_env+=(DOTFILES_PLYMOUTH_FAILPOINT=term-after-theme)
            ;;
        mkinitcpio)
            failure_env+=(FAKE_MKINITCPIO_FAIL_AFTER_FIRST=1)
            ;;
        validation)
            failure_env+=(FAKE_LSINITCPIO_BAD=1)
            ;;
        embedded-config)
            failure_env+=(FAKE_LSINITCPIO_WRONG_CONFIG=1)
            ;;
        embedded-config-drift)
            failure_env+=(FAKE_LSINITCPIO_CONFIG_DRIFT=1)
            ;;
        grub-generation)
            sed -i 's/ splash//' "${failure_root}/etc/default/grub"
            failure_env+=(FAKE_GRUB_MKCONFIG_FAIL=1)
            ;;
        grub-main-kernel-argument)
            sed -i 's/ splash//' "${failure_root}/etc/default/grub"
            failure_env+=(FAKE_GRUB_DROP_MAIN_GLOBAL_ARGUMENT=1)
            ;;
        grub-btrfs-kernel-argument)
            sed -i 's/ splash//' "${failure_root}/etc/default/grub"
            failure_env+=(FAKE_GRUB_CREATE_BTRFS=1 FAKE_GRUB_DROP_BTRFS_GLOBAL_ARGUMENT=1)
            ;;
        grub-all-default-argument)
            sed -i 's/ splash//' "${failure_root}/etc/default/grub"
            failure_env+=(FAKE_GRUB_DROP_ALL_DEFAULT_ARGUMENT=1)
            ;;
        grub-btrfs-no-linux-entries)
            sed -i 's/ splash//' "${failure_root}/etc/default/grub"
            failure_env+=(FAKE_GRUB_CREATE_BTRFS=1 FAKE_GRUB_EMPTY_BTRFS=1)
            ;;
    esac
    failure_snapshot="${test_tmp}/snapshot-${failure_case}"
    snapshot_fake_root "${failure_root}" "${failure_snapshot}"
    if run_fake_transaction "${failure_root}" "${failure_env[@]}" >/dev/null 2>&1; then
        fail "fake-root failure case unexpectedly succeeded: ${failure_case}"
    fi
    assert_restored_fake_root "${failure_root}" "${failure_snapshot}"
done

backup_symlink_root="${test_tmp}/root-backup-symlink"
backup_symlink_target="${test_tmp}/external-backups"
backup_symlink_sentinel="${backup_symlink_target}/sentinel"
make_fake_root "${backup_symlink_root}"
mkdir "${backup_symlink_target}"
printf 'do not mutate\n' > "${backup_symlink_sentinel}"
ln -s -- "${backup_symlink_target}" \
    "${backup_symlink_root}/var/backups"
backup_symlink_snapshot="${test_tmp}/snapshot-backup-symlink"
snapshot_fake_root "${backup_symlink_root}" \
    "${backup_symlink_snapshot}"
assert_preflight_rejected_without_mutation \
    "${backup_symlink_root}" "${backup_symlink_snapshot}" "a backup symlink"
[[ -L "${backup_symlink_root}/var/backups" ]] \
    || fail "backup symlink preflight replaced the unsafe path"
grep -Fxq 'do not mutate' "${backup_symlink_sentinel}" \
    || fail "backup symlink preflight mutated the external sentinel"
if [[ -n "$(find "${backup_symlink_target}" -mindepth 1 -maxdepth 1 \
    ! -path "${backup_symlink_sentinel}" -print -quit)" ]]; then
    fail "backup symlink preflight wrote transaction data outside the fake root"
fi

backup_dangling_root="${test_tmp}/root-backup-dangling"
backup_dangling_target="${test_tmp}/missing-external-backups"
make_fake_root "${backup_dangling_root}"
ln -s -- "${backup_dangling_target}" "${backup_dangling_root}/var/backups"
backup_dangling_snapshot="${test_tmp}/snapshot-backup-dangling"
snapshot_fake_root "${backup_dangling_root}" \
    "${backup_dangling_snapshot}"
assert_preflight_rejected_without_mutation \
    "${backup_dangling_root}" "${backup_dangling_snapshot}" "a dangling backup symlink"
[[ -L "${backup_dangling_root}/var/backups" \
    && ! -e "${backup_dangling_root}/var/backups" ]] \
    || fail "dangling backup symlink preflight replaced the unsafe path"
[[ ! -e "${backup_dangling_target}" && ! -L "${backup_dangling_target}" ]] \
    || fail "dangling backup symlink preflight created its external target"

backup_file_root="${test_tmp}/root-backup-file"
make_fake_root "${backup_file_root}"
printf 'do not replace\n' > "${backup_file_root}/var/backups"
backup_file_snapshot="${test_tmp}/snapshot-backup-file"
snapshot_fake_root "${backup_file_root}" "${backup_file_snapshot}"
assert_preflight_rejected_without_mutation \
    "${backup_file_root}" "${backup_file_snapshot}" "a backup regular file"
grep -Fxq 'do not replace' "${backup_file_root}/var/backups" \
    || fail "backup-file preflight replaced or mutated the sentinel file"

unsafe_root="${test_tmp}/root-unsafe"
make_fake_root "${unsafe_root}"
mv -- "${unsafe_root}/etc/plymouth/plymouthd.conf" \
    "${unsafe_root}/etc/plymouth/plymouthd.real"
ln -s -- plymouthd.real "${unsafe_root}/etc/plymouth/plymouthd.conf"
if run_fake_transaction "${unsafe_root}" >/dev/null 2>&1; then
    fail "root transaction accepted a symlinked Plymouth config"
fi
grep -Fxq 'old image a' "${unsafe_root}/boot/initramfs-linux-a.img" \
    || fail "unsafe preflight mutated an initramfs image"

lock_symlink_root="${test_tmp}/root-lock-symlink"
make_fake_root "${lock_symlink_root}"
lock_sentinel="${test_tmp}/lock-sentinel"
printf 'do not truncate\n' > "${lock_sentinel}"
ln -s -- "${lock_sentinel}" \
    "${lock_symlink_root}/run/lock/dotfiles-div-meter-plymouth.lock"
if run_fake_transaction "${lock_symlink_root}" >/dev/null 2>&1; then
    fail "root transaction accepted a symlinked lock file"
fi
grep -Fxq 'do not truncate' "${lock_sentinel}" \
    || fail "root transaction followed and truncated a symlinked lock file"

escaped_root="${test_tmp}/root-escaped"
escaped_etc="${test_tmp}/escaped-etc"
make_fake_root "${escaped_root}"
mv -- "${escaped_root}/etc" "${escaped_etc}"
ln -s -- "${escaped_etc}" "${escaped_root}/etc"
escaped_config_before="$(
    sha256sum "${escaped_etc}/plymouth/plymouthd.conf" | awk '{print $1}'
)"
if run_fake_transaction "${escaped_root}" >/dev/null 2>&1; then
    fail "root transaction accepted a descendant symlink escaping fake root"
fi
[[ "$(
    sha256sum "${escaped_etc}/plymouth/plymouthd.conf" | awk '{print $1}'
)" == "${escaped_config_before}" ]] \
    || fail "escaped fake-root preflight mutated the symlink target"

printf 'plymouth theme contract: ok\n'
