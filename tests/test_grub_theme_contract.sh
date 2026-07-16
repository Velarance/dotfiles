#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${ROOT}/lib/steinsgrub.conf"
MANIFEST="${ROOT}/lib/steinsgrub.sha256"
THEME_PATCH="${ROOT}/lib/steinsgrub-theme.patch"
UPSTREAM="${ROOT}/lib/steinsgrub-UPSTREAM"
LIBRARY="${ROOT}/lib/steinsgrub.sh"
ROOT_INSTALLER="${ROOT}/scripts/install-steinsgrub-root.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for metadata_file in "${CONF}" "${MANIFEST}" "${THEME_PATCH}" "${UPSTREAM}"; do
    [[ -f "${metadata_file}" ]] || fail "Steins;GRUB metadata is missing: ${metadata_file#"${ROOT}/"}"
done

# shellcheck source=../lib/steinsgrub.conf
source "${CONF}"

[[ "${STEINSGRUB_COMMIT}" == "147f7deb28aef2e2cd50ab67535945f4dd32f381" ]] \
    || fail "Steins;GRUB commit is not pinned to the audited revision"
[[ "${STEINSGRUB_ARCHIVE_SHA256}" == "2abd0545a4fcdbfdf70ca36e060e5dcd0b4b18332ebc4d8caf90bf6552b0d688" ]] \
    || fail "Steins;GRUB archive digest changed"
[[ "${STEINSGRUB_PATCHED_THEME_SHA256}" == "9e5d05ec49c45981c18c3d5b9cfaa8b5f093409f1563df8006fe4fe9b2391105" ]] \
    || fail "Steins;GRUB patched theme digest changed"
[[ "${STEINSGRUB_ARCHIVE_URL}" == "https://codeload.github.com/RansomDark/steinsgrub-theme/tar.gz/${STEINSGRUB_COMMIT}" ]] \
    || fail "Steins;GRUB archive URL must be commit-pinned"
[[ "${STEINSGRUB_USER_AGENT}" == Mozilla/5.0* ]] \
    || fail "Steins;GRUB requests must emulate a browser user agent"
[[ "${STEINSGRUB_ACCEPT}" == "application/octet-stream" ]] \
    || fail "Steins;GRUB requests must use the binary Accept header"
[[ "${STEINSGRUB_ACCEPT_LANGUAGE}" == "en-US,en;q=0.9" ]] \
    || fail "Steins;GRUB requests must set Accept-Language"
[[ "${STEINSGRUB_REFERER}" == "https://github.com/RansomDark/steinsgrub-theme" ]] \
    || fail "Steins;GRUB requests must set the upstream Referer"

manifest_count=0
declare -A manifest_paths=()
while read -r digest relative_path extra; do
    [[ -n "${digest}" && -n "${relative_path}" && -z "${extra:-}" ]] \
        || fail "Steins;GRUB manifest has an invalid row"
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] \
        || fail "Steins;GRUB manifest has an invalid SHA-256 for ${relative_path}"
    [[ "${relative_path}" != /* && "${relative_path}" != *..* && "${relative_path}" != */* ]] \
        || fail "Steins;GRUB manifest path is unsafe: ${relative_path}"
    [[ -z "${manifest_paths[${relative_path}]:-}" ]] \
        || fail "Steins;GRUB manifest path is duplicated: ${relative_path}"
    manifest_paths["${relative_path}"]=1
    ((manifest_count += 1))
done < "${MANIFEST}"
[[ "${manifest_count}" -eq 30 ]] \
    || fail "Steins;GRUB manifest must contain exactly 30 runtime files"

for required_file in theme.txt background.png IBMPlexMono-Thin-22.pf2 Orbitron-regular-30.pf2; do
    [[ -n "${manifest_paths[${required_file}]:-}" ]] \
        || fail "Steins;GRUB manifest is missing ${required_file}"
done

[[ "$(grep -Ec -- '^-[[:space:]]*item_font = "Orbitron regular 30"$' "${THEME_PATCH}")" -eq 1 ]] \
    || fail "Steins;GRUB patch must match the bad boot-menu font name"
[[ "$(grep -Ec -- '^\+[[:space:]]*item_font = "Orbitron Regular 30"$' "${THEME_PATCH}")" -eq 1 ]] \
    || fail "Steins;GRUB patch must correct the boot-menu font name"
[[ "$(grep -Ec -- '^-[[:space:]]*font = "Orbitron regular 30"$' "${THEME_PATCH}")" -eq 2 ]] \
    || fail "Steins;GRUB patch must match both bad label font names"
[[ "$(grep -Ec -- '^\+[[:space:]]*font = "Orbitron Regular 30"$' "${THEME_PATCH}")" -eq 2 ]] \
    || fail "Steins;GRUB patch must correct both label font names"
grep -Eq -- '^-[[:space:]]*widht = 600$' "${THEME_PATCH}" \
    || fail "Steins;GRUB patch must match the misspelled width"
grep -Eq -- '^\+[[:space:]]*width = 600$' "${THEME_PATCH}" \
    || fail "Steins;GRUB patch must correct the misspelled width"

grep -Fq "Commit: ${STEINSGRUB_COMMIT}" "${UPSTREAM}" \
    || fail "Steins;GRUB provenance must record the pinned commit"
