#!/usr/bin/env zsh

local repository_root
repository_root="$(git rev-parse --show-toplevel 2>/dev/null)"

if [[ -n "$repository_root" ]]; then
  local repository_name="${repository_root##*/}"
  local subdirectory="${PWD#"$repository_root"}"

  # A linked worktree is named after its branch, by whatever layout worktrunk
  # is configured with (frontends.some-branch beside the checkout, or
  # .system/some-branch for this repo). The common git directory belongs to the
  # main checkout under every layout, so name the repository from that instead;
  # custom.worktree marks that this is a worktree.
  local -a git_paths
  git_paths=("${(@f)$(git rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)}")
  if [[ "${git_paths[1]}" != "${git_paths[2]}" ]]; then
    if [[ "${git_paths[2]:t}" == .git ]]; then
      repository_name="${git_paths[2]:h:t}"
    else
      repository_name="${${git_paths[2]:t}%.git}"
    fi
  fi

  directory="…/${repository_name}${subdirectory}"
else
  directory="${PWD/#$HOME/~}"
  parts=("${(@s:/:)directory}")
  if (( ${#parts} > 3 )); then
    directory="…/${(j:/:)parts[-3,-1]}"
  fi
fi

[[ ! -w "$PWD" ]] && directory="$directory "
printf '%s' "$directory"
