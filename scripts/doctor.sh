#!/usr/bin/env bash
# doctor — health check for the whole Hyprland rice setup.

DOTS="${HOME}/dotfiles"
G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; C='\033[1;36m'; D='\033[2m'; X='\033[0m'
N_OK=0; N_WARN=0; N_FAIL=0
hdr(){  printf "\n${C}▌ %s${X}\n" "$1"; }
ok(){   printf "  ${G}✓${X} %s\n" "$1"; N_OK=$((N_OK+1)); }
warn(){ printf "  ${Y}!${X} %s\n" "$1"; N_WARN=$((N_WARN+1)); }
fail(){ printf "  ${R}✗${X} %s\n" "$1"; N_FAIL=$((N_FAIL+1)); }
have(){ command -v "$1" &>/dev/null; }

[[ -d "$DOTS" ]] || { fail "~/dotfiles not found"; exit 1; }
source "$DOTS/lib/packages.conf" 2>/dev/null

hdr "System"
ok "Linux $(uname -r)"
if have hyprctl; then ok "Hyprland $(hyprctl version 2>/dev/null | grep -oE 'v[0-9.]+' | head -1)"; else fail "hyprctl not found"; fi
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    e=$(hyprctl configerrors 2>/dev/null)
    if [[ -z "$e" ]]; then ok "config: no errors"; else fail "config errors:"; printf "%s\n" "$e" | sed 's/^/      /'; fi
else
    warn "not inside a Hyprland session — process/config checks skipped (run from a kitty in Hyprland)"
fi

hdr "Symlinks (~/.config → dotfiles)"
for cfg in "${CONFIGS[@]}"; do
    t="$HOME/.config/$cfg"
    if [[ -L "$t" && "$(readlink -f "$t")" == "$DOTS/config/$cfg" ]]; then ok "$cfg"
    elif [[ -e "$t" ]]; then warn "$cfg — exists but not linked to dotfiles"
    else fail "$cfg — missing"; fi
done

hdr "Packages"
m=(); for p in "${CORE_PACKAGES[@]}"; do pacman -Q "$p" &>/dev/null || m+=("$p"); done
((${#m[@]}==0)) && ok "all ${#CORE_PACKAGES[@]} CORE installed" || fail "missing CORE: ${m[*]}"
m=(); for p in "${OPTIONAL_PACKAGES[@]}"; do pacman -Q "$p" &>/dev/null || m+=("$p"); done
((${#m[@]}==0)) && ok "all ${#OPTIONAL_PACKAGES[@]} OPTIONAL installed" || warn "missing OPTIONAL: ${m[*]}"

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hdr "Running services"
    for p in waybar swaync hypridle; do pgrep -x "$p" >/dev/null && ok "$p" || warn "$p not running"; done
    (pgrep -x awww-daemon >/dev/null || pgrep -x hyprpaper >/dev/null) && ok "wallpaper daemon" || warn "no wallpaper daemon"
    pgrep -f 'cliphist store' >/dev/null && ok "clipboard history watcher" || warn "cliphist watcher not running (SUPER+C history will be stale)"
fi

hdr "Theme (matugen)"
for f in colors-hyprland.conf colors-waybar.css colors-rofi.rasi; do
    [[ -s "$HOME/.cache/$f" ]] && ok "$f generated" || fail "$f missing/empty (run wallpaper.sh scheme)"
done
wp=$(cat "$HOME/.cache/current_wallpaper" 2>/dev/null)
[[ -f "$wp" ]] && ok "wallpaper: $(basename "$wp")" || warn "no wallpaper set"

hdr "Fonts"
fc-list 2>/dev/null | grep -qi 'FiraCode Nerd Font' && ok "FiraCode Nerd Font" || fail "FiraCode Nerd Font missing (UI/icons break)"
fc-list 2>/dev/null | grep -qi 'Fira Sans'          && ok "Fira Sans (rofi)"  || warn "Fira Sans missing (rofi falls back)"

hdr "Shell"
[[ "$(getent passwd "$(whoami)" | cut -d: -f7)" == *zsh ]] && ok "default shell = zsh" || warn "default shell is not zsh (chsh -s /usr/bin/zsh)"
for pl in zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete; do
    [[ -d "/usr/share/zsh/plugins/$pl" ]] && ok "$pl" || warn "$pl not installed"
done

hdr "Keyboard"
kc="$DOTS/config/hypr/conf/keyboard.conf"
grep -qE 'kb_layout *= *us, *ru' "$kc" 2>/dev/null && ok "layouts us, ru" || warn "ru layout not configured"
grep -q 'win_space_toggle' "$kc" 2>/dev/null && ok "switch on Super+Space" || warn "Super+Space toggle not set"

hdr "Account lockout (faillock)"
if [[ -f /etc/security/faillock.conf ]]; then
    d=$(grep -E '^[[:space:]]*deny' /etc/security/faillock.conf | grep -oE '[0-9]+' | head -1)
    if [[ "${d:-3}" -ge 100 ]]; then ok "relaxed (deny=$d) — won't lock on wrong password"
    else warn "deny=${d:-3} — a few wrong passwords WILL lock you out (run install.sh or edit faillock.conf)"; fi
else warn "faillock.conf not found"; fi

hdr "Dotfiles repo"
cd "$DOTS" 2>/dev/null && {
    [[ -z "$(git status --porcelain 2>/dev/null)" ]] && ok "working tree clean" || warn "uncommitted local changes"
    git fetch --quiet 2>/dev/null
    b=$(git rev-list --count '@..@{u}' 2>/dev/null)
    if [[ -z "$b" ]]; then warn "no remote tracking branch"
    elif [[ "$b" == "0" ]]; then ok "up to date with remote"
    else warn "$b commit(s) behind — run dots-update"; fi
}

printf "\n${C}▌ Summary${X}   ${G}%d ok${X}   ${Y}%d warn${X}   ${R}%d fail${X}\n" "$N_OK" "$N_WARN" "$N_FAIL"
[[ $N_FAIL -gt 0 ]] && exit 1 || exit 0
