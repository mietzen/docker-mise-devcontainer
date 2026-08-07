# Minimal zsh config for the vscode devcontainer base image.
# It primes mise so every interactive shell starts mise-aware.

# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# mise: make its shims available and activate the shell hook
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
eval "$(mise activate zsh)"