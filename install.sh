#!/usr/bin/env bash

#==============================================================================
# Dotfiles Installation Script
# Automated setup for Hyprland environment
#==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES_DIR="${SCRIPT_DIR}"
readonly BACKUP_DIR="${HOME}/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
readonly CONFIG_DIR="${HOME}/.config"
readonly LOG_FILE="${DOTFILES_DIR}/install.log"

readonly -a AMADEUS_THEME_FILES=(
    "COPYING"
    "IPA_Font_License_Agreement_v1.0.txt"
    "Main.qml"
    "amadeus-background.png"
    "amadeus-secondary.png"
    "components/SpComboBox.qml"
    "components/SpTextBox.qml"
    "fonts/TakaoMincho.ttf"
    "metadata.desktop"
    "theme.conf"
    "vk.qml"
)
readonly AMADEUS_CHECKSUM_MANIFEST_SHA256="a4caac995ce54c19bf7b22a41c4ba4ff23012fe1a67c7e80159d583724757ede"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Load package lists
if [[ ! -f "${DOTFILES_DIR}/lib/packages.conf" ]]; then
    echo -e "${RED}✗${NC} lib/packages.conf not found in ${DOTFILES_DIR}"
    exit 1
fi
source "${DOTFILES_DIR}/lib/packages.conf"

for steinsgrub_library in steinsgrub.conf steinsgrub.sh; do
    if [[ ! -f "${DOTFILES_DIR}/lib/${steinsgrub_library}" ]]; then
        echo -e "${RED}✗${NC} lib/${steinsgrub_library} not found in ${DOTFILES_DIR}"
        exit 1
    fi
    # shellcheck disable=SC1090
    source "${DOTFILES_DIR}/lib/${steinsgrub_library}"
done
unset steinsgrub_library

if [[ ! -f "${DOTFILES_DIR}/lib/div-meter-plymouth.sh" ]]; then
    echo -e "${RED}✗${NC} lib/div-meter-plymouth.sh not found in ${DOTFILES_DIR}"
    exit 1
fi
# shellcheck disable=SC1090
source "${DOTFILES_DIR}/lib/div-meter-plymouth.sh"

#==============================================================================
# Helper Functions
#==============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

print_header() {
    echo -e "\n${BLUE}==>${NC} ${1}" | tee -a "${LOG_FILE}"
}

print_success() {
    echo -e "${GREEN}✓${NC} ${1}" | tee -a "${LOG_FILE}"
}

print_warning() {
    echo -e "${YELLOW}!${NC} ${1}" | tee -a "${LOG_FILE}"
}

print_error() {
    echo -e "${RED}✗${NC} ${1}" | tee -a "${LOG_FILE}"
}

ask_confirmation() {
    read -rp "$(echo -e "${YELLOW}?${NC}") ${1} (y/N): " response
    [[ "${response}" =~ ^[Yy]$ ]]
}

# Install an optional tool via yay. Optionally runs a post-install hook
# (name of a shell function) after a successful install.
# Usage: install_optional_tool NAME "pkg1 pkg2" [post_hook_fn]
install_optional_tool() {
    local name="$1"
    local pkgs="$2"
    local post_hook="${3:-}"

    if ! command_exists yay; then
        print_warning "yay not found, please install ${name} manually: yay -S ${pkgs}"
        return 1
    fi

    # shellcheck disable=SC2086
    if with_retry "${name} install" bash -c "yay -S --noconfirm ${pkgs}"; then
        print_success "${name} installed successfully"
        if [[ -n "${post_hook}" ]] && declare -F "${post_hook}" >/dev/null; then
            "${post_hook}"
        fi
        return 0
    fi

    print_warning "${name} skipped"
    return 1
}

with_retry() {
    local label="$1"; shift
    local rc choice
    while true; do
        set +e
        "$@"
        rc=$?
        set -e
        [[ ${rc} -eq 0 ]] && return 0
        print_error "${label} failed (exit ${rc})"
        read -rp "$(echo -e "${YELLOW}?${NC}") [r]etry / [s]kip / [a]bort '${label}'? (r/s/a): " choice
        case "${choice}" in
            r|R|'') print_warning "Retrying ${label}..." ;;
            s|S)    print_warning "Skipping ${label}"; return 1 ;;
            a|A)    error_exit "Installation aborted by user at: ${label}" ;;
            *)      print_warning "Please answer r, s, or a" ;;
        esac
    done
}

latest_git_tag() {
    git ls-remote --tags --refs "https://github.com/$1" 2>/dev/null \
        | awk -F/ '{print $NF}' | grep -E '^v?[0-9]' | sort -V | tail -1
}

cleanup() {
    if [[ -n "${BACKUP_DIR:-}" ]] && [[ -d "${BACKUP_DIR}" ]]; then
        if [[ -z "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]]; then
            rm -rf "${BACKUP_DIR}"
            log "Removed empty backup directory"
        fi
    fi
}

error_exit() {
    print_error "$1"
    cleanup
    exit 1
}

command_exists() {
    command -v "$1" &> /dev/null
}

package_installed() {
    pacman -Qi "$1" &> /dev/null
}

validate_amadeus_theme_tree() {
    local theme_dir="$1"
    local theme_file
    local first_symlink
    local checksum_manifest="${theme_dir}/SHA256SUMS"
    local digest_line manifest_digest
    local expected_files actual_files

    if [[ ! -d "$theme_dir" || -L "$theme_dir" ]]; then
        print_error "Amadeus theme root must be a real directory"
        return 1
    fi
    if ! first_symlink="$(find "$theme_dir" -type l -print -quit)"; then
        print_error "Failed to inspect the Amadeus theme tree"
        return 1
    fi
    if [[ -n "$first_symlink" ]]; then
        print_error "Amadeus theme symlinks are not allowed: $first_symlink"
        return 1
    fi

    for theme_file in "${AMADEUS_THEME_FILES[@]}"; do
        if [[ ! -f "${theme_dir}/${theme_file}" || ! -r "${theme_dir}/${theme_file}" || -L "${theme_dir}/${theme_file}" ]]; then
            print_error "Amadeus theme file is missing or unreadable: ${theme_file}"
            return 1
        fi
    done

    if [[ ! -f "$checksum_manifest" || ! -r "$checksum_manifest" || -L "$checksum_manifest" ]] \
        || ! digest_line="$(sha256sum -- "$checksum_manifest")"; then
        print_error "Amadeus checksum manifest is missing or unreadable"
        return 1
    fi
    manifest_digest="${digest_line%% *}"
    if [[ "$manifest_digest" != "$AMADEUS_CHECKSUM_MANIFEST_SHA256" ]]; then
        print_error "Amadeus checksum manifest does not match the pinned reviewed variant"
        return 1
    fi

    if ! (cd "$theme_dir" && sha256sum --check --strict --quiet SHA256SUMS); then
        print_error "Amadeus theme asset checksum validation failed"
        return 1
    fi
    expected_files="$(printf '%s\n' "${AMADEUS_THEME_FILES[@]}" SHA256SUMS UPSTREAM | LC_ALL=C sort)"
    if ! actual_files="$(find "$theme_dir" -type f -printf '%P\n' | LC_ALL=C sort)"; then
        print_error "Failed to enumerate the Amadeus theme tree"
        return 1
    fi
    if [[ "$actual_files" != "$expected_files" ]]; then
        print_error "Amadeus theme tree contains missing or unreviewed files"
        return 1
    fi



    if ! grep -Fxq "Theme-Id=amadeus" "${theme_dir}/metadata.desktop" \
        || ! grep -Fxq "QtVersion=6" "${theme_dir}/metadata.desktop" \
        || ! grep -Fxq "MirrorScreens=false" "${theme_dir}/theme.conf"; then
        print_error "Amadeus theme metadata is invalid"
        return 1
    fi
}

validate_sddm_critical_settings() {
    local config_file="$1"

    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            section = $0
            sub(/^[[:space:]]*\[/, "", section)
            sub(/\][[:space:]]*$/, "", section)
            next
        }
        /^[[:space:]]*(#|$)/ { next }
        {
            line = $0
            separator = index(line, "=")
            if (!separator) next
            key = trim(substr(line, 1, separator - 1))
            value = trim(substr(line, separator + 1))

            if (section == "General" && key == "DisplayServer") {
                display_server_count++
                display_server_valid = (value == "x11")
            } else if (section == "Theme" && key == "ThemeDir") {
                theme_dir_count++
                theme_dir_valid = (value == "/usr/share/sddm/themes")
            } else if (section == "Theme" && key == "Current") {
                current_count++
                current_valid = (value == "amadeus")
            } else if (section == "X11" && key == "DisplayCommand") {
                display_command_count++
                display_command_valid = (value == "/usr/local/lib/sddm/Xsetup-dotfiles")
            }
        }
        END {
            if (display_server_count != 1 || !display_server_valid ||
                theme_dir_count != 1 || !theme_dir_valid ||
                current_count != 1 || !current_valid ||
                display_command_count != 1 || !display_command_valid) {
                exit 65
            }
        }
    ' "$config_file"
}

validate_sddm_managed_override_source() {
    local override_file="$1"

    validate_sddm_critical_settings "$override_file" || return 1

    awk '
        BEGIN {
            in_block = 0
            begin_count = 0
            end_count = 0
            saw_nonblank = 0
            block_closed = 0
            invalid = 0
        }
        /^[[:space:]]*$/ { next }
        /^# BEGIN DOTFILES SDDM OVERRIDE$/ {
            if (saw_nonblank || in_block || begin_count > 0) invalid = 1
            begin_count++
            in_block = 1
            saw_nonblank = 1
            next
        }
        /^# END DOTFILES SDDM OVERRIDE$/ {
            if (!in_block || end_count > 0) invalid = 1
            end_count++
            in_block = 0
            block_closed = 1
            saw_nonblank = 1
            next
        }
        {
            if (!in_block || block_closed) invalid = 1
            saw_nonblank = 1
        }
        END {
            if (invalid || in_block || begin_count != 1 || end_count != 1) exit 65
        }
    ' "$override_file"
}

