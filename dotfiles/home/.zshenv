#
# Options
#

setopt bang_hist
setopt extended_history
setopt hist_ignore_space
setopt hist_verify
setopt share_history

#
# Environment
#

# XDG
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_CACHE_HOME="${HOME}/.cache"

# Source optional machine-specific environment first
machine_env="${XDG_CONFIG_HOME}/zsh/env.$(hostname -s | tr '[:upper:]' '[:lower:]')"
[[ -f $machine_env ]] && source $machine_env

export KEYTIMEOUT=1

# Dotfiles
export HOMESHICK_KINGDOM="${HOMESHICK_DIR:-$HOME/.homesick/repos}"
export HS_KINGDOM=$HOMESHICK_KINGDOM
export ZSH_EXTRA_COMPLETIONS="${XDG_CONFIG_HOME}/zsh/completions"

export GITHUB_USER="jrolfs"
export ORGANIZATION="meterup"
export DEVELOPER="${HOME}/Developer"
export SOURCES="${DEVELOPER}/Sources"

export WORK_HOME="${SOURCES}/${ORGANIZATION}"
export PERSONAL_HOME="${DEVELOPER}/${ORGANIZATION}"

export WORK_BIN="${XDG_DATA_HOME}/${(L)ORGANIZATION}/bin"

# History Sync
export ZSH_HISTORY_FILE_NAME=".zsh_history"
export ZSH_HISTORY_FILE="${HOME}/${ZSH_HISTORY_FILE_NAME}"
export ZSH_HISTORY_PROJ="${XDG_DATA_HOME}/history"
export ZSH_HISTORY_FILE_ENC_NAME="zsh_history"
export ZSH_HISTORY_FILE_ENC="${ZSH_HISTORY_PROJ}/${ZSH_HISTORY_FILE_ENC_NAME}"
export ZSH_HISTORY_COMMIT_MSG="sync($(hostname | tr '[:upper:]' '[:lower:]')): $(date +'%A, %B %d %Y @ %T')"

export SYNC="${HOME}/Sync"

# Go
export GOPATH="${DEVELOPER}/Go"

# Git Duet
export GIT_DUET_CO_AUTHORED_BY=1
export GIT_DUET_AUTHORS_FILE="${XDG_CONFIG_HOME}/git/authors.yml"

# GPG/SSH
export SSH_AUTH_SOCK="${HOME}/.gnupg/S.gpg-agent.ssh"

# FZF
export FZF_DEFAULT_COMMAND='ag --hidden --ignore .git -g ""'
export FZF_TMUX=1
export FZF_TMUX_HEIGHT='50%'

export SKIM_DEFAULT_COMMAND="fd --type f --hidden"

# Nix
export NIXPKGS_ALLOW_UNFREE=1

# 1Password
# No OP_CONFIG_DIR override: op's config holds device-local state (account
# registrations keyed to a per-device UUID), so pointing every machine at one
# synced copy makes them fight — each signin invalidates the others. Let op use
# its own per-machine ~/.config/op.

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# Claude Code
export CLAUDE_CODE_USE_FOUNDRY=1
export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5
export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5
export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5[1m]
export ANTHROPIC_DEFAULT_FABLE_MODEL=claude-fable-5[1m]
export ANTHROPIC_MODEL=$ANTHROPIC_DEFAULT_OPUS_MODEL

# Starship
# (silence noisy timeout warnings... although I wish Node and
# Git wouldn't timeout so much and would like to fix that)
export STARSHIP_LOG=error

# Spicetify (install directory isn't currently
# configurable but I put it in XDG manually)
export SPICETIFY_INSTALL="${XDG_DATA_HOME}/spicetify"

# Ensure that a non-login, non-interactive shell has a defined environment.
if [[ "$SHLVL" -eq 1 && ! -o LOGIN && -s "${ZDOTDIR:-$HOME}/.zprofile" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprofile"

  path=(
    $path
  )

  source $XDG_CONFIG_HOME/zsh/mise.zsh
fi
