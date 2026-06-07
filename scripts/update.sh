#!/usr/bin/env bash
# Update dotfiles: pull latest, re-link configs, install new packages, reload.

DOTS="${HOME}/dotfiles"
G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; C='\033[1;36m'; X='\033[0m'
say(){ printf "${C}▌ %s${X}\n" "$1"; }
ok(){  printf "  ${G}✓${X} %s\n" "$1"; }
warn(){ printf "  ${Y}!${X} %s\n" "$1"; }
err(){ printf "  ${R}✗${X} %s\n" "$1"; }

cd "$DOTS" 2>/dev/null || { err "~/dotfiles not found"; exit 1; }

say "Checking for updates"
if [[ -n "$(git status --porcelain)" ]]; then
    warn "you have local uncommitted changes:"
    git --no-pager status --short | sed 's/^/    /'
fi

git fetch --quiet 2>/dev/null
upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)
if [[ -z "$upstream" ]]; then
    warn "no remote tracking branch set — can't pull updates"
    echo  "    set your fork:  git -C ~/dotfiles remote set-url origin <your-repo> && git -C ~/dotfiles branch --set-upstream-to=origin/master"
    exit 0
fi

if [[ "$(git rev-parse @)" == "$(git rev-parse '@{u}')" ]]; then
    ok "already up to date ($upstream)"
else
    echo "  new commits:"
    git --no-pager log --oneline '@..@{u}' | sed 's/^/    /'
    if git pull --ff-only --quiet; then ok "pulled"; else err "pull failed (diverged) — resolve manually"; exit 1; fi
fi

# install any packages added to packages.conf
if command -v yay >/dev/null 2>&1 && [[ -f lib/packages.conf ]]; then
    source lib/packages.conf
    missing=()
    for p in "${CORE_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}"; do
        pacman -Q "$p" &>/dev/null || missing+=("$p")
    done
    if (( ${#missing[@]} )); then
        say "Installing ${#missing[@]} new package(s)"
        yay -S --needed --noconfirm "${missing[@]}"
    fi
fi

# re-link configs (idempotent) in case new dirs were added
if [[ -f lib/packages.conf ]]; then
    source lib/packages.conf
    for cfg in "${CONFIGS[@]}"; do
        [[ -d "config/$cfg" ]] && ln -sfn "$DOTS/config/$cfg" "$HOME/.config/$cfg"
    done
    for f in "${HOME_FILES[@]}"; do
        [[ -f "home/$f" ]] && ln -sfn "$DOTS/home/$f" "$HOME/$f"
    done
    ok "symlinks refreshed"
fi

# reload live session
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null 2>&1
    "$DOTS/config/waybar/launch.sh" >/dev/null 2>&1 &
    ok "Hyprland + waybar reloaded"
fi

printf "${G}Done.${X}\n"
