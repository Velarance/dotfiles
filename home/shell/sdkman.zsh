#!/bin/zsh
# =====================================================
# SDKMAN (lazy)
# =====================================================

export SDKMAN_DIR="${HOME}/.sdkman"

if [[ -d "${SDKMAN_DIR}" ]]; then
    for _sdk_bin in "${SDKMAN_DIR}"/candidates/*/current/bin(N); do
        export PATH="${_sdk_bin}:${PATH}"
    done
    unset _sdk_bin
    if [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then
        sdk() {
            unset -f sdk
            source "${SDKMAN_DIR}/bin/sdkman-init.sh"
            sdk "$@"
        }
    fi
fi