grep -Fq "Archive-SHA256: ${STEINSGRUB_ARCHIVE_SHA256}" "${UPSTREAM}" \
    || fail "Steins;GRUB provenance must record the archive digest"
grep -Fq 'License: not provided by upstream' "${UPSTREAM}" \
    || fail "Steins;GRUB provenance must disclose the missing upstream license"

[[ -f "${LIBRARY}" ]] || fail "Steins;GRUB helper library is missing"
# shellcheck source=../lib/steinsgrub.sh
source "${LIBRARY}"
for helper in \
    fetch_steinsgrub_archive \
    validate_steinsgrub_theme_tree \
    prepare_steinsgrub_source \
    write_grub_theme_config \
    validate_steinsgrub_kernel_arguments \
    steinsgrub_source_path_is_trusted; do
    declare -F "${helper}" >/dev/null \
        || fail "Steins;GRUB helper is missing: ${helper}"
done

test_tmp="$(mktemp -d)"
trap 'rm -rf -- "${test_tmp}"' EXIT

fake_bin="${test_tmp}/bin"
curl_fixture="${test_tmp}/download-fixture.tar.gz"
curl_log="${test_tmp}/curl.log"
archive_cache="${test_tmp}/cache/theme.tar.gz"
mkdir -p "${fake_bin}" "${archive_cache%/*}"
printf 'pinned archive fixture\n' > "${curl_fixture}"
fixture_sha="$(sha256sum "${curl_fixture}" | awk '{ print $1 }')"