format_sddm_monitor_options() {
    jq -r '
        if type != "array" then
            error("Hyprland monitor response is not an array")
        else
            (
                [
                    .[]
                    | select((.name | type) == "string")
                    | select(.name | test("^[A-Za-z0-9._-]+$"))
                ]
                | unique_by(.name)[]
                | . as $monitor
                | (
                    ($monitor.description // "Unknown display")
                    | tostring
                    | gsub("[\\t\\r\\n]+"; " ")
                    | gsub(" +"; " ")
                    | gsub("^ +| +$"; "")
                ) as $description
                | (
                    if $description == "" then "Unknown display"
                    else $description
                    end
                ) as $clean_description
                | (
                    if (($monitor.width | type) == "number"
                        and ($monitor.height | type) == "number"
                        and $monitor.width > 0
                        and $monitor.height > 0)
                    then (($monitor.width | floor | tostring) + "x" + ($monitor.height | floor | tostring))
                    else "mode unknown"
                    end
                ) as $resolution
                | (
                    if (($monitor.disabled // false) == true)
                    then "disabled in Hyprland"
                    else "active in Hyprland"
                    end
                ) as $state
                | [$monitor.name, $clean_description, $resolution, $state]
                | @tsv
            )
        end
    '
}

validate_root_file_backup() {
    local backup_path="$1"
    local checksum_path="${backup_path}.sha256"
    local expected_digest actual_digest_line actual_digest

    if ! sudo test -f "$backup_path" || sudo test -L "$backup_path" \
        || ! sudo test -f "$checksum_path" || sudo test -L "$checksum_path"; then
        return 1
    fi
    if ! expected_digest="$(sudo sed -n '1p' -- "$checksum_path")" \
        || [[ ! "$expected_digest" =~ ^[[:xdigit:]]{64}$ ]]; then
        return 1
    fi
    if ! actual_digest_line="$(sudo sha256sum -- "$backup_path")"; then
        return 1
    fi
    actual_digest="${actual_digest_line%% *}"
    [[ "$actual_digest" == "$expected_digest" ]]
}

create_root_file_backup_once() {
    local backup_path="$2"
    local lock_path="${backup_path}.lock"
    local lock_fd rc unlock_rc=0

    if ! sudo touch -- "$lock_path" \
        || sudo test -L "$lock_path" \
        || ! sudo test -f "$lock_path" \
        || ! sudo chown root:root "$lock_path" \
        || ! sudo chmod 0644 "$lock_path"; then
        print_error "Failed to prepare backup lock: ${lock_path}"
        return 1
    fi
    if ! exec {lock_fd}< "$lock_path"; then
        print_error "Failed to open backup lock: ${lock_path}"
        return 1
    fi
    if ! flock -x "$lock_fd"; then
        print_error "Failed to acquire backup lock: ${lock_path}"
        exec {lock_fd}<&-
        return 1
    fi

    if create_root_file_backup_once_locked "$@"; then
        rc=0
    else
        rc=$?
    fi

    flock -u "$lock_fd" || unlock_rc=$?
    exec {lock_fd}<&-
    if (( unlock_rc != 0 )); then
        print_error "Failed to release backup lock: ${lock_path}"
        return 1
    fi
    return "$rc"
}

create_root_file_backup_once_locked() {
    local source_path="$1"
    local backup_path="$2"
    local staged_backup="${backup_path}.dotfiles-new"
    local checksum_path="${backup_path}.sha256"
    local staged_checksum="${checksum_path}.dotfiles-new"
    local digest_line staged_digest

    if sudo test -e "$backup_path" || sudo test -L "$backup_path"; then
        if ! validate_root_file_backup "$backup_path"; then
            print_error "Existing backup is missing a valid checksum: ${backup_path}"
            return 1
        fi
        if ! sudo rm -f -- "$staged_backup" "$staged_checksum"; then
            print_error "Failed to clear stale backup staging paths"
            return 1
        fi
        return 0
    fi

    if ! sudo test -e "$source_path" && ! sudo test -L "$source_path"; then
        if ! sudo rm -f -- "$staged_backup" "$staged_checksum"; then
            print_error "Failed to clear stale backup staging paths"
            return 1
        fi
        if sudo test -e "$checksum_path" || sudo test -L "$checksum_path"; then
            if ! sudo test -f "$checksum_path" || sudo test -L "$checksum_path" \
                || ! sudo rm -f -- "$checksum_path"; then
                print_error "Failed to clear an orphaned backup checksum"
                return 1
            fi
        fi
        return 0
    fi
    if sudo test -L "$source_path" || ! sudo test -f "$source_path"; then
        print_error "Cannot back up a symlink or non-file path: ${source_path}"
        return 1
    fi

    if sudo test -e "$checksum_path" || sudo test -L "$checksum_path"; then
        if ! sudo test -f "$checksum_path" || sudo test -L "$checksum_path" \
            || ! sudo rm -f -- "$checksum_path"; then
            print_error "Orphaned backup checksum path is unsafe: ${checksum_path}"
            return 1
        fi
    fi

    if ! sudo rm -f -- "$staged_backup" "$staged_checksum"; then
        print_error "Failed to clear backup staging paths"
        return 1
    fi

    if ! sudo cp -a -- "$source_path" "$staged_backup" \
        || ! sudo test -f "$staged_backup" \
        || sudo test -L "$staged_backup" \
        || ! sudo cmp -s -- "$source_path" "$staged_backup"; then
        print_error "Failed to stage a verified backup for ${source_path}"
        sudo rm -f -- "$staged_backup" "$staged_checksum" || true
        return 1
    fi

    if ! digest_line="$(sudo sha256sum -- "$staged_backup")"; then
        print_error "Failed to checksum the staged backup"
        sudo rm -f -- "$staged_backup" "$staged_checksum" || true
        return 1
    fi
    staged_digest="${digest_line%% *}"
    if [[ ! "$staged_digest" =~ ^[[:xdigit:]]{64}$ ]] \
        || ! printf '%s\n' "$staged_digest" | sudo install -o root -g root -m 0644 /dev/stdin "$staged_checksum"; then
        print_error "Failed to stage the backup checksum"
        sudo rm -f -- "$staged_backup" "$staged_checksum" || true
        return 1
    fi

    if ! sudo mv --update=none-fail -T "$staged_checksum" "$checksum_path"; then
        print_error "Failed to atomically publish backup checksum: ${checksum_path}"
        sudo rm -f -- "$staged_backup" "$staged_checksum" || true
        return 1
    fi

    if ! sudo mv --update=none-fail -T "$staged_backup" "$backup_path"; then
        if validate_root_file_backup "$backup_path"; then
            sudo rm -f -- "$staged_backup" "$staged_checksum" || true
            return 0
        fi
        print_error "Failed to atomically publish backup: ${backup_path}"
        sudo rm -f -- "$staged_backup" "$staged_checksum" "$checksum_path" || true
        return 1
    fi

    if ! validate_root_file_backup "$backup_path"; then
        print_error "Published backup validation failed: ${backup_path}"
        sudo rm -f -- "$backup_path" "$checksum_path" || true
        return 1
    fi
}

install_sddm_final_override() {
    local override_source="$1"
    local temporary_dir temporary_config original_config override_snapshot
    local staged_config="/etc/.sddm.conf.dotfiles-new"
    local backup_config="/etc/sddm.conf.dotfiles-backup"
    local recovery_config="/etc/sddm.conf.dotfiles-recovery.$$"
    local had_config=0

    if [[ ! -f "$override_source" || ! -r "$override_source" || -L "$override_source" ]]; then
        print_error "Final SDDM override source is unsafe"
        return 1
    fi
    if ! temporary_dir="$(mktemp -d)"; then
        print_error "Failed to create temporary SDDM workspace"
        return 1
    fi
    temporary_config="${temporary_dir}/sddm.conf"
    original_config="${temporary_dir}/original.conf"
    override_snapshot="${temporary_dir}/override.conf"

    if ! cp -- "$override_source" "$override_snapshot" \
        || ! validate_sddm_managed_override_source "$override_snapshot"; then
        print_error "Failed to snapshot a valid final SDDM override"
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if sudo test -L /etc/sddm.conf \
        || { sudo test -e /etc/sddm.conf && ! sudo test -f /etc/sddm.conf; }; then
        print_error "Existing /etc/sddm.conf must be a regular non-symlink file"
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if sudo test -f /etc/sddm.conf; then
        had_config=1
        if ! sudo cat -- /etc/sddm.conf > "$original_config"; then
            print_error "Failed to snapshot the existing SDDM config"
            rm -rf -- "$temporary_dir"
            return 1
        fi
        if ! awk '
            BEGIN { in_override = 0; block_closed = 0; block_count = 0; invalid = 0 }
            /^# BEGIN DOTFILES SDDM OVERRIDE$/ {
                if (in_override || block_count > 0) invalid = 1
                in_override = 1
                block_count++
                next
            }
            /^# END DOTFILES SDDM OVERRIDE$/ {
                if (!in_override) invalid = 1
                in_override = 0
                block_closed = 1
                next
            }
            block_closed {
                if ($0 !~ /^[[:space:]]*$/) invalid = 1
                next
            }
            !in_override { preserved[++line_count] = $0 }
            END {
                if (in_override || invalid) exit 65
                while (line_count > 0 && preserved[line_count] ~ /^[[:space:]]*$/) line_count--
                for (line_number = 1; line_number <= line_count; line_number++) print preserved[line_number]
            }
        ' "$original_config" > "$temporary_config"; then
            print_error "Failed to preserve the existing SDDM config"
            rm -rf -- "$temporary_dir"
            return 1
        fi
    else
        : > "$temporary_config"
    fi

    if ! printf '\n' >> "$temporary_config" || ! sed -n 'p' "$override_snapshot" >> "$temporary_config"; then
        print_error "Failed to prepare the final SDDM override"
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if ! sudo rm -f -- "$staged_config" \
        || ! sudo install -o root -g root -m 0644 "$temporary_config" "$staged_config"; then
        print_error "Failed to stage the final SDDM override"
        sudo rm -f -- "$staged_config" || true
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if ! sudo cmp -s -- "$temporary_config" "$staged_config"; then
        print_error "Staged SDDM override validation failed"
        sudo rm -f -- "$staged_config" || true
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if (( had_config )); then
        if ! sudo cmp -s -- "$original_config" /etc/sddm.conf; then
            print_error "Existing SDDM config changed during preparation"
            sudo rm -f -- "$staged_config" || true
            rm -rf -- "$temporary_dir"
            return 1
        fi
    elif sudo test -e /etc/sddm.conf || sudo test -L /etc/sddm.conf; then
        print_error "SDDM config appeared during preparation"
        sudo rm -f -- "$staged_config" || true
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if ! create_root_file_backup_once /etc/sddm.conf "$backup_config"; then
        print_error "Failed to back up the existing SDDM config"
        sudo rm -f -- "$staged_config" || true
        rm -rf -- "$temporary_dir"
        return 1
    fi

    if (( had_config )); then
        if ! sudo mv --exchange --no-copy -T "$staged_config" /etc/sddm.conf; then
            print_error "Failed to atomically exchange the SDDM config"
            sudo rm -f -- "$staged_config" || true
            rm -rf -- "$temporary_dir"
            return 1
        fi

        if ! sudo test -f "$staged_config" || sudo test -L "$staged_config" \
            || ! sudo cmp -s -- "$original_config" "$staged_config"; then
            print_error "SDDM config changed during atomic activation"
            if sudo cmp -s -- "$temporary_config" /etc/sddm.conf; then
                if ! sudo mv --exchange --no-copy -T "$staged_config" /etc/sddm.conf; then
                    print_error "Failed to restore the concurrently changed SDDM config"
                    rm -rf -- "$temporary_dir"
                    return 1
                fi
                if sudo test -f "$staged_config" && ! sudo test -L "$staged_config" \
                    && sudo cmp -s -- "$temporary_config" "$staged_config"; then
                    sudo rm -f -- "$staged_config" || true
                elif sudo mv --update=none-fail --no-copy -T "$staged_config" "$recovery_config"; then
                    print_warning "A second concurrent SDDM config was preserved at ${recovery_config}"
                else
                    print_error "Concurrent SDDM config remains at ${staged_config}"
                fi
            elif sudo mv --update=none-fail --no-copy -T "$staged_config" "$recovery_config"; then
                print_warning "Concurrent SDDM config was preserved at ${recovery_config}"
            else
                print_error "Concurrent SDDM config remains at ${staged_config}"
            fi
            rm -rf -- "$temporary_dir"
            return 1
        fi
        sudo rm -f -- "$staged_config" || print_warning "Old SDDM config remains at ${staged_config}"
    elif ! sudo mv --update=none-fail --no-copy -T "$staged_config" /etc/sddm.conf; then
        print_error "Failed to atomically create the SDDM config"
        sudo rm -f -- "$staged_config" || true
        rm -rf -- "$temporary_dir"
        return 1
    fi

    rm -rf -- "$temporary_dir"
}

#==============================================================================
# Installation Steps
#==============================================================================

check_requirements() {
    print_header "Checking requirements"

    # Check if running from correct directory
    if [[ ! -f "${DOTFILES_DIR}/install.sh" ]]; then
        error_exit "Please run this script from the dotfiles directory"
    fi

    # Check if directories exist
    if [[ ! -d "${DOTFILES_DIR}/config" ]]; then
        error_exit "config/ directory not found in ${DOTFILES_DIR}"
    fi

    print_success "Requirements check passed"
}

check_arch() {
    print_header "Checking system compatibility"

    if [[ ! -f /etc/arch-release ]]; then
        print_warning "This script is designed for Arch Linux"
        if ! ask_confirmation "Continue anyway?"; then
            exit 1
        fi
    fi

    print_success "System check passed"
}

check_yay() {
    print_header "Checking package manager"

    if command_exists yay; then
        print_success "yay is installed"
        return 0
    fi

    print_warning "yay AUR helper not found"

    if ! ask_confirmation "Install yay? (required for AUR packages)"; then
        print_warning "Continuing without yay - some packages may not be available"
        return 0
    fi

    # Install required dependencies for building yay
    sudo pacman -S --needed --noconfirm base-devel git || {
        print_error "Failed to install base-devel and git"
        return 1
    }

    # Install yay
    print_header "Installing yay"
    local tmp_dir
    tmp_dir=$(mktemp -d) || {
        print_error "Failed to create temporary directory"
        return 1
    }
    local original_dir="${PWD}"

    if git clone https://aur.archlinux.org/yay.git "${tmp_dir}"; then
        cd "${tmp_dir}" || {
            rm -rf "${tmp_dir}"
            return 1
        }
        if makepkg -si --noconfirm; then
            print_success "yay installed successfully"
            cd "${original_dir}" || true
            rm -rf "${tmp_dir}"
            return 0
        else
            print_error "Failed to build yay"
            cd "${original_dir}" || true
            rm -rf "${tmp_dir}"
            return 1
        fi
    else
        print_error "Failed to clone yay repository"
        rm -rf "${tmp_dir}"
        return 1
    fi
}

check_dependencies() {
    print_header "Checking dependencies"

    local -a missing=()

    for pkg in "${CORE_PACKAGES[@]}"; do
        if ! package_installed "${pkg}"; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing core dependencies: ${missing[*]}"
        echo ""

        if command_exists yay; then
            if ask_confirmation "Install missing dependencies automatically?"; then
                print_header "Installing dependencies"
                if yay -S --needed --noconfirm "${missing[@]}"; then
                    print_success "All dependencies installed successfully"
                else
                    print_error "Failed to install some dependencies"
                    if ! ask_confirmation "Continue anyway?"; then
                        exit 1
                    fi
                fi
            else
                echo "Install manually with:"
                echo "  yay -S ${missing[*]}"
                echo ""
                if ! ask_confirmation "Continue without installing dependencies?"; then
                    exit 1
                fi
            fi
        else
            print_warning "yay not found. Please install dependencies manually:"
            for pkg in "${missing[@]}"; do
                echo "  yay -S ${pkg}"
            done
            echo ""
            if ! ask_confirmation "Continue without installing dependencies?"; then
                exit 1
            fi
        fi
    else
        print_success "All core dependencies installed"
    fi
}

backup_existing_configs() {
    print_header "Backing up existing configurations"

    local backed_up=0

    for config in "${CONFIGS[@]}"; do
        local config_path="${CONFIG_DIR}/${config}"
        if [[ -e "${config_path}" ]] || [[ -L "${config_path}" ]]; then
            # Backup real files/directories, remove old symlinks
            if [[ ! -L "${config_path}" ]]; then
                mkdir -p "${BACKUP_DIR}"
                if mv "${config_path}" "${BACKUP_DIR}/"; then
                    print_success "Backed up ${config}"
                    backed_up=1
                else
                    print_warning "Failed to backup ${config}"
                fi
            else
                # Remove old symlink
                rm -f "${config_path}"
                print_success "Removed old symlink ${config}"
            fi
        fi
    done

    # Backup or remove home directory files
    for file in "${HOME_FILES[@]}"; do
        local file_path="${HOME}/${file}"
        if [[ -e "${file_path}" ]] || [[ -L "${file_path}" ]]; then
            if [[ ! -L "${file_path}" ]]; then
                mkdir -p "${BACKUP_DIR}"
                if mv "${file_path}" "${BACKUP_DIR}/"; then
                    print_success "Backed up ${file}"
                    backed_up=1
                else
                    print_warning "Failed to backup ${file}"
                fi
            else
                # Remove old symlink
                rm -f "${file_path}"
                print_success "Removed old symlink ${file}"
            fi
        fi
    done

    if [[ ${backed_up} -eq 1 ]]; then
        print_success "Backups saved to: ${BACKUP_DIR}"
    else
        print_success "No existing configs to backup"
    fi
}

link_dotfiles_home() {
    print_header "Linking ~/dotfiles"

    local target="${HOME}/dotfiles"
    if [[ "${DOTFILES_DIR}" == "${target}" ]]; then
        print_success "repo already at ~/dotfiles"
        return 0
    fi
    if [[ -e "${target}" && ! -L "${target}" ]]; then
        print_warning "${target} exists and is not a symlink — configs reference ~/dotfiles; move it aside and re-run"
        return 0
    fi
    ln -sfn "${DOTFILES_DIR}" "${target}"
    print_success "Linked ~/dotfiles -> ${DOTFILES_DIR}"
}

create_symlinks() {
    print_header "Creating symlinks"

    # Ensure config directory exists
    mkdir -p "${CONFIG_DIR}"

    # Config symlinks
    for config in "${CONFIGS[@]}"; do
        local source="${DOTFILES_DIR}/config/${config}"
        local target="${CONFIG_DIR}/${config}"

        if [[ -e "${source}" ]]; then
            # Use -n flag to prevent creating symlink inside existing directory symlink
            ln -sfn "${source}" "${target}"
            print_success "Linked ${config}"
        else
            print_warning "Skipped ${config} (source not found)"
        fi
    done

    # Home directory symlinks
    for file in "${HOME_FILES[@]}"; do
        local source="${DOTFILES_DIR}/home/${file}"
        local target="${HOME}/${file}"

        if [[ -e "${source}" ]]; then
            ln -sfn "${source}" "${target}"
            print_success "Linked ${file}"
        else
            print_warning "Skipped ${file} (source not found)"
        fi
    done

    print_success "All symlinks created"
}

setup_user_services() {
    print_header "Setting up user services"

    local unit_name="polkit-gnome-authentication-agent.service"
    local unit_source="${DOTFILES_DIR}/config/systemd/user/${unit_name}"
    local unit_dir="${CONFIG_DIR}/systemd/user"
    local unit_target="${unit_dir}/${unit_name}"

    if [[ ! -f "${unit_source}" ]]; then
        print_warning "Skipped ${unit_name} (source not found)"
        return 0
    fi

    mkdir -p -- "${unit_dir}"
    if [[ -e "${unit_target}" && ! -L "${unit_target}" ]]; then
        local unit_backup_dir="${BACKUP_DIR}/systemd/user"
        mkdir -p -- "${unit_backup_dir}"
        if ! mv -- "${unit_target}" "${unit_backup_dir}/${unit_name}"; then
            print_warning "Failed to back up existing ${unit_name}"
            return 0
        fi
        print_success "Backed up existing ${unit_name}"
    fi

    if ! ln -sfn -- "${unit_source}" "${unit_target}"; then
        print_warning "Failed to link ${unit_name}"
        return 0
    fi
    print_success "Linked ${unit_name}"

    if command_exists systemctl; then
        if systemctl --user daemon-reload; then
            print_success "Reloaded the user systemd manager"
        else
            print_warning "Could not reload the user systemd manager; it will load the unit next session"
        fi
    else
        print_warning "systemctl not found; the user service will load next session"
    fi
}

setup_local_config() {
    print_header "Setting up device-specific configuration"

    local local_conf="${CONFIG_DIR}/hypr/conf/local.conf"
    local example_conf="${CONFIG_DIR}/hypr/conf/local.conf.example"
    local generated_name generated_conf

    if [[ ! -f "${local_conf}" ]]; then
        if [[ -f "${example_conf}" ]]; then
            cp -- "${example_conf}" "${local_conf}"
            print_success "Created local.conf from example"
            print_warning "Use nwg-displays for monitor layout; edit local.conf only for other per-machine overrides"
        else
            print_warning "local.conf.example not found, skipping"
        fi
    else
        print_success "local.conf already exists"
    fi

    for generated_name in monitors workspaces; do
        generated_conf="${CONFIG_DIR}/hypr/${generated_name}.conf"
        if [[ -e "${generated_conf}" || -L "${generated_conf}" ]]; then
            print_success "nwg-displays ${generated_name} configuration already exists"
        else
            mkdir -p -- "${generated_conf%/*}"
            : > "${generated_conf}"
            print_success "Created an empty nwg-displays ${generated_name} configuration"
        fi
    done
}

setup_wallpaper_dir() {
    print_header "Setting up wallpaper directory"

    local wallpaper_dir="${HOME}/wallpaper"
    mkdir -p "${wallpaper_dir}"

    # Check if wallpapers already exist
    local existing_count
    existing_count=$(find "${wallpaper_dir}" -type f \( -name "*.jpg" -o -name "*.png" \) 2>/dev/null | wc -l)

    if [[ ${existing_count} -gt 0 ]]; then
        print_success "~/wallpaper directory contains ${existing_count} wallpaper(s)"
        return 0
    fi

    print_success "Created ~/wallpaper directory"
    local copied=0

    # Try to copy from Hyprland
    if [[ -d "/usr/share/hypr" ]]; then
        shopt -s nullglob
        for wallpaper in /usr/share/hypr/wall*.png /usr/share/hypr/wall*.jpg; do
            if [[ -f "${wallpaper}" ]]; then
                if cp "${wallpaper}" "${wallpaper_dir}/" 2>/dev/null; then
                    print_success "Copied $(basename "${wallpaper}") from Hyprland"
                    copied=1
                fi
            fi
        done
        shopt -u nullglob
    fi

    # Try system backgrounds if nothing copied yet
    if [[ ${copied} -eq 0 ]] && [[ -d "/usr/share/backgrounds" ]]; then
        shopt -s nullglob
        for wallpaper in /usr/share/backgrounds/*.png /usr/share/backgrounds/*.jpg; do
            if [[ -f "${wallpaper}" ]]; then
                if cp "${wallpaper}" "${wallpaper_dir}/" 2>/dev/null; then
                    print_success "Copied $(basename "${wallpaper}") from system backgrounds"
                    copied=1
                    break
                fi
            fi
        done
        shopt -u nullglob
    fi

    # Download default wallpaper if nothing was copied
    if [[ ${copied} -eq 0 ]]; then
        print_warning "No local wallpapers found, downloading default wallpaper..."
        if command_exists curl; then
            # Download a simple default wallpaper (Hyprland's default from GitHub)
            if curl -L -o "${wallpaper_dir}/default.png" \
                "https://raw.githubusercontent.com/hyprwm/Hyprland/main/assets/wall_8K.png" 2>/dev/null; then
                print_success "Downloaded default wallpaper"
                copied=1
            else
                print_warning "Failed to download default wallpaper"
            fi
        elif command_exists wget; then
            if wget -q -O "${wallpaper_dir}/default.png" \
                "https://raw.githubusercontent.com/hyprwm/Hyprland/main/assets/wall_8K.png" 2>/dev/null; then
                print_success "Downloaded default wallpaper"
                copied=1
            else
                print_warning "Failed to download default wallpaper"
            fi
        fi
    fi

    # Final check
    if [[ ${copied} -eq 0 ]]; then
        print_error "No wallpapers available in ~/wallpaper"
        print_warning "Please manually add at least one wallpaper (PNG or JPG) to ~/wallpaper"
        print_warning "This is required for color scheme generation"
        if ! ask_confirmation "Continue installation without wallpaper?"; then
            error_exit "Installation cancelled - wallpaper required"
        fi
    fi
}

smoke_test_sddm_theme() {
    local theme_dir="$1"
    local smoke_log smoke_status

    if ! command_exists sddm-greeter-qt6 || ! command_exists timeout; then
        print_warning "Cannot run the Qt6 SDDM greeter smoke test"
        return 1
    fi
    if ! smoke_log="$(mktemp)"; then
        print_warning "Cannot create the SDDM greeter smoke log"
        return 1
    fi

    if QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        timeout --signal=TERM 8s sddm-greeter-qt6 --test-mode --theme "$theme_dir" \
        >"$smoke_log" 2>&1; then
        smoke_status=0
    else
        smoke_status=$?
    fi

    if [[ "$smoke_status" -ne 0 && "$smoke_status" -ne 124 ]] \
        || grep -Eiq 'module ".+" is not installed|Type .+ unavailable|failed to load component|QQmlApplicationEngine failed|Error loading QML' "$smoke_log"; then
        print_warning "Amadeus Qt6 greeter smoke test failed"
        sed -n '1,20p' "$smoke_log" >&2
        rm -f -- "$smoke_log"
        return 1
    fi

    rm -f -- "$smoke_log"
    print_success "Amadeus Qt6 greeter smoke test passed"
}

activate_amadeus_theme_tree() {
    local theme_stage="$1"
    local theme_target="$2"
    local theme_backup="$3"
    local previous_int_trap previous_term_trap
    local signal_status=0
    local activation_status=0
    local preserve_failed=0

    if sudo test -e "$theme_backup" || sudo test -L "$theme_backup"; then
        if ! sudo test -d "$theme_backup" || sudo test -L "$theme_backup"; then
            print_error "Existing Amadeus theme backup path is unsafe"
            sudo rm -rf -- "$theme_stage" || true
            return 1
        fi
    fi

    if ! sudo test -e "$theme_target" && ! sudo test -L "$theme_target"; then
        if sudo mv --update=none-fail --no-copy -T "$theme_stage" "$theme_target"; then
            return 0
        fi
        print_error "Failed to activate the staged Amadeus theme"
        sudo rm -rf -- "$theme_stage" || true
        return 1
    fi
    if ! sudo test -d "$theme_target" || sudo test -L "$theme_target"; then
        print_error "Existing Amadeus theme target is not a real directory"
        sudo rm -rf -- "$theme_stage" || true
        return 1
    fi

    previous_int_trap="$(trap -p INT)"
    previous_term_trap="$(trap -p TERM)"
    trap 'signal_status=130' INT
    trap 'signal_status=143' TERM

    if ! sudo mv --exchange --no-copy -T "$theme_stage" "$theme_target"; then
        print_error "Failed to atomically exchange the Amadeus theme"
        sudo rm -rf -- "$theme_stage" || true
        activation_status=1
    elif ! sudo test -d "$theme_stage" || sudo test -L "$theme_stage"; then
        print_error "Displaced Amadeus theme is not a real directory"
        preserve_failed=1
    elif sudo test -e "$theme_backup" || sudo test -L "$theme_backup"; then
        if ! sudo test -d "$theme_backup" || sudo test -L "$theme_backup" \
            || ! sudo mv --exchange --no-copy -T "$theme_stage" "$theme_backup"; then
            preserve_failed=1
        else
            sudo rm -rf -- "$theme_stage" \
                || print_warning "Older Amadeus backup remains at ${theme_stage}"
        fi
    elif ! sudo mv --update=none-fail --no-copy -T "$theme_stage" "$theme_backup"; then
        preserve_failed=1
    fi

    if (( preserve_failed )); then
        print_error "Failed to preserve the displaced Amadeus theme"
        if ! sudo mv --exchange --no-copy -T "$theme_stage" "$theme_target"; then
            print_error "Rollback failed; both Amadeus trees were left in place"
        else
            sudo rm -rf -- "$theme_stage" || true
        fi
        activation_status=1
    fi

    if [[ -n "$previous_int_trap" ]]; then
        eval "$previous_int_trap"
    else
        trap - INT
    fi
    if [[ -n "$previous_term_trap" ]]; then
        eval "$previous_term_trap"
    else
        trap - TERM
    fi

    if (( signal_status != 0 )); then
        print_warning "Signal deferred until Amadeus theme activation reached a safe state"
        return "$signal_status"
    fi
    return "$activation_status"
}

setup_sddm() {
    print_header "Setting up SDDM"

    if ! command_exists sddm; then
        print_warning "SDDM not installed, skipping"
        return 0
    fi

    if ask_confirmation "Configure SDDM with Amadeus theme?"; then
        local -a monitor_options=()
        local choice primary_output PS3
        local monitors_json monitor_listing

        if ! command_exists hyprctl || ! command_exists jq; then
            print_warning "Cannot enumerate monitors without hyprctl and jq; SDDM left unchanged"
            return 0
        fi

        if ! monitors_json="$(hyprctl -j monitors all 2>/dev/null)"; then
            print_warning "Hyprland monitor query failed; SDDM left unchanged"
            return 0
        fi

        if ! monitor_listing="$(format_sddm_monitor_options <<< "$monitors_json")"; then
            print_warning "Hyprland returned an invalid monitor list; SDDM left unchanged"
            return 0
        fi

        if [[ -n "$monitor_listing" ]]; then
            mapfile -t monitor_options <<< "$monitor_listing"
        fi

        if [[ ${#monitor_options[@]} -eq 0 ]]; then
            print_warning "No usable Hyprland monitors found; SDDM left unchanged"
            return 0
        fi

        printf 'Choose the primary display for the SDDM login screen:\n' >&2
        PS3='Primary SDDM display: '
        select choice in "${monitor_options[@]}"; do
            if [[ -n "${choice:-}" ]]; then
                primary_output="${choice%%$'\t'*}"
                break
            fi
            printf 'Choose one of the listed display numbers.\n' >&2
        done

        if [[ -z "${primary_output:-}" || "${primary_output}" == *[![:alnum:]._-]* ]]; then
            print_warning "No valid primary display selected; SDDM left unchanged"
            return 0
        fi

        local theme_source="${DOTFILES_DIR}/config/sddm/themes/amadeus"
        local upstream_source="${theme_source}/UPSTREAM"
        local hook_source="${DOTFILES_DIR}/config/sddm/scripts/Xsetup-dotfiles"
        local drop_in_source="${DOTFILES_DIR}/config/sddm/sddm.conf"
        local override_source="${DOTFILES_DIR}/config/sddm/dotfiles-override.conf"
        local theme_target="/usr/share/sddm/themes/amadeus"
        local theme_stage="/usr/share/sddm/themes/.amadeus-dotfiles-new"
        local theme_backup="/usr/share/sddm/themes/.amadeus-dotfiles-backup"
        local hook_target="/usr/local/lib/sddm/Xsetup-dotfiles"
        local hook_stage="/usr/local/lib/sddm/.Xsetup-dotfiles-new"
        local hook_backup="/usr/local/lib/sddm/.Xsetup-dotfiles-backup"
        local primary_target="/etc/sddm/primary-output"
        local primary_stage="/etc/sddm/.primary-output-dotfiles-new"
        local sddm_backup_dir="/etc/sddm/dotfiles-backups"
        local drop_in_target="/etc/sddm.conf.d/99-dotfiles.conf"
        local drop_in_stage="/etc/sddm/.99-dotfiles.conf-new"
        local drop_in_backup="${sddm_backup_dir}/99-dotfiles.conf"
        local legacy_drop_in_target="/etc/sddm.conf.d/10-dotfiles.conf"
        local legacy_drop_in_backup="${sddm_backup_dir}/10-dotfiles.conf"
        local mv_help

        if ! validate_amadeus_theme_tree "${theme_source}" \
            || [[ ! -f "${upstream_source}" || ! -r "${upstream_source}" || -L "${upstream_source}" ]] \
            || ! grep -Fxq "Source: https://github.com/jericjan/sddm-theme-amadeus" "${upstream_source}" \
            || ! grep -Fxq "Commit: ad42165b22e4d7ce69dcef8fef6caa3e9d6f88f3" "${upstream_source}" \
            || [[ ! -f "${hook_source}" || ! -r "${hook_source}" || ! -x "${hook_source}" || -L "${hook_source}" ]] \
            || ! bash -n "${hook_source}" \
            || [[ ! -f "${drop_in_source}" || ! -r "${drop_in_source}" || -L "${drop_in_source}" ]] \
            || ! validate_sddm_critical_settings "${drop_in_source}" \
            || [[ ! -f "${override_source}" || ! -r "${override_source}" || -L "${override_source}" ]] \
            || ! validate_sddm_managed_override_source "${override_source}"; then
            print_error "Vendored Amadeus or SDDM configuration sources are unsafe"
            return 1
        fi

        if ! command_exists sha256sum \
            || ! command_exists flock \
            || ! mv_help="$(mv --help 2>&1)" \
            || ! grep -Fq -- '--exchange' <<< "$mv_help" \
            || ! grep -Fq -- '--no-copy' <<< "$mv_help" \
            || ! grep -Fq -- 'none-fail' <<< "$mv_help"; then
            print_error "GNU mv with atomic exchange support is required for SDDM setup"
            return 1
        fi

        # Check sudo access
        if ! sudo -v; then
            print_error "Failed to get sudo access"
            return 1
        fi

        local -a required_sddm_packages=(qt6-5compat qt6-virtualkeyboard xorg-xrandr)
        local -a missing_sddm_packages=()
        local package

        for package in "${required_sddm_packages[@]}"; do
            if ! package_installed "${package}"; then
                missing_sddm_packages+=("${package}")
            fi
        done

        if [[ ${#missing_sddm_packages[@]} -gt 0 ]]; then
            print_header "Installing SDDM theme dependencies"
            if ! sudo pacman -S --needed --noconfirm "${missing_sddm_packages[@]}"; then
                print_error "Failed to install required SDDM theme dependencies"
                return 1
            fi
        fi

        if ! sudo rm -rf -- "$theme_stage" \
            || ! sudo rm -f -- "$hook_stage" \
            || ! sudo install -d -o root -g root -m 0755 "$theme_stage" \
            || ! sudo cp -r "${theme_source}/." "$theme_stage/" \
            || ! sudo chown -R root:root "$theme_stage" \
            || ! sudo find "$theme_stage" -type d -exec chmod 0755 {} + \
            || ! sudo find "$theme_stage" -type f -exec chmod 0644 {} + \
            || ! sudo install -D -o root -g root -m 0755 "${hook_source}" "$hook_stage"; then
            print_error "Failed to prepare the Amadeus theme or Xsetup staging area"
            sudo rm -rf -- "$theme_stage" || true
            sudo rm -f -- "$hook_stage" || true
            return 1
        fi

        if ! validate_amadeus_theme_tree "$theme_stage" || ! bash -n "$hook_stage"; then
            print_error "Staged Amadeus theme or Xsetup validation failed"
            sudo rm -rf -- "$theme_stage" || true
            sudo rm -f -- "$hook_stage" || true
            return 1
        fi

        if ! create_root_file_backup_once "$hook_target" "$hook_backup"; then
            print_error "Failed to back up the existing SDDM Xsetup hook"
            sudo rm -rf -- "$theme_stage" || true
            sudo rm -f -- "$hook_stage" || true
            return 1
        fi

        if ! sudo mv -fT "$hook_stage" "$hook_target"; then
            print_error "Failed to atomically activate the SDDM Xsetup hook"
            sudo rm -rf -- "$theme_stage" || true
            sudo rm -f -- "$hook_stage" || true
            return 1
        fi

        if ! activate_amadeus_theme_tree "$theme_stage" "$theme_target" "$theme_backup"; then
            return 1
        fi
        if ! smoke_test_sddm_theme "$theme_target"; then
            print_error "Amadeus was installed but SDDM configuration was left unchanged"
            return 1
        fi


        if ! sudo install -d -o root -g root -m 0755 /etc/sddm /etc/sddm.conf.d "$sddm_backup_dir"; then
            print_error "Failed to create the SDDM state directory"
            return 1
        fi
        if ! sudo rm -f -- "$primary_stage"; then
            print_error "Failed to clear the SDDM primary-output staging path"
            return 1
        fi
        if ! printf '%s\n' "${primary_output}" | sudo install -o root -g root -m 0644 /dev/stdin "$primary_stage" \
            || ! sudo mv -fT "$primary_stage" "$primary_target"; then
            print_error "Failed to save the SDDM primary display"
            sudo rm -f -- "$primary_stage" || true
            return 1
        fi

        # Install the drop-in only after the theme and its metadata have been
        # staged successfully, so distro defaults cannot select a missing theme.
        if ! sudo rm -f -- "$drop_in_stage" \
            || ! sudo install -Dm644 "$drop_in_source" "$drop_in_stage"; then
            print_error "Failed to stage the SDDM drop-in"
            sudo rm -f -- "$drop_in_stage" || true
            return 1
        fi

        if ! validate_sddm_critical_settings "$drop_in_stage"; then
            print_error "Staged SDDM drop-in validation failed"
            sudo rm -f -- "$drop_in_stage" || true
            return 1
        fi

        if ! create_root_file_backup_once "$drop_in_target" "$drop_in_backup"; then
            print_error "Failed to back up the existing SDDM drop-in"
            sudo rm -f -- "$drop_in_stage" || true
            return 1
        fi

        if ! sudo mv -fT "$drop_in_stage" "$drop_in_target"; then
            print_error "Failed to atomically activate the SDDM drop-in"
            sudo rm -f -- "$drop_in_stage" || true
            return 1
        fi

        if ! install_sddm_final_override "${override_source}"; then
            return 1
        fi

        if ! create_root_file_backup_once "$legacy_drop_in_target" "$legacy_drop_in_backup"; then
            print_error "Failed to back up the legacy SDDM drop-in"
            return 1
        fi
        if ! sudo rm -f -- "$legacy_drop_in_target"; then
            print_error "Failed to remove the legacy SDDM drop-in"
            return 1
        fi

        if package_installed sddm-silent-theme; then
            if sudo pacman -R --noconfirm sddm-silent-theme; then
                print_success "Removed the obsolete Silent SDDM theme package"
            else
                print_warning "Could not remove sddm-silent-theme; Amadeus is still active"
            fi
        fi
        print_success "Amadeus theme configured for SDDM primary output ${primary_output}"

        # Enable SDDM
        if ask_confirmation "Enable SDDM service?"; then
            sudo systemctl enable sddm || print_warning "Failed to enable SDDM"
            print_success "SDDM enabled"
        fi
    fi
}

setup_grub_theme() (
    print_header "Setting up Steins;GRUB theme"

    local grub_cfg_path="${DOTFILES_GRUB_CFG_PATH:-/boot/grub/grub.cfg}"
    local cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/dotfiles/steinsgrub"
    local archive_path="${cache_dir}/${STEINSGRUB_COMMIT}.tar.gz"
    local temporary_dir source_dir

    if [[ ! -f "${grub_cfg_path}" || -L "${grub_cfg_path}" ]]; then
        print_warning "GRUB configuration not found; skipping Steins;GRUB"
        return 0
    fi
    if ! command_exists grub-mkconfig; then
        print_warning "grub-mkconfig not found; skipping Steins;GRUB"
        return 0
    fi
    for required_command in curl tar sha256sum; do
        if ! command_exists "${required_command}"; then
            print_warning "${required_command} not found; skipping Steins;GRUB"
            return 0
        fi
    done
    if ! ask_confirmation "Install Steins;Gate GRUB theme?"; then
        print_warning "Steins;GRUB theme skipped"
        return 0
    fi

    if ! fetch_steinsgrub_archive \
        "${archive_path}" \
        "${STEINSGRUB_ARCHIVE_URL}" \
        "${STEINSGRUB_ARCHIVE_SHA256}"; then
        print_error "Steins;GRUB download or checksum verification failed"
        return 1
    fi

    temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-steinsgrub.XXXXXX")" || {
        print_error "Could not create Steins;GRUB staging directory"
        return 1
    }
    trap 'rm -rf -- "${temporary_dir}"' EXIT
    source_dir="${temporary_dir}/theme"
    if ! prepare_steinsgrub_source \
        "${archive_path}" \
        "${source_dir}" \
        "${DOTFILES_DIR}/lib/steinsgrub.sha256" \
        "steinsgrub-theme-${STEINSGRUB_COMMIT}"; then
        print_error "Steins;GRUB archive structure validation failed"
        return 1
    fi

    if sudo "${DOTFILES_DIR}/scripts/install-steinsgrub-root.sh" "${source_dir}"; then
        print_success "Steins;GRUB theme installed"
    else
        print_error "Steins;GRUB installation failed; review the transaction output for rollback or recovery details"
        return 1
    fi
)

setup_plymouth() (
    print_header "Setting up Divergence Meter Plymouth theme"

    local theme_source="${DOTFILES_DIR}/config/plymouth/themes/div-meter"
    local manifest="${theme_source}/SHA256SUMS"
    local root_installer="${DOTFILES_DIR}/scripts/install-div-meter-plymouth-root.sh"
    local required_command

    if ! ask_confirmation "Install Divergence Meter Plymouth theme?"; then
        print_warning "Divergence Meter Plymouth theme skipped"
        return 0
    fi

    for required_command in mkinitcpio lsinitcpio plymouth-set-default-theme; do
        if ! command_exists "${required_command}"; then
            print_error "${required_command} not found; cannot configure Plymouth safely"
            return 1
        fi
    done
    if [[ ! -x "${root_installer}" || -L "${root_installer}" ]]; then
        print_error "Divergence Meter Plymouth root transaction is unavailable"
        return 1
    fi
    if ! validate_div_meter_theme_tree "${theme_source}" "${manifest}"; then
        print_error "Vendored Divergence Meter Plymouth theme failed validation"
        return 1
    fi

    if sudo "${root_installer}" "${theme_source}"; then
        print_success "Divergence Meter Plymouth theme installed"
    else
        print_error "Divergence Meter Plymouth installation failed; review the transaction output for rollback or recovery details"
        return 1
    fi
)

install_shell_plugins() {
    print_header "Checking shell plugins"

    local -a shell_plugins=(
        "starship"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "zsh-history-substring-search"
    )
    local -a missing_plugins=()

    for plugin in "${shell_plugins[@]}"; do
        if package_installed "${plugin}"; then
            print_success "${plugin} already installed"
        else
            missing_plugins+=("${plugin}")
        fi
    done

    if [[ ${#missing_plugins[@]} -gt 0 ]]; then
        print_warning "Missing shell plugins: ${missing_plugins[*]}"
        if command_exists yay; then
            if ask_confirmation "Install missing shell plugins?"; then
                with_retry "Shell plugins install" yay -S --needed --noconfirm "${missing_plugins[@]}" \
                    || print_warning "Some shell plugins skipped"
            fi
        else
            print_warning "yay not found, install manually: yay -S ${missing_plugins[*]}"
        fi
    fi
}

install_optional_packages() {
    print_header "Installing optional packages"

    if ! command_exists yay; then
        print_warning "yay not found, skipping optional packages"
        return 0
    fi

    local -a missing=()
    local -a already_installed=()

    for pkg in "${OPTIONAL_PACKAGES[@]}"; do
        if ! package_installed "${pkg}"; then
            missing+=("${pkg}")
        else
            already_installed+=("${pkg}")
        fi
    done

    if [[ ${#already_installed[@]} -gt 0 ]]; then
        print_success "${#already_installed[@]} optional packages already installed"
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        print_success "All optional packages already installed"
        return 0
    fi

    echo ""
    echo "Missing optional packages (${#missing[@]}):"
    for pkg in "${missing[@]}"; do
        echo "  • ${pkg}"
    done
    echo ""

    if ask_confirmation "Install all missing optional packages?"; then
        if with_retry "Optional packages install" yay -S --needed --noconfirm "${missing[@]}"; then
            print_success "Optional packages installed successfully"
        else
            print_warning "Some optional packages skipped"
        fi
    else
        print_warning "Skipped optional packages installation"
        echo "Install manually with: yay -S ${missing[*]}"
    fi
}

setup_nautilus_integration() {
    print_header "Configuring Nautilus integration"

    local desktop_id="org.gnome.Nautilus.desktop"
    local directory_mime="inode/directory"
    local terminal_schema="com.github.stunkymonkey.nautilus-open-any-terminal"
    local current_handler=""
    local schemas=""

    if ! command_exists xdg-mime; then
        print_warning "xdg-mime not found, skipping the directory association"
    elif xdg-mime default "${desktop_id}" "${directory_mime}"; then
        current_handler="$(xdg-mime query default "${directory_mime}" 2>/dev/null || true)"
        if [[ "${current_handler}" == "${desktop_id}" ]]; then
            print_success "Nautilus is the default directory handler"
        else
            print_warning "Directory handler is still ${current_handler:-unset}"
        fi
    else
        print_warning "Failed to set Nautilus as the directory handler"
    fi

    if ! command_exists gsettings; then
        print_warning "gsettings not found, skipping the Nautilus terminal extension"
        return 0
    fi

    schemas="$(gsettings list-schemas 2>/dev/null || true)"
    if ! grep -Fxq "${terminal_schema}" <<< "${schemas}"; then
        print_warning "Nautilus terminal extension is not installed, skipping Kitty setup"
        return 0
    fi

    if gsettings set "${terminal_schema}" terminal kitty; then
        print_success "Nautilus terminal extension uses Kitty"
    else
        print_warning "Failed to configure Kitty for the Nautilus terminal extension"
    fi
}

install_sdkman_java() {
    local init="${HOME}/.sdkman/bin/sdkman-init.sh"
    if [[ ! -s "${init}" ]]; then
        print_warning "sdkman-init.sh not found, skipping Java"
        return 0
    fi

    local major id default_id=""
    for major in 8 17 21 26; do
        id=$( source "${init}" >/dev/null 2>&1; sdk list java 2>/dev/null \
              | awk -F'|' '{gsub(/ /,"",$6); print $6}' \
              | grep -E "^${major}"'\.[0-9].*-tem$' | head -1 ) || true
        if [[ -z "${id}" ]]; then
            print_warning "No Temurin build found for Java ${major}"
            continue
        fi
        [[ "${major}" == "21" ]] && default_id="${id}"
        if [[ -d "${HOME}/.sdkman/candidates/java/${id}" ]]; then
            print_success "Java ${id} already installed"
            continue
        fi
        print_header "Installing Java ${id}"
        with_retry "Java ${id}" bash -c "source '${init}'; yes | sdk install java '${id}'" \
            && print_success "Java ${id} installed" \
            || print_warning "Java ${id} skipped"
    done

    if [[ -n "${default_id}" ]] && [[ -d "${HOME}/.sdkman/candidates/java/${default_id}" ]]; then
        bash -c "source '${init}'; sdk default java '${default_id}'" >/dev/null 2>&1 \
            && print_success "Default Java set to ${default_id}"
    fi
}

install_optional_components() {
    print_header "Optional components installation"

    echo ""
    echo "The following components are optional and can enhance your workflow:"
    echo ""

    # pyenv
    if [[ ! -d "${HOME}/.pyenv" ]] && ! command_exists pyenv; then
        if ask_confirmation "Install pyenv? (Python version manager)"; then
            print_header "Installing pyenv"
            if command_exists yay; then
                yay -S --needed --noconfirm base-devel openssl xz tk libffi \
                    || print_warning "Some Python build dependencies failed to install"
            fi
            with_retry "pyenv install" bash -c 'curl -fsSL https://pyenv.run | bash' \
                && print_success "pyenv installed to ~/.pyenv" \
                || print_warning "pyenv installation skipped"
        fi
    else
        print_success "pyenv already installed"
    fi

    # Go
    if ! command_exists go; then
        if ask_confirmation "Install Go? (yay -S go)"; then
            install_optional_tool "Go" "go"
        fi
    else
        print_success "Go already installed"
    fi

    # Docker
    docker_post_install() {
        if ask_confirmation "Add current user to docker group?"; then
            if sudo usermod -aG docker "${USER}"; then
                print_success "User added to docker group"
                print_warning "Logout and login again for group changes to take effect"
            else
                print_error "Failed to add user to docker group"
            fi
        fi
        if ask_confirmation "Enable Docker service?"; then
            if sudo systemctl enable docker; then
                print_success "Docker service enabled"
            else
                print_error "Failed to enable Docker service"
            fi
        fi
    }

    if ! command_exists docker; then
        if ask_confirmation "Install Docker? (yay -S docker docker-compose)"; then
            install_optional_tool "Docker" "docker docker-compose" docker_post_install
        fi
    else
        print_success "Docker already installed"
    fi

    # nvm + Node.js
    if [[ ! -s "${HOME}/.nvm/nvm.sh" ]]; then
        if ask_confirmation "Install nvm + Node.js LTS? (Node Version Manager)"; then
            print_header "Installing nvm"
            local nvm_ver
            nvm_ver="$(latest_git_tag nvm-sh/nvm)" || true
            [[ -z "${nvm_ver}" ]] && nvm_ver="v0.40.5"
            print_success "Using nvm ${nvm_ver}"
            if with_retry "nvm install" bash -o pipefail -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_ver}/install.sh | PROFILE=/dev/null bash"; then
                export NVM_DIR="${HOME}/.nvm"
                if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
                    with_retry "Node.js LTS install" bash -c 'export NVM_DIR="${HOME}/.nvm"; source "${NVM_DIR}/nvm.sh"; nvm install --lts' \
                        && print_success "Node.js LTS installed via nvm" \
                        || print_warning "Node.js LTS install skipped"
                else
                    print_warning "nvm.sh not found after install"
                fi
            else
                print_warning "nvm installation skipped"
            fi
        fi
    else
        print_success "nvm already installed"
    fi

    # Flatpak + Flathub
    flatpak_post_install() {
        if sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            print_success "Flathub remote added"
        else
            print_warning "Failed to add Flathub remote"
        fi
    }

    if ! command_exists flatpak; then
        if ask_confirmation "Install Flatpak + Flathub? (yay -S flatpak)"; then
            install_optional_tool "Flatpak" "flatpak" flatpak_post_install
        fi
    else
        print_success "Flatpak already installed"
        if ! flatpak remotes 2>/dev/null | grep -q '^flathub'; then
            flatpak_post_install
        fi
    fi

    # SDKMAN + Java
    if [[ ! -d "${HOME}/.sdkman" ]]; then
        if ask_confirmation "Install SDKMAN + Java 8, 17, 21, 26 (Temurin)?"; then
            print_header "Installing SDKMAN"
            if with_retry "SDKMAN install" bash -c 'curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash'; then
                install_sdkman_java
            else
                print_warning "SDKMAN installation skipped"
            fi
        fi
    else
        print_success "SDKMAN already installed"
        if ask_confirmation "Install/refresh Java 8, 17, 21, 26 via SDKMAN?"; then
            install_sdkman_java
        fi
    fi

    echo ""
    print_success "Optional components setup complete"
}

generate_initial_colors() {
    print_header "Generating initial color scheme"

    if ! command_exists matugen; then
        print_warning "Matugen not installed, skipping"
        return 0
    fi

    # Pick a random wallpaper from ~/wallpaper
    local wallpaper
    wallpaper=$(find "${HOME}/wallpaper" -type f \( -name "*.jpg" -o -name "*.png" \) 2>/dev/null | shuf -n 1)

    if [[ -z "${wallpaper}" ]]; then
        print_warning "No wallpapers found in ~/wallpaper, skipping"
        return 0
    fi

    mkdir -p "${HOME}/.cache"
    echo "${wallpaper}" > "${HOME}/.cache/current_wallpaper"

    # Generate colors
    matugen image "${wallpaper}" --type scheme-content --prefer saturation || print_warning "Matugen color generation failed"
    print_success "Generated colors from ${wallpaper##*/}"

    # Generate rasi file for rofi background
    local blurred="${HOME}/.cache/blurred_wallpaper.png"
    if command_exists magick; then
        magick "${wallpaper}" -filter box -quality 85 -resize 900x -blur 50x30 "${blurred}" 2>/dev/null
    else
        cp "${wallpaper}" "${blurred}"
    fi
    echo "* { current-image: url(\"${blurred}\", height); }" > "${HOME}/.cache/current_wallpaper.rasi"

    # Apply wallpaper if Hyprland is running
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        if command_exists awww; then
            # Ensure awww-daemon is running
            if ! pgrep -x awww-daemon > /dev/null; then
                awww-daemon > /dev/null 2>&1 &
                disown
                sleep 1
            fi
            awww img "${wallpaper}" --transition-type fade --transition-duration 1 2>/dev/null \
                && print_success "Wallpaper applied via awww"
        elif command_exists hyprpaper; then
            local hyprpaper_conf="${HOME}/.config/hypr/hyprpaper.conf"
            cat > "${hyprpaper_conf}" <<EOF
preload = ${wallpaper}
wallpaper = ,${wallpaper}
splash = false
EOF
            killall hyprpaper 2>/dev/null
            hyprpaper &
            disown
            print_success "Wallpaper applied via hyprpaper"
        else
            print_warning "No wallpaper engine found (awww or hyprpaper)"
        fi
    fi
}

