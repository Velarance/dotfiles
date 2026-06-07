#!/usr/bin/env bash
# Set up SSH auth to GitHub via the gh CLI — clone & edit private repos.

set -u
G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[1;36m'; X='\033[0m'
say(){ printf "\n${C}▌ %s${X}\n" "$1"; }
ok(){  printf "  ${G}✓${X} %s\n" "$1"; }
warn(){ printf "  ${Y}!${X} %s\n" "$1"; }
err(){ printf "  ${R}✗${X} %s\n" "$1"; }
ask(){ printf "${C}?${X} %s " "$1"; read -r REPLY; }

KEY="$HOME/.ssh/id_ed25519"
gh_ok(){ ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; }

# Already working? bail early.
if gh_ok; then ok "SSH to GitHub already works — nothing to do."; exit 0; fi

say "Git identity"
[[ -z "$(git config --global user.name 2>/dev/null)" ]]  && { ask "Name for git commits:"; git config --global user.name "$REPLY"; }
[[ -z "$(git config --global user.email 2>/dev/null)" ]] && { ask "GitHub email:";        git config --global user.email "$REPLY"; }
ok "$(git config --global user.name) <$(git config --global user.email)>"

say "SSH key"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [[ -f "$KEY" ]]; then
    ok "key exists: $KEY"
else
    ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$KEY" -N "" >/dev/null
    ok "generated $KEY"
fi
ssh-keygen -F github.com >/dev/null 2>&1 || ssh-keyscan -t ed25519,rsa github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
if ! grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile $KEY
    IdentitiesOnly yes
EOF
fi
chmod 600 "$HOME/.ssh/config" 2>/dev/null
ok "known_hosts + ~/.ssh/config ready"

say "GitHub CLI"
if ! command -v gh >/dev/null 2>&1; then
    warn "installing github-cli..."
    sudo pacman -S --needed --noconfirm github-cli || { err "failed to install gh"; exit 1; }
fi
ok "gh $(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1)"

say "Authorize with GitHub (one-time, in browser)"
if gh auth status >/dev/null 2>&1; then
    ok "gh already authenticated"
else
    echo "  gh will show a code → press Enter → paste it in the browser that opens."
    gh auth login --hostname github.com --git-protocol ssh --web || { err "gh login failed"; exit 1; }
fi
# make sure this machine's key is on the account (login usually uploads it; this is a fallback)
gh ssh-key add "$KEY.pub" --title "$(hostname)" >/dev/null 2>&1 && ok "key uploaded" || ok "key already on GitHub"

say "Test"
if gh_ok; then ok "SSH to GitHub works — private repos available"; else err "SSH test failed — check github.com/settings/keys"; exit 1; fi

# Offer to switch ~/dotfiles to SSH so push works
DOTS="$HOME/dotfiles"
if [[ -d "$DOTS/.git" ]]; then
    url=$(git -C "$DOTS" remote get-url origin 2>/dev/null || echo "")
    if [[ "$url" == https://github.com/* ]]; then
        ssh_url="git@github.com:${url#https://github.com/}"; ssh_url="${ssh_url%.git}.git"
        ask "Switch ~/dotfiles remote to SSH ($ssh_url)? [y/N]"
        [[ "${REPLY:-}" =~ ^[Yy] ]] && { git -C "$DOTS" remote set-url origin "$ssh_url"; ok "dotfiles → SSH"; }
    fi
fi

printf "\n${G}Done — git over SSH is set up. Clone private repos with: git clone git@github.com:USER/REPO${X}\n"