cat > "${fake_bin}/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${CURL_LOG:?}"
output=""
while (( $# )); do
    case "$1" in
        --output)
            output="${2:?}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[[ -n "${output}" ]]
cp -- "${CURL_FIXTURE:?}" "${output}"
FAKE_CURL
chmod +x "${fake_bin}/curl"

cp -- "${curl_fixture}" "${archive_cache}"
PATH="${fake_bin}:/usr/bin:/bin" \
    CURL_LOG="${curl_log}" \
    CURL_FIXTURE="${curl_fixture}" \
    fetch_steinsgrub_archive "${archive_cache}" "https://invalid.example/theme.tar.gz" "${fixture_sha}" \
    || fail "valid Steins;GRUB cache entry was rejected"
[[ ! -e "${curl_log}" ]] \
    || fail "valid Steins;GRUB cache entry must not trigger a download"

printf 'corrupt cache\n' > "${archive_cache}"
PATH="${fake_bin}:/usr/bin:/bin" \
    CURL_LOG="${curl_log}" \
    CURL_FIXTURE="${curl_fixture}" \
    fetch_steinsgrub_archive "${archive_cache}" "https://invalid.example/theme.tar.gz" "${fixture_sha}" \
    || fail "Steins;GRUB cache refresh failed"
cmp -s "${curl_fixture}" "${archive_cache}" \
    || fail "Steins;GRUB cache refresh did not install the verified archive"
for expected_arg in \
    "User-Agent: ${STEINSGRUB_USER_AGENT}" \
    "Accept: ${STEINSGRUB_ACCEPT}" \
    "Accept-Language: ${STEINSGRUB_ACCEPT_LANGUAGE}" \
    "Referer: ${STEINSGRUB_REFERER}"; do
    grep -Fxq -- "${expected_arg}" "${curl_log}" \
        || fail "Steins;GRUB curl request is missing '${expected_arg}'"
done

printf 'corrupt cache\n' > "${archive_cache}"
if PATH="${fake_bin}:/usr/bin:/bin" \
    CURL_LOG="${curl_log}" \
    CURL_FIXTURE="${curl_fixture}" \
    fetch_steinsgrub_archive "${archive_cache}" "https://invalid.example/theme.tar.gz" "$(printf '0%.0s' {1..64})"; then
    fail "Steins;GRUB downloader accepted a checksum mismatch"
fi
[[ ! -e "${archive_cache}" ]] \
    || fail "Steins;GRUB downloader retained an unverified cache entry"
! find "${archive_cache%/*}" -maxdepth 1 -name '*.part.*' -print -quit | grep -q . \
    || fail "Steins;GRUB downloader retained an unverified partial archive"

fixture_theme="${test_tmp}/fixture-theme"
fixture_manifest="${test_tmp}/fixture.sha256"
mkdir -p "${fixture_theme}"
printf 'theme\n' > "${fixture_theme}/theme.txt"
printf 'image\n' > "${fixture_theme}/background.png"
(
    cd "${fixture_theme}"
    sha256sum background.png theme.txt > "${fixture_manifest}"
)
validate_steinsgrub_theme_tree "${fixture_theme}" "${fixture_manifest}" \
    || fail "valid Steins;GRUB source tree was rejected"

printf 'extra\n' > "${fixture_theme}/extra.png"
validate_steinsgrub_theme_tree "${fixture_theme}" "${fixture_manifest}" >/dev/null 2>&1 \
    && fail "Steins;GRUB source validator accepted an extra file"
rm -f "${fixture_theme}/extra.png"
ln -s theme.txt "${fixture_theme}/link.txt"
validate_steinsgrub_theme_tree "${fixture_theme}" "${fixture_manifest}" >/dev/null 2>&1 \
    && fail "Steins;GRUB source validator accepted a symlink"
rm -f "${fixture_theme}/link.txt"
rm -f "${fixture_theme}/background.png"
validate_steinsgrub_theme_tree "${fixture_theme}" "${fixture_manifest}" >/dev/null 2>&1 \
    && fail "Steins;GRUB source validator accepted a missing file"
printf 'changed image\n' > "${fixture_theme}/background.png"
validate_steinsgrub_theme_tree "${fixture_theme}" "${fixture_manifest}" >/dev/null 2>&1 \
    && fail "Steins;GRUB source validator accepted a bad file hash"

grub_input="${test_tmp}/grub.in"
grub_output="${test_tmp}/grub.out"
cat > "${grub_input}" <<'GRUB_INPUT'
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT='keep-this-argument'
GRUB_THEME='/usr/share/grub/themes/old/theme.txt'
GRUB_DISABLE_OS_PROBER='false'
GRUB_INPUT
write_grub_theme_config \
    "${grub_input}" \
    "${grub_output}" \
    "/usr/share/grub/themes/steinsgrub/theme.txt" \
    || fail "Steins;GRUB config writer failed"
grep -Fxq "GRUB_THEME='/usr/share/grub/themes/steinsgrub/theme.txt'" "${grub_output}" \
    || fail "Steins;GRUB config writer did not select the new theme"
grep -Fxq "GRUB_CMDLINE_LINUX_DEFAULT='keep-this-argument'" "${grub_output}" \
    || fail "Steins;GRUB config writer changed kernel arguments"
[[ "$(grep -c '^GRUB_THEME=' "${grub_output}")" -eq 1 ]] \
    || fail "Steins;GRUB config writer produced duplicate theme assignments"

archive_build="${test_tmp}/archive-build"
archive_manifest="${test_tmp}/archive.sha256"
archive_fixture="${test_tmp}/archive.tar.gz"
archive_output="${test_tmp}/archive-output"
mkdir -p "${archive_build}/fixture-root/steinsgrub"
printf 'archive theme\n' > "${archive_build}/fixture-root/steinsgrub/theme.txt"
printf 'archive image\n' > "${archive_build}/fixture-root/steinsgrub/background.png"
(
    cd "${archive_build}/fixture-root/steinsgrub"
    sha256sum background.png theme.txt > "${archive_manifest}"
)
tar -czf "${archive_fixture}" -C "${archive_build}" fixture-root
prepare_steinsgrub_source \
    "${archive_fixture}" \
    "${archive_output}" \
    "${archive_manifest}" \
    fixture-root \
    || fail "valid Steins;GRUB archive was rejected"
validate_steinsgrub_theme_tree "${archive_output}" "${archive_manifest}" \
    || fail "prepared Steins;GRUB archive tree is invalid"

symlink_archive="${test_tmp}/symlink.tar.gz"
symlink_output="${test_tmp}/symlink-output"
rm -f "${archive_build}/fixture-root/steinsgrub/background.png"
ln -s theme.txt "${archive_build}/fixture-root/steinsgrub/background.png"
tar -czf "${symlink_archive}" -C "${archive_build}" fixture-root
prepare_steinsgrub_source \
    "${symlink_archive}" \
    "${symlink_output}" \
    "${archive_manifest}" \
    fixture-root >/dev/null 2>&1 \
    && fail "Steins;GRUB archive preparation accepted a symlink"
[[ ! -e "${symlink_output}" ]] \
    || fail "rejected Steins;GRUB archive left an extracted tree"

traversal_archive="${test_tmp}/traversal.tar.gz"
traversal_output="${test_tmp}/traversal-output"
rm -f "${archive_build}/fixture-root/steinsgrub/background.png"
printf 'archive image\n' > "${archive_build}/fixture-root/steinsgrub/background.png"
tar -czf "${traversal_archive}" \
    --transform='s|fixture-root/steinsgrub/theme.txt|fixture-root/../escape.txt|' \
    -C "${archive_build}" fixture-root
prepare_steinsgrub_source \
    "${traversal_archive}" \
    "${traversal_output}" \
    "${archive_manifest}" \
    fixture-root >/dev/null 2>&1 \
    && fail "Steins;GRUB archive preparation accepted path traversal"
[[ ! -e "${test_tmp}/escape.txt" && ! -e "${traversal_output}" ]] \
    || fail "rejected Steins;GRUB archive escaped its extraction directory"

export_grub_input="${test_tmp}/grub-export.in"
export_grub_output="${test_tmp}/grub-export.out"
cat > "${export_grub_input}" <<'EXPORT_GRUB'
GRUB_DEFAULT=0
export GRUB_THEME='/usr/share/grub/themes/old/theme.txt'
GRUB_DISABLE_OS_PROBER='false'
EXPORT_GRUB
write_grub_theme_config \
    "${export_grub_input}" \
    "${export_grub_output}" \
    "/usr/share/grub/themes/steinsgrub/theme.txt" \
    || fail "Steins;GRUB config writer rejected an exported theme assignment"
[[ "$(grep -Ec '^[[:space:]]*(export[[:space:]]+)?GRUB_THEME[[:space:]]*=' "${export_grub_output}")" -eq 1 ]] \
    || fail "Steins;GRUB config writer retained an exported duplicate"
! grep -Fq '/usr/share/grub/themes/old/theme.txt' "${export_grub_output}" \
    || fail "Steins;GRUB config writer retained the old exported theme"
printf '%s\n' "GRUB_THEME='/one'" "export GRUB_THEME='/two'" > "${export_grub_input}"
write_grub_theme_config \
    "${export_grub_input}" \
    "${export_grub_output}" \
    "/usr/share/grub/themes/steinsgrub/theme.txt" >/dev/null 2>&1 \
    && fail "Steins;GRUB config writer accepted duplicate theme assignments"

validator_defaults="${test_tmp}/grub-validator-defaults"
cat > "${validator_defaults}" <<'VALIDATOR_DEFAULTS'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"
GRUB_CMDLINE_LINUX='audit=0 lockdown=integrity'
VALIDATOR_DEFAULTS
validator_valid="${test_tmp}/grub-validator-valid.cfg"
cat > "${validator_valid}" <<'VALIDATOR_VALID'
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
menuentry 'fallback' --class recovery {
    linuxefi /boot/vmlinuz root=fixture audit=0 lockdown=integrity single
}
VALIDATOR_VALID
validate_steinsgrub_kernel_arguments "${validator_defaults}" "${validator_valid}" \
    || fail "Steins;GRUB validator rejected quoted defaults with ordered normal and recovery arguments"

validator_inline_submenu_commands="${test_tmp}/grub-validator-inline-submenu-commands.cfg"
cat > "${validator_inline_submenu_commands}" <<'VALIDATOR_INLINE_SUBMENU_COMMANDS'
submenu 'unexpected command' { configfile /boot/grub/other.cfg }
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
VALIDATOR_INLINE_SUBMENU_COMMANDS
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_inline_submenu_commands}"; then
    fail "Steins;GRUB validator accepted executable commands in an inline submenu"
