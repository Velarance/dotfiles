#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/install.sh"
README="${ROOT}/README.md"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

clone_command=$(grep -E '^git clone ' "${README}" || true)
[[ "${clone_command}" == 'git clone https://github.com/Velarance/dotfiles.git ~/dotfiles' ]] \
    || fail "README must use the canonical Velarance clone command"
! grep -Fq 'say8hi/dotfiles' "${README}" \
    || fail "README still references say8hi/dotfiles"

optional_readme_section=$(sed -n '/^\*\*Optional:\*\*$/,/^### Installation$/p' "${README}")
if grep -Eq '(^|[[:space:]])nautilus([[:space:]]|$)' <<< "${optional_readme_section}"; then
    fail "README still lists required nautilus as optional"
fi

grep -Fq 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then' "${INSTALLER}" \
    || fail "install.sh must guard main when sourced"

main_body=$(sed -n '/^main() {$/,/^}$/p' "${INSTALLER}")
optional_call_line=$(grep -nFx '    install_optional_packages' <<< "${main_body}" | cut -d: -f1 || true)
nautilus_call_line=$(grep -nFx '    setup_nautilus_integration' <<< "${main_body}" | cut -d: -f1 || true)
symlinks_call_line=$(grep -nFx '    create_symlinks' <<< "${main_body}" | cut -d: -f1 || true)
user_services_call_line=$(grep -nFx '    setup_user_services' <<< "${main_body}" | cut -d: -f1 || true)
sddm_call_line=$(grep -nFx '    setup_sddm' <<< "${main_body}" | cut -d: -f1 || true)
grub_theme_call_line=$(grep -nFx '    setup_grub_theme' <<< "${main_body}" | cut -d: -f1 || true)
plymouth_call_line=$(grep -nFx '    setup_plymouth' <<< "${main_body}" | cut -d: -f1 || true)
[[ -n "${optional_call_line}" && -n "${nautilus_call_line}" ]] \
    || fail "main must call setup_nautilus_integration"
[[ "${nautilus_call_line}" -eq $((optional_call_line + 1)) ]] \
    || fail "main must configure Nautilus immediately after optional packages"
[[ -n "${symlinks_call_line}" && -n "${user_services_call_line}" ]] \
    || fail "main must call setup_user_services"
[[ "${user_services_call_line}" -eq $((symlinks_call_line + 1)) ]] \
    || fail "main must install user services immediately after config symlinks"
[[ -n "${sddm_call_line}" && -n "${grub_theme_call_line}" ]] \
    || fail "main must call setup_grub_theme"
[[ "${grub_theme_call_line}" -eq $((sddm_call_line + 1)) ]] \
    || fail "main must configure the GRUB theme immediately after SDDM"
[[ -n "${plymouth_call_line}" ]] \
    || fail "main must call setup_plymouth"
[[ "${plymouth_call_line}" -eq $((grub_theme_call_line + 1)) ]] \
    || fail "main must configure Plymouth immediately after the GRUB theme"

grep -Fq 'source "${DOTFILES_DIR}/lib/div-meter-plymouth.sh"' "${INSTALLER}" \
    || fail "install.sh must load the div-meter helper library"
grep -Fq 'Set up the vendored Divergence Meter Plymouth theme' "${INSTALLER}" \
    || fail "installer summary must disclose the Plymouth boot change"

