#!/usr/bin/env zsh

# A long path pushes the git segments off the end of the line. Past this width
# the path drops whole leading components first, keeping the directories
# closest to $PWD, and only then shortens the current directory's own name.
local -i maximum_width=40

local repository_root
repository_root="$(git rev-parse --show-toplevel 2>/dev/null)"

if [[ -n "$repository_root" ]]; then
  local repository_name="${repository_root##*/}"
  local subdirectory="${PWD#"$repository_root"}"

  # Strip worktree suffix (e.g. frontends.jamie-some-branch → frontends)
  if [[ "$repository_name" == *.* ]] && [[ -d "${repository_root:h}/${repository_name%%.*}/.git" ]]; then
    repository_name="${repository_name%%.*}"
  fi

  directory="…/${repository_name}${subdirectory}"
else
  directory="${PWD/#$HOME/~}"
  parts=("${(@s:/:)directory}")
  if (( ${#parts} > 3 )); then
    directory="…/${(j:/:)parts[-3,-1]}"
  fi
fi

if (( ${#directory} > maximum_width )); then
  local -a components=("${(@s:/:)directory}")
  local kept="${components[-1]}"
  local -i index=$(( ${#components} - 1 ))

  # Each candidate costs its own width, a slash, and the leading "…/".
  while (( index > 1 && ${#components[index]} + ${#kept} + 3 <= maximum_width )); do
    kept="${components[index]}/$kept"
    (( index-- ))
  done

  # Only the current directory is left and it still doesn't fit. Keep the start
  # of its name, which is what tells siblings apart (a date or a customer, say,
  # rather than a trailing UUID).
  (( ${#kept} + 2 > maximum_width )) && kept="${kept[1,maximum_width - 3]}…"

  directory="…/$kept"
fi

[[ ! -w "$PWD" ]] && directory="$directory "
printf '%s' "$directory"
