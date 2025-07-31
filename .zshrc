# ~/.zshrc - Main ZSH configuration
# Last updated: $(date)

#==========================================
# INSTANT PROMPT (Keep at top)
#==========================================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#==========================================
# PLUGIN MANAGER (ZINIT)
#==========================================
ZINIT_HOME="${XDG_CONFIG_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

#==========================================
# PLUGINS
#==========================================
# Theme
zinit ice depth=1; zinit light romkatv/powerlevel10k

# Essential plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Additional useful plugins
zinit light zdharma-continuum/fast-syntax-highlighting
zinit light zsh-users/zsh-history-substring-search

autoload -U compinit && compinit

#==========================================
# ENVIRONMENT SETUP
#==========================================
# Load environment files if they exist
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
[[ -f "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env"

# OS-specific setup
setup_os_environment() {
    local os_name=$(uname -s)
    case "$os_name" in
        "Darwin")
            [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
            ;;
        "Linux")
            [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            ;;
        *)
            echo "Warning: Unknown OS ($os_name)" >&2
            ;;
    esac
}
setup_os_environment

#==========================================
# PATH CONFIGURATION
#==========================================
# Build PATH more efficiently
typeset -U path  # Keep PATH entries unique
path=(
    "$HOME/bin"
    "$HOME/.local/bin"
    "$HOME/.local/share/bob/nvim-bin"
    "$HOME/go/bin"
    "$HOME/.cargo/bin"
    $path
)

#==========================================
# EXPORTS
#==========================================
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

#==========================================
# HISTORY CONFIGURATION
#==========================================
HISTSIZE=10000
HISTFILE=~/.zsh_history
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups
setopt hist_expire_dups_first
setopt hist_reduce_blanks

#==========================================
# ZSH OPTIONS
#==========================================
setopt auto_cd              # cd by typing directory name if it's not a command
setopt correct              # auto correct mistakes
setopt interactivecomments  # allow comments in interactive mode
setopt magicequalsubst      # enable filename expansion for arguments of the form 'anything=expression'
setopt nonomatch           # hide error message if there is no match for the pattern
setopt notify              # report the status of background jobs immediately
setopt numericglobsort     # sort filenames numerically when it makes sense
setopt promptsubst         # enable command substitution in prompt

#==========================================
# KEY BINDINGS
#==========================================
bindkey -e  # Use emacs key bindings

# History search
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^r' history-incremental-search-backward

# Better word movement
bindkey '^[[1;5C' forward-word    # Ctrl+Right
bindkey '^[[1;5D' backward-word   # Ctrl+Left

#==========================================
# COMPLETION CONFIGURATION
#==========================================
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ~/.zsh/cache
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --color=always $realpath 2>/dev/null || ls --color $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'less ${(Q)realpath} 2>/dev/null || file ${(Q)realpath}'

#==========================================
# ALIASES
#==========================================
# Enhanced ls with eza
alias ls='eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions'
alias ll='eza --color=always --long --git --icons=always'
alias la='eza --color=always --long --git --icons=always --all'
alias lt='eza --tree --color=always --icons=always'

# Common shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'

# Tooling specific
alias deploy_staging='git tag eks-staging -f && git push origin eks-staging -f'
alias claude='claude --mcp-config ~/.claude/mcp_servers.json'

#==========================================
# FUNCTIONS
#==========================================

# Yazi with cd integration
y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# Enhanced directory navigation with fzf
fzcd() {
    local dir
    dir=$(fd --type directory --hidden --exclude .git | fzf --preview 'eza --tree --color=always {} | head -200')
    [[ -n "$dir" ]] && cd "$dir"
}

# Improved grep and open in nvim
nvim_grep_open() {
    local query="$1"

    if [[ -z "$query" ]]; then
        echo "Usage: nvim_grep_open <search_term>"
        return 1
    fi

    local selected
    selected=$(rg --vimgrep --smart-case "$query" |
        fzf --delimiter : --nth=4.. \
            --preview 'bat --style=numbers --color=always --line-range {2}: --highlight-line {2} {1}' \
            --preview-window=up:70% \
            --bind 'enter:become(echo {1}:{2})')

    if [[ -n "$selected" ]]; then
        local file=$(echo "$selected" | cut -d: -f1)
        local linenum=$(echo "$selected" | cut -d: -f2)
        nvim "$file" "+$linenum"
    fi
}

# Enhanced file finder
nvim_file_open() {
    local pattern="${1:-.}"
    local selected
    selected=$(fd --type file --hidden --exclude .git "$pattern" |
        fzf --preview 'bat --color=always --style=numbers {}' \
            --preview-window=right:60%)
    [[ -n "$selected" ]] && nvim "$selected"
}

# Improved CLI help function
cli_help() {
    if [[ -z "$1" ]]; then
        echo "Usage: cli_help <your question about CLI commands>"
        return 1
    fi
    cmd=$(claude --system-prompt "You are a command-line expert specializing in Bash and ZSH. When the user asks how to perform a task, respond with a single-line CLI command that solves it. Only output the command itself, in plain text—no code blocks, no commentary, no syntax highlighting, no shell output, and no functions or aliases unless explicitly requested. Output must be suitable for direct copy-paste into a terminal." -p "I want a shell command to: $1")
    echo "Suggested command:"
    echo "$cmd"
    echo -n "Execute? [y/N]: "; read confirm
    if [[ "$confirm" == [Yy] ]]; then
        bash -c "$cmd"
    fi
}

git_help() {
    prompt=$(cat ~/.prompts/git-gud.md)
    claude --system-prompt "$prompt" --append-system-prompt "$prompt" -p "Command to: $1"
}

# New utility functions
take() {
    mkdir -p "$1" && cd "$1"
}

extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

#==========================================
# EXTERNAL TOOL INITIALIZATION
#==========================================
# Initialize tools that modify shell behavior
command -v fzf >/dev/null && eval "$(fzf --zsh)"
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

#==========================================
# THEME CONFIGURATION
#==========================================
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

#==========================================
# LOCAL CUSTOMIZATIONS
#==========================================
# Source local customizations if they exist
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# bun completions
[ -s "/Users/danrousseau/.bun/_bun" ] && source "/Users/danrousseau/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
