#!/usr/bin/env bash

# Contract checks for the Amadeus SDDM migration.  Keep this test independent
# from a live SDDM installation: the Xsetup behavior runs against fake xrandr.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_CONF="${ROOT}/lib/packages.conf"
INSTALLER="${ROOT}/install.sh"
SDDM_CONF="${ROOT}/config/sddm/sddm.conf"
THEME_DIR="${ROOT}/config/sddm/themes/amadeus"
METADATA="${THEME_DIR}/metadata.desktop"
THEME_CONF="${THEME_DIR}/theme.conf"
UPSTREAM="${THEME_DIR}/UPSTREAM"
CHECKSUMS="${THEME_DIR}/SHA256SUMS"
OVERRIDE="${ROOT}/config/sddm/dotfiles-override.conf"
XSETUP="${ROOT}/config/sddm/scripts/Xsetup-dotfiles"

failures=0
test_tmp="$(mktemp -d)"

cleanup() {
    rm -rf -- "${test_tmp}"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

require_readable() {
    local path="$1"
    local description="$2"

    [[ -r "${path}" ]] || {
        fail "${description} is missing or unreadable: ${path}"
        return 1
    }
}

assert_setting() {
    local path="$1"
    local key="$2"
    local value="$3"

    grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*(#.*)?$" "${path}" \
        || fail "${path#"${ROOT}/"} must set ${key}=${value}"
}

assert_array_contains() {
    local array_name="$1"
    local wanted="$2"
    local package
    local -n packages_ref="${array_name}"

    for package in "${packages_ref[@]}"; do
        [[ "${package}" == "${wanted}" ]] && return 0
    done

    fail "${array_name} must contain ${wanted}"
}

assert_array_excludes() {
    local array_name="$1"
    local unwanted="$2"
    local package
    local -n packages_ref="${array_name}"

    for package in "${packages_ref[@]}"; do
        [[ "${package}" == "${unwanted}" ]] \
            && fail "${array_name} must not contain ${unwanted}" \
            && return 1
    done
}

installer_function_body() {
    local function_name="$1"

    awk -v function_name="${function_name}" '
        $0 ~ ("^[[:space:]]*" function_name "[[:space:]]*\\(\\)[[:space:]]*\\{") {
            capture = 1
        }
        capture {
            print
            opens = gsub(/\{/, "{")
            closes = gsub(/\}/, "}")
            depth += opens - closes
            if (depth == 0) {
                exit
            }
        }
    ' "${INSTALLER}"
}

line_number() {
    local haystack="$1"
    local pattern="$2"

    awk -v pattern="${pattern}" '$0 ~ pattern { print NR; exit }' <<< "${haystack}"
}

assert_log_calls() {
    local label="$1"
    local log="$2"
    shift 2
    local -a expected=("$@")
    local -a actual=()
    local index

    mapfile -t actual < "${log}"
    if [[ "${#actual[@]}" -ne "${#expected[@]}" ]]; then
        fail "Xsetup ${label} expected ${#expected[@]} event(s), got ${#actual[@]}"
        return
    fi

    for index in "${!expected[@]}"; do
        [[ "${actual[${index}]}" == "${expected[${index}]}" ]] \
            || fail "Xsetup ${label} event $((index + 1)) must be '${expected[${index}]}' (got '${actual[${index}]}')"
    done
}

run_xsetup_fixture() {
    local fixture_dir="${test_tmp}/xsetup-fixture"
    local fake_bin="${fixture_dir}/bin"
    local primary_output="${fixture_dir}/primary-output"
    local base_xsetup="${fixture_dir}/Xsetup"
    local fixture_xsetup="${fixture_dir}/Xsetup-dotfiles"
    local event_log="${fixture_dir}/events.log"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/xrandr" <<'FAKE_XRANDR'
#!/usr/bin/env bash
set -uo pipefail

printf 'xrandr %s\n' "$*" >> "${XSETUP_EVENT_LOG}"

case "${1:-}" in
    --query)
        printf '%s\n' "${XSETUP_QUERY_OUTPUT:-DP-1 connected 1920x1080+0+0}"
        ;;
    --output)
        [[ "${2:-}" == 'DP-1' && "${3:-}" == '--primary' ]] || exit 64
        [[ "${XSETUP_PRIMARY_FAIL:-0}" != '1' ]] || exit 66
        ;;
    *)
        exit 65
        ;;