if ! source_result=$(timeout 5 bash -c '
    source "$1"
    printf "sourced\n"
' bash "${INSTALLER}" </dev/null); then
    fail "sourcing install.sh did not return successfully"
fi

[[ "${source_result}" == "sourced" ]] \
    || fail "sourcing install.sh must not run main"

test_tmp=$(mktemp -d)
trap 'rm -rf -- "${test_tmp}"' EXIT

local_home="${test_tmp}/local-home"
mkdir -p "${local_home}/.config/hypr/conf"
printf 'monitor = test-output\n' \
    > "${local_home}/.config/hypr/conf/local.conf.example"

if ! HOME="${local_home}" bash -c '
    set -euo pipefail
    source "$1"
    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    setup_local_config
    [[ -f "${HOME}/.config/hypr/conf/local.conf.example" ]]
    [[ -f "${HOME}/.config/hypr/conf/local.conf" ]]
    cmp -s \
        "${HOME}/.config/hypr/conf/local.conf.example" \
        "${HOME}/.config/hypr/conf/local.conf"
    [[ -f "${HOME}/.config/hypr/monitors.conf" ]]
    [[ ! -s "${HOME}/.config/hypr/monitors.conf" ]]
    [[ -f "${HOME}/.config/hypr/workspaces.conf" ]]
    [[ ! -s "${HOME}/.config/hypr/workspaces.conf" ]]
    printf "generated monitor sentinel\n" > "${HOME}/.config/hypr/monitors.conf"
    printf "generated workspace sentinel\n" > "${HOME}/.config/hypr/workspaces.conf"
    setup_local_config
    [[ "$(< "${HOME}/.config/hypr/monitors.conf")" == "generated monitor sentinel" ]]
    [[ "$(< "${HOME}/.config/hypr/workspaces.conf")" == "generated workspace sentinel" ]]
' bash "${INSTALLER}"; then
    fail "setup_local_config must preserve templates and generated display state"
fi

symlink_home="${test_tmp}/symlink-home"
symlink_hypr="${test_tmp}/symlink-target/hypr"
mkdir -p "${symlink_home}/.config" "${symlink_hypr}/conf"
printf 'env = SYMLINK_TEST,1\n' > "${symlink_hypr}/conf/local.conf.example"
ln -s "${symlink_hypr}" "${symlink_home}/.config/hypr"

if ! HOME="${symlink_home}" bash -c '
    set -euo pipefail
    source "$1"
    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    setup_local_config
    [[ -f "$2/monitors.conf" ]]
    [[ -f "$2/workspaces.conf" ]]
    printf "symlink monitor sentinel\n" > "$2/monitors.conf"
    printf "symlink workspace sentinel\n" > "$2/workspaces.conf"
    setup_local_config
    [[ "$(< "$2/monitors.conf")" == "symlink monitor sentinel" ]]
    [[ "$(< "$2/workspaces.conf")" == "symlink workspace sentinel" ]]
' bash "${INSTALLER}" "${symlink_hypr}"; then
    fail "setup_local_config must preserve generated state through the Hyprland directory symlink"
fi

service_home="${test_tmp}/service-home"
service_fake_bin="${test_tmp}/service-fake-bin"
service_systemctl_log="${test_tmp}/service-systemctl.log"
mkdir -p "${service_home}" "${service_fake_bin}"

cat > "${service_fake_bin}/systemctl" <<'FAKE_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG:?}"
FAKE_SYSTEMCTL
chmod +x "${service_fake_bin}/systemctl"

if ! HOME="${service_home}" \
    PATH="${service_fake_bin}:/usr/bin:/bin" \
    SYSTEMCTL_LOG="${service_systemctl_log}" \
    bash -c '
        set -euo pipefail
        source "$1"
        print_header() { :; }
        print_success() { :; }
        print_warning() { :; }
        setup_user_services
        service_link="${HOME}/.config/systemd/user/polkit-gnome-authentication-agent.service"
        [[ -L "${service_link}" ]]
        [[ "$(readlink -- "${service_link}")" == "${DOTFILES_DIR}/config/systemd/user/polkit-gnome-authentication-agent.service" ]]
    ' bash "${INSTALLER}"; then
    fail "setup_user_services must link the supervised polkit unit"
fi

[[ "$(< "${service_systemctl_log}")" == '--user daemon-reload' ]] \
    || fail "setup_user_services must only reload the user systemd manager"

grub_home="${test_tmp}/grub-home"
grub_fake_bin="${test_tmp}/grub-fake-bin"
grub_cfg_fixture="${test_tmp}/grub.cfg"
grub_sudo_log="${test_tmp}/grub-sudo.log"
mkdir -p "${grub_home}" "${grub_fake_bin}"
printf "menuentry 'fixture' {}\n" > "${grub_cfg_fixture}"
cat > "${grub_fake_bin}/grub-mkconfig" <<'FAKE_GRUB_MKCONFIG_COMMAND'
#!/usr/bin/env bash
exit 0
FAKE_GRUB_MKCONFIG_COMMAND
chmod +x "${grub_fake_bin}/grub-mkconfig"

if ! HOME="${grub_home}" \
    PATH="${grub_fake_bin}:/usr/bin:/bin" \
    DOTFILES_GRUB_CFG_PATH="${grub_cfg_fixture}" \
    GRUB_SUDO_LOG="${grub_sudo_log}" \
    bash -c '
        set -euo pipefail
        source "$1"
        print_header() { :; }
        print_success() { :; }
        print_warning() { :; }
        ask_confirmation() {
            [[ "$1" == "Install Steins;Gate GRUB theme?" ]]
        }
        fetch_steinsgrub_archive() {
            local destination="$1"
            [[ "$2" == "${STEINSGRUB_ARCHIVE_URL}" ]]
            [[ "$3" == "${STEINSGRUB_ARCHIVE_SHA256}" ]]
            mkdir -p "${destination%/*}"
            printf "archive fixture\n" > "${destination}"
        }
        prepare_steinsgrub_source() {
            local archive="$1"
            local output_dir="$2"
            [[ -f "${archive}" ]]
            [[ "$3" == "${DOTFILES_DIR}/lib/steinsgrub.sha256" ]]
            [[ "$4" == "steinsgrub-theme-${STEINSGRUB_COMMIT}" ]]
            mkdir -p "${output_dir}"
            printf "theme fixture\n" > "${output_dir}/theme.txt"
        }
        sudo() {
            [[ "$1" == "${DOTFILES_DIR}/scripts/install-steinsgrub-root.sh" ]]
            [[ -f "$2/theme.txt" ]]
            printf "%s\n" "$1" > "${GRUB_SUDO_LOG:?}"
        }
        setup_grub_theme
    ' bash "${INSTALLER}"; then
    fail "setup_grub_theme orchestration probe failed"
fi

grep -Fxq "${ROOT}/scripts/install-steinsgrub-root.sh" "${grub_sudo_log}" \
    || fail "setup_grub_theme did not invoke the pinned root transaction"

if HOME="${grub_home}" \
    PATH="${grub_fake_bin}:/usr/bin:/bin" \
    DOTFILES_GRUB_CFG_PATH="${grub_cfg_fixture}" \
    bash -c '
        set -euo pipefail
        source "$1"
        print_header() { :; }
        print_success() { :; }
        print_warning() { :; }
        print_error() { :; }
        ask_confirmation() {
            [[ "$1" == "Install Steins;Gate GRUB theme?" ]]
        }
        fetch_steinsgrub_archive() {
            return 1
        }
        setup_grub_theme
    ' bash "${INSTALLER}"; then
    fail "setup_grub_theme must propagate a failure after explicit confirmation"
fi

grep -Fq 'review the transaction output for rollback or recovery details' "${INSTALLER}" \
    || fail "setup_grub_theme failure guidance must not overstate rollback success"
! grep -Fq 'the previous GRUB state was restored' "${INSTALLER}" \
    || fail "setup_grub_theme must not claim an unverified rollback result"
! grep -Fq 'retained backup' "${INSTALLER}" \
    || fail "setup_grub_theme must not promise a backup before the transaction creates one"

plymouth_sudo_log="${test_tmp}/plymouth-sudo.log"
if ! PLYMOUTH_SUDO_LOG="${plymouth_sudo_log}" bash -c '
    set -euo pipefail
    source "$1"
    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    command_exists() { return 0; }
    ask_confirmation() {
        [[ "$1" == "Install Divergence Meter Plymouth theme?" ]]
    }
    sudo() {
        [[ "$1" == "${DOTFILES_DIR}/scripts/install-div-meter-plymouth-root.sh" ]]
        [[ "$2" == "${DOTFILES_DIR}/config/plymouth/themes/div-meter" ]]
        validate_div_meter_theme_tree "$2" "$2/SHA256SUMS"
        printf "%s\n" "$1" > "${PLYMOUTH_SUDO_LOG:?}"
    }
    setup_plymouth
' bash "${INSTALLER}"; then
    fail "setup_plymouth orchestration probe failed"
fi
grep -Fxq "${ROOT}/scripts/install-div-meter-plymouth-root.sh" "${plymouth_sudo_log}" \
    || fail "setup_plymouth did not invoke the vendored root transaction"

if bash -c '
    set -euo pipefail
    source "$1"
    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    print_error() { :; }
    command_exists() { return 0; }
    ask_confirmation() {
        [[ "$1" == "Install Divergence Meter Plymouth theme?" ]]
    }
    sudo() {
        return 1
    }
    setup_plymouth
' bash "${INSTALLER}"; then
    fail "setup_plymouth must propagate root transaction failure"
fi

plymouth_decline_log="${test_tmp}/plymouth-decline.log"
if ! PLYMOUTH_DECLINE_LOG="${plymouth_decline_log}" bash -c '
    set -euo pipefail
    source "$1"
    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    command_exists() { return 1; }
    ask_confirmation() {
        return 1
    }
    sudo() {
        printf "called\n" > "${PLYMOUTH_DECLINE_LOG:?}"
    }
    setup_plymouth
' bash "${INSTALLER}"; then
    fail "declining setup_plymouth must not abort installation"
fi
[[ ! -e "${plymouth_decline_log}" ]] \
    || fail "declining setup_plymouth still invoked the root transaction"

grep -Fq 'Divergence Meter Plymouth installation failed; review the transaction output for rollback or recovery details' \
    "${INSTALLER}" \
    || fail "setup_plymouth failure guidance must remain accurate"

grep -Fq 'with_retry "nvm install" bash -o pipefail -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_ver}/install.sh | PROFILE=/dev/null bash"' \
    "${INSTALLER}" \
    || fail "nvm installer pipeline must pass PROFILE to bash with pipefail enabled"

nvm_home="${test_tmp}/nvm-home"
fake_bin="${test_tmp}/fake-bin"
mkdir -p "${nvm_home}" "${fake_bin}"
printf 'sentinel\n' > "${nvm_home}/.zshrc"
printf 'sentinel\n' > "${nvm_home}/expected-zshrc"

cat > "${fake_bin}/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

cat <<'FAKE_INSTALLER'
printf '%s\n' "${PROFILE-}" > "${HOME}/profile-probe"
if [[ "${PROFILE-}" != "/dev/null" ]]; then
    printf 'installer mutation\n' >> "${HOME}/.zshrc"
fi
mkdir -p "${HOME}/.nvm"
cat > "${HOME}/.nvm/nvm.sh" <<'FAKE_NVM'
nvm() { return 0; }
FAKE_NVM
FAKE_INSTALLER
FAKE_CURL
chmod +x "${fake_bin}/curl"

if ! HOME="${nvm_home}" PATH="${fake_bin}:/usr/bin:/bin" bash -c '
    set -euo pipefail
    source "$1"
    print_header() { :; }
    print_success() { :; }
    print_warning() { :; }
    print_error() { :; }
    latest_git_tag() { printf "v-test\n"; }
    ask_confirmation() { [[ "$1" == "Install nvm + Node.js LTS? (Node Version Manager)" ]]; }
    command_exists() { return 1; }
    install_optional_components
' bash "${INSTALLER}"; then
    fail "offline nvm installer probe failed"
fi

[[ -f "${nvm_home}/profile-probe" ]] \
    || fail "fake nvm installer did not record PROFILE"
[[ "$(< "${nvm_home}/profile-probe")" == "/dev/null" ]] \
    || fail "nvm installer bash did not receive PROFILE=/dev/null"
cmp -s "${nvm_home}/expected-zshrc" "${nvm_home}/.zshrc" \
    || fail "nvm installer modified .zshrc"

nautilus_home="${test_tmp}/nautilus-home"
nautilus_fake_bin="${test_tmp}/nautilus-fake-bin"
nautilus_mime_state="${test_tmp}/nautilus-mime-state"
nautilus_mime_log="${test_tmp}/nautilus-mime.log"
nautilus_gsettings_log="${test_tmp}/nautilus-gsettings.log"
mkdir -p "${nautilus_home}" "${nautilus_fake_bin}"

cat > "${nautilus_fake_bin}/xdg-mime" <<'FAKE_XDG_MIME'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    default)
        printf '%s\n' "$*" >> "${XDG_MIME_LOG:?}"
        printf '%s\n' "${2:?}" > "${XDG_MIME_STATE:?}"
        ;;
    query)
        cat "${XDG_MIME_STATE:?}"
        ;;
    *)
        exit 64
        ;;