fi

validator_grub_btrfs_wrappers="${test_tmp}/grub-validator-grub-btrfs-wrappers.cfg"
cat > "${validator_grub_btrfs_wrappers}" <<'VALIDATOR_GRUB_BTRFS_WRAPPERS'
menuentry '| Date | Snapshot | Type | Description |' { echo }
submenu '| Snapshot | Kernel | Options |' { echo }
submenu 'CachyOS Linux snapshots' {
    menuentry 'snapshot boot' {
        linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
    }
}
VALIDATOR_GRUB_BTRFS_WRAPPERS
validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_grub_btrfs_wrappers}" \
    || fail "Steins;GRUB validator rejected grub-btrfs display-only wrappers"

validator_inline_linux="${test_tmp}/grub-validator-inline-linux.cfg"
cat > "${validator_inline_linux}" <<'VALIDATOR_INLINE_LINUX'
menuentry 'inline kernel' { linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3 }
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
VALIDATOR_INLINE_LINUX
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_inline_linux}"; then
    fail "Steins;GRUB validator accepted an inline kernel command"
fi

validator_inline_commands="${test_tmp}/grub-validator-inline-commands.cfg"
cat > "${validator_inline_commands}" <<'VALIDATOR_INLINE_COMMANDS'
menuentry 'unexpected command' { echo; reboot }
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
VALIDATOR_INLINE_COMMANDS
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_inline_commands}"; then
    fail "Steins;GRUB validator accepted executable commands in an inline wrapper"
fi

validator_multiline_menuentry_body="${test_tmp}/grub-validator-multiline-menuentry-body.cfg"
cat > "${validator_multiline_menuentry_body}" <<'VALIDATOR_MULTILINE_MENUENTRY_BODY'
menuentry 'hidden body' { linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
VALIDATOR_MULTILINE_MENUENTRY_BODY
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_multiline_menuentry_body}"; then
    fail "Steins;GRUB validator accepted a command after a multiline menuentry brace"
fi

validator_multiline_submenu_body="${test_tmp}/grub-validator-multiline-submenu-body.cfg"
cat > "${validator_multiline_submenu_body}" <<'VALIDATOR_MULTILINE_SUBMENU_BODY'
submenu 'hidden body' { configfile /boot/grub/other.cfg
}
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
VALIDATOR_MULTILINE_SUBMENU_BODY
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_multiline_submenu_body}"; then
    fail "Steins;GRUB validator accepted a command after a multiline submenu brace"
fi

validator_extra_open_brace="${test_tmp}/grub-validator-extra-open-brace.cfg"
cat > "${validator_extra_open_brace}" <<'VALIDATOR_EXTRA_OPEN_BRACE'
menuentry 'malformed braces' {{
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
VALIDATOR_EXTRA_OPEN_BRACE
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_extra_open_brace}"; then
    fail "Steins;GRUB validator accepted a menuentry with an extra opening brace"
fi

validator_outside_entry="${test_tmp}/grub-validator-outside-entry.cfg"
printf '%s\n' \
    'linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3' \
    > "${validator_outside_entry}"
if validate_steinsgrub_kernel_arguments "${validator_defaults}" "${validator_outside_entry}"; then
    fail "Steins;GRUB validator accepted a kernel line outside an explicit menuentry"
fi

validator_nested_entry="${test_tmp}/grub-validator-nested-entry.cfg"
cat > "${validator_nested_entry}" <<'VALIDATOR_NESTED_ENTRY'
menuentry 'nested' {
    conditional {
        linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
    }
}
VALIDATOR_NESTED_ENTRY
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_nested_entry}"; then
    fail "Steins;GRUB validator accepted nested structural braces inside a menuentry"
