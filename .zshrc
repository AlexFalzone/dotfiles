# Path to the Oh My Zsh installation
export ZSH="$HOME/.oh-my-zsh"
export PATH=$PATH:$HOME/.cargo/bin

# Theme settings
ZSH_THEME="bira"

# Auto Update settings
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 7

# Plugins to load
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    colorize
    colored-man-pages
    sudo
    common-aliases
    command-not-found
)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Custom aliases
alias update="sudo dnf update -y && flatpak update -y"

alias vpnUp='sudo wg-quick up /etc/wireguard/ideapad.conf'
alias vpnDown='sudo wg-quick down /etc/wireguard/ideapad.conf'

alias ll="ls -la"
alias gs="git status"
alias gp="git push"
alias gc="git commit -m"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gl="git log --oneline --graph --decorate"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias ls="/usr/bin/ls -lh --color=auto"

# Enable command auto-correction
ENABLE_CORRECTION="true"

# Configuration for zsh-autosuggestions
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# Configuration for zsh-syntax-highlighting
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)

# Command history settings
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

setopt INC_APPEND_HISTORY       # Append history incrementally
setopt SHARE_HISTORY            # Share history among all sessions

# Zsh options
setopt auto_cd                  # Automatically change to a directory by typing its name
setopt multios                  # Enable multiple redirections
setopt prompt_subst             # Enable prompt variable substitution

# Custom PATH
export PATH="$HOME/bin:$PATH"

# Preferred editor
export EDITOR="nano"

export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$PATH:/usr/local/go/bin"
export PATH="$HOME/.local/bin:$PATH"
