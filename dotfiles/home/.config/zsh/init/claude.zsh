# ╌╌↘
#
# Resume a Claude Code thread that was started by Zed's ACP client. The built-in
# `/resume` picker mixes these in with terminal sessions and is scoped to the
# current directory; Zed history is siloed per working directory, so threads
# started elsewhere never show. This narrows to just the Zed threads and can
# widen the search across the repo or everything, reattaching the chosen one
# from its own home directory.
#
# Picking happens in claude-zed-threads itself now, so there is no external
# fuzzy finder in the loop: type to filter, ↑↓ to move, ⏎ to reattach.
#
# ```sh
#   resume-zed          # threads for this project directory
#   resume-zed --repo   # every git worktree of the current repo
#   resume-zed --all    # every project on disk
#   resume-zed -d PATH  # a different project directory
# ```
#
# ╌╌↗
resume-zed() {
  # The packaged command (claude-helpers) where the flake manages this machine,
  # the homeshick symlink on one still linking the dot castle.
  local script=${commands[claude-zed-threads]:-${HOME}/.claude/bin/claude-zed-threads}
  [[ -x "$script" ]] || { print -u2 "resume-zed: missing or non-executable $script"; return 1 }

  # The picker draws on stderr and writes the chosen thread to stdout, so the
  # id and its directory come back through a plain command substitution. It
  # exits non-zero when nothing was picked.
  local chosen id dir
  chosen=$("$script" --pick "$@") || return 0
  IFS=$'\t' read -r id dir <<<"$chosen"
  [[ -n "$id" ]] || return 0

  # Reattach from the thread's own directory when it still exists, so file
  # references in the transcript resolve; otherwise resume in place.
  [[ -n "$dir" && -d "$dir" ]] && cd "$dir"
  claude --resume "$id"
}

# OpenCode cannot resume a Claude UUID directly. The helper imports an inert
# snapshot once, then returns the same OpenCode continuation on later picks.
resume-claude() {
  local script=${commands[claude-opencode-threads]}
  [[ -x "$script" ]] || { print -u2 "resume-claude: missing claude-opencode-threads; run nix-switch"; return 1 }

  local chosen id dir result argument
  local -a action=(--pick)
  for argument in "$@"; do
    case "$argument" in
      -h|--help) "$script" "$@"; return ;;
      --import|--import=*) action=() ;;
    esac
  done
  chosen=$("$script" "${action[@]}" "$@")
  result=$?
  [[ $result == 130 ]] && return 0
  (( result == 0 )) || return $result
  IFS=$'\t' read -r id dir <<<"$chosen"
  [[ -n "$id" && -n "$dir" ]] || return 0

  opencode "$dir" --session "$id"
}