fi

validator_no_linux="${test_tmp}/grub-validator-no-linux.cfg"
printf "%s\n" "submenu 'snapshots' {" '}' > "${validator_no_linux}"
if validate_steinsgrub_kernel_arguments "${validator_defaults}" "${validator_no_linux}"; then
    fail "Steins;GRUB validator accepted a config without Linux entries"
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
if validate_steinsgrub_kernel_arguments \
    "${validator_duplicate_defaults}" "${validator_duplicate_cfg}"; then
    fail "Steins;GRUB validator ignored duplicate argument multiplicity"
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
if validate_steinsgrub_kernel_arguments \
    "${validator_cross_duplicate_defaults}" "${validator_cross_duplicate_cfg}"; then
    fail "Steins;GRUB validator let one token satisfy cross-variable duplicates"
fi

validator_partial_normal="${test_tmp}/grub-validator-partial-normal.cfg"
cat > "${validator_partial_normal}" <<'VALIDATOR_PARTIAL_NORMAL'
menuentry 'complete normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3
}
menuentry 'incomplete normal' {
    linuxefi /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash
}
VALIDATOR_PARTIAL_NORMAL
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_partial_normal}"; then
    fail "Steins;GRUB validator let one complete normal entry mask another incomplete entry"
fi

validator_recovery_defaults_only="${test_tmp}/grub-validator-recovery-defaults-only.cfg"
cat > "${validator_recovery_defaults_only}" <<'VALIDATOR_RECOVERY_DEFAULTS_ONLY'
menuentry 'normal' {
    linux /boot/vmlinuz root=fixture audit=0 lockdown=integrity
}
menuentry 'fallback' --class recovery {
    linuxefi /boot/vmlinuz root=fixture audit=0 lockdown=integrity quiet splash loglevel=3 single
}
VALIDATOR_RECOVERY_DEFAULTS_ONLY
if validate_steinsgrub_kernel_arguments \
    "${validator_defaults}" "${validator_recovery_defaults_only}"; then
    fail "Steins;GRUB validator accepted defaults found only in a recovery entry"
fi

for reordered_kind in global defaults; do
    reordered_cfg="${test_tmp}/grub-validator-reordered-${reordered_kind}.cfg"
    if [[ "${reordered_kind}" == global ]]; then
        reordered_arguments='lockdown=integrity audit=0 quiet splash loglevel=3'
    else
        reordered_arguments='audit=0 lockdown=integrity splash quiet loglevel=3'
    fi
    printf "%s\n" \
        "menuentry 'reordered ${reordered_kind}' {" \
        "    linux /boot/vmlinuz root=fixture ${reordered_arguments}" \
        '}' > "${reordered_cfg}"
    if validate_steinsgrub_kernel_arguments "${validator_defaults}" "${reordered_cfg}"; then
        fail "Steins;GRUB validator ignored ${reordered_kind} argument order"
    fi
done

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
            '}' > "${ambiguous_cfg}"
    else
        printf '%s\n' \
            "GRUB_CMDLINE_LINUX_DEFAULT=''" \
            "GRUB_CMDLINE_LINUX='rd.luks.name=foo\ bar'" \
            > "${ambiguous_defaults}"
        printf '%s\n' \
            "menuentry 'escaped' {" \
            '    linux /boot/vmlinuz root=fixture rd.luks.name=foo\ bar' \
            '}' > "${ambiguous_cfg}"
    fi
    if validate_steinsgrub_kernel_arguments "${ambiguous_defaults}" "${ambiguous_cfg}"; then
        fail "Steins;GRUB validator unsafely accepted ${ambiguous_kind} kernel arguments"
    fi
done

trusted_defaults="${test_tmp}/grub-validator-trusted-defaults"
cp -- "${validator_defaults}" "${trusted_defaults}"
chmod 0644 "${trusted_defaults}"
current_uid="$(id -u)"
steinsgrub_source_path_is_trusted "${trusted_defaults}" "${current_uid}" \
    || fail "Steins;GRUB trust check rejected a protected owner-controlled file"
if steinsgrub_source_path_is_trusted "${trusted_defaults}" "$((current_uid + 1))"; then
    fail "Steins;GRUB trust check accepted the wrong owner"
fi
chmod 0664 "${trusted_defaults}"
if steinsgrub_source_path_is_trusted "${trusted_defaults}" "${current_uid}"; then
    fail "Steins;GRUB trust check accepted group-writable input"
fi

[[ -f "${ROOT_INSTALLER}" ]] \
    || fail "Steins;GRUB root transaction installer is missing"

