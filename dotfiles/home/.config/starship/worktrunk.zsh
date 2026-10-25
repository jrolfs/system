#!/usr/bin/env zsh
#
# worktrunk's view of this branch against the default branch, which git_status
# can't give: integrated (safe to remove), would conflict, how far ahead of or
# behind main, and the open PR.
#
# Printed from a cache and refreshed in the background, never inline. `wt list
# statusline` fetches CI status whenever its 30–60s cache has expired, and that
# takes about 1.6s against 60ms warm, well past starship's 500ms
# command_timeout. So each prompt shows what the previous prompt's refresh
# found, which after a commit means one prompt of stale counts.

zmodload zsh/system

local git_directory
git_directory="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" || exit 0

local cache_directory="${XDG_CACHE_HOME:-$HOME/.cache}/starship/worktrunk"
local cache="$cache_directory/${git_directory//\//%}.json"
mkdir -p "$cache_directory"

[[ -r "$cache" ]] && jq -r '
  .repo.default_branch as $default
  | .items[0] // empty
  | (.display.state // "") as $state
  | ({
      orphan: "∅", empty: "_", integrated: "⊂", would_conflict: "✗",
      same_commit: "–"
    }[$state]) as $symbol
  | (
      if $state == "integrated" or $state == "empty" then ""
      else
        [ (.default_branch.ahead // 0 | select(. > 0) | "↑\(.)"),
          (.default_branch.behind // 0 | select(. > 0) | "↓\(.)") ]
        | if length > 0 then "\($default)\(join(""))" else "" end
      end
    ) as $divergence
  | [ $symbol, $divergence, (.pr.number // empty | "#\(.)") ]
  | map(select(. != null and . != ""))
  | join(" ")
' "$cache" 2>/dev/null

# flock rather than a lock directory: the lock goes with the process, so a
# refresh that dies can't leave a lock behind to block every later prompt. The
# file has to exist first, since zsystem won't create it. All
# three descriptors are redirected because starship waits for the pipe to
# close, not for the process.
#
# Pinned to JSON schema 2 so the default flipping in a later worktrunk release
# doesn't silently empty this module.
(
  : >>"$cache.lock"
  zsystem flock -t 0 "$cache.lock" || exit 0
  wt list statusline --format=json --config-set list.json-schema=2 >"$cache.tmp" \
    && mv "$cache.tmp" "$cache"
) </dev/null >/dev/null 2>&1 &!