esac
FAKE_XRANDR
    chmod +x "${fake_bin}/xrandr"

    cat > "${base_xsetup}" <<'FAKE_BASE_XSETUP'
#!/usr/bin/env bash
printf '%s\n' base >> "${XSETUP_EVENT_LOG}"
FAKE_BASE_XSETUP
    chmod +x "${base_xsetup}"

    # Substitute only the system-owned state path in a disposable copy.
    sed \
        -e "s|/usr/share/sddm/scripts/Xsetup|${base_xsetup}|g" \
        -e "s|/etc/sddm/primary-output|${primary_output}|g" \
        -e "s|/usr/bin/xrandr|${fake_bin}/xrandr|g" \
        "${XSETUP}" > "${fixture_xsetup}"
    chmod +x "${fixture_xsetup}"

    : > "${event_log}"
    rm -f -- "${primary_output}"
    if ! XSETUP_EVENT_LOG="${event_log}" bash "${fixture_xsetup}"; then
        fail 'Xsetup must succeed without a saved primary output'
    fi
    assert_log_calls 'without config' "${event_log}" base

    : > "${event_log}"
    printf '%s\n' 'DP-1' > "${primary_output}"
    if ! XSETUP_EVENT_LOG="${event_log}" bash "${fixture_xsetup}"; then
        fail 'Xsetup must succeed with a valid saved primary output'
    fi
    assert_log_calls 'with DP-1' "${event_log}" \
        base 'xrandr --query' 'xrandr --output DP-1 --primary'

    : > "${event_log}"
    printf '%s\n' 'stale-output' > "${primary_output}"
    if ! XSETUP_EVENT_LOG="${event_log}" bash "${fixture_xsetup}"; then
        fail 'Xsetup must tolerate a stale saved primary output'
    fi
    assert_log_calls 'with stale output' "${event_log}" base 'xrandr --query'

    : > "${event_log}"
    printf '%s\n' 'DP-1;bad' > "${primary_output}"
    if ! XSETUP_EVENT_LOG="${event_log}" bash "${fixture_xsetup}"; then
        fail 'Xsetup must tolerate an invalid saved primary output'
    fi
    assert_log_calls 'with invalid output' "${event_log}" base

    : > "${event_log}"
    printf '%s\n' 'DP-2' > "${primary_output}"
    if ! XSETUP_EVENT_LOG="${event_log}" XSETUP_QUERY_OUTPUT='DP-2 disconnected primary' bash "${fixture_xsetup}"; then
        fail 'Xsetup must tolerate a disconnected saved primary output'
    fi
    assert_log_calls 'with disconnected output' "${event_log}" base 'xrandr --query'

    : > "${event_log}"
    printf '%s\n' 'DP-1' > "${primary_output}"
    if ! XSETUP_EVENT_LOG="${event_log}" XSETUP_PRIMARY_FAIL=1 bash "${fixture_xsetup}"; then
        fail 'Xsetup must tolerate a hot-unplug race while setting primary'
    fi
    assert_log_calls 'with primary race' "${event_log}" \
        base 'xrandr --query' 'xrandr --output DP-1 --primary'
}

if require_readable "${PACKAGES_CONF}" 'package declarations'; then
    # shellcheck source=../lib/packages.conf
    source "${PACKAGES_CONF}"
    for package in sddm qt6-5compat qt6-virtualkeyboard xorg-xrandr; do
        assert_array_contains OPTIONAL_PACKAGES "${package}"
        assert_array_excludes CORE_PACKAGES "${package}"
    done
    assert_array_excludes CORE_PACKAGES sddm-silent-theme
    assert_array_excludes OPTIONAL_PACKAGES sddm-silent-theme
fi

if require_readable "${SDDM_CONF}" 'SDDM configuration'; then
    assert_setting "${SDDM_CONF}" DisplayServer x11
    assert_setting "${SDDM_CONF}" ThemeDir /usr/share/sddm/themes
    assert_setting "${SDDM_CONF}" Current amadeus
    assert_setting "${SDDM_CONF}" DisplayCommand /usr/local/lib/sddm/Xsetup-dotfiles
fi