transaction_source="${test_tmp}/transaction-source"
transaction_manifest="${test_tmp}/transaction.sha256"
transaction_patch="${test_tmp}/transaction.patch"
transaction_upstream="${test_tmp}/UPSTREAM"
transaction_root="${test_tmp}/root"
transaction_bin="${test_tmp}/transaction-bin"
mkdir -p "${transaction_source}" "${transaction_bin}"
printf 'bad-theme\n' > "${transaction_source}/theme.txt"
printf 'image\n' > "${transaction_source}/background.png"
(
    cd "${transaction_source}"
    sha256sum background.png theme.txt > "${transaction_manifest}"
)
cat > "${transaction_patch}" <<'TRANSACTION_PATCH'
--- a/theme.txt
+++ b/theme.txt
@@ -1 +1 @@
-bad-theme
+good-theme
TRANSACTION_PATCH
printf 'fixture provenance\n' > "${transaction_upstream}"
patched_fixture_sha="$(printf 'good-theme\n' | sha256sum | awk '{ print $1 }')"

cat > "${transaction_bin}/grub-mkconfig" <<'FAKE_GRUB_MKCONFIG'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (( $# )); do
    case "$1" in
        -o) output="${2:?}"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "${output}" ]]
[[ "${GRUB_BTRFS_GRUB_DIRNAME:?}" == "${output%/*}" ]]
[[ "${GRUB_BTRFS_GBTRFS_DIRNAME:?}" == "${output%/*}" ]]
mkdir -p -- "${output%/*}"
cat > "${output}" <<'GRUB_CFG'
set theme=($root)/usr/share/grub/themes/steinsgrub/theme.txt
menuentry 'CachyOS Linux' {
    linux /vmlinuz-linux root=test nowatchdog systemd.tpm2_wait=false
}
GRUB_CFG
if [[ "${FAKE_GRUB_DROP_WINDOWS:-0}" != 1 ]]; then
cat >> "${output}" <<'WINDOWS_CFG'
menuentry 'Windows Boot Manager' {
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
WINDOWS_CFG
fi
cat > "${GRUB_BTRFS_GBTRFS_DIRNAME}/grub-btrfs.cfg" <<'BTRFS_CFG'
submenu 'Snapshots' {
    menuentry 'Snapshot' {
        linux /vmlinuz-linux root=test nowatchdog systemd.tpm2_wait=false
    }
}
BTRFS_CFG
FAKE_GRUB_MKCONFIG
cat > "${transaction_bin}/grub-script-check" <<'FAKE_GRUB_CHECK'
#!/usr/bin/env bash
set -euo pipefail
[[ -s "${1:?}" ]]
FAKE_GRUB_CHECK
chmod +x "${transaction_bin}/grub-mkconfig" "${transaction_bin}/grub-script-check"

reset_transaction_root() {
    rm -rf -- "${transaction_root}"
    mkdir -p \
        "${transaction_root}/etc/default/grub-btrfs" \
        "${transaction_root}/boot/grub" \
        "${transaction_root}/usr/share/grub/themes/steinsgrub" \
        "${transaction_root}/var" \
        "${transaction_root}/run/lock"
    ln -s -- ../run/lock "${transaction_root}/var/lock"
    cat > "${transaction_root}/etc/default/grub" <<'DEFAULT_GRUB'
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog systemd.tpm2_wait=false'
GRUB_THEME='/usr/share/grub/themes/old/theme.txt'
GRUB_DISABLE_OS_PROBER='false'
DEFAULT_GRUB
    : > "${transaction_root}/etc/default/grub-btrfs/config"
    cat > "${transaction_root}/boot/grub/grub.cfg" <<'ACTIVE_GRUB'
menuentry 'CachyOS Linux' {
    linux /vmlinuz-linux root=test systemd.tpm2_wait=false
}
menuentry 'Windows Boot Manager' {
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
ACTIVE_GRUB
    cat > "${transaction_root}/boot/grub/grub-btrfs.cfg" <<'ACTIVE_BTRFS'
submenu 'Snapshots' {
    menuentry 'Snapshot' {
        linux /vmlinuz-linux root=test systemd.tpm2_wait=false
    }
}
ACTIVE_BTRFS
    printf 'old theme sentinel\n' \
        > "${transaction_root}/usr/share/grub/themes/steinsgrub/old.txt"
}

run_transaction() {
    PATH="${transaction_bin}:/usr/bin:/bin" \
    DOTFILES_STEINSGRUB_ROOT="${transaction_root}" \
    DOTFILES_STEINSGRUB_MANIFEST="${transaction_manifest}" \
    DOTFILES_STEINSGRUB_PATCH="${transaction_patch}" \
    DOTFILES_STEINSGRUB_UPSTREAM="${transaction_upstream}" \
    DOTFILES_STEINSGRUB_PATCHED_THEME_SHA256="${patched_fixture_sha}" \
    DOTFILES_STEINSGRUB_FAILPOINT="${DOTFILES_STEINSGRUB_FAILPOINT:-}" \
    FAKE_GRUB_DROP_WINDOWS="${FAKE_GRUB_DROP_WINDOWS:-0}" \
        bash "${ROOT_INSTALLER}" "${transaction_source}"
}

reset_transaction_root
run_transaction >/dev/null \
    || fail "Steins;GRUB root transaction failed"
[[ "$(< "${transaction_root}/usr/share/grub/themes/steinsgrub/theme.txt")" == 'good-theme' ]] \
    || fail "Steins;GRUB root transaction did not install the patched theme"
[[ -f "${transaction_root}/usr/share/grub/themes/steinsgrub/UPSTREAM" ]] \
    || fail "Steins;GRUB root transaction did not install provenance"
grep -Fxq "GRUB_THEME='/usr/share/grub/themes/steinsgrub/theme.txt'" \
    "${transaction_root}/etc/default/grub" \
    || fail "Steins;GRUB root transaction did not activate the theme"
grep -Fq 'Windows Boot Manager' "${transaction_root}/boot/grub/grub.cfg" \
    || fail "Steins;GRUB root transaction lost the Windows boot entry"
grep -Fq 'systemd.tpm2_wait=false' "${transaction_root}/boot/grub/grub.cfg" \
    || fail "Steins;GRUB root transaction lost existing kernel arguments"
grep -Fq 'nowatchdog systemd.tpm2_wait=false' "${transaction_root}/boot/grub/grub.cfg" \
    || fail "Steins;GRUB root transaction changed the kernel argument set"
[[ -d "${transaction_root}/var/backups" && ! -L "${transaction_root}/var/backups" ]] \
    || fail "Steins;GRUB transaction did not safely create /var/backups"
[[ "$(stat -c '%a' "${transaction_root}/var/backups")" == '700' ]] \
    || fail "Steins;GRUB transaction did not protect the created backup directory"
[[ "$(stat -c '%u:%g' "${transaction_root}/var/backups")" == "$(id -u):$(id -g)" ]] \
    || fail "Steins;GRUB fake-root backup directory has the wrong owner"
[[ -f "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" \
    && ! -L "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" ]] \
    || fail "Steins;GRUB transaction did not use the canonical /run/lock directory"

backup_dir="$(find "${transaction_root}/var/backups" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "${backup_dir}" ]] || fail "Steins;GRUB transaction did not retain a recovery backup"
grep -Fq "/usr/share/grub/themes/old/theme.txt" "${backup_dir}/default-grub" \
    || fail "Steins;GRUB backup does not contain the previous defaults"
grep -Fq 'Windows Boot Manager' "${backup_dir}/grub.cfg" \
    || fail "Steins;GRUB backup does not contain the previous main config"
grep -Fxq 'old theme sentinel' "${backup_dir}/theme/old.txt" \
    || fail "Steins;GRUB backup does not contain the previous theme"
run_transaction >/dev/null \
    || fail "Steins;GRUB transaction rejected an existing backup directory"

capture_transaction_state() {
    default_before="$(sha256sum "${transaction_root}/etc/default/grub")"
    grub_before="$(sha256sum "${transaction_root}/boot/grub/grub.cfg")"
    had_btrfs_before=0
    if [[ -f "${transaction_root}/boot/grub/grub-btrfs.cfg" ]]; then
        had_btrfs_before=1
        btrfs_before="$(sha256sum "${transaction_root}/boot/grub/grub-btrfs.cfg")"
    fi
    theme_before="$(sha256sum "${transaction_root}/usr/share/grub/themes/steinsgrub/old.txt")"
}

assert_transaction_restored() {
    [[ "$(sha256sum "${transaction_root}/etc/default/grub")" == "${default_before}" ]] \
        || fail "Steins;GRUB rollback did not restore /etc/default/grub"
    [[ "$(sha256sum "${transaction_root}/boot/grub/grub.cfg")" == "${grub_before}" ]] \
        || fail "Steins;GRUB rollback did not restore grub.cfg"
    if [[ "${had_btrfs_before}" -eq 1 ]]; then
        [[ "$(sha256sum "${transaction_root}/boot/grub/grub-btrfs.cfg")" == "${btrfs_before}" ]] \
            || fail "Steins;GRUB rollback did not restore grub-btrfs.cfg"
    elif [[ -e "${transaction_root}/boot/grub/grub-btrfs.cfg" \
        || -L "${transaction_root}/boot/grub/grub-btrfs.cfg" ]]; then
        fail "Steins;GRUB rollback retained grub-btrfs.cfg that did not exist before the transaction"
    fi
    [[ "$(sha256sum "${transaction_root}/usr/share/grub/themes/steinsgrub/old.txt")" == "${theme_before}" ]] \
        || fail "Steins;GRUB rollback did not restore the previous theme"
    for temporary_target in \
        "${transaction_root}/etc/default/grub.new" \
        "${transaction_root}/boot/grub/grub-btrfs.cfg.new" \
        "${transaction_root}/boot/grub/grub.cfg.new"; do
        [[ ! -e "${temporary_target}" ]] \
            || fail "Steins;GRUB rollback retained ${temporary_target#"${transaction_root}"}"
    done
}

reset_transaction_root
rm -f -- "${transaction_root}/var/lock"
run_transaction >/dev/null \
    || fail "Steins;GRUB transaction required a /var/lock alias"
[[ ! -e "${transaction_root}/var/lock" \
    && ! -L "${transaction_root}/var/lock" ]] \
    || fail "Steins;GRUB transaction recreated the absent /var/lock alias"
[[ -f "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" \
    && ! -L "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" ]] \
    || fail "Steins;GRUB transaction did not lock through /run/lock without a /var/lock alias"

reset_transaction_root
capture_transaction_state
dangling_backup_target="${test_tmp}/missing-steinsgrub-backups"
rm -rf -- "${dangling_backup_target}"
ln -s -- "${dangling_backup_target}" "${transaction_root}/var/backups"
if run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted a dangling /var/backups symlink"
fi
[[ -L "${transaction_root}/var/backups" ]] \
    || fail "Steins;GRUB transaction replaced the dangling /var/backups symlink"
[[ ! -e "${dangling_backup_target}" && ! -L "${dangling_backup_target}" ]] \
    || fail "Steins;GRUB transaction created the dangling backup target"
[[ ! -e "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" \
    && ! -L "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" ]] \
    || fail "Steins;GRUB backup preflight failure created a transaction lock"
assert_transaction_restored

reset_transaction_root
capture_transaction_state
external_backup_target="${test_tmp}/external-steinsgrub-backups"
rm -rf -- "${external_backup_target}"
mkdir -p -- "${external_backup_target}"
external_backup_sentinel="${external_backup_target}/sentinel"
printf 'do not mutate external backups\n' > "${external_backup_sentinel}"
external_backup_before="$(sha256sum "${external_backup_sentinel}")"
ln -s -- "${external_backup_target}" "${transaction_root}/var/backups"
if run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted an external /var/backups symlink"
fi
[[ -L "${transaction_root}/var/backups" ]] \
    || fail "Steins;GRUB transaction replaced the external /var/backups symlink"
[[ "$(sha256sum "${external_backup_sentinel}")" == "${external_backup_before}" ]] \
    || fail "Steins;GRUB transaction mutated the external backup sentinel"
[[ ! -e "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" \
    && ! -L "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" ]] \
    || fail "Steins;GRUB external-backup rejection created a transaction lock"
assert_transaction_restored

reset_transaction_root
capture_transaction_state
printf 'backup path sentinel\n' > "${transaction_root}/var/backups"
backup_file_before="$(sha256sum "${transaction_root}/var/backups")"
if run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted a regular-file /var/backups"
fi
[[ "$(sha256sum "${transaction_root}/var/backups")" == "${backup_file_before}" ]] \
    || fail "Steins;GRUB transaction mutated the regular-file /var/backups"
[[ ! -e "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" \
    && ! -L "${transaction_root}/run/lock/dotfiles-steinsgrub.lock" ]] \
    || fail "Steins;GRUB regular-file rejection created a transaction lock"
assert_transaction_restored

for failpoint in after-theme term-after-theme after-default after-generation after-sidecar before-main; do
    reset_transaction_root
    capture_transaction_state
    if DOTFILES_STEINSGRUB_FAILPOINT="${failpoint}" run_transaction >/dev/null 2>&1; then
        fail "Steins;GRUB failure injection '${failpoint}' unexpectedly succeeded"
    fi
    assert_transaction_restored
done

reset_transaction_root
rm -f -- "${transaction_root}/boot/grub/grub-btrfs.cfg"
capture_transaction_state
if DOTFILES_STEINSGRUB_FAILPOINT=after-sidecar run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB no-prior-sidecar rollback injection unexpectedly succeeded"
fi
assert_transaction_restored

reset_transaction_root
capture_transaction_state
if FAKE_GRUB_DROP_WINDOWS=1 run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted a generated config without Windows"
fi
assert_transaction_restored

reset_transaction_root
capture_transaction_state
cat > "${transaction_root}/etc/default/grub-btrfs/config" <<'EXPORTED_BTRFS_OVERRIDE'
export GRUB_BTRFS_GRUB_DIRNAME=/tmp/unsafe-main
  export   GRUB_BTRFS_GBTRFS_DIRNAME = /tmp/unsafe-sidecar
EXPORTED_BTRFS_OVERRIDE
if run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted exported grub-btrfs staging overrides"
fi
assert_transaction_restored

reset_transaction_root
capture_transaction_state
lock_sentinel="${test_tmp}/steinsgrub-lock-sentinel"
printf 'do not truncate\n' > "${lock_sentinel}"
ln -s -- "${lock_sentinel}" \
    "${transaction_root}/run/lock/dotfiles-steinsgrub.lock"
if run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted a symlinked lock file"
fi
assert_transaction_restored
grep -Fxq 'do not truncate' "${lock_sentinel}" \
    || fail "Steins;GRUB transaction followed and truncated a symlinked lock file"

reset_transaction_root
capture_transaction_state
escaped_etc="${test_tmp}/steinsgrub-escaped-etc"
rm -rf -- "${escaped_etc}"
mv -- "${transaction_root}/etc" "${escaped_etc}"
ln -s -- "${escaped_etc}" "${transaction_root}/etc"
escaped_default_before="$(sha256sum "${escaped_etc}/default/grub")"
if run_transaction >/dev/null 2>&1; then
    fail "Steins;GRUB transaction accepted a descendant symlink escaping fake root"
fi
[[ "$(sha256sum "${escaped_etc}/default/grub")" == "${escaped_default_before}" ]] \
    || fail "Steins;GRUB escaped-root preflight mutated the symlink target"
assert_transaction_restored

printf 'grub theme transaction contract: ok\n'