setup_icons() {
    print_header "Setting up icon theme"

    if ! command_exists papirus-folders; then
        if command_exists yay; then
            yay -S --needed --noconfirm papirus-folders-git \
                || { print_warning "Failed to install papirus-folders"; return 0; }
        else
            print_warning "yay not found, skipping papirus-folders"
            return 0
        fi
    fi

    papirus-folders -C black --theme Papirus-Dark \
        && print_success "Papirus-Dark folder color set to black" \
        || print_warning "papirus-folders failed"
}

generate_gtk_bookmarks() {
    print_header "Generating GTK bookmarks"

    if [[ -f "${DOTFILES_DIR}/scripts/generate-bookmarks.sh" ]]; then
        bash "${DOTFILES_DIR}/scripts/generate-bookmarks.sh" || print_warning "Failed to generate bookmarks"
        print_success "GTK bookmarks generated"
    else
        print_warning "generate-bookmarks.sh not found, skipping"
    fi
}

set_default_shell() {
    print_header "Setting default shell"

    local zsh_path
    zsh_path=$(command -v zsh) || {
        print_warning "zsh not found"
        return 0
    }

    if [[ "${SHELL}" != "${zsh_path}" ]]; then
        if ask_confirmation "Set zsh as default shell?"; then
            chsh -s "${zsh_path}" || print_warning "Failed to change shell"
            print_success "Default shell changed to zsh"
            print_warning "Logout and login again for changes to take effect"
        fi
    else
        print_success "Zsh already set as default shell"
    fi
}