esac
FAKE_XDG_MIME

cat > "${nautilus_fake_bin}/gsettings" <<'FAKE_GSETTINGS'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    list-schemas)
        printf '%s\n' "${GSETTINGS_SCHEMAS-com.github.stunkymonkey.nautilus-open-any-terminal}"
        ;;
    set)
        printf '%s\n' "$*" >> "${GSETTINGS_LOG:?}"
        ;;
    *)
        exit 64
        ;;
esac
FAKE_GSETTINGS

chmod +x "${nautilus_fake_bin}/xdg-mime" "${nautilus_fake_bin}/gsettings"

if ! HOME="${nautilus_home}" \
    PATH="${nautilus_fake_bin}:/usr/bin:/bin" \
    XDG_MIME_STATE="${nautilus_mime_state}" \
    XDG_MIME_LOG="${nautilus_mime_log}" \
    GSETTINGS_LOG="${nautilus_gsettings_log}" \
    bash -c '
        set -euo pipefail
        source "$1"
        print_header() { :; }
        print_success() { :; }
        print_warning() { :; }
        setup_nautilus_integration
        setup_nautilus_integration
    ' bash "${INSTALLER}"; then
    fail "setup_nautilus_integration probe failed"
fi

[[ "$(grep -Fxc 'default org.gnome.Nautilus.desktop inode/directory' "${nautilus_mime_log}")" -eq 2 ]] \
    || fail "repeated runs must keep Nautilus as the directory MIME handler"
