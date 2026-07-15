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
[[ -n "${optional_call_line}" && -n "${nautilus_call_line}" ]] \
    || fail "main must call setup_nautilus_integration"
[[ "${nautilus_call_line}" -eq $((optional_call_line + 1)) ]] \
    || fail "main must configure Nautilus immediately after optional packages"

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
