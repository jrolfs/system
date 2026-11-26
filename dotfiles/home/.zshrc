# zmodload zsh/zprof

preztorc="${XDG_CONFIG_HOME}/zsh/prezto.zsh"
platformrc="${HOME}/.zshrc.$(uname | tr '[:upper:]' '[:lower:]')"

[[ -f $preztorc ]] && source $preztorc
[[ -f $platformrc ]] && source $platformrc

unset preztorc platformrc

#
# <zinit>
#

declare -A ZINIT

ZINIT[NO_ALIASES]=1

source "$XDG_DATA_HOME/zinit/zinit.git/zinit.zsh"

# Prezto (synchronous — must load before interactive features)
zinit ice pick"init.zsh" \
  atclone"git clone git@github.com:belak/prezto-contrib.git contrib" \
  atpull"cd contrib && git pull"
zinit light sorin-ionescu/prezto

# Local configs
for config in $XDG_CONFIG_HOME/zsh/init/(^_*).zsh; zinit snippet "$config"

# Post-Prezto hooks (order-sensitive — must load after Prezto's editor module)
zinit ice atload'
  eval "$(atuin init zsh --disable-up-arrow)"
  bindkey "^[[A" up-line-or-search
  bindkey "^[[B" down-line-or-search
'
zinit light zdharma-continuum/null

zinit ice has'zoxide'; zinit light ajeetdsouza/zoxide

zinit ice nocd atload'eval "$(direnv hook zsh)"'
zinit light zdharma-continuum/null

# Sticking with direnv for now
zinit ice nocd atload'eval "$(devenv hook zsh)"'
zinit light zdharma-continuum/null

zinit ice nocd atload'eval "$(command wt config shell init zsh)"' if'command -v wt >/dev/null 2>&1'
zinit light zdharma-continuum/null

# Homeshick
zinit snippet "$HOME/.homesick/repos/homeshick/homeshick.sh"

# OMZ plugins (Turbo — mostly completions)
zinit wait lucid for \
  OMZ::plugins/gem/gem.plugin.zsh \
  OMZ::plugins/golang/golang.plugin.zsh \
  OMZ::plugins/mosh/mosh.plugin.zsh \
  OMZ::plugins/pip/pip.plugin.zsh

# Completions (Turbo)
zinit wait lucid for \
  zsh-users/zsh-completions \
  ryutok/rust-zsh-completions

zinit ice wait lucid pick"completions"
zinit light andsens/homeshick

zinit ice wait lucid pick"completions/zsh"
zinit light homebrew/brew

zinit ice wait lucid pick"launchctl-completion.bash"
zinit light bobthecow/launchctl-completion

# Kubectx
zinit ice wait lucid
zinit light ahmetb/kubectx

# Initialize completions after Turbo-loaded plugins register theirs.
#
# `wt`'s completion is registered here rather than beside its shell init
# because zinit only substitutes its compdef-queueing shim while a plugin file
# is being sourced, and restores (or unfunctions) it immediately after. An
# `atload` therefore runs with no compdef at all, so calling it there is a
# "command not found" and the binding is silently lost. Running it after
# zicdreplay also lets this wrapper win over anything wt queued itself.
zinit ice wait lucid atload'zicompinit; zicdreplay; (( $+functions[_wt_with_restore] )) && compdef _wt_with_restore wt'
zinit light zdharma-continuum/null

#
# </zinit>
#

if [[ -v STARSHIP_ENABLED ]] then
  eval "$(starship init zsh)"
fi

# zprof
