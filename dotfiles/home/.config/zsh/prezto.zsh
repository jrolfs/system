zstyle ':prezto:*:*' color 'yes'

zstyle ':prezto:load' pmodule \
  'environment' \
  'editor' \
  'history' \
  'directory' \
  'spectrum' \
  'gpg' \
  'git' \
  'ruby' \
  'node' \
  'python' \
  'utility' \
  'autosuggestions' \
  'history-substring-search' \
  'syntax-highlighting' \
  'wakeonlan' \
  'prompt'

zstyle ':completion:*' menu select

zstyle ':prezto:module:editor' key-bindings 'vi'
zstyle ':prezto:module:editor:info:completing' format "%B%216F…%f%b"

zstyle ':prezto:module:prompt' pwd-length 'short'

zstyle ':prezto:module:utility' safe-ops 'no'

zstyle ':prezto:module:syntax-highlighting' highlighters \
  'main' \
  'brackets' \
  'pattern' \
  'line' \
  'cursor' \
  'root'

zstyle ':prezto:module:syntax-highlighting' styles \
  'unknown-token' 'fg=1' \
  'alias' 'fg=14' \
  'builtin' 'fg=4' \
  'command' 'fg=151' \
  'function' 'fg=11' \
  'single-hyphen-option' 'fg=247,bold' \
  'double-hyphen-option' 'fg=247,bold'