if require_readable "${OVERRIDE}" 'final SDDM override'; then
    assert_setting "${OVERRIDE}" DisplayServer x11
    assert_setting "${OVERRIDE}" ThemeDir /usr/share/sddm/themes
    assert_setting "${OVERRIDE}" Current amadeus
    assert_setting "${OVERRIDE}" DisplayCommand /usr/local/lib/sddm/Xsetup-dotfiles
    grep -Fq '# BEGIN DOTFILES SDDM OVERRIDE' "${OVERRIDE}" \
        || fail 'final SDDM override must have a managed marker'
fi

if require_readable "${METADATA}" 'vendored Amadeus metadata'; then
    assert_setting "${METADATA}" QtVersion 6
    assert_setting "${METADATA}" Theme-Id amadeus
fi

if require_readable "${THEME_CONF}" 'vendored Amadeus theme.conf'; then
    assert_setting "${THEME_CONF}" MirrorScreens false
fi

for theme_file in \
    COPYING IPA_Font_License_Agreement_v1.0.txt Main.qml \
    amadeus-background.png amadeus-secondary.png \
    components/SpComboBox.qml components/SpTextBox.qml \
    fonts/TakaoMincho.ttf kurisu.gif vk.qml; do
    require_readable "${THEME_DIR}/${theme_file}" "vendored Amadeus ${theme_file}"
done
if require_readable "${CHECKSUMS}" 'Amadeus checksum manifest'; then
    [[ "$(sha256sum "${CHECKSUMS}" | awk '{print $1}')" == 'c7fd03497037e11af13f2ef7e2043d6a40814443a0a21bcf844ff3f45dd903f7' ]] \
        || fail 'Amadeus checksum manifest must match the pinned installer digest'
fi


if require_readable "${UPSTREAM}" 'Amadeus upstream provenance'; then
    grep -Fq 'https://github.com/jericjan/sddm-theme-amadeus' "${UPSTREAM}" \
        || fail 'Amadeus provenance must name the upstream repository'
    grep -Fq 'ad42165b22e4d7ce69dcef8fef6caa3e9d6f88f3' "${UPSTREAM}" \
        || fail 'Amadeus provenance must pin the reviewed upstream commit'
fi

if require_readable "${THEME_DIR}/components/SpTextBox.qml" 'Amadeus Qt5Compat component'; then
    grep -Fq 'Qt5Compat.GraphicalEffects' "${THEME_DIR}/components/SpTextBox.qml" \
        || fail 'Amadeus must use the Qt6 Qt5Compat graphical-effects import'
fi

if [[ ! -e "${XSETUP}" ]]; then
    fail "custom Xsetup source is missing: ${XSETUP#"${ROOT}/"}"
elif [[ ! -x "${XSETUP}" ]]; then
    fail "custom Xsetup source must be executable: ${XSETUP#"${ROOT}/"}"
elif ! bash -n "${XSETUP}"; then
    fail "custom Xsetup source must be Bash syntax-valid: ${XSETUP#"${ROOT}/"}"
else
    run_xsetup_fixture
fi

formatter_body="$(installer_function_body format_sddm_monitor_options)"
if [[ -z "${formatter_body}" ]]; then
    fail 'install.sh must define format_sddm_monitor_options'