disable_faillock() {
    print_header "Relaxing account lockout (faillock)"

    if [[ -f /etc/security/faillock.conf ]]; then
        if sudo sed -i -E 's/^#?[[:space:]]*deny[[:space:]]*=.*/deny = 1000/; s/^#?[[:space:]]*unlock_time[[:space:]]*=.*/unlock_time = 1/' /etc/security/faillock.conf; then
            print_success "faillock relaxed (deny=1000, unlock_time=1) — a wrong password won't lock you out"
        else
            print_warning "Could not edit /etc/security/faillock.conf"
        fi
    else
        print_warning "faillock.conf not found, skipping"
    fi
}

setup_qt_theme() {
    print_header "Setting up Qt theming (qt5ct/qt6ct)"

    mkdir -p "${HOME}/.config/qt5ct/colors" "${HOME}/.config/qt5ct/qss"
    mkdir -p "${HOME}/.config/qt6ct/colors" "${HOME}/.config/qt6ct/qss"

    cat > "${HOME}/.config/qt5ct/qt5ct.conf" <<EOF
[Appearance]
color_scheme_path=${HOME}/.config/qt5ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=${HOME}/.config/qt5ct/qss/matugen-style.qss

[Interface]
stylesheets=${HOME}/.config/qt5ct/qss/matugen-style.qss
EOF

    cat > "${HOME}/.config/qt6ct/qt6ct.conf" <<EOF
[Appearance]
color_scheme_path=${HOME}/.config/qt6ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=${HOME}/.config/qt6ct/qss/matugen-style.qss

[Interface]
stylesheets=${HOME}/.config/qt6ct/qss/matugen-style.qss
EOF

    print_success "qt5ct/qt6ct configured (Fusion + matugen palette/qss)"
}

