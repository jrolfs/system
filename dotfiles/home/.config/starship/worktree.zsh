#!/usr/bin/env zsh
#
# A glyph when this is a linked worktree rather than the main checkout, and the
# branch's worktrunk marker. The worktrunk Claude Code plugin sets that marker
# from its hooks, 🤖 while a session is working and 💬 while it waits for
# input, so the prompt shows whether this worktree's agent needs attention.
#
# Both reads are local, about 10ms together, so unlike worktrunk.zsh this runs
# inline.

local -a git_paths
git_paths=("${(@f)$(git rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)}")
(( ${#git_paths} == 2 )) || exit 0

local -a parts
[[ "${git_paths[1]}" != "${git_paths[2]}" ]] && parts+=("󰙅")

local marker
marker="$(wt config state marker get 2>/dev/null)"
[[ -n "$marker" ]] && parts+=("$marker")

printf '%s' "${(j: :)parts}"