[[ "$(grep -Fxc 'set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty' "${nautilus_gsettings_log}")" -eq 2 ]] \
    || fail "repeated runs must keep the Nautilus terminal extension on Kitty"

missing_schema_mime_state="${test_tmp}/missing-schema-mime-state"
missing_schema_mime_log="${test_tmp}/missing-schema-mime.log"
missing_schema_gsettings_log="${test_tmp}/missing-schema-gsettings.log"
: > "${missing_schema_gsettings_log}"

if ! HOME="${nautilus_home}" \
    PATH="${nautilus_fake_bin}:/usr/bin:/bin" \
    XDG_MIME_STATE="${missing_schema_mime_state}" \
    XDG_MIME_LOG="${missing_schema_mime_log}" \
    GSETTINGS_LOG="${missing_schema_gsettings_log}" \
    GSETTINGS_SCHEMAS="" \
    bash -c '
        set -euo pipefail
        source "$1"
        print_header() { :; }
        print_success() { :; }
        print_warning() { :; }
        setup_nautilus_integration
    ' bash "${INSTALLER}"; then
    fail "missing Nautilus terminal schema must not abort installation"
fi

grep -Fxq 'default org.gnome.Nautilus.desktop inode/directory' \
    "${missing_schema_mime_log}" \
    || fail "missing terminal schema must not skip the Nautilus MIME handler"
[[ ! -s "${missing_schema_gsettings_log}" ]] \
    || fail "installer must not write terminal settings when the schema is absent"

printf 'installer contract: ok\n'