setup_easyeffects() {
    print_header "Setting up EasyEffects (routed EQ)"

    mkdir -p "${HOME}/.config/easyeffects/output"
    cp -n "${DOTFILES_DIR}/config/easyeffects/output/"*.json "${HOME}/.config/easyeffects/output/" 2>/dev/null || true

    local rc="${HOME}/.config/easyeffects/db/easyeffectsrc"
    if [[ -f "${rc}" ]]; then
        print_success "EasyEffects presets synced; existing config left untouched"
        return 0
    fi

    mkdir -p "$(dirname "${rc}")"
    cat > "${rc}" <<'EOF'
[EffectsPipelines]
bypass=false

[Main]
processAllOutputs=true
showTrayIcon=false

[Presets]
lastLoadedOutputPreset=Classic

[StreamOutputs]
plugins=equalizer#0
EOF

    print_success "EasyEffects primed (routed EQ, Classic default, presets installed, no tray)"
}

setup_btrfs_swap() {
    print_header "Setting up btrfs swapfile"

    local fstab_path="${DOTFILES_FSTAB_PATH:-/etc/fstab}"
    local swap_dir="${DOTFILES_SWAP_DIR:-/swap}"
    local meminfo_path="${DOTFILES_MEMINFO_PATH:-/proc/meminfo}"
    swap_dir="${swap_dir%/}"

    if [[ -z "${swap_dir}" || "${swap_dir}" == "/" ]]; then
        print_error "Refusing unsafe swap directory: '${swap_dir}'"
        return 1
    fi

    local swapfile="${swap_dir}/swapfile"

    if [[ "$(findmnt -no FSTYPE / 2>/dev/null)" != "btrfs" ]]; then
        print_warning "Root filesystem is not btrfs, skipping swapfile"
        return 0
    fi

    if ! command_exists btrfs || ! btrfs filesystem mkswapfile --help >/dev/null 2>&1; then
        print_warning "btrfs mkswapfile unavailable (needs btrfs-progs >= 6.1), skipping"
        return 0
    fi

    if [[ ! -f "${fstab_path}" ]]; then
        print_error "fstab file is missing or is not a regular file: ${fstab_path}"
        return 1
    fi

    local dev uuid
    dev=$(findmnt -no SOURCE / 2>/dev/null || true)
    dev="${dev%%\[*}"
    uuid=$(findmnt -no UUID / 2>/dev/null || true)
    if [[ -z "${dev}" || -z "${uuid}" ]]; then
        print_error "Could not determine the root btrfs device and UUID"
        return 1
    fi

    local mount_entry="UUID=${uuid} ${swap_dir} btrfs noatime,subvol=@swap 0 0"
    local swap_entry="${swapfile} none swap defaults 0 0"

    if sudo awk \
        -v dir="${swap_dir}" \
        -v file="${swapfile}" \
        -v mount_source="UUID=${uuid}" '
            /^[[:space:]]*($|#)/ { next }
            {
                sub(/#.*/, "")
                if ($2 == dir) {
                    if ($1 == mount_source && $3 == "btrfs" &&
                        $4 == "noatime,subvol=@swap" && $5 == "0" &&
                        $6 == "0" && NF == 6) {
                        mount_count++
                    } else {
                        conflict = 1
                    }
                }
                if ($1 == file || $2 == file) {
                    if ($1 == file && $2 == "none" && $3 == "swap" &&
                        $4 == "defaults" && $5 == "0" && $6 == "0" &&
                        NF == 6) {
                        swap_count++
                    } else {
                        conflict = 1
                    }
                }
            }
            END {
                exit(conflict || mount_count > 1 || swap_count > 1 ? 0 : 1)
            }
        ' "${fstab_path}"; then
        print_error "Conflicting fstab entry targets ${swap_dir} or ${swapfile}"
        return 1
    fi

    local mount_entry_present=0
    local swap_entry_present=0
    if sudo awk -v dir="${swap_dir}" -v mount_source="UUID=${uuid}" '
        /^[[:space:]]*($|#)/ { next }
        {
            sub(/#.*/, "")
            if ($1 == mount_source && $2 == dir && $3 == "btrfs" &&
                $4 == "noatime,subvol=@swap" && $5 == "0" &&
                $6 == "0" && NF == 6) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${fstab_path}"; then
        mount_entry_present=1
    fi
    if sudo awk -v file="${swapfile}" '
        /^[[:space:]]*($|#)/ { next }
        {
            sub(/#.*/, "")
            if ($1 == file && $2 == "none" && $3 == "swap" &&
                $4 == "defaults" && $5 == "0" && $6 == "0" &&
                NF == 6) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${fstab_path}"; then
        swap_entry_present=1
    fi

    local swap_mounted=0
    if [[ -e "${swap_dir}" && ( ! -d "${swap_dir}" || -L "${swap_dir}" ) ]]; then
        print_error "Swap path exists but is not a plain directory: ${swap_dir}"
        return 1
    fi
    if mountpoint -q "${swap_dir}" 2>/dev/null; then
        local mounted_fstype mounted_options mounted_uuid
        mounted_fstype=$(findmnt -no FSTYPE --target "${swap_dir}" 2>/dev/null || true)
        mounted_options=$(findmnt -no OPTIONS --target "${swap_dir}" 2>/dev/null || true)
        mounted_uuid=$(findmnt -no UUID --target "${swap_dir}" 2>/dev/null || true)
        if [[ "${mounted_fstype}" != "btrfs" || "${mounted_uuid}" != "${uuid}" ]] ||
            [[ ! ",${mounted_options}," =~ ,subvol=/?@swap, ]]; then
            print_error "${swap_dir} is mounted from the wrong filesystem, device, or subvolume"
            return 1
        fi
        swap_mounted=1
    elif [[ -d "${swap_dir}" ]]; then
        local first_swap_dir_entry
        if ! first_swap_dir_entry=$(find "${swap_dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null); then
            print_error "Could not inspect existing swap directory: ${swap_dir}"
            return 1
        fi
        if [[ -n "${first_swap_dir_entry}" ]]; then
            print_error "Refusing to mount over nonempty directory: ${swap_dir}"
            return 1
        fi
    fi

    local swap_active=0
    if swapon --show=NAME --noheadings 2>/dev/null |
        awk -v file="${swapfile}" '$1 == file { found = 1 } END { exit(found ? 0 : 1) }'; then
        swap_active=1
    fi

    if [[ "${swap_active}" -eq 1 && ! -f "${swapfile}" ]]; then
        print_error "Active swap path is not a regular file: ${swapfile}"
        return 1
    fi
    if [[ -e "${swapfile}" ]]; then
        if [[ ! -f "${swapfile}" ]]; then
            print_error "Swapfile path exists but is not a regular file: ${swapfile}"
            return 1
        fi
        if ! sudo btrfs inspect-internal map-swapfile -r "${swapfile}" >/dev/null 2>&1; then
            print_error "Existing swapfile is not valid for btrfs swap: ${swapfile}"
            return 1
        fi
    fi

    local ram_kb ram_gb rec
    ram_kb=$(awk '/MemTotal/{print $2; exit}' "${meminfo_path}" 2>/dev/null || true)
    if ! [[ "${ram_kb}" =~ ^[0-9]+$ ]] || [[ "${ram_kb}" -lt 1 ]]; then
        print_error "Could not read MemTotal from ${meminfo_path}"
        return 1
    fi
    ram_gb=$(awk "BEGIN{printf \"%.1f\", ${ram_kb}/1048576}")
    rec=$(awk "BEGIN{r=${ram_kb}/1048576; v=r+sqrt(r); printf \"%d\", (v==int(v)?v:int(v)+1)}")

    echo "Detected RAM: ${ram_gb} GiB"
    echo "Recommended:  ${rec} GiB (RAM plus working headroom)"
    if ! ask_confirmation "Configure an on-disk btrfs swapfile?"; then
        return 0
    fi

    local size
    read -rp "$(echo -e "${YELLOW}?${NC}") Swapfile size in GiB [${rec}]: " size
    size="${size:-$rec}"
    if ! [[ "${size}" =~ ^[0-9]+$ ]] || [[ "${size}" -lt 1 ]]; then
        print_warning "Invalid size '${size}', using recommended ${rec} GiB"
        size="${rec}"
    fi

    local tmp=""
    local fstab_original=""
    local fstab_candidate=""
    local fstab_stage=""
    local fstab_stage_owned=0
    local top_mounted=0
    local created_subvolume=0
    local created_swap_dir=0
    local mounted_swap_by_run=0
    local created_swapfile=0
    local activated_swap_by_run=0
    local traps_installed=0
    local previous_int_trap previous_term_trap
    previous_int_trap=$(trap -p INT)
    previous_term_trap=$(trap -p TERM)

    _dotfiles_btrfs_swap_is_active() {
        swapon --show=NAME --noheadings 2>/dev/null |
            awk -v file="${swapfile}" \
                '$1 == file { found = 1 } END { exit(found ? 0 : 1) }'
    }

    _dotfiles_btrfs_swap_restore_traps() {
        [[ "${traps_installed}" -eq 1 ]] || return 0

        trap - INT TERM
        if [[ -n "${previous_int_trap}" ]]; then
            eval "${previous_int_trap}"
        fi
        if [[ -n "${previous_term_trap}" ]]; then
            eval "${previous_term_trap}"
        fi
        traps_installed=0
    }

    _dotfiles_btrfs_swap_rollback() {
        local can_remove_runtime=1
        local can_remove_subvolume=1

        if [[ "${activated_swap_by_run}" -eq 1 ]]; then
            if ! _dotfiles_btrfs_swap_is_active; then
                activated_swap_by_run=0
            elif sudo swapoff "${swapfile}"; then
                activated_swap_by_run=0
            else
                print_error "Rollback could not disable ${swapfile}"
                can_remove_runtime=0
                can_remove_subvolume=0
            fi
        fi

        if [[ "${can_remove_runtime}" -eq 1 && "${created_swapfile}" -eq 1 ]]; then
            if [[ ! -e "${swapfile}" ]]; then
                created_swapfile=0
            elif sudo rm -f -- "${swapfile}"; then
                created_swapfile=0
            else
                print_error "Rollback could not remove ${swapfile}"
                can_remove_subvolume=0
            fi
        fi

        if [[ "${can_remove_runtime}" -eq 1 && "${mounted_swap_by_run}" -eq 1 ]]; then
            if ! mountpoint -q "${swap_dir}" 2>/dev/null; then
                mounted_swap_by_run=0
                swap_mounted=0
            elif sudo umount "${swap_dir}"; then
                mounted_swap_by_run=0
                swap_mounted=0
            else
                print_error "Rollback could not unmount ${swap_dir}"
                can_remove_subvolume=0
            fi
        fi

        if [[ "${created_swap_dir}" -eq 1 && "${mounted_swap_by_run}" -eq 0 ]]; then
            if [[ ! -d "${swap_dir}" ]]; then
                created_swap_dir=0
            elif sudo rmdir "${swap_dir}"; then
                created_swap_dir=0
            else
                print_error "Rollback could not remove ${swap_dir}"
            fi
        fi

        if [[ "${created_subvolume}" -eq 1 && "${can_remove_subvolume}" -eq 1 ]]; then
            if [[ -z "${tmp}" ]]; then
                tmp=$(mktemp -d 2>/dev/null || true)
            fi
            if [[ -n "${tmp}" ]] && mountpoint -q "${tmp}" 2>/dev/null; then
                top_mounted=1
            elif [[ -n "${tmp}" ]]; then
                top_mounted=1
                if sudo mount -o subvolid=5 "${dev}" "${tmp}"; then
                    top_mounted=1
                elif mountpoint -q "${tmp}" 2>/dev/null; then
                    top_mounted=1
                else
                    top_mounted=0
                    print_error "Rollback could not remount the btrfs top level"
                fi
            fi
            if [[ "${top_mounted}" -eq 1 ]]; then
                if ! sudo btrfs subvolume show "${tmp}/@swap" >/dev/null 2>&1; then
                    created_subvolume=0
                elif sudo btrfs subvolume delete "${tmp}/@swap"; then
                    created_subvolume=0
                else
                    print_error "Rollback could not delete the created @swap subvolume"
                fi
            fi
        fi

        if [[ "${top_mounted}" -eq 1 ]]; then
            if ! mountpoint -q "${tmp}" 2>/dev/null; then
                top_mounted=0
            elif sudo umount "${tmp}"; then
                top_mounted=0
            else
                print_error "Rollback could not unmount the btrfs top level"
            fi
        fi
        if [[ -n "${tmp}" && "${top_mounted}" -eq 0 ]]; then
            rmdir "${tmp}" 2>/dev/null || true
            tmp=""
        fi

        if [[ "${fstab_stage_owned}" -eq 1 && -n "${fstab_stage}" ]]; then
            sudo rm -f -- "${fstab_stage}" >/dev/null 2>&1 || true
            fstab_stage_owned=0
            fstab_stage=""
        fi
        if [[ -n "${fstab_candidate}" ]]; then
            rm -f -- "${fstab_candidate}" || true
            fstab_candidate=""
        fi
        if [[ -n "${fstab_original}" ]]; then
            rm -f -- "${fstab_original}" || true
            fstab_original=""
        fi
    }

    _dotfiles_btrfs_swap_fail() {
        trap '' INT TERM
        print_error "$1"
        _dotfiles_btrfs_swap_rollback
        _dotfiles_btrfs_swap_restore_traps
        unset -f \
            _dotfiles_btrfs_swap_is_active \
            _dotfiles_btrfs_swap_restore_traps \
            _dotfiles_btrfs_swap_rollback \
            _dotfiles_btrfs_swap_fail \
            _dotfiles_btrfs_swap_signal
        return 1
    }

    _dotfiles_btrfs_swap_signal() {
        local signal_name="$1"
        local signal_status="$2"

        trap '' INT TERM
        print_error "Interrupted by ${signal_name}; rolling back btrfs swap setup"
        _dotfiles_btrfs_swap_rollback
        _dotfiles_btrfs_swap_restore_traps
        unset -f \
            _dotfiles_btrfs_swap_is_active \
            _dotfiles_btrfs_swap_restore_traps \
            _dotfiles_btrfs_swap_rollback \
            _dotfiles_btrfs_swap_fail \
            _dotfiles_btrfs_swap_signal
        exit "${signal_status}"
    }

    traps_installed=1
    trap '_dotfiles_btrfs_swap_signal INT 130' INT
    trap '_dotfiles_btrfs_swap_signal TERM 143' TERM

    if [[ "${swap_mounted}" -eq 0 ]]; then
        tmp=$(mktemp -d) || {
            _dotfiles_btrfs_swap_fail "Could not create a btrfs mountpoint"
            return 1
        }
        top_mounted=1
        if ! sudo mount -o subvolid=5 "${dev}" "${tmp}"; then
            _dotfiles_btrfs_swap_fail "Failed to mount btrfs top-level subvolume"
            return 1
        fi

        if [[ -e "${tmp}/@swap" ]]; then
            if [[ ! -d "${tmp}/@swap" ]] ||
                ! sudo btrfs subvolume show "${tmp}/@swap" >/dev/null 2>&1; then
                _dotfiles_btrfs_swap_fail "Existing @swap is not a btrfs subvolume"
                return 1
            fi
        else
            created_subvolume=1
            if ! sudo btrfs subvolume create "${tmp}/@swap"; then
                _dotfiles_btrfs_swap_fail "Failed to create @swap subvolume"
                return 1
            fi
        fi

        if [[ ! -d "${swap_dir}" ]]; then
            created_swap_dir=1
            if ! sudo mkdir -- "${swap_dir}"; then
                _dotfiles_btrfs_swap_fail "Failed to create ${swap_dir}"
                return 1
            fi
        fi

        mounted_swap_by_run=1
        if ! sudo mount -o noatime,subvol=@swap "${dev}" "${swap_dir}"; then
            _dotfiles_btrfs_swap_fail "Failed to mount @swap at ${swap_dir}"
            return 1
        fi
        swap_mounted=1
    fi

    if [[ ! -e "${swapfile}" ]]; then
        created_swapfile=1
        if ! sudo btrfs filesystem mkswapfile --size "${size}g" "${swapfile}"; then
            _dotfiles_btrfs_swap_fail "mkswapfile failed"
            return 1
        fi
    fi
    if ! sudo btrfs inspect-internal map-swapfile -r "${swapfile}" >/dev/null 2>&1; then
        _dotfiles_btrfs_swap_fail "btrfs rejected the swapfile mapping"
        return 1
    fi

    if [[ "${swap_active}" -eq 0 ]]; then
        activated_swap_by_run=1
        if ! sudo swapon "${swapfile}"; then
            _dotfiles_btrfs_swap_fail "Failed to activate ${swapfile}"
            return 1
        fi
    fi

    if ! _dotfiles_btrfs_swap_is_active; then
        _dotfiles_btrfs_swap_fail "Swap activation verification failed for ${swapfile}"
        return 1
    fi

    if [[ "${top_mounted}" -eq 1 ]]; then
        if mountpoint -q "${tmp}" 2>/dev/null && ! sudo umount "${tmp}"; then
            _dotfiles_btrfs_swap_fail "Failed to unmount the btrfs top level"
            return 1
        fi
        top_mounted=0
    fi
    if [[ -n "${tmp}" ]]; then
        if ! rmdir "${tmp}"; then
            _dotfiles_btrfs_swap_fail "Failed to remove the temporary btrfs mountpoint"
            return 1
        fi
        tmp=""
    fi

    if [[ "${mount_entry_present}" -eq 0 || "${swap_entry_present}" -eq 0 ]]; then
        fstab_original=$(mktemp) || {
            _dotfiles_btrfs_swap_fail "Could not snapshot ${fstab_path}"
            return 1
        }
        if ! sudo cat -- "${fstab_path}" > "${fstab_original}"; then
            _dotfiles_btrfs_swap_fail "Could not snapshot ${fstab_path}"
            return 1
        fi

        local snapshot_fstab_state
        if ! snapshot_fstab_state=$(awk \
            -v dir="${swap_dir}" \
            -v file="${swapfile}" \
            -v mount_source="UUID=${uuid}" '
                /^[[:space:]]*($|#)/ { next }
                {
                    sub(/#.*/, "")
                    if ($2 == dir) {
                        if ($1 == mount_source && $3 == "btrfs" &&
                            $4 == "noatime,subvol=@swap" && $5 == "0" &&
                            $6 == "0" && NF == 6) {
                            mount_count++
                        } else {
                            conflict = 1
                        }
                    }
                    if ($1 == file || $2 == file) {
                        if ($1 == file && $2 == "none" && $3 == "swap" &&
                            $4 == "defaults" && $5 == "0" && $6 == "0" &&
                            NF == 6) {
                            swap_count++
                        } else {
                            conflict = 1
                        }
                    }
                }
                END {
                    if (conflict || mount_count > 1 || swap_count > 1) {
                        exit 1
                    }
                    printf "%d %d\n", mount_count == 1, swap_count == 1
                }
            ' "${fstab_original}"); then
            _dotfiles_btrfs_swap_fail \
                "Conflicting fstab entry appeared while the swap transaction was running"
            return 1
        fi
        read -r mount_entry_present swap_entry_present <<< "${snapshot_fstab_state}"
    fi

    if [[ "${mount_entry_present}" -eq 0 || "${swap_entry_present}" -eq 0 ]]; then

        fstab_candidate=$(mktemp) || {
            _dotfiles_btrfs_swap_fail "Could not create an fstab candidate"
            return 1
        }
        if ! cp -- "${fstab_original}" "${fstab_candidate}"; then
            _dotfiles_btrfs_swap_fail "Could not initialize the fstab candidate"
            return 1
        fi
        if [[ -s "${fstab_candidate}" ]] &&
            [[ "$(tail -c 1 "${fstab_candidate}" | wc -l)" -eq 0 ]]; then
            if ! printf '\n' >> "${fstab_candidate}"; then
                _dotfiles_btrfs_swap_fail "Could not terminate the fstab candidate"
                return 1
            fi
        fi
        if [[ "${mount_entry_present}" -eq 0 ]]; then
            if ! printf '%s\n' "${mount_entry}" >> "${fstab_candidate}"; then
                _dotfiles_btrfs_swap_fail "Could not append the @swap mount entry"
                return 1
            fi
        fi
        if [[ "${swap_entry_present}" -eq 0 ]]; then
            if ! printf '%s\n' "${swap_entry}" >> "${fstab_candidate}"; then
                _dotfiles_btrfs_swap_fail "Could not append the swapfile entry"
                return 1
            fi
        fi

        if ! findmnt --verify --tab-file "${fstab_candidate}"; then
            _dotfiles_btrfs_swap_fail "fstab candidate validation failed"
            return 1
        fi

        if ! sudo cmp -s -- "${fstab_original}" "${fstab_path}"; then
            _dotfiles_btrfs_swap_fail "fstab changed while the swap transaction was running"
            return 1
        fi

        if ! fstab_stage=$(sudo mktemp -- "${fstab_path}.dotfiles.XXXXXX"); then
            fstab_stage=""
            _dotfiles_btrfs_swap_fail "Failed to create a staged fstab in ${fstab_path%/*}"
            return 1
        fi
        fstab_stage_owned=1
        if ! sudo cp --preserve=all -- "${fstab_path}" "${fstab_stage}"; then
            _dotfiles_btrfs_swap_fail "Failed to stage the fstab candidate"
            return 1
        fi
        if ! sudo tee "${fstab_stage}" < "${fstab_candidate}" >/dev/null; then
            _dotfiles_btrfs_swap_fail "Failed to write the staged fstab candidate"
            return 1
        fi

        # Ignore interrupts only through the atomic exchange/recovery decision.
        # The displaced live file proves whether another writer won the race.
        trap '' INT TERM
        if ! sudo mv --exchange --no-copy -- "${fstab_stage}" "${fstab_path}"; then
            _dotfiles_btrfs_swap_fail "Failed to commit the fstab candidate"
            return 1
        fi

        local displaced_fstab_status
        if sudo cmp -s -- "${fstab_original}" "${fstab_stage}"; then
            if ! sudo rm -f -- "${fstab_stage}"; then
                print_warning "Committed fstab, but could not remove displaced copy ${fstab_stage}"
            fi
            fstab_stage_owned=0
            fstab_stage=""
            _dotfiles_btrfs_swap_restore_traps
            rm -f -- "${fstab_candidate}" "${fstab_original}" || true
            fstab_candidate=""
            fstab_original=""
        else
            displaced_fstab_status=$?
            if sudo mv --exchange --no-copy -- "${fstab_stage}" "${fstab_path}"; then
                if [[ "${displaced_fstab_status}" -eq 1 ]]; then
                    _dotfiles_btrfs_swap_fail \
                        "fstab changed during the atomic commit; the external version was restored"
                else
                    _dotfiles_btrfs_swap_fail \
                        "Could not verify the displaced fstab; the previous version was restored"
                fi
                return 1
            fi

            # The candidate remains live, so keep runtime swap active and retain
            # the displaced file instead of producing a broken persistent state.
            fstab_stage_owned=0
            print_error "fstab changed during commit and could not be restored"
            print_warning \
                "Swap remains active; displaced fstab preserved at ${fstab_stage} for manual recovery"
            _dotfiles_btrfs_swap_restore_traps
            rm -f -- "${fstab_candidate}" "${fstab_original}" || true
            fstab_candidate=""
            fstab_original=""
            unset -f \
                _dotfiles_btrfs_swap_is_active \
                _dotfiles_btrfs_swap_restore_traps \
                _dotfiles_btrfs_swap_rollback \
                _dotfiles_btrfs_swap_fail \
                _dotfiles_btrfs_swap_signal
            return 1
        fi
    else
        _dotfiles_btrfs_swap_restore_traps
        if [[ -n "${fstab_original}" ]]; then
            rm -f -- "${fstab_original}" || true
            fstab_original=""
        fi
    fi

    unset -f \
        _dotfiles_btrfs_swap_is_active \
        _dotfiles_btrfs_swap_restore_traps \
        _dotfiles_btrfs_swap_rollback \
        _dotfiles_btrfs_swap_fail \
        _dotfiles_btrfs_swap_signal
    print_success "btrfs swapfile ready at ${swapfile} (zram swap, if present, stays primary)"
}

check_manual_hibernation() {
    local efi_path="${DOTFILES_EFI_PATH:-/sys/firmware/efi}"
    local mkinitcpio_config="${DOTFILES_MKINITCPIO_CONFIG:-/etc/mkinitcpio.conf}"
    local can_hibernate

    if [[ ! -d "${efi_path}" ]]; then
        print_warning "Manual hibernation is unavailable: UEFI was not detected at ${efi_path}"
        return 0
    fi

    if [[ ! -r "${mkinitcpio_config}" ]]; then
        print_warning "Manual hibernation is indeterminate: cannot read ${mkinitcpio_config}"
        return 0
    fi

    if ! awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*HOOKS[[:space:]]*=/ {
            found = 0
            line = $0
            sub(/[[:space:]]*#.*/, "", line)
            count = split(line, fields, /[[:space:]]+/)
            for (i = 1; i <= count; i++) {
                token = fields[i]
                gsub(/^[^[:alnum:]_.+-]+/, "", token)
                gsub(/[^[:alnum:]_.+-]+$/, "", token)
                if (token == "systemd") {
                    found = 1
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${mkinitcpio_config}"; then
        print_warning "Manual hibernation is unavailable: active HOOKS lacks the systemd hook"
        return 0
    fi

    if ! command_exists busctl; then
        print_warning "Manual hibernation is indeterminate: busctl is unavailable"
        return 0
    fi

    if ! can_hibernate=$(busctl call org.freedesktop.login1 \
        /org/freedesktop/login1 \
        org.freedesktop.login1.Manager CanHibernate 2>/dev/null); then
        print_warning "Manual hibernation is indeterminate: login1 CanHibernate query failed"
        return 0
    fi

    case "${can_hibernate}" in
        's "yes"'|'s "challenge"')
            print_success "Manual hibernation is available via Wlogout"
            ;;
        *)
            print_warning "Manual hibernation is unavailable: login1 CanHibernate returned ${can_hibernate:-no result}"
            ;;
    esac

    return 0
}

#==============================================================================
# Main Installation
#==============================================================================

main() {
    # Set up error handling
    trap cleanup EXIT
    trap 'error_exit "Script interrupted"' INT TERM

    # Start logging
    log "Installation started"

    clear
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   Dotfiles Installation Script        ║"
    echo "║   Hyprland + Waybar + Rofi + More     ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    # Confirmation
    echo "This script will:"
    echo "  • Backup existing configs to ${BACKUP_DIR}"
    echo "  • Create symlinks from ${DOTFILES_DIR} to ~/.config/"
    echo "  • Set up SDDM (optional)"
    echo "  • Set up the pinned Steins;GRUB theme when GRUB is detected (optional)"
    echo "  • Set up the vendored Divergence Meter Plymouth theme (optional)"
    echo "  • Install shell plugins (optional)"
    echo "  • Install optional components: pyenv, Go, Docker, nvm + Node.js, Flatpak, SDKMAN + Java (optional)"
    echo "  • Create a btrfs swapfile, auto-sized (optional)"
    echo "  • Generate initial color scheme"
    echo ""
    echo "Installation log: ${LOG_FILE}"
    echo ""

    if ! ask_confirmation "Continue with installation?"; then
        echo "Installation cancelled"
        exit 0
    fi

    # Run installation steps
    check_requirements
    link_dotfiles_home
    check_arch
    check_yay
    check_dependencies
    backup_existing_configs
    create_symlinks
    setup_user_services
    setup_local_config
    setup_wallpaper_dir
    install_shell_plugins
    install_optional_packages
    setup_nautilus_integration
    setup_sddm
    setup_grub_theme
    setup_plymouth
    install_optional_components
    setup_icons
    setup_qt_theme
    setup_easyeffects
    setup_btrfs_swap
    check_manual_hibernation
    generate_initial_colors
    generate_gtk_bookmarks
    set_default_shell
    disable_faillock

    # Reload Hyprland and launch services if running
    if command_exists hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        hyprctl reload && print_success "Hyprland config reloaded"

        # Launch waybar if not running
        if ! pgrep -x waybar > /dev/null; then
            "${DOTFILES_DIR}/config/waybar/launch.sh" &
            disown
            print_success "Waybar launched"
        fi
    fi

    # Done
    print_header "Installation Complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Change wallpaper: Super + Ctrl + W"
    echo "  2. If not in Hyprland: logout and select 'Hyprland' session"
    echo "  3. If you have any problems: logout or reboot and login again"
    echo ""
    echo "Installation log saved to: ${LOG_FILE}"
    echo ""
    print_success "Enjoy your new setup!"

    log "Installation completed successfully"
}

# Run main function only when executed directly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