else
    eval "${formatter_body}"
    monitor_fixture='[
        {"name":"DP-1","description":"Main\tPanel\nOffice","width":1920,"height":1080,"disabled":false},
        {"name":"DP-1","description":"Main\tPanel\nOffice","width":1920,"height":1080,"disabled":false},
        {"name":"HDMI-A-1","description":"","width":0,"height":0,"disabled":true},
        {"name":"DP-1;bad","description":"Injected","width":1,"height":1,"disabled":false}
    ]'
    if ! formatted_monitors_output="$(format_sddm_monitor_options <<< "${monitor_fixture}")"; then
        fail 'monitor formatter must accept a valid Hyprland monitor array'
    else
        mapfile -t formatted_monitors <<< "${formatted_monitors_output}"
        [[ ${#formatted_monitors[@]} -eq 2 ]] \
            || fail 'monitor formatter must deduplicate connectors and reject unsafe names'
        [[ "${formatted_monitors[0]:-}" == $'DP-1\tMain Panel Office\t1920x1080\tactive in Hyprland' ]] \
            || fail 'monitor formatter must sanitize descriptions without creating extra menu rows'
        [[ "${formatted_monitors[1]:-}" == $'HDMI-A-1\tUnknown display\tmode unknown\tdisabled in Hyprland' ]] \
            || fail 'monitor formatter must keep disabled outputs in the primary-display menu'
    fi

    if format_sddm_monitor_options <<< '{}' >/dev/null 2>&1; then
        fail 'monitor formatter must reject a non-array response'
    fi
    if format_sddm_monitor_options <<< '{' >/dev/null 2>&1; then
        fail 'monitor formatter must reject malformed JSON'
    fi
fi
if require_readable "${INSTALLER}" 'installer'; then
    setup_body="$(installer_function_body setup_sddm)"
    if [[ -z "${setup_body}" ]]; then
        fail 'install.sh must define setup_sddm'
    else
        grep -Eq 'hyprctl[[:space:]]+-j[[:space:]]+monitors' <<< "${setup_body}" \
            || fail 'setup_sddm must query monitors with hyprctl -j monitors'
        grep -Eq '(^|[;[:space:]])(select|read)[[:space:]]' <<< "${setup_body}" \
            || fail 'setup_sddm must offer a Bash select/read primary-output choice'
        if grep -Eq '(^|[^[:alnum:]_])gum([^[:alnum:]_]|$)' <<< "${setup_body}"; then
            fail 'setup_sddm must not depend on gum'
        fi

        grep -Fq '[[ -z "${primary_output:-}"' <<< "${setup_body}" \
            || fail 'setup_sddm must leave SDDM unchanged when no primary output is selected'

        if grep -Eq 'sudo[[:space:]]+cp[[:space:]]+-a[^#]*/usr/share/sddm/themes/amadeus' <<< "${setup_body}"; then
            fail 'setup_sddm must not preserve unprivileged ownership while staging the theme'
        fi
        grep -Fq 'sudo chown -R root:root "$theme_stage"' <<< "${setup_body}" \
            || fail 'setup_sddm must make staged Amadeus files root-owned'
        grep -Fq 'sudo find "$theme_stage" -type f -exec chmod 0644 {} +' <<< "${setup_body}" \
            || fail 'setup_sddm must set safe modes on staged Amadeus files'

        grep -Fq '/etc/sddm/primary-output' <<< "${setup_body}" \
            || fail 'setup_sddm must create /etc/sddm/primary-output'
        grep -Fq 'sudo install -o root -g root -m 0644 /dev/stdin "$primary_stage"' <<< "${setup_body}" \
            || fail 'setup_sddm must stage the selected primary output as root'
        grep -Fq 'sudo mv -fT "$primary_stage" "$primary_target"' <<< "${setup_body}" \
            || fail 'setup_sddm must atomically activate the selected primary output'

        grep -Fq 'install_sddm_final_override "${override_source}"' <<< "${setup_body}" \
            || fail 'setup_sddm must install the final highest-priority SDDM override'
        grep -Fq '[[ ! -f "${hook_source}" || ! -r "${hook_source}" || ! -x "${hook_source}" || -L "${hook_source}" ]]' <<< "${setup_body}" \
            || fail 'setup_sddm must reject an unsafe Xsetup source before package changes'
        grep -Fq '! bash -n "${hook_source}"' <<< "${setup_body}" \
            || fail 'setup_sddm must syntax-check Xsetup before package changes'
        grep -Fq '[[ ! -f "${drop_in_source}" || ! -r "${drop_in_source}" || -L "${drop_in_source}" ]]' <<< "${setup_body}" \
            || fail 'setup_sddm must reject an unsafe drop-in source before package changes'
        grep -Fq -- '--exchange' <<< "${setup_body}" \
            || fail 'setup_sddm must preflight atomic theme exchange support'
        theme_stage_line="$(line_number "${setup_body}" 'sudo[[:space:]]+cp[[:space:]]+-r[^#]*theme_stage')"
        hook_stage_line="$(line_number "${setup_body}" 'sudo[[:space:]]+install[^#]*hook_stage')"
        staged_validation_line="$(line_number "${setup_body}" 'validate_amadeus_theme_tree[^#]*theme_stage')"
        source_preflight_line="$(line_number "${setup_body}" 'validate_amadeus_theme_tree')"
        package_install_line="$(line_number "${setup_body}" 'sudo[[:space:]]+pacman[[:space:]]+-S')"
        drop_in_line="$(line_number "${setup_body}" 'sudo[[:space:]]+install[^#]*drop_in_stage')"
        theme_activation_line="$(line_number "${setup_body}" 'activate_amadeus_theme_tree')"
        smoke_line="$(line_number "${setup_body}" 'smoke_test_sddm_theme')"

        [[ -n "${theme_stage_line}" ]] \
            || fail 'setup_sddm must stage the vendored Amadeus theme'
        [[ -n "${hook_stage_line}" ]] \
            || fail 'setup_sddm must stage Xsetup-dotfiles'
        [[ -n "${staged_validation_line}" ]] \
            || fail 'setup_sddm must validate the complete staged Amadeus tree'
        [[ -n "${source_preflight_line}" ]] \
            || fail 'setup_sddm must preflight the vendored Amadeus tree'
        [[ -n "${package_install_line}" ]] \
            || fail 'setup_sddm must install missing SDDM dependencies when needed'
        if [[ -n "${source_preflight_line}" && -n "${package_install_line}" ]] \
            && (( source_preflight_line >= package_install_line )); then
            fail 'setup_sddm must preflight vendored Amadeus files before sudo pacman'
        fi
        [[ -n "${drop_in_line}" ]] \
            || fail 'setup_sddm must write /etc/sddm.conf.d/99-dotfiles.conf'
        grep -Fq 'local sddm_backup_dir="/etc/sddm/dotfiles-backups"' <<< "${setup_body}" \
            || fail 'setup_sddm must keep backups outside the watched sddm.conf.d directory'
        if grep -Eq 'local (drop_in_stage|drop_in_backup|legacy_drop_in_backup)="/etc/sddm\.conf\.d/' <<< "${setup_body}"; then
            fail 'setup_sddm must not place staging or backup files in the watched sddm.conf.d directory'
        fi
        grep -Fq 'sudo rm -f -- "$legacy_drop_in_target"' <<< "${setup_body}" \
            || fail 'setup_sddm must remove the obsolete 10-dotfiles.conf after migration'
        grep -Fq 'sudo pacman -R --noconfirm sddm-silent-theme' <<< "${setup_body}" \
            || fail 'setup_sddm must remove the obsolete Silent theme package after activation'

        grep -Fq 'sudo mv -fT "$hook_stage" "$hook_target"' <<< "${setup_body}" \
            || fail 'setup_sddm must atomically activate the staged Xsetup hook'
        grep -Fq 'activate_amadeus_theme_tree "$theme_stage" "$theme_target" "$theme_backup"' <<< "${setup_body}" \
            || fail 'setup_sddm must delegate atomic Amadeus activation'
        grep -Fq 'smoke_test_sddm_theme "$theme_target"' <<< "${setup_body}" \
            || fail 'setup_sddm must smoke-test Amadeus before writing SDDM state'
        grep -Fq 'sudo mv -fT "$drop_in_stage" "$drop_in_target"' <<< "${setup_body}" \
            || fail 'setup_sddm must atomically activate the staged SDDM drop-in'

        if [[ -n "${theme_stage_line}" && -n "${hook_stage_line}" \
            && -n "${staged_validation_line}" && -n "${drop_in_line}" ]]; then
            if (( theme_stage_line >= staged_validation_line \
                || hook_stage_line >= staged_validation_line \
                || staged_validation_line >= drop_in_line )); then
                fail 'setup_sddm must stage theme and hook before staged-tree validation and 99-dotfiles.conf'
            fi
        fi
    fi
        if [[ -n "${theme_activation_line}" && -n "${smoke_line}" && -n "${drop_in_line}" ]] \
            && (( theme_activation_line >= smoke_line || smoke_line >= drop_in_line )); then
            fail 'setup_sddm must activate, smoke-test, then publish SDDM configuration in order'
        fi


fi

activation_body="$(installer_function_body activate_amadeus_theme_tree)"
if [[ -z "${activation_body}" ]]; then
    fail 'install.sh must define activate_amadeus_theme_tree'
else
    grep -Fq 'trap '\''signal_status=130'\'' INT' <<< "${activation_body}" \
        || fail 'Amadeus activation must defer INT across theme exchanges'
    grep -Fq 'trap '\''signal_status=143'\'' TERM' <<< "${activation_body}" \
        || fail 'Amadeus activation must defer TERM across theme exchanges'
    grep -Fq 'sudo mv --exchange --no-copy -T "$theme_stage" "$theme_backup"' <<< "${activation_body}" \
        || fail 'Amadeus activation must atomically rotate an existing rollback tree'

    print_warning() { :; }
    eval "${activation_body}"
    SIGNAL_ON_THEME_EXCHANGE=0
    SIGNAL_THEME_TARGET=''
    sudo() {
        local command_name="$1"
        local command_status
        shift
        if [[ "$command_name" == mv ]] \
            && (( SIGNAL_ON_THEME_EXCHANGE )) \
            && [[ " $* " == *" --exchange "* && "${@: -1}" == "$SIGNAL_THEME_TARGET" ]]; then
            command mv "$@"
            command_status=$?
            SIGNAL_ON_THEME_EXCHANGE=0
            (( command_status == 0 )) && kill -TERM "$BASHPID"
            return "$command_status"
        fi
        command "$command_name" "$@"
    }

    activation_fixture="${test_tmp}/theme-activation"
    theme_stage_fixture="${activation_fixture}/stage"
    theme_target_fixture="${activation_fixture}/target"
    theme_backup_fixture="${activation_fixture}/backup"
    mkdir -p "${theme_stage_fixture}" "${theme_target_fixture}" "${theme_backup_fixture}"
    printf 'new\n' > "${theme_stage_fixture}/marker"
    printf 'current\n' > "${theme_target_fixture}/marker"
    printf 'older-backup\n' > "${theme_backup_fixture}/marker"
    if ! activate_amadeus_theme_tree "${theme_stage_fixture}" "${theme_target_fixture}" "${theme_backup_fixture}"; then
        fail 'Amadeus activation must rotate an existing target and arbitrary older backup'
    fi
    [[ "$(< "${theme_target_fixture}/marker")" == new ]] \
        || fail 'atomic theme activation must publish the staged tree'
    [[ "$(< "${theme_backup_fixture}/marker")" == current ]] \
        || fail 'theme rollback must become the immediately previous active tree'
    [[ ! -e "${theme_stage_fixture}" ]] \
        || fail 'successful theme rotation must clean the displaced older backup'

    rm -rf -- "${activation_fixture}"
    mkdir -p "${theme_stage_fixture}" "${theme_target_fixture}"
    printf 'new-after-signal\n' > "${theme_stage_fixture}/marker"
    printf 'current-before-signal\n' > "${theme_target_fixture}/marker"
    SIGNAL_ON_THEME_EXCHANGE=1
    SIGNAL_THEME_TARGET="${theme_target_fixture}"
    if activate_amadeus_theme_tree "${theme_stage_fixture}" "${theme_target_fixture}" "${theme_backup_fixture}"; then
        fail 'a deferred TERM must be reported after theme state becomes safe'
    else
        activation_status=$?
        [[ "$activation_status" -eq 143 ]] \
            || fail 'deferred TERM must return status 143'
    fi
    [[ "$(< "${theme_target_fixture}/marker")" == new-after-signal ]] \
        || fail 'deferred TERM must leave the new theme active'
    [[ "$(< "${theme_backup_fixture}/marker")" == current-before-signal ]] \
        || fail 'deferred TERM must preserve the previous active theme'
    [[ ! -e "${theme_stage_fixture}" ]] \
        || fail 'deferred TERM must not leave an ambiguous staging tree'
    unset -f sudo
fi

override_body="$(installer_function_body install_sddm_final_override)"
if [[ -z "${override_body}" ]]; then
    fail 'install.sh must define install_sddm_final_override'
else
    grep -Fq 'if (in_override || invalid) exit 65' <<< "${override_body}" \
        || fail 'final override merge must fail closed on invalid marker structure'
    grep -Fq 'block_closed' <<< "${override_body}" \
        || fail 'final override merge must require the managed block at EOF'
    grep -Fq 'validate_sddm_managed_override_source "$override_snapshot"' <<< "${override_body}" \
        || fail 'final override must validate the exact snapshotted override bytes'
    grep -Fq 'sudo mv --exchange --no-copy -T "$staged_config" /etc/sddm.conf' <<< "${override_body}" \
        || fail 'final override must atomically exchange an existing /etc/sddm.conf'
    grep -Fq 'sudo cmp -s -- "$original_config" "$staged_config"' <<< "${override_body}" \
        || fail 'final override must verify the displaced config against its snapshot'
    grep -Fq 'sudo mv --update=none-fail --no-copy -T "$staged_config" /etc/sddm.conf' <<< "${override_body}" \
        || fail 'final override must create a previously absent config without clobbering'
fi

validator_body="$(installer_function_body validate_amadeus_theme_tree)"
if [[ -z "${validator_body}" ]]; then
    fail 'install.sh must define validate_amadeus_theme_tree'
else
    grep -Fq '[[ ! -f "${theme_dir}/${theme_file}"' <<< "${validator_body}" \
        || fail 'Amadeus manifest validation must require regular files'
    grep -Fq 'find "$theme_dir" -type l -print -quit' <<< "${validator_body}" \
        || fail 'Amadeus validation must reject symlinks anywhere in the tree'

    AMADEUS_THEME_FILES=(
        COPYING IPA_Font_License_Agreement_v1.0.txt Main.qml
        amadeus-background.png amadeus-secondary.png
        components/SpComboBox.qml components/SpTextBox.qml
        fonts/TakaoMincho.ttf kurisu.gif metadata.desktop theme.conf vk.qml
    )
    AMADEUS_CHECKSUM_MANIFEST_SHA256='c7fd03497037e11af13f2ef7e2043d6a40814443a0a21bcf844ff3f45dd903f7'
    print_error() { :; }
    eval "${validator_body}"
    if ! validate_amadeus_theme_tree "${THEME_DIR}"; then
        fail 'vendored Amadeus tree must match all pinned asset checksums'
    fi
    checksum_fixture="${test_tmp}/amadeus-checksum-fixture"
    cp -a -- "${THEME_DIR}" "${checksum_fixture}"
    printf '\n// changed\n' >> "${checksum_fixture}/Main.qml"
    if validate_amadeus_theme_tree "${checksum_fixture}" >/dev/null 2>&1; then
        fail 'Amadeus validation must reject a modified runtime asset'
    fi
    extra_fixture="${test_tmp}/amadeus-extra-file-fixture"
    cp -a -- "${THEME_DIR}" "${extra_fixture}"
    printf 'module Injected\n' > "${extra_fixture}/components/qmldir"
    if validate_amadeus_theme_tree "${extra_fixture}" >/dev/null 2>&1; then
        fail 'Amadeus validation must reject files absent from the pinned manifest'
    fi
    validator_fixture="${test_tmp}/amadeus-symlink-fixture"
    cp -a -- "${THEME_DIR}" "${validator_fixture}"
    mv -- "${validator_fixture}/components" "${validator_fixture}/components-real"
    ln -s components-real "${validator_fixture}/components"
    if validate_amadeus_theme_tree "${validator_fixture}"; then
        fail 'Amadeus validation must reject a symlinked parent directory'
    fi
fi

backup_helper_body="$(installer_function_body create_root_file_backup_once)"
backup_locked_body="$(installer_function_body create_root_file_backup_once_locked)"
backup_implementation="${backup_helper_body}"$'\n'"${backup_locked_body}"
if [[ -z "${backup_helper_body}" || -z "${backup_locked_body}" ]]; then
    fail 'install.sh must define locked root backup helpers'
else
    grep -Fq 'flock -x "$lock_fd"' <<< "${backup_helper_body}" \
        || fail 'root backup helper must serialize each backup publication'
    grep -Fq 'sudo cmp -s -- "$source_path" "$staged_backup"' <<< "${backup_implementation}" \
        || fail 'root backup helper must validate staged backup bytes'
    grep -Fq 'sudo mv --update=none-fail -T "$staged_backup" "$backup_path"' <<< "${backup_implementation}" \
        || fail 'root backup helper must publish first backups atomically without clobbering'
    grep -Fq 'sudo test -L "$source_path"' <<< "${backup_implementation}" \
        || fail 'root backup helper must reject symlink sources'
    grep -Fq 'validate_root_file_backup "$backup_path"' <<< "${backup_implementation}" \
        || fail 'root backup helper must checksum-validate existing backups'
fi

while IFS= read -r -d '' wallpaper_script; do
    if grep -Eq '/sddm/themes/(silent|sugar-candy)(/|["[:space:]]|$)' "${wallpaper_script}"; then
        fail "executable wallpaper script still targets a legacy SDDM theme: ${wallpaper_script#"${ROOT}/"}"
    fi
done < <(find "${ROOT}/config" -type f -perm -u+x -name '*wallpaper*.sh' -print0)

if (( failures > 0 )); then
    printf 'sddm contract: %d failure(s)\n' "${failures}" >&2
    exit 1
fi

printf 'sddm contract: ok\n'
