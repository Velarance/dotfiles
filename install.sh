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

setup_sddm() {
    print_header "Setting up SDDM"

    if ! command_exists sddm; then
        print_warning "SDDM not installed, skipping"
        return 0
    fi

    if ask_confirmation "Configure SDDM with Silent theme?"; then
        # Check sudo access
        if ! sudo -v; then
            print_error "Failed to get sudo access"
            return 1
        fi

        # Install SDDM config as drop-in so it overrides distro defaults
        # (SDDM reads /etc/sddm.conf.d/*.conf AFTER /etc/sddm.conf, so the
        # drop-in wins over things like kde_settings.conf that ship with
        # sddm-kcm and force Current=breeze).
        sudo install -Dm644 "${DOTFILES_DIR}/config/sddm/sddm.conf" \
            /etc/sddm.conf.d/10-dotfiles.conf \
            || print_warning "Failed to install SDDM config"
        print_success "SDDM config installed to /etc/sddm.conf.d/10-dotfiles.conf"

        # Check if Silent theme exists
        if [[ -d "/usr/share/sddm/themes/silent" ]]; then
            print_success "Silent theme found"
        else
            print_warning "Silent theme not found at /usr/share/sddm/themes/silent"
            echo "Install with: yay -S sddm-silent-theme"
        fi

        # Enable SDDM
        if ask_confirmation "Enable SDDM service?"; then
            sudo systemctl enable sddm || print_warning "Failed to enable SDDM"
            print_success "SDDM enabled"
        fi
    fi
}

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
    setup_local_config
    setup_wallpaper_dir
    install_shell_plugins
    install_optional_packages
    setup_nautilus_integration
    setup_sddm
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
