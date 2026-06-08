#!/usr/bin/env bash
# Install Throne (proxy client) from the GitHub release zip — user-local, no sudo.
# Usage: install-throne.sh [version]   (default below)
set -euo pipefail

VERSION="${1:-1.1.5}"
URL="https://github.com/throneproj/Throne/releases/download/${VERSION}/Throne-${VERSION}-linux-amd64.zip"

DEST="${HOME}/.local/share/Throne"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
WRAPPER="${BIN_DIR}/throne"
DESKTOP="${DESKTOP_DIR}/throne.desktop"

G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; X='\033[0m'
say(){ printf "${G}==>${X} %s\n" "$1"; }
warn(){ printf "${Y}!${X} %s\n" "$1"; }
die(){ printf "${R}✗${X} %s\n" "$1"; exit 1; }

command -v curl >/dev/null || die "curl not found"
command -v unzip >/dev/null || die "unzip not found"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

say "Downloading Throne ${VERSION}"
curl -fSL --retry 3 -o "${tmp}/throne.zip" "${URL}" || die "download failed"

say "Extracting"
unzip -q -o "${tmp}/throne.zip" -d "${tmp}"
[[ -x "${tmp}/Throne/Throne" ]] || die "unexpected zip layout (no Throne/Throne)"

say "Installing to ${DEST}"
mkdir -p "$(dirname "${DEST}")"
rm -rf "${DEST}"
mv "${tmp}/Throne" "${DEST}"
chmod +x "${DEST}/Throne" "${DEST}/ThroneCore" "${DEST}/updater" 2>/dev/null || true

say "Writing launcher wrapper ${WRAPPER}"
mkdir -p "${BIN_DIR}"
cat > "${WRAPPER}" <<EOF
#!/bin/sh
DIR="${DEST}"
export LD_LIBRARY_PATH="\${DIR}/usr/lib:\${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="\${DIR}/usr/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="\${DIR}/usr/plugins/platforms"
cd "\${DIR}" && exec ./Throne "\$@"
EOF
chmod +x "${WRAPPER}"

say "Creating desktop entry (shows up in rofi / Super+M)"
mkdir -p "${DESKTOP_DIR}"
cat > "${DESKTOP}" <<EOF
[Desktop Entry]
Type=Application
Name=Throne
GenericName=Proxy Client
Comment=Throne proxy client
Exec=${WRAPPER} %U
Icon=${DEST}/Throne.png
Terminal=false
Categories=Network;
StartupWMClass=Throne
EOF
update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true

say "Throne ${VERSION} installed"
echo "    launch: throne   (or Super+M -> Throne)"
[[ ":${PATH}:" == *":${BIN_DIR}:"* ]] || warn "${BIN_DIR} is not on PATH — add it or use the menu entry"
