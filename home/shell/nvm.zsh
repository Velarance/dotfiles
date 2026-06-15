#!/bin/zsh
# =====================================================
# nvm (Node Version Manager)
# =====================================================

export NVM_DIR="${HOME}/.nvm"

if [[ -d "${NVM_DIR}/versions/node" ]]; then
    _nvm_default="$(cat "${NVM_DIR}/alias/default" 2>/dev/null)"
    if [[ "${_nvm_default}" != v* ]]; then
        _nvm_default="$(command ls -1 "${NVM_DIR}/versions/node" 2>/dev/null | sort -V | tail -1)"
    fi
    if [[ -d "${NVM_DIR}/versions/node/${_nvm_default}/bin" ]]; then
        export PATH="${NVM_DIR}/versions/node/${_nvm_default}/bin:${PATH}"
    fi
    unset _nvm_default
fi

if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    nvm() {
        unset -f nvm
        source "${NVM_DIR}/nvm.sh"
        [[ -s "${NVM_DIR}/bash_completion" ]] && source "${NVM_DIR}/bash_completion"
        nvm "$@"
    }
fi
