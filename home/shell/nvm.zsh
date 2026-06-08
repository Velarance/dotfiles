#!/bin/zsh
# =====================================================
# nvm (Node Version Manager)
# =====================================================

export NVM_DIR="${HOME}/.nvm"

if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    source "${NVM_DIR}/nvm.sh"
    [[ -s "${NVM_DIR}/bash_completion" ]] && source "${NVM_DIR}/bash_completion"
fi
