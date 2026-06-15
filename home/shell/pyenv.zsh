#!/bin/zsh
# =====================================================
# pyenv (Python Version Manager)
# =====================================================

export PYENV_ROOT="${HOME}/.pyenv"

if [[ -d "${PYENV_ROOT}/bin" ]]; then
    export PATH="${PYENV_ROOT}/bin:${PATH}"
fi

if [[ -x "${PYENV_ROOT}/bin/pyenv" ]]; then
    export PATH="${PYENV_ROOT}/shims:${PATH}"
    export PYENV_SHELL=zsh
    pyenv() {
        unset -f pyenv
        eval "$(command pyenv init - zsh)"
        pyenv "$@"
    }
fi
